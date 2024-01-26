// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.23;

///////////////////////////////////////////////////////
// Dependencies 
///////////////////////////////////////////////////////

// The locksmith keys operate on face as an ERC1155 token. The
// interface extends the ERC1155 interface such that token receiving,
// sending, holding, and off-chain indexing work as expected.
//
// Locksmith keys behave differently than the ERC1155 spec in a few important
// ways:
//
// * Tokens can be minted, burned, or soulbound by their owners at will.
// * The Locksmith contract has multiple "owners," with their own separate key rings they control.
//
// For these reasons, Locksmith keys are utilitarian in nature and shouldn't be
// considered safe for trading, or storing in regular vaults. Safe Locksmith key
// storage is provided by the "KeyLocker" which enables key holders to borrow a key
// for the duration of a transaction.
import { IERC1155 } from "openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
//
// As part of the KeyLocker strategy, we want to ensure via standards (ERC-165) that
// contracts can cleanly detect proper locksmiths, regardless of their deployment address.
// This enables a more vibrant eco-system of deployed instances, without having to worry
// about canonical network deployments.
import { IERC165 } from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

// Transactions will revert with this message when an operation
// is attempted on an invalid key ring ID.
error InvalidRing();

// Transactions will revert with this message when an operation
// is attempted by a message sender that doesn't hold the appropriate
// key.
error KeyNotHeld(); 

// Transactions will revert with this message when an operation
// is attempted that requires root, but a non-root key was used.
error KeyNotRoot();

// Transactions will revert with this message when an operation
// is attempted on a key that doesn't exist on the relevant ring.
error InvalidRingKey();

// Transactions will revert with this message when an operation
// fails validating a set of keys to a given ring.
error InvalidRingKeySet();

// Transactions will revert with this message when an operation
// results in a soulbound key amount being breached.
error SoulboundTransferBreach();

/**
 * Locksmith 
 *
 * This contract has a single responsiblity: managing the lifecycle of keys.
 * The Locksmith is an ERC1155 contract that can mint, burn, and bind permissions
 * to owners.
 *
 * Users can permissionlessly mint and manage a collection of NFTs known as
 * a "key ring." Each key ring has a root key, which gives the holder permissions
 * to mint, burn, and soulbind/unbind any other key that belongs to their
 * ring to any address at any time.
 *
 * In effect, the key ring acts as an onchain access control list. The keys
 * can be sent, delegated, and dynamically bound to any actor for any amount of
 * time - including only for a part of a single transaction.
 * 
 */
interface ILocksmith is IERC165, IERC1155 {
    ///////////////////////////////////////////////////////
    // Events
    ///////////////////////////////////////////////////////
    
    /**
     * KeyRingCreated 
     *
     * This event is emitted when a key ring is created and a root key is minted.
     *
     * @param operator  the message sender and creator of the key ring.
     * @param ringId    the resulting id of the new key ring. 
     * @param ringName  the ring's human readable name, encoded as a bytes32.
     * @param recipient the address of the root key recipient
     */
    event KeyRingCreated(address operator, uint256 ringId, bytes32 ringName, address recipient);

    /**
     * KeyMinted
     *
     * This event is emitted when a key is minted. This event
     * is also emitted when a root key is minted upon ring creation.
     *
     * The operator will always hold the root key for the ringId.
     *
     * @param operator the creator of the ring key.
     * @param ringId   the key ring ID they are creating the key on. 
     * @param keyId    the key ID that was minted by the operator. 
     * @param receiver the receiving wallet address where the keyId was deposited.
     */
    event KeyMinted(address operator, uint256 ringId, uint256 keyId, address receiver);
    
    /**
     * KeyBurned
     *
     * This event is emitted when a key is burned by the root key
     * holder. 
     *
     * @param operator the root key holder requesting the burn. 
     * @param ringId   the ring ID they are burning from.
     * @param keyId    the key ID that was burned. 
     * @param target   the address of the wallet that had keys burned. 
     * @param amount   the number of keys burned in the operation.
     */
    event KeyBurned(address operator, uint256 ringId, uint256 keyId, address target, uint256 amount);

