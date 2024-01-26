// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

///////////////////////////////////////////////////////////
// IMPORTS
import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

import "./interfaces/ILocksmith.sol";
import "./interfaces/IKeyLocker.sol";
///////////////////////////////////////////////////////////

/**
 * KeyLocker 
 */
contract KeyLocker is IKeyLocker, ERC1155Holder {
    constructor() {}

	/**
     * supportsInterface
     *
     * @param interfaceId the interface identifier you want to check support for
     * @return true if the identifier is within the interface support.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC1155Holder) returns (bool) {
        return interfaceId == type(IKeyLocker).interfaceId || 
			super.supportsInterface(interfaceId); 
    }

    ////////////////////////////////////////////////////////
    // Locker methods 
    //
    // These methods are designed for locker interactions. 
    // Implementations of IKeyLocker are assumed to be implementing
    // IERC1155Holder, and use onERC1155Received as way to ensure
    // a proper key deposit before initiating the locker.
    ////////////////////////////////////////////////////////
    
    /**
     * useKeys 
     *
     * A message sender is assumed to be calling this method while holding
     * a soulbound version of the key the expect to use. If held, the caller's
     * provided destination and calldata will be used to *send* the key
     * into the destination contract with associated calldata.
     *
     * It is *critical* that this interface is not extended to otherwise delegate calls
     * or call other contracts from the Locker because the locker will also hold other
     * keys.
     *
     * It is fully expected that the key will be returned to the locker by the end of
     * the transaction, or the entire transction will revert. This protects the key
     * from being arbitrarily stolen.
     *
     * It will also ensure that at the end of the transaction the message sender is
     * still holding the soulbound key, as to ensure malicious transactions cannot
     * use the Locker to somehow strip you of the permission you are using.
     *
     * It is not explicitly enforced that *other* keys cannot be removed from the caller
     * for composability. When using a root key locker for a trust, it is critical to
     * trust the destination contract.
     *
     * This method can revert for the following reasons:
     * - InsufficientKeys(): The key locker doesn't currently hold keyId from the provided locksmith.
     * - KeyNotHeld(): The message sender doesn't hold the proper key to use the locker.
     * - KeyNotReturned(): The instructions didn't result in the key being returned. 
     * - CallerKeyStripped(): The instructions resulted in the message caller losing their key.
     *
     * @param locksmith the dependency injected locksmith to use.
     * @param keyId the key ID you want to action
     * @param amount the amount of keys to borrow from the locker
     * @param destination the target address to send the key, requiring it be returned
     * @param data the encoded calldata to send along with the key to destination.
     */
    function useKeys(address locksmith, uint256 keyId, uint256 amount, address destination, bytes memory data) external {
        ILocksmith l = ILocksmith(locksmith); 

        // get the start key balance. At the end, we have to have at least this many keys to remain whole.
        // this means that you can't borrow a key, redeem the rest of the same type with the root key 
        // in the same transaction, and then return the borrowed key. This is a trade-off against only
        // being able to locker one key at a time. In this above "bug" scenario, the operator should return
        // the borrowed key before redeeming the rest.
        uint256 startKeyBalance  = l.balanceOf(address(this), keyId);
        uint256 startUserBalance = l.balanceOf(msg.sender, keyId);

        // ensure that the locker key even exists
		if(startKeyBalance < amount) {
			revert InsufficientKeys();
		}

        // make sure the caller is holding the key, or the root key
        if(!l.hasKeyOrRoot(msg.sender, keyId)) {
			revert KeyNotHeld();
		}

        // run the calldata to destination while sending a key
        // note: this is re-entrant as we can't really trust
        // the destination.
        emit KeyLockerLoan(msg.sender, locksmith, keyId, amount, destination);
        IERC1155(locksmith).safeTransferFrom(address(this), destination, keyId, amount, data);

        // ensure that the key has been returned. we define this by having at least as many keys as we started with,
        // allowing additional keys of that type to be deposited during the loan, for whatever reason.
        // also ensure the operator hasn't been stripped of their keys.
        // this limits the user of the locker to have the ability to reduce your permission count
        // for instance, if I have two root keys, I can't use the root key in the locker to burn a root key out of
        // my wallet. this applies when holding a root key - but to the key in question and not root. if
        // a key could be used to escalate back to generic root permissions (via a use of a contractbound root key), 
        // that would enable the destination to remove the root key from the caller. Giving ring keys unfettered 
        // root escalation or specifically to key management functions needs to be considered with care and isn't advised.
		if(l.balanceOf(address(this), keyId) < startKeyBalance) {
			revert KeyNotReturned();
		}
		if(l.balanceOf(msg.sender, keyId) < startUserBalance) {
			revert CallerKeyStripped();
		}
    }

    /**
     * redeemKeys 
     *
     * If a key is held in the locker for use, only a root key holder can remove it. 
     * This process is known as "redemption" as the root key is used to redeem
     * the key out of the contract and deactivate the locker for it. It does not "cost"
     * the redeemer posession of their root key. The implication of this is that the 
     * returned key is *not* soulbound to the receiver, and must be handled accordingly. 
     * Direct redemption by an EOA is a security concern because it leaves the key unbound
     * at the end of the transaction and could be otherwised signed away. If an agent 
     * isn't handling the locker, users and UIs should instead call Locksmith#burnKey
     * to safely eliminate the key from the locker.
     *
     * The reason only a root key can remove the key is due to security. It is assumed
     * that an unbound key can be put into the locker by anyone, as only the root key
     * holder can create unbound keys. However, we want to avoid situations where niave key holders
     * can sign a transaction or message that steals the extra key in any way. A properly segmented
     * wallet EOA won't be holding a root key, and such using the key locker is safe even against
     * malicious transactions.
     *
     * This method can revert for the following reasons:
     * - InsufficientKeys(): The key locker doesn't currently hold keyId from the provided locksmith.
     * - KeyNotHeld(): The message sender doesn't hold the associated root key 
     * - InvalidRing(): The message sender is attempting to redeem a key with the wrong root key.
	 * - KeyNotRoot(): The message sender is attempting to redeem a key not using a root key.
     *
     * @param locksmith the dependency injected locksmith to use
     * @param rootKeyId the root key ID you are claiming to use to redeem
     * @param keyId the key ID to redeem.
     */
    function redeemKeys(address locksmith, uint256 rootKeyId, uint256 keyId, uint256 amount) external {
        ILocksmith l = ILocksmith(locksmith);
			
		// can't redeem zero
        if(amount < 1) {
			revert InvalidInput();
		}
       
		// make sure the key used is actually a root key
        bool isValidRoot = l.isRootKey(rootKeyId);
		uint256 rootRing = l.getRingId(rootKeyId);
		if (!isValidRoot) {
			revert KeyNotRoot(); 
		}
        
		// make sure the caller is actually holding the root key
		if (l.balanceOf(msg.sender, rootKeyId) < 1) {
			revert KeyNotHeld();
		}	
		
		// validate that the redeeming key is on the root ring,
		// and you can redeem root keys here
		uint256[] memory keys = new uint256[](1);
		keys[0] = keyId;
		l.validateKeyRing(rootRing, keys, true);

		// make sure we can even redeem this many 
		if(l.balanceOf(address(this), keyId) < amount) {
			revert InsufficientKeys();
		}

        // send the redeemed keys to the message sender. they are not soulbound.
        IERC1155(locksmith).safeTransferFrom(address(this), msg.sender, keyId, amount, '');

        // emit the final event for records
        emit KeyLockerWithdrawal(msg.sender, locksmith, rootKeyId, keyId, amount);
    }

    ////////////////////////////////////////////////////////
    // KEY CONSUMPTION
    ////////////////////////////////////////////////////////
    
    /**
     * onERC1155Received
     *
     * Sending a key into this method assumes you want to create a key locker.
     * This method also detects when to just quietly expect an awaiting key
	 * that was already loaned out.
     *
     * It's possible to create lockers when a key is loaned out, and after
     * the loaned key has been returned but control flow hasn't returned
     * to the end of _useKey. This means that *awaitingKey* can be still be
     * true even when the key has technically been returned, and keys can
     * still come in of other varieties without any implications.
	 *
	 * The message sender will always be a healthy Locksmith.
     *
     * @param from     where the key is coming from
     * @param keyId    the id of the key that was deposited
     * @param count    the number of keys sent
     * @return the function selector to prove valid response
     */
    function onERC1155Received(address, address from, uint256 keyId, uint256 count, bytes memory)
        public virtual override returns (bytes4) {
        // make sure the locksmith is a proper one
		if(!IERC165(msg.sender).supportsInterface(type(ILocksmith).interfaceId)) {
			revert InvalidInput();
		}
				
		// we are going to accept this key no matter what.
        emit KeyLockerDeposit(from, msg.sender, keyId, count);

        // success
        return this.onERC1155Received.selector;
    }

	function onERC1155BatchReceived(address,address from ,uint256[] memory ids, uint256[] memory values, bytes memory)
		public virtual override returns (bytes4) {
		
		if(!IERC165(msg.sender).supportsInterface(type(ILocksmith).interfaceId)) {
			revert InvalidInput();
		}

		// we are going to accept all the keys no matter what.
		for(uint256 x = 0; x < ids.length; x++) {
			emit KeyLockerDeposit(from, msg.sender, ids[x], values[x]);
		}

		// success
		return this.onERC1155BatchReceived.selector;
	}
} 
