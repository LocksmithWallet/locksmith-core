// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console2} from 'forge-std/Test.sol';
import "openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {IKeyLocker} from '../src/interfaces/IKeyLocker.sol';
import {ILocksmith} from '../src/interfaces/ILocksmith.sol';
import {
    KeyNotHeld,
    KeyNotRoot,
    InvalidRing,
    InvalidRingKey,
    InvalidRingKeySet,
    SoulboundTransferBreach
} from 'src/interfaces/ILocksmith.sol';
import {Locksmith} from '../src/Locksmith.sol';
import {
	InsufficientKeys,
	KeyNotReturned,
	CallerKeyStripped,
	InvalidInput
} from 'src/interfaces/IKeyLocker.sol';
import {KeyLocker} from '../src/KeyLocker.sol';
import {ShadowKey} from './stubs/ShadowKey.sol';
import {KeyTaker}  from './stubs/KeyTaker.sol';
import {CleverKeyTaker} from './stubs/CleverKeyTaker.sol';
import {NiceDoubleLoan} from './stubs/NiceDoubleLoan.sol';
import {RedeemSneak} from './stubs/RedeemSneak.sol';

contract KeyLockerUnitTest is Test, ERC1155Holder {
    Locksmith public locksmith;
	KeyLocker public keyLocker;

	receive() external payable {
        // needed to be able to take money
    }

    function setUp() public {
        locksmith = new Locksmith();
		keyLocker = new KeyLocker();

		// fund our accounts
        vm.deal(address(this), 10 ether);

		// create a default ring
		locksmith.createKeyRing(stb('My Ring'), stb('Root'), '', address(this));
    }

	//////////////////////////////////////////////
	// Key Deposits 
	//////////////////////////////////////////////

	function test_KeyDepositMustBeLocksmith() public {
		// stub token
		ShadowKey shadow = new ShadowKey();
			
		// use a regular ERC1155 token, it will reject
		vm.expectRevert(InvalidInput.selector);
		shadow.mint(address(keyLocker), 0, 1, '');	
	}

	function test_SuccessfulDeposit() public {
		// pre-conditions
		assertEq(0, locksmith.balanceOf(address(keyLocker), 0));
		
		// want to make sure I have three copies
		locksmith.copyKey(0, 0, address(this), false);
		locksmith.copyKey(0, 0, address(this), false);
	
		// the key locker will accept the key
		vm.expectEmit(address(keyLocker));
		emit IKeyLocker.keyLockerDeposit(address(this), address(locksmith), 0, 1);
		locksmith.safeTransferFrom(address(this), address(keyLocker), 0, 1, '');
		
		assertEq(1, locksmith.balanceOf(address(keyLocker), 0));

		// send two and test 
		vm.expectEmit(address(keyLocker));
		emit IKeyLocker.keyLockerDeposit(address(this), address(locksmith), 0, 2);
		locksmith.safeTransferFrom(address(this), address(keyLocker), 0, 2, '');

		// post-conditions
		assertEq(3, locksmith.balanceOf(address(keyLocker), 0));
	}

	//////////////////////////////////////////////
	// Key Usage and Returns 
	//////////////////////////////////////////////

	function test_KeyMustExistToBorrow() public {
		vm.expectRevert(InsufficientKeys.selector);
		keyLocker.useKeys(address(locksmith), 0, 1, address(this), '');
	}

	function test_CallerMustHoldKeyOrRoot() public {
		// send the key in, so we don't hold it anymore
		locksmith.safeTransferFrom(address(this), address(keyLocker), 0, 1, '');

		// will not be able to borrow it, since its not held
		vm.expectRevert(KeyNotHeld.selector);
		keyLocker.useKeys(address(locksmith), 0, 1, address(this), '');
	}

	function test_DestinationMustReturnKey() public {
		// copy the key into the locker
		locksmith.copyKey(0, 0, address(keyLocker), false);

		// improperly useKeys where I just send it to me and do nothing
		vm.expectRevert(KeyNotReturned.selector);
		keyLocker.useKeys(address(locksmith), 0, 1, address(this), '');
	}

	function test_CallerMusntLoseKeyUsed() public {
		// will burn all holders of keys given
		KeyTaker taker = new KeyTaker();

		// give it a key
		locksmith.copyKey(0, 0, address(keyLocker), false);

		// give it to a taker - who tries to steal callers key, will revert
		vm.expectRevert(CallerKeyStripped.selector);
		keyLocker.useKeys(address(locksmith), 0, 1, address(taker), '');
	}

	function test_ReEnteringOnSameKeyMustReturnBoth() public {
		CleverKeyTaker taker = new CleverKeyTaker(0);
		NiceDoubleLoan nice = new NiceDoubleLoan(0);

		// load up with two keys to take
		assertEq(0, locksmith.balanceOf(address(keyLocker), 0));
		locksmith.copyKey(0, 0, address(keyLocker), false);
		locksmith.copyKey(0, 0, address(keyLocker), false);
		assertEq(2, locksmith.balanceOf(address(keyLocker), 0));

		// receiver will take a loan out again, but only return one.
		vm.expectRevert(KeyNotReturned.selector);
		keyLocker.useKeys(address(locksmith), 0, 1, address(taker), '');
		assertEq(2, locksmith.balanceOf(address(keyLocker), 0));

		// this one will be nice
		vm.expectEmit(address(keyLocker));
		emit IKeyLocker.keyLockerLoan(address(this), address(locksmith), 0, 1, address(nice)); 
		vm.expectEmit(address(keyLocker));
		emit IKeyLocker.keyLockerLoan(address(nice), address(locksmith), 0, 1, address(nice)); 
		vm.expectEmit(address(keyLocker));
		emit IKeyLocker.keyLockerDeposit(address(nice), address(locksmith), 0, 1);
		vm.expectEmit(address(keyLocker));
		emit IKeyLocker.keyLockerDeposit(address(nice), address(locksmith), 0, 1);
		keyLocker.useKeys(address(locksmith), 0, 1, address(nice), '');
		assertEq(2, locksmith.balanceOf(address(keyLocker), 0));
	}

	function test_ReEnteringOnDifferentKeyMustReturnBoth() public {
		CleverKeyTaker taker = new CleverKeyTaker(1);
        
		// load up with two keys to take
        locksmith.copyKey(0, 0, address(keyLocker), false);
		locksmith.createKey(0, stb('one'), '', address(keyLocker), false);

        // receiver will take a loan out again, but only return one.
        vm.expectRevert(KeyNotReturned.selector);
        keyLocker.useKeys(address(locksmith), 0, 1, address(taker), '');
	}
	
	//////////////////////////////////////////////
	// Key Redemptions 
	//////////////////////////////////////////////
	
	function test_KeyMustExistToRedeem() public {
		vm.expectRevert(InsufficientKeys.selector);
		keyLocker.redeemKeys(address(locksmith), 0, 0, 1);
	}

	function test_MustRedeemAtLeastOneKey() public {
		vm.expectRevert(InvalidInput.selector);
		keyLocker.redeemKeys(address(locksmith), 0, 0, 0);
	}

	function test_RedemptionKeyMustBeRoot() public {
		vm.expectRevert(KeyNotRoot.selector);
		keyLocker.redeemKeys(address(locksmith), 1, 0, 1);
	}

	function test_CallerMustHoldRootKey() public {
		// put a key in the locker, and burn ours
		locksmith.copyKey(0, 0, address(keyLocker), false);
		locksmith.burnKey(0, 0, address(this), 1);
		vm.expectRevert(KeyNotHeld.selector);
		keyLocker.redeemKeys(address(locksmith), 0, 0, 1);
	}

	function test_SuccessfulRedemption() public {
		locksmith.copyKey(0, 0, address(keyLocker), false);
		vm.expectEmit(address(keyLocker));
		emit IKeyLocker.keyLockerWithdrawal(address(this), address(locksmith), 0, 0, 1);
		keyLocker.redeemKeys(address(locksmith), 0, 0, 1);
	}
	
	function test_CantRedeemInLoanWithoutDeposit() public {
		RedeemSneak bad = new RedeemSneak(1, 0);
		RedeemSneak good = new RedeemSneak(1, 1);
		locksmith.copyKey(0, 0, address(keyLocker), false);
		locksmith.copyKey(0, 0, address(keyLocker), false);

		// bad sneak will revert
		vm.expectRevert(KeyNotReturned.selector);
		keyLocker.useKeys(address(locksmith), 0, 1, address(bad), '');

		// this one won't revert
		assertEq(2, locksmith.balanceOf(address(keyLocker), 0));
		assertEq(0, locksmith.balanceOf(address(good), 0));
		keyLocker.useKeys(address(locksmith), 0, 1, address(good), '');
		assertEq(2, locksmith.balanceOf(address(keyLocker), 0));
		assertEq(1, locksmith.balanceOf(address(good), 0));
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