    /**
     * SetSoulboundKeyAmount
     *
     * This event fires when the state of a soulbind key is set.
     *
     * @param operator  the root key holder that is changing the soulbinding 
     * @param keyHolder the address we are changing the binding for
     * @param keyId     the Id we are setting the binding state for
     * @param amount    the number of tokens this address must hold
     */
    event SetSoulboundKeyAmount(address operator, address keyHolder, uint256 keyId, uint256 amount);

    ///////////////////////////////////////////////////////
    // Key Operations 
    ///////////////////////////////////////////////////////
    
    /**
     * createKeyRing
     *
     * Calling this function will create a key ring with a name,
     * mint the first root key, and give it to the desginated receiver.
     *
     * @param ringName    A string defining the name of the key ring encoded as bytes32.
	 * @param rootKeyName A string denoting a human readable name of the root key. 
     * @param keyUri      The metadata URI for the new root key.
     * @param recipient   The address to receive the root key for this key ring.
     * @return the key ring ID that was created
     * @return the root key ID that was created
     */
	function createKeyRing(bytes32 ringName, bytes32 rootKeyName, string calldata keyUri, address recipient) external returns (uint256, uint256); 
    
    /**
     * createKey
     *
     * The holder of a root key can use it to generate brand new keys 
     * and add them to the root key's key ring, sending it to the 
     * destination wallets.
     *
     * This code will panic if:
     *  - the caller doesn't hold the declared root key
     *
     * @param rootKeyId The root key the sender is attempting to operate to create new keys.
     * @param keyName   An alias that you want to give the key.
	 * @param keyUri    The metadata URI for the newly created key.
     * @param receiver  address you want to receive the ring key. 
     * @param bind      true if you want to bind the key to the receiver.
     * @return the ID of the key that was created
     */
    function createKey(uint256 rootKeyId, bytes32 keyName, string calldata keyUri, address receiver, bool bind) external returns (uint256); 
    
    /**
     * copyKey
     *
     * The root key holder can call this method if they have an existing key
     * they want to copy. This allows multiple addresses to hold the same role,
     * share a set of benefits, or enables the root key holder to restore
     * the role for someone who lost their seed or access to their wallet.
     *
     * This method can only be invoked with a root key, which is held by
     * the message sender. The key they want to copy also must be associated
     * with the ring bound to the root key used.
     *
     * This code will panic if:
     *  - the caller doesn't hold the root key
     *  - the provided key ID isn't associated with the root key's key ring
     *
     * @param rootKeyId root key to be used for this operation.
     * @param keyId     key ID the message sender wishes to copy.
     * @param receiver  addresses of the receivers for the copied key.
     * @param bind      true if you want to bind the key to the receiver. 
     */
    function copyKey(uint256 rootKeyId, uint256 keyId, address receiver, bool bind) external;
    
    /**
     * soulbindKey
     *
     * This method can be called by a root key holder to make a key
     * soulbound to a specific address. When soulbinding a key,
     * it is not required that the current target address hold that key.
     * The amount set ensures that when sending a key of a specific
     * type, that they hold at least the amount that is bound to them.
     *
     * This code will panic if:
     *  - the caller doesn't have the root key
     *  - the target keyId doesn't exist in the ring
     *
     * @param rootKeyId the operator's root key.
     * @param keyHolder the address to bind the key to.
     * @param keyId     the keyId they want to bind.
     * @param amount    the amount of keys to bind to the holder.
     */
    function soulbindKey(uint256 rootKeyId, address keyHolder, uint256 keyId, uint256 amount) external;

