// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console2} from 'forge-std/Test.sol';
import {ILocksmith} from '../src/interfaces/ILocksmith.sol';
import {Locksmith} from '../src/Locksmith.sol';
import {
    KeyNotHeld,
    KeyNotRoot,
    InvalidRing,
    InvalidRingKey,
    InvalidRingKeySet,
    SoulboundTransferBreach
} from 'src/interfaces/ILocksmith.sol';
import "openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract LocksmithUnitTest is Test, ERC1155Holder {
    Locksmith public locksmith;

	receive() external payable {
        // needed to be able to take money
    }

    function setUp() public {
        locksmith = new Locksmith();

		// fund our accounts
        vm.deal(address(this), 10 ether);
    }

	//////////////////////////////////////////////
	// Post Deployment
	//////////////////////////////////////////////

    function test_EmptyLocksmithState() public {
		// check interface
		assertEq(true, locksmith.supportsInterface(type(IERC1155).interfaceId));
		assertEq(true, locksmith.supportsInterface(type(IERC165).interfaceId));
		assertEq(true, locksmith.supportsInterface(type(ILocksmith).interfaceId));
			
		// initial state
    	assertEq(locksmith.keySupply(0), 0);
		assertEq("Locksmith Keys", locksmith.name());

		// this will revert if you are asking for bad info
		vm.expectRevert();
		locksmith.getRingInfo(0);

		// the first key has no holders
		assertEq(0, locksmith.getHolders(0).length);

		// while the first key will be a root key obviously,
		// this will return false if the root key isn't valid
		assertEq(false, locksmith.isRootKey(0));

		// similarly, inspectKey will return invalid flag for
		// the first key
		(bool isValid,,,,) = locksmith.inspectKey(0);
		assertEq(false, isValid);

		// trying to validate the key ring against the root,
		// with allowRoot will still revert for invalid ring.
		vm.expectRevert(InvalidRing.selector);
		uint256[] memory keys = new uint256[](1);
		locksmith.validateKeyRing(0, keys, true);

		// calling getRingId fails on invalid key
		vm.expectRevert(InvalidRingKey.selector);
		locksmith.getRingId(99);
	}

	//////////////////////////////////////////////
	// Ring Creation 
	//////////////////////////////////////////////

	function test_SuccessfulRingCreation() public {
		// preconditions 
		assertEq(0, locksmith.balanceOf(address(this), 0));
		assertEq(0, locksmith.keySupply(0));
		assertEq(0, locksmith.getHolders(0).length);
		assertEq(0, locksmith.getKeysForHolder(address(this)).length);
		assertEq(false, locksmith.hasKeyOrRoot(address(this), 0));

		// define the events we expect to fire on the next call
		vm.expectEmit(address(locksmith));
		emit ILocksmith.KeyMinted(address(this), 0, 0, address(this));
		vm.expectEmit(address(locksmith));
		emit ILocksmith.KeyRingCreated(address(this), 0, stb("My Key Ring"), address(this));

		// successfully create a ring and a root key
		(uint256 ringId, uint256 keyId) = locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), 
			'https://locksmithwallet.com/mykey.json', address(this));
		assertEq(0, ringId);
		assertEq(0, keyId);

		// get the ring info
		(uint256 ringIdBack, bytes32 ringName, uint256 rootKeyId, uint256[] memory ringKeys) =
			locksmith.getRingInfo(0);
		assertEq(0, ringIdBack);
		assertEq(stb('My Key Ring'), ringName);
		assertEq(0, rootKeyId);
		assertEq(0, ringKeys[0]);
		assertEq(1, ringKeys.length);

		// make sure we are now holding the key
		assertEq(1, locksmith.balanceOf(address(this), 0));

		// check the supply metrics
		assertEq(1, locksmith.keySupply(0));

		// check the holder indexes
		assertEq(1, locksmith.getHolders(0).length);
	   	assertEq(address(this), locksmith.getHolders(0)[0]);
		assertEq(1, locksmith.getKeysForHolder(address(this)).length);
		assertEq(0, locksmith.getKeysForHolder(address(this))[0]);

		// make sure the key is root
		assertEq(true, locksmith.isRootKey(0));

		// escalation detection works on root
		assertEq(true, locksmith.hasKeyOrRoot(address(this), 0));

		// inspecting the key is sane
		(bool isValid, bytes32 keyName, uint256 ring, bool isRoot, uint256[] memory keys) =
			locksmith.inspectKey(0);
		assertEq(true, isValid);
		assertEq(stb("Master Key"), keyName);
		assertEq(0, ring);
		assertEq(true, isRoot);
		assertEq(1, keys.length);
		assertEq(0, keys[0]);
		assertEq('https://locksmithwallet.com/mykey.json', locksmith.uri(0));

		// the key ring will validate with asserting
		uint256[] memory list = new uint256[](1);
		list[0] = 0;
		assertEq(true, locksmith.validateKeyRing(0, list, true));

		// it won't validate if we don't allow root though
		vm.expectRevert(InvalidRingKeySet.selector);
		locksmith.validateKeyRing(0, list, false);

		// the key ring now won't validate with bad rings
		list[0] = 1;
		vm.expectRevert(InvalidRingKeySet.selector);
		locksmith.validateKeyRing(0, list, true);
	}

	//////////////////////////////////////////////
	// Key Creation 
	//////////////////////////////////////////////

	function test_CantCreateKeyRingWithoutHoldingRootKey() public {
		// create the default ring at 0,0
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(0x1337));

		vm.expectRevert(KeyNotHeld.selector);
		locksmith.createKey(0, stb('Second'), '', address(this), false);
	}
	
	function test_SuccessfulRingKeyCreation() public {
		// create the default ring at 0,0
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));

		// preconditions
		assertEq(0, locksmith.balanceOf(address(this), 1));
		assertEq(0, locksmith.keySupply(1));
		assertEq(0, locksmith.getHolders(1).length);
		assertEq(1, locksmith.getKeysForHolder(address(this)).length);
		assertEq(false, locksmith.hasKeyOrRoot(address(this), 1));

		// ensure the event is logged
		vm.expectEmit(address(locksmith));
		emit ILocksmith.KeyMinted(address(this), 0, 1, address(0x1337));
		locksmith.createKey(0, stb('Second'), '', address(0x1337), false); // id: 1

		// post conditions
		assertEq(0, locksmith.balanceOf(address(this), 1));
		assertEq(1, locksmith.balanceOf(address(0x1337), 1));
		assertEq(1, locksmith.keySupply(1));
		assertEq(1, locksmith.getHolders(1).length);
		assertEq(1, locksmith.getKeysForHolder(address(0x1337)).length);
		assertEq(1, locksmith.getKeysForHolder(address(this)).length);
		assertEq(true, locksmith.hasKeyOrRoot(address(this), 1));
		assertEq(true, locksmith.hasKeyOrRoot(address(0x1337), 1));
	}

	function test_CreatingRingKeyMustUseRoot() public {
		// create the default ring at 0,0
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));
		locksmith.createKey(0, stb('Second'), '', address(this), false); // id: 1

		// attempt to use key 1 on ring 0. This will fail
		vm.expectRevert(KeyNotRoot.selector);
		locksmith.createKey(1, stb('third'), '', address(this), false); 
	}
	
	//////////////////////////////////////////////
	// Sending and Soulbinding 
	//////////////////////////////////////////////

	function test_SendingZeroKeysWorks() public {
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));

		assertEq(1, locksmith.getHolders(0).length);
		locksmith.safeTransferFrom(address(this), address(0x1337), 0, 0, '');
		assertEq(1, locksmith.getHolders(0).length);
	}

	function test_SendingViaBatchDoesntBypassSoulbinding() public {
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));
		locksmith.copyKey(0, 0, address(this), true);

		// i have two soulbound root keys, shouldnt be able to send them both.
		uint256[] memory ids = new uint256[](2);
		ids[0] = 0;
		ids[1] = 0;
		uint256[] memory amounts = new uint256[](2);
		amounts[0] = 1;
		amounts[1] = 1;
		vm.expectRevert(SoulboundTransferBreach.selector);
		locksmith.safeBatchTransferFrom(address(this), address(0x1337), ids, amounts, '');	
	}
	function test_CanSendKeys() public {
		// create the default ring at 0,0
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));
		locksmith.createKey(0, stb('Second'), '', address(this), false); // id: 1
		
		// preconditions
		assertEq(0, locksmith.balanceOf(address(0x1337), 1));
		assertEq(1, locksmith.keySupply(1));
		assertEq(1, locksmith.getHolders(1).length);
	
		// ensure the event occurs, and that the balance changes
		vm.expectEmit(address(locksmith));
		emit IERC1155.TransferSingle(address(this), address(this), address(0x1337), 1, 1); 
		locksmith.safeTransferFrom(address(this), address(0x1337), 1, 1, '');
		
		// post conditions, the key has moved 
		assertEq(1, locksmith.balanceOf(address(0x1337), 1));
		assertEq(1, locksmith.keySupply(1));
		assertEq(1, locksmith.getHolders(1).length);
		assertEq(1, locksmith.getKeysForHolder(address(0x1337))[0]);
		
		// mint multiple copies
		locksmith.copyKey(0, 1, address(this), false);
		locksmith.copyKey(0, 1, address(this), false);
		locksmith.copyKey(0, 1, address(this), false);
		
		// check supply
		assertEq(4, locksmith.keySupply(1));
		assertEq(2, locksmith.getHolders(1).length);
		assertEq(1, locksmith.getKeysForHolder(address(this))[1]);
		assertEq(2, locksmith.getKeysForHolder(address(this)).length);

		// send out root key 
		locksmith.safeTransferFrom(address(this), address(0x1337), 0, 1, '');
		assertEq(1, locksmith.getKeysForHolder(address(this)).length);
	}

	function test_MustBeRootToSoulbindKeys() public {
		// create the default ring at 0,0
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));
		locksmith.safeTransferFrom(address(this), address(0x1337), 0, 1, '');

		vm.expectRevert(KeyNotHeld.selector);
		locksmith.soulbindKey(0, address(this), 1, 1); 
	}

	function test_MustSoulbindValidRingKeysOnly() public {
		// create the default ring at 0,0
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));
		vm.expectRevert(InvalidRingKey.selector);
		locksmith.soulbindKey(0, address(this), 1, 1); 
	}

	function test_CantSendSoulboundKeysUnboundWorks() public {
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));
		
		// pre-conditions 
		assertEq(1, locksmith.balanceOf(address(this), 0));
		assertEq(1, locksmith.keySupply(0));
		assertEq(1, locksmith.getHolders(0).length);
		assertEq(0, locksmith.getKeysForHolder(address(this))[0]);

		// soulbind the root key
		vm.expectEmit(address(locksmith));
		emit ILocksmith.SetSoulboundKeyAmount(address(this), address(this), 0, 1);
		locksmith.soulbindKey(0, address(this), 0, 1);
	
		// we won't be able to send it now	
		vm.expectRevert(SoulboundTransferBreach.selector);
		locksmith.safeTransferFrom(address(this), address(0x1337), 0, 1, '');
		
		// same state 
		assertEq(1, locksmith.balanceOf(address(this), 0));
		assertEq(1, locksmith.keySupply(0));
		assertEq(1, locksmith.getHolders(0).length);
		assertEq(0, locksmith.getKeysForHolder(address(this))[0]);

		// unbind the key
		vm.expectEmit(address(locksmith));
		emit ILocksmith.SetSoulboundKeyAmount(address(this), address(this), 0, 0);
		locksmith.soulbindKey(0, address(this), 0, 0);
		
		// we can now send
		vm.expectEmit(address(locksmith));
		emit IERC1155.TransferSingle(address(this), address(this), address(0x1337), 0, 1); 
		locksmith.safeTransferFrom(address(this), address(0x1337), 0, 1, '');
		
		// post conditions, the key has moved 
		assertEq(1, locksmith.balanceOf(address(0x1337), 0));
		assertEq(1, locksmith.keySupply(0));
		assertEq(1, locksmith.getHolders(0).length);
		assertEq(0, locksmith.getKeysForHolder(address(0x1337))[0]);
		assertEq(0, locksmith.getKeysForHolder(address(this)).length);
	}

	function test_CanSendSoulboundWithSufficientBalance() public {
		// create and soulbind root key
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));
        locksmith.soulbindKey(0, address(this), 0, 1);

        // we won't be able to send it now
        vm.expectRevert(SoulboundTransferBreach.selector);
        locksmith.safeTransferFrom(address(this), address(0x1337), 0, 1, '');

		// now copy the key
		locksmith.copyKey(0, 0, address(this), false);
        
		// we can send, because the soulbound amount is 1,
		// and we now hold two keys
		vm.expectEmit(address(locksmith));
		emit IERC1155.TransferSingle(address(this), address(this), address(0x1337), 0, 1); 
		locksmith.safeTransferFrom(address(this), address(0x1337), 0, 1, '');

		// post conditions, the key has moved 
		assertEq(1, locksmith.balanceOf(address(0x1337), 0));
		assertEq(2, locksmith.keySupply(0));
		assertEq(2, locksmith.getHolders(0).length);
		assertEq(0, locksmith.getKeysForHolder(address(0x1337))[0]);
		assertEq(1, locksmith.getKeysForHolder(address(this)).length);
	}
	
	//////////////////////////////////////////////
	// Key Copying 
	//////////////////////////////////////////////

	function test_MustHoldRootKeyToCopy() public {
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(0x1337));
		vm.expectRevert(KeyNotHeld.selector);
		locksmith.copyKey(0, 0, address(this), false);
	}

	function test_KeyUsedForCopyMustBeRoot() public {
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));
		locksmith.createKey(0, stb('Second'), '', address(this), false);

		vm.expectRevert(KeyNotRoot.selector);
		locksmith.copyKey(1, 0, address(this), false);
	}

	function test_CopiedKeyMustBeOnRing() public {
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this)); // 0
		locksmith.createKeyRing(stb("My Key Ring 2"), stb("Master Key 2"), '', address(this)); // 1
		vm.expectRevert(InvalidRingKey.selector);
		locksmith.copyKey(0, 1, address(this), false);
	}

	function test_SuccessfulKeyCopiesSoulbound() public {
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));

		// do it soulbound to make sure that works
		vm.expectEmit(address(locksmith));
		emit ILocksmith.KeyMinted(address(this), 0, 0, address(0x1337));
		locksmith.copyKey(0, 0, address(0x1337), true); 
	
		// has the key been copied?	
		assertEq(1, locksmith.balanceOf(address(0x1337), 0));
		assertEq(2, locksmith.keySupply(0));
		assertEq(2, locksmith.getHolders(0).length);
		assertEq(0, locksmith.getKeysForHolder(address(0x1337))[0]);
		assertEq(1, locksmith.getKeysForHolder(address(this)).length);

		// is it soulbind?
		assertEq(1, locksmith.getSoulboundAmount(address(0x1337), 0));
	}

	function test_SoulboundCopyCantBeSent() public {
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));

		// soulbind the existing key
		locksmith.soulbindKey(0, address(this), 0, 1);

        // do it soulbound to make sure that works
        locksmith.copyKey(0, 0, address(this), true);

		// both are soulbound, send will fail
		vm.expectRevert(SoulboundTransferBreach.selector);
		locksmith.safeTransferFrom(address(this), address(0x1337), 0, 1, '');
	}
	
	//////////////////////////////////////////////
	// Key Burning 
	//////////////////////////////////////////////

	function test_OnlyRootCanBurnKeys() public {
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(0x1337));
		vm.expectRevert(KeyNotHeld.selector);
		locksmith.burnKey(0, 0, address(0x1337), 1);	
	}

	function test_BurnTargetMustHoldKey() public {
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));
		vm.expectRevert();
		locksmith.burnKey(0, 0, address(0x1337), 1);	
	}

	function test_KeyBurnedMustBeOnRing() public {
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));
		locksmith.createKeyRing(stb("My Key Ring 2"), stb("Master Key 2"), '', address(this));

		vm.expectRevert(InvalidRingKey.selector);
		locksmith.burnKey(0, 1, address(this), 1);
	}

	function test_BurnKeySuccess() public {
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));
		locksmith.copyKey(0, 0, address(0x1337), false);

		// preconditions
		assertEq(1, locksmith.balanceOf(address(0x1337), 0));

		vm.expectEmit(address(locksmith));
		emit ILocksmith.KeyBurned(address(this), 0, 0, address(0x1337), 1);
		locksmith.burnKey(0, 0, address(0x1337), 1);

		// post conditions
		assertEq(0, locksmith.balanceOf(address(0x1337), 0));
		assertEq(address(this), locksmith.getHolders(0)[0]);
		assertEq(1, locksmith.getHolders(0).length);
	}

	function test_IrrevocablePermissionsRootKeyBurned() public {
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));
		locksmith.burnKey(0, 0, address(this), 1);

		// ive made this permission set immutable!
		vm.expectRevert(KeyNotHeld.selector);
		locksmith.copyKey(0, 0, address(this), false);
	}

	function test_SoulboundKeysCanBurnButKeepsBinding() public {
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));
		locksmith.soulbindKey(0, address(this), 0, 1);

		// precondition
		assertEq(1, locksmith.getSoulboundAmount(address(this), 0));

		// burn the key, which you can do as root
		locksmith.burnKey(0, 0, address(this), 1);
	
		// post condition, keeps the binding configuration	
		assertEq(1, locksmith.getSoulboundAmount(address(this), 0));
	}

	function test_RingValidationRequiresValidKeys() public {
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));
		locksmith.createKey(0, stb('Second'), '', address(this), false);
		locksmith.createKey(0, stb('Third'), '', address(this), false);
		locksmith.createKey(0, stb('Fourth'), '', address(this), false);
		locksmith.createKeyRing(stb("My Key Ring 2"), stb("Master Key 2"), '', address(this));

		uint256[] memory keys = new uint256[](3);
	   	keys[0] = 0;
		keys[1] = 1;
		keys[2] = 10;	
		vm.expectRevert(InvalidRingKeySet.selector);
		locksmith.validateKeyRing(0, keys, true);

		keys[2] = 4; // valid key, bad ring	
		vm.expectRevert(InvalidRingKeySet.selector);
		locksmith.validateKeyRing(0, keys, true);

		// success
		keys[2] = 2; 
		assertEq(true, locksmith.validateKeyRing(0, keys, true));
	}

	/**
     * stb (String to Bytes32) 
     *
     * https://ethereum.stackexchange.com/questions/9142/how-to-convert-a-string-to-bytes32
     *
     * @param source the string you want to convert
     * @return result the equivalent result of the same using ethers.js
     */
    function stb(string memory source) internal pure returns (bytes32 result) {
        // Note: I'm not using this portion because there isn't
        // a use case where this will be empty.
        // bytes memory tempEmptyStringTest = bytes(source);
        //if (tempEmptyStringTest.length == 0) {
        //    return 0x0;
        // }

        assembly {
            result := mload(add(source, 32))
        }
    }
}
