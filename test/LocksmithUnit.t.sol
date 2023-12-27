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
}