    /**
     * burnKey
     *
     * The root key holder can call this method if they want to revoke
     * a key from a holder.
     *
     * This code will panic if:
     *  - The caller doesn't hold the root key.
     *  - The key id is not on the same ring as the root key.
     *  - The target holder doesn't have sufficient keys to burn.
     *
     * @param rootKeyId root key for the associated ring.
     * @param keyId     id of the key you want to burn.
     * @param holder    address of the holder you want to burn from.
     * @param amount    the number of keys you want to burn.
     */
    function burnKey(uint256 rootKeyId, uint256 keyId, address holder, uint256 amount) external;
    
    ///////////////////////////////////////////////////////
    // Introspection 
    ///////////////////////////////////////////////////////

	/**
     * getRingInfo()
     *
     * Given a ring, provides ring metadata back.
     *
     * @param ringId The ID of the ring to inspect.
     * @return The ring ID back as verification.
     * @return The human readable name for the ring.
     * @return The root key ID for the ring.
     * @return The list of keys for the ring.
     */
    function getRingInfo(uint256 ringId) external view returns (uint256, bytes32, uint256, uint256[] memory);

	/**
     * getKeysForHolder
     *
     * This method will return the IDs of the keys held
     * by the given address.
     *
     * @param  holder the address of the key holder you want to see.
     * @return an array of key IDs held by the user.
     */
    function getKeysForHolder(address holder) external view returns (uint256[] memory);

	/**
     * getHolders
     *
     * This method will return the addresses that hold
     * a particular keyId.
     *
     * @param  keyId the key ID to look for.
     * @return an array of addresses that hold that key.
     */
    function getHolders(uint256 keyId) external view returns (address[] memory);

	/**
     * getSoulboundAmount 
     *
     * Returns the number of keys a given holder must maintain when
	 * sending the associated key ID out of their address.
	 *
     * @param account   The wallet address you want the binding amount for. 
     * @param keyId     The key id you want the soulbound amount for. 
     * @return the soulbound token requirement for that wallet and key id.
     */
    function getSoulboundAmount(address account, uint256 keyId) external view returns (uint256);

    /**
     * isRootKey
     *
     * @param keyId the key id in question
     * @return true if the key Id is the root key of it's associated key ring 
     */
    function isRootKey(uint256 keyId) external view returns(bool); 
    
    /**
     * inspectKey 
     * 
     * Takes a key id and inspects it.
     * 
     * @return true if the key is a valid key
     * @return alias of the key 
     * @return the ring id of the key (only if its considered valid)
     * @return true if the key is a root key
     * @return the keys associated with the given ring 
     */ 
    function inspectKey(uint256 keyId) external view returns (bool, bytes32, uint256, bool, uint256[] memory);

    /**
     * hasKeyOrRoot
     *
     * Determines if the given address holders either the key specified,
     * or the ring's root key.
     *
     * This is used by contracts to enable root-key escalation,
     * and prevents the need for root key holders to hold every key to
     * operate as an admin.
     *
     * @param keyHolder the address of the keyholder to check.
     * @param keyId     the key you want to check they are holding.
     * @return true if keyHolder has either keyId, or the keyId's associated root key.
     */
    function hasKeyOrRoot(address keyHolder, uint256 keyId) external view returns (bool);

    /**
     * validateKeyRing
     *
     * Contracts can call this method to determine if a set
     * of keys belong to the same ring. This is used as a validation
	 * method and will *revert* if the keys do not belong to the same
	 * ring. This is extremely useful when taking a set of keys and ensuring
	 * each is part of the same ring first.
     *
     * You can use allowRoot to enable cases were passing in the root key
     * for validation is acceptable. Setting it to false enables you
     * to easily detect if one of the keys provided is the root key.
	 * Remember, this method will revert also based on allowRoot semantics. 
     *
     * @param ringId    the ring ID you want to validate against
     * @param keys      the supposed keys that belong to the ring
     * @param allowRoot true if providing the ring's root key as input is acceptable
     * @return true if valid, or will otherwise revert.
     */
    function validateKeyRing(uint256 ringId, uint256[] calldata keys, bool allowRoot) external view returns (bool);
}
