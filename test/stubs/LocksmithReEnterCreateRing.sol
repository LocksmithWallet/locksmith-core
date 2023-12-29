//SPDX-License-Identifier: MIT 
pragma solidity ^0.8.23;

import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ILocksmith} from '../../src/interfaces/ILocksmith.sol';
import {console} from 'forge-std/Test.sol';

///////////////////////////////////////////////////////////
// LocksmithReEnterCreateRing 
//
// This contract, upon receiving a key from a supposed Locksmith,
// will immediate re-enter the function to create Rings.
///////////////////////////////////////////////////////////
contract LocksmithReEnterCreateRing is ERC1155Holder {
	constructor() {}

	/**
     * onERC1155Received
     *
     * Will trigger when this contract is sent a key. 
     * @return the function selector to prove valid response
     */
    function onERC1155Received(address, address, uint256, uint256, bytes memory)
		public virtual override returns (bytes4) {

		// just immediate assume the operator is who we are attacking here.
		ILocksmith(msg.sender).createKeyRing(bytes32(0), bytes32(0), '', address(0x1337));
		return this.onERC1155Received.selector;
	}
}
