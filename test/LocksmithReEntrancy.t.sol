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
import "./stubs/LocksmithReEnterBurnKey.sol";
import "./stubs/LocksmithReEnterCreateRing.sol";
import "./stubs/LocksmithReEnterCreateKey.sol";
import "./stubs/LocksmithReEnterCopyKey.sol";

contract LocksmithReEntrancyTest is Test, ERC1155Holder {
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
	// Re-entering everything after creating a ring 
	//////////////////////////////////////////////
    
	function test_WontDuplicateRingAfterCreation() public {
		LocksmithReEnterCreateRing attacker = new LocksmithReEnterCreateRing();
		
		(bool isValid, bytes32 keyName, uint256 ringId, bool isRoot, uint256[] memory keys) =
			locksmith.inspectKey(1);

		// pre conditions
		assertEq(false, isValid);
		assertEq(bytes32(0), keyName);
		assertEq(0, ringId);
		assertEq(false, isRoot);
		assertEq(0, keys.length);

		// do the re-entrancy	
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(attacker));

		// the attacker will hold key ID 1, for ring ID 1, and not key 0.
		assertEq(1, locksmith.balanceOf(address(0x1337), 1));	
		assertEq(0, locksmith.balanceOf(address(0x1337), 0));

		// we can inspect the second ring and it is coherent
		(isValid, keyName, ringId, isRoot, keys) = locksmith.inspectKey(1);

		// post conditions
		assertEq(true, isValid);
		assertEq(bytes32(0), keyName);
		assertEq(1, ringId);
		assertEq(true, isRoot);
		assertEq(1, keys[0]);
		assertEq(1, keys.length);
	}

	function test_CantCopyWrongKeyAfterCreateRing() public {
		LocksmithReEnterCopyKey attacker = new LocksmithReEnterCopyKey(0, 0);
		attacker.ready();
        (bool isValid, bytes32 keyName, uint256 ringId, bool isRoot, uint256[] memory keys) =
            locksmith.inspectKey(0);

        // pre conditions
        assertEq(false, isValid);
        assertEq(bytes32(0), keyName);
        assertEq(0, ringId);
        assertEq(false, isRoot);
        assertEq(0, keys.length);

        // do the re-entrancy
        locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(attacker));

        // the attacker will hold key ID 0, for ring ID 0
        assertEq(1, locksmith.balanceOf(address(0x1337), 0));
        assertEq(1, locksmith.balanceOf(address(attacker), 0));
	}

	function test_CantCreateDuplicateKeyAfterCreateRing() public {
		LocksmithReEnterCreateKey attacker = new LocksmithReEnterCreateKey(0);
		attacker.ready();

		(bool isValid, bytes32 keyName, uint256 ringId, bool isRoot, uint256[] memory keys) =
            locksmith.inspectKey(1);

        // pre conditions
        assertEq(false, isValid);
        assertEq(bytes32(0), keyName);
        assertEq(0, ringId);
        assertEq(false, isRoot);
        assertEq(0, keys.length);
        
		// do the re-entrancy
        locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(attacker));

		// its going to take the key, and try to create another one,
		// which it can do, as ID one
		// post conditions
		(isValid, keyName, ringId, isRoot, keys) = locksmith.inspectKey(1);
		assertEq(true, isValid);
		assertEq(bytes32(0), keyName);
		assertEq(0, ringId);
		assertEq(false, isRoot);
		assertEq(0, keys[0]);
		assertEq(1, keys[1]);
		assertEq(2, keys.length);
		assertEq(1, locksmith.balanceOf(address(0x1337), 1));
		assertEq(1, locksmith.getHolders(1).length);
	}

	function test_BurningReceivedRootKeyHasSaneResult() public {
		LocksmithReEnterBurnKey attacker = new LocksmithReEnterBurnKey(0, 0);
		attacker.setTarget(address(attacker));
		attacker.ready();

		(bool isValid, bytes32 keyName, uint256 ringId, bool isRoot, uint256[] memory keys) =
            locksmith.inspectKey(0);

        // pre conditions
        assertEq(false, isValid);
        assertEq(bytes32(0), keyName);
        assertEq(0, ringId);
        assertEq(false, isRoot);
        assertEq(0, keys.length);
        
		// do the re-entrancy
        locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(attacker));

        // post conditions
		(isValid, keyName, ringId, isRoot, keys) = locksmith.inspectKey(0);
        assertEq(true, isValid);
        assertEq(stb('Master Key'), keyName);
        assertEq(0, ringId);
        assertEq(true, isRoot);
		assertEq(0, locksmith.keySupply(0));
		assertEq(0, locksmith.balanceOf(address(attacker), 0));
	}

	//////////////////////////////////////////////
	// Re-entering everything after creating a key 
	//////////////////////////////////////////////

	function test_ReEnterCreateRingAfterCreateKeyIsLegit() public {	
		// create the ring
		locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));

		// build the attacker
		LocksmithReEnterCreateRing attacker = new LocksmithReEnterCreateRing();
		
		// pre conditions	
		(bool isValid, bytes32 keyName, uint256 ringId, bool isRoot, uint256[] memory keys) =
			locksmith.inspectKey(2);
		assertEq(false, isValid);
		assertEq(bytes32(0), keyName);
		assertEq(0, ringId);
		assertEq(false, isRoot);
		assertEq(0, keys.length);
	
		// do the re-entrancy attack
		locksmith.createKey(0, stb('Key Name'), '', address(attacker), false);

		// they simply would have created a new ring, with key ID 2, not 1
		(isValid, keyName, ringId, isRoot, keys) = locksmith.inspectKey(2);
		assertEq(true, isValid);
		assertEq(bytes32(0), keyName);
		assertEq(1, ringId);
		assertEq(true, isRoot);
		assertEq(1, keys.length);
	}

	function test_ReEnterCreateKeyAfterCreatingKeyDoesntDuplicate() public {
        // build the attacker
        LocksmithReEnterCreateKey attacker = new LocksmithReEnterCreateKey(0);

		// create the ring, copy the key to the attacker
        locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));
		locksmith.copyKey(0, 0, address(attacker), false);
		
		// ready the attacker				  
		attacker.ready();

        // pre conditions
        (bool isValid, bytes32 keyName, uint256 ringId, bool isRoot, uint256[] memory keys) =
            locksmith.inspectKey(1);
        assertEq(false, isValid);
        assertEq(bytes32(0), keyName);
        assertEq(0, ringId);
        assertEq(false, isRoot);
        assertEq(0, keys.length);

        // do the re-entrancy attack
        locksmith.createKey(0, stb('Key Name'), '', address(attacker), false);

        // they simply would have created a new ring, with key ID 2, not 1 
        (isValid, keyName, ringId, isRoot, keys) = locksmith.inspectKey(2);
        assertEq(true, isValid);
        assertEq(bytes32(0), keyName);
        assertEq(0, ringId);
        assertEq(false, isRoot);
        assertEq(3, keys.length);
        assertEq(0, keys[0]);
        assertEq(1, keys[1]);
        assertEq(2, keys[2]);
	}

	function test_ReEnterBurnKeyAfterCreatingKeyWorksFine() public {
		// build the attacker
        LocksmithReEnterBurnKey attacker = new LocksmithReEnterBurnKey(0, 1);

        // create the ring, copy the key to the attacker
        locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));
        locksmith.copyKey(0, 0, address(attacker), false);

        // ready the attacker
		attacker.setTarget(address(attacker));
        attacker.ready();

		// pre conditions
        (bool isValid, bytes32 keyName, uint256 ringId, bool isRoot, uint256[] memory keys) =
            locksmith.inspectKey(1);
        assertEq(false, isValid);
        assertEq(bytes32(0), keyName);
        assertEq(0, ringId);
        assertEq(false, isRoot);
        assertEq(0, keys.length);

		// create the key, re-entrancy attack the burn function 
		locksmith.createKey(0, stb('Key'), '', address(attacker), false);

		// it was created
		(isValid, keyName, ringId, isRoot, keys) = locksmith.inspectKey(1);
		assertEq(true, isValid);
		assertEq(stb('Key'), keyName);
		assertEq(0, ringId);
		assertEq(false, isRoot);
		assertEq(2, keys.length);

		// but no one holds it
		assertEq(0, locksmith.keySupply(1));
	}

	function test_ReEnterCopyKeyAfterCreateKeyWorks() public {
		// build the attacker
        LocksmithReEnterCopyKey attacker = new LocksmithReEnterCopyKey(0, 1);

        // create the ring, copy the key to the attacker
        locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));
        locksmith.copyKey(0, 0, address(attacker), false);

        // ready the attacker
        attacker.ready();

        // pre conditions
        (bool isValid, bytes32 keyName, uint256 ringId, bool isRoot, uint256[] memory keys) =
            locksmith.inspectKey(1);
        assertEq(false, isValid);
        assertEq(bytes32(0), keyName);
        assertEq(0, ringId);
        assertEq(false, isRoot);
        assertEq(0, keys.length);

        // create the key, re-entrancy attack the copy function
        locksmith.createKey(0, stb('Key'), '', address(attacker), false);

        // it was created
        (isValid, keyName, ringId, isRoot, keys) = locksmith.inspectKey(1);
        assertEq(true, isValid);
        assertEq(stb('Key'), keyName);
        assertEq(0, ringId);
        assertEq(false, isRoot);
        assertEq(2, keys.length);

		// and now the attackers destination wallet also has the key
		assertEq(2, locksmith.keySupply(1));
		assertEq(2, locksmith.getHolders(1).length);
		assertEq(address(attacker), locksmith.getHolders(1)[0]);
		assertEq(address(0x1337), locksmith.getHolders(1)[1]);
	}	
	
	//////////////////////////////////////////////
	// Re-entering everything after a copying a key 
	//////////////////////////////////////////////

	function test_ReEnterCopyKeyAfterCopyKeyWorks() public {
		 // build the attacker
        LocksmithReEnterCopyKey attacker = new LocksmithReEnterCopyKey(0, 0);

        // create the ring, copy the key to the attacker
        locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));
        locksmith.copyKey(0, 0, address(attacker), false);

        // ready the attacker
        attacker.ready();

        // pre conditions
		assertEq(2, locksmith.keySupply(0));

        // create the key, re-entrancy attack the copy function
        locksmith.copyKey(0, 0, address(attacker), false);

        // it was created twice, to the attacker address
        assertEq(4, locksmith.keySupply(0));
        assertEq(3, locksmith.getHolders(0).length);
        assertEq(address(0x1337), locksmith.getHolders(0)[2]);
	}

	function test_ReEnterCreateRingAfterCopyKeyWorks() public {
		// create the ring
        locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));

        // build the attacker
        LocksmithReEnterCreateRing attacker = new LocksmithReEnterCreateRing();

        // pre conditions
		assertEq(0, locksmith.keySupply(1));

        // do the re-entrancy attack
        locksmith.copyKey(0, 0, address(attacker), false);

		// created a ring, harmlessly	
		assertEq(1, locksmith.keySupply(1));
        (bool isValid, bytes32 keyName, uint256 ringId, bool isRoot, uint256[] memory keys) = locksmith.inspectKey(1);
        assertEq(true, isValid);
        assertEq(bytes32(0), keyName);
        assertEq(1, ringId);
        assertEq(true, isRoot);
        assertEq(1, keys.length);
	}

	function test_ReEnterBurnKeyAfterCopyKeyWorks() public {
		 // build the attacker
        LocksmithReEnterBurnKey attacker = new LocksmithReEnterBurnKey(0, 0);

        // create the ring, copy the key to the attacker
        locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));

        // ready the attacker
        attacker.setTarget(address(attacker));
        attacker.ready();

        // pre conditions
		assertEq(1, locksmith.keySupply(0));

        // copy the key, re-entrancy attack the burn function
        locksmith.copyKey(0, 0, address(attacker), false);

        // It was actually just burned out
	   	assertEq(1, locksmith.keySupply(0));
		assertEq(0, locksmith.balanceOf(address(attacker), 0));
	}

	function test_ReEnterCreateKeyAfterCopyKeyWorks() public {
		 // build the attacker
        LocksmithReEnterCreateKey attacker = new LocksmithReEnterCreateKey(0);

        // create the ring, copy the key to the attacker
        locksmith.createKeyRing(stb("My Key Ring"), stb("Master Key"), '', address(this));

        // ready the attacker
        attacker.ready();

        // pre conditions
		assertEq(1, locksmith.keySupply(0));
		assertEq(0, locksmith.keySupply(1));
        
		// do the re-entrancy attack
        locksmith.copyKey(0, 0, address(attacker), false);

		// post conditions
		assertEq(2, locksmith.keySupply(0));
		assertEq(1, locksmith.keySupply(1));
		assertEq(1, locksmith.balanceOf(address(0x1337), 1));
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
