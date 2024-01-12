// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

///////////////////////////////////////////////////////
// Dependencies 
///////////////////////////////////////////////////////
import { 
	ILocksmith,
	KeyNotHeld
} from 'src/interfaces/ILocksmith.sol';

// We are going to use the standard OZ ERC1155 implementation,
// and then override the transfer callbacks to enforce soulbinding.
import "openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";

// This error is thrown when a token address does not comply with
// the ILocksmith interface.
error InvalidLocksmith();

/**
 * LocksmithKeyChecker
 *
 * Developers can extend this contract to introduce modifiers for Locksmith
 * token gating in their contracts.
 */
contract LocksmithKeyChecker {

	/**
	 * onlyValidLocksmiths
	 *
	 * Use this modifier especially when receiving keys via onERC1155Received()
	 * events. Add this to ensure that the tokens received have compliant
	 * Locksmith interfaces.
	 *
	 * If it does not implement the ILocksmith interface, it will revert
	 * with InvalidLocksmith().
	 *
	 * @param locksmith the contract address of the token received.
	 */

	/**
	 * onlyKeyHolder
	 *
	 * Add this modifier to your functions if you want to ensure that the
	 * caller is holding a specific key minted by a certain locksmith.
	 *
	 * If conditions are not met, the transaction fails with KeyNotHeld().
	 *
	 * @param locksmith the address of the locksmith, implementing ILocksmith.
	 * @param keyId     the key id from the locksmith the message sender must hold.
	 */
	modifier onlyKeyHolder(address locksmith, uint256 keyId) {
		if (ILocksmith(locksmith).balanceOf(msg.sender, keyId) < 1) {
			revert KeyNotHeld();
		}
		_;
	}	
	
	/**
	 * onlyKeyOrRootHolder
	 *
	 * Add this modifier to your functions if you want to ensure that the
	 * caller is holding a specific key minted by a certain locksmith, or
	 * optionally the root key of the associated key ring. This enables
	 * admin-level escalation to the key ring root key holder.
     *
	 * If conditions are not met, the transaction fails with KeyNotHeld().
	 *
	 * @param locksmith the address of the locksmith, implementing ILocksmith.
	 * @param keyId     the key id denoting the key or ring root key needed. 
	 */
	modifier onlyKeyOrRootHolder(address locksmith, uint256 keyId) {
		if (!ILocksmith(locksmith).hasKeyOrRoot(msg.sender, keyId)) {
			revert KeyNotHeld();
		}
		_;
	}	
}
