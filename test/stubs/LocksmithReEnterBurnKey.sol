//SPDX-License-Identifier: MIT 
pragma solidity ^0.8.23;

import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ILocksmith} from '../../src/interfaces/ILocksmith.sol';

///////////////////////////////////////////////////////////
// LocksmithReEnterBurnKey
//
// This contract, upon receiving a key from a supposed Locksmith,
// will immediate re-enter the function to burn keys.
///////////////////////////////////////////////////////////
contract LocksmithReEnterBurnKey is ERC1155Holder {
    uint256 public rootKeyId;
	uint256 public keyTarget;
	address public holderTarget;

	bool public isReady;

	constructor(uint256 _rootKeyId, uint256 _keyTarget, address _holderTarget) {
		rootKeyId = _rootKeyId;
		keyTarget = _keyTarget;
		holderTarget = _holderTarget;
		isReady = false;	
	}

	function ready() external {
		isReady = true;
	}

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
			
		if (isReady) {
			// just immediate assume the operator is who we are attacking here.
			ILocksmith(operator).burnKey(rootKeyId, keyTarget, holderTarget, 1);
		}
		return this.onERC1155Received.selector;
	}
}
