// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Locksmith} from "../src/Locksmith.sol";

contract LocksmithUnitTest is Test {
    Locksmith public locksmith;

    function setUp() public {
        locksmith = new Locksmith();
    }

    function test_EmptyLocksmithState() public {
        assertEq(true, true);
    }

	function test_SuccessfulRingCreation() public {

	}

	function test_RingsAreSegmentedLogically() public {

	}

	function test_CantCreateKeyRingWithoutHoldingRootKey() public {

	}

	function test_CreatingRingKeyMustUseRoot() public {

	}

	function test_SuccessfulRingKeyCreation() public {

	}

	function test_CanSendKeys() public {

	}

	function test_MustBeRootToSoulbindKeys() public {

	}

	function test_MustSoulbindValidRingKeysOnly() public {

	}

	function test_CantSendSoulboundKeys() public {

	}

	function test_PostMintSoulbindingPreventsTransfer() public {

	}

	function test_UsingAmountZeroRemovesBinding() public {

	}

	function test_CanSendSoulboundWithSufficientBalance() public {

	}

	function test_MustHoldRootKeyToCopy() public {

	}

	function test_KeyUsedForCopyMustBeRoot() public {

	}

	function test_CopiedKeyMustBeOnRing() public {

	}

	function test_SuccessfulKeyCopies() public {

	}

	function test_SoulboundCopyCantBeSent() public {

	}

	function test_OnlyRootCanBurnKeys() public {
		
	}

	function test_BurnTargetMustHoldKey() public {

	}

	function test_KeyBurnedMustBeOnRing() public {

	}

	function test_BurnKeySuccess() public {

	}

	function test_IrrevocablePermissionsRootKeyBurned() public {

	}

	function test_SoulboundKeysCanBurnButKeepsBinding() public {

	}

	function test_RingValidationRequiresValidRing() public {

	}
	
	function test_RingValidationRequiresValidKeys() public {

	}

	function test_RingValidationRequiresProperKeys() public {

	}

	function test_RingValidationSuccess() public {

	}

	function test_BigStateTest() public {

	}
}
