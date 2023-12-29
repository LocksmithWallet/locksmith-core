//SPDX-License-Identifier: MIT 
pragma solidity ^0.8.23;

import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ILocksmith} from '../../src/interfaces/ILocksmith.sol';

///////////////////////////////////////////////////////////
// LocksmithReEnterCreateKey
//
// This contract, upon receiving a key from a supposed Locksmith,
// will immediate re-enter the function to create keys.
///////////////////////////////////////////////////////////
contract LocksmithReEnterCreateKey is ERC1155Holder {
    constructor() {}

	/**
     * onERC1155Received
     *
     * Will trigger when this contract is sent a key. 
     *
	 * @param operator the message sender, which should be the locksmith
     * @return the function selector to prove valid response
     */
    function onERC1155Received(address operator, address, uint256, uint256, bytes memory)
		public virtual override returns (bytes4) {
		// just immediate assume the operator is who we are attacking here.
		ILocksmith(operator).createKey(0, bytes32(0), '', address(0x1337), false);
		return this.onERC1155Received.selector;
	}
}
