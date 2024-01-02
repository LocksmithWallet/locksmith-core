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
    }

	//////////////////////////////////////////////
	// Post Deployment
	//////////////////////////////////////////////

    function test_EmptyKeyLockerState() public {
	
	}
	
	//////////////////////////////////////////////
	// Key Deposits 
	//////////////////////////////////////////////

	function test_KeyDepositMustBeLocksmith() public {

	}

	function test_SuccessfulDeposit() public {

	}

	function test_SuccessfulDepositMultiple() public {

	}

	//////////////////////////////////////////////
	// Key Usage and Returns 
	//////////////////////////////////////////////

	function test_KeyMustExistToBorrow() public {

	}

	function test_CallerMustHoldKeyOrRoot() public {

	}

	function test_DestinationMustReturnKey() public {

	}

	function test_CallerMusntLoseKeyUsed() public {

	}

	function test_ReEnteringOnSameKeyMustReturnBoth() public {

	}

	function test_ReEnteringOnDifferentKeyMustReturnBoth() public {

	}
	
	//////////////////////////////////////////////
	// Key Redemptions 
	//////////////////////////////////////////////
	
	function test_KeyMustExistToRedeem() public {

	}

	function test_MustRedeemAtLeastOneKey() public {

	}

	function test_RedemptionKeyMustBeRoot() public {

	}

	function test_CallerMustHoldRootKey() public {

	}

	function test_SuccessfulRedemption() public {

	}
	
	function test_CantRedeemInLoanWithoutDeposit() public {

	}
}
