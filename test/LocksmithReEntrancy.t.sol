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

		// post conditions
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

	}

	function test_ReEnterCreateKeyAfterCreatingKeyDoesntDuplicate public {

	}

	function test_ReEnterBurnKeyAfterCreatingKeyWorksFine public {

	}

	function test_ReEnterCopyKeyAfterCreateKeyWorks public {

	}	
	
	//////////////////////////////////////////////
	// Re-entering everything after a copying a key 
	//////////////////////////////////////////////

	function test_ReEnterCopyKeyAfterCopyKeyWorks public {

	}

	function test_ReEnterCreateRingAfterCopyKeyWorks public {

	}

	function test_ReEnterBurnKeyAfterCopyKeyWorks public {

	}

	function test_ReEnterCreateKeyAfterCopyKeyWorks public {

	}

	//////////////////////////////////////////////
	// Re-entering everything after burning a key 
	//////////////////////////////////////////////

	function test_ReEnterCreateRingAfterBurnKeyIsSane public {

	}

	function test_ReEnterCopyAfterBurnWorksAsExpected public {

	}

	function test_ReEnterBurnAfterBurnWorks public {

	}

	function test_ReEnterCreateKeyAfterBurnWorks public {

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
