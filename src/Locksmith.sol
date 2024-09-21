// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

///////////////////////////////////////////////////////
// Dependencies 
///////////////////////////////////////////////////////
// The Locksmith Interface
import { 
	ILocksmith,
	KeyNotHeld,
	KeyNotRoot,
	InvalidRing,
	InvalidRingKey,
	InvalidRingKeySet,
	SoulboundTransferBreach
} from 'src/interfaces/ILocksmith.sol';

// We are going to use the standard OZ ERC1155 implementation,
// and then override the transfer callbacks to enforce soulbinding.
import "openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";

// We use unsigned integer sets to manage key lists
import "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/**
 * Locksmith
 *
 * A canoncial implementation of ILocksmith with full support for key rings,
 * minting, burning, and soulbinding tokens. This contract does not include
 * any vaults or asset storage functionality themselves.
 *
 * The contract implements both the ILocksmith interface, and the IERC1155
 * interface by adopting a majority of Open Zeppelin's ERC1155 implementation.
 * The major difference in the interface is the soulbinding behavior on
 * key transfers.
 */
contract Locksmith is ILocksmith, ERC1155 {
	using EnumerableSet for EnumerableSet.UintSet;
	using EnumerableSet for EnumerableSet.AddressSet;

	///////////////////////////////////////////////////////
    // Data Structures 
    ///////////////////////////////////////////////////////

	/**
	 * KeyMetadata
	 *
	 * Each minted key has additional metadata attached to it,
	 * including an easily retrievable onchain name, and a metadata URI.
	 */
	struct KeyMetadata {
		bytes32 name;
		string  uri;
	}

    /**
     * KeyRing
     *
     * A key ring represents a set of ERC1155 tokens that are
     * collectively owned by that key ring's root key. It operates
     * as a permission set, or a set of keys on a ring. 
	 * 
	 * Keys can be copied and given out, and revoked at any time.
	 * Locksmith keys can also be made non-transferrable by the root
	 * key holder.
     */ 
    struct KeyRing {
        uint256 id;        // every ring in the registry has a unique, monotonically increasing ID
        bytes32 name;      // an encoded string for a human readable name
        uint256 rootKeyId; // this is the ERC1155 token that "owns" the key ring

        EnumerableSet.UintSet keys;           // Set of keys associated with the ring, including root
    }
	
	///////////////////////////////////////////////////////
    // Storage
    ///////////////////////////////////////////////////////
   
   	// Global index interface	
	mapping(uint256 => KeyRing)     private ringRegistry;        // the global ring registry
    mapping(uint256 => uint256)     public  keyRingAssociations; // O(1) index for key:ring resolution
    mapping(uint256 => KeyMetadata) public  keyData;             // Each key has metadata attached to it 
	mapping(uint256 => uint256) 	public  keySupply;			// Keep track of total key supply

    // wallet => keyId => amount
    mapping(address => mapping(uint256 => uint256)) private soulboundKeyAmounts; // soulbound restrictions
    mapping(address => EnumerableSet.UintSet)       private addressKeys;         // all keys held by every address
    mapping(uint256 => EnumerableSet.AddressSet)    private keyHolders;          // all holders of of each key
	
	uint256 private ringCount; // total number of rings
    uint256 private keyCount;  // the total number of keys
	
	///////////////////////////////////////////////////////
    // Initialization and Contract Information 
    ///////////////////////////////////////////////////////

	/**
	 * constructor
	 *
	 * This contract is immutable and unowned. The URI is blank, as
	 * it will be set during key creation, and can be accessed via
	 * IERCMetadataURI.
	 */
	constructor() ERC1155('') {}

	/**
     * name
     *
     * This is the name of the ERC1155 collection. 
     */
    function name() external virtual pure returns (string memory) {
        return "Locksmith Keys";
    }

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
	function createKeyRing(bytes32 ringName, bytes32 rootKeyName, string calldata keyUri, address recipient) external returns (uint256, uint256) {
		// build the ring with post-increment IDs,
		// prevent re-entrancy attacks on keys
        KeyRing storage r = ringRegistry[ringCount];
        r.id = ringCount++;
        r.rootKeyId = keyCount++;
        r.name = ringName;

		// store the new key metadata
		KeyMetadata storage kmd = keyData[r.rootKeyId];
		kmd.name = rootKeyName;
		kmd.uri  = keyUri;

        // mint the root key, give it to the sender.
		// check-effects-interaction: this is re-entrant
        _mintKey(r, r.rootKeyId, recipient, false);

        // the ring was successfully created
		emit KeyRingCreated(msg.sender, r.id, r.name, recipient);
        return (r.id, r.rootKeyId);
	}

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
     * @param keyUri	The metadata URI for the newly created key.
     * @param receiver  address you want to receive the ring key.
     * @param bind      true if you want to bind the key to the receiver.
     * @return the ID of the key that was created
     */
    function createKey(uint256 rootKeyId, bytes32 keyName, string calldata keyUri, address receiver, bool bind) external returns (uint256) {
		// get the ring object but only if the root key holder is legit
        KeyRing storage ring = ringRegistry[_getRingFromRootKey(rootKeyId)];

        // increment the number of unique keys in the system
        uint256 newKeyId = keyCount++;
		
		// store the new key metadata
		KeyMetadata storage kmd = keyData[newKeyId];
		kmd.name = keyName;
		kmd.uri  = keyUri;

        // mint the key into the target wallet.
        // THIS IS RE-ENTRANT!!!!
        _mintKey(ring, newKeyId, receiver, bind);

        return newKeyId;
	}

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
    function copyKey(uint256 rootKeyId, uint256 keyId, address receiver, bool bind) external {
		KeyRing storage ring = ringRegistry[_getRingFromRootKey(rootKeyId)];

        // we can only copy a key that exists on the ring 
		if (!ring.keys.contains(keyId)) {
			revert InvalidRingKey();
		}

        // the root key is valid, the message sender holds it,
        // and the key requested to be copied has already been
        // minted into that ring at least once.
        _mintKey(ring, keyId, receiver, bind);
	}

	/**
     * soulbindKey
     *
     * This method can be called by a root key holder to make a key
     * soulbound to a specific wallet. When soulbinding a key,
     * it is not required that the current target address hold that key.
     * The amount set ensures that when sending a key of a specific
     * type, that they hold at least the amount that is bound to them.
     *
     * This code will panic if:
     *  - the caller doesn't have the root key
     *  - the target keyId doesn't exist in the ring 
     *
     * @param rootKeyId the operator's root key
     * @param keyHolder the address to bind the key to
     * @param keyId     the keyId they want to bind
     * @param amount    the amount of keys to bind to the holder
     */
    function soulbindKey(uint256 rootKeyId, address keyHolder, uint256 keyId, uint256 amount) external {
        KeyRing storage ring = ringRegistry[_getRingFromRootKey(rootKeyId)];

        // we can only bind keys that exist on the key ring 
		if (!ring.keys.contains(keyId)) {
			revert InvalidRingKey();
		}

        // the root key holder has permission, so bind it
        _soulbind(keyHolder, keyId, amount);
    }

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
    function burnKey(uint256 rootKeyId, uint256 keyId, address holder, uint256 amount) external {
		KeyRing storage ring = ringRegistry[_getRingFromRootKey(rootKeyId)];

		// we can only burn a key that exists on the ring 
		if (!ring.keys.contains(keyId)) {
			revert InvalidRingKey();
		}

        // manage total key supply. the holder indexes
	    // will be managed on the transfer callback	
		keySupply[keyId] -= amount;
       
	   	// burn is not re-entrant	
        _burn(holder, keyId, amount);

        emit KeyBurned(msg.sender, ring.id, keyId, holder, amount);
	}

	///////////////////////////////////////////////////////
    // Introspection
    ///////////////////////////////////////////////////////

	/**
	 * supportsInterface
	 *
	 * The Locksmith implements three specific interfaces:
	 * - ILocksmith
	 * - ERC1155
	 * - ERC165
	 *
	 * @param interfaceId the interface identifier you want to check support for
	 * @return true if the identifier is within the interface support.
	 */
	function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, IERC165) returns (bool) {
		return interfaceId == type(ILocksmith).interfaceId ||
        	super.supportsInterface(interfaceId); 
	}

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
	function getRingInfo(uint256 ringId) external view returns (uint256, bytes32, uint256, uint256[] memory) {
		KeyRing storage ring = ringRegistry[ringId];
		
		// an invalid ring key is always empty
        assert(ring.keys.length() != 0);
		
		return (ring.id, ring.name, ring.rootKeyId, ring.keys.values());
	}

	/**
     * getKeysForHolder
     *
     * This method will return the IDs of the keys held
     * by the given address.
     *
     * @param  holder the address of the key holder you want to see.
     * @return an array of key IDs held by the user.
     */
    function getKeysForHolder(address holder) external view returns (uint256[] memory) {
		return addressKeys[holder].values();
	}

	/**
     * getHolders
     *
     * This method will return the addresses that hold
     * a particular keyId.
     *
     * @param  keyId the key ID to look for.
     * @return an array of addresses that hold that key.
     */
    function getHolders(uint256 keyId) external view returns (address[] memory) {
		 return keyHolders[keyId].values();
	}

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
    function getSoulboundAmount(address account, uint256 keyId) external view returns (uint256) {
		return soulboundKeyAmounts[account][keyId];
	}

	/**
     * getRingId
     *
     * Returns the ring ID for a given key. If the key is invalid,
     * it will revert with InvalidRingKey().
     *
     * @param keyId the id of the key you are looking for
     * @return the id of the ring.
     */
     function getRingId(uint256 keyId) external view returns (uint256) {
		if (keyId >= keyCount) {
			revert InvalidRingKey();
		}
		return keyRingAssociations[keyId]; 
	 }

	/**
     * isRootKey
     *
     * @param keyId the key id in question
     * @return true if the key Id is the root key of it's associated key ring
     */
    function isRootKey(uint256 keyId) external view returns(bool) {
		return _isRootKey(keyId);
	}

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
    function inspectKey(uint256 keyId) public view returns (bool, bytes32, uint256, bool, uint256[] memory) {
        uint256[] memory empty = new uint256[](0);

		// the key is a valid key number
        return ((keyId < keyCount),
            // the human readable name of the key
            keyData[keyId].name,
            // ring Id of the key
            keyRingAssociations[keyId],
            // the key is a root key
            _isRootKey(keyId),
            // the keys associated with the ring 
            keyId >= keyCount ? empty : ringRegistry[keyRingAssociations[keyId]].keys.values());
    }

	/**
     * uri
     *
     * Given a key id, will provide the metadata uri. 
     *
     * @param id the id of the NFT we want to inspect
     */
    function uri(uint256 id) public view virtual override returns (string memory) {
    	return keyData[id].uri;
	}

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
    function hasKeyOrRoot(address keyHolder, uint256 keyId) external view returns (bool) {
        return (keyId < keyCount) &&              	            					         // is a valid key
        	((balanceOf(keyHolder, keyId) > 0) || 			   							     // actually holds key, or
             balanceOf(keyHolder, ringRegistry[keyRingAssociations[keyId]].rootKeyId) > 0);  // holds root key
	}

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
    function validateKeyRing(uint256 ringId, uint256[] calldata keys, bool allowRoot) external view returns (bool) {
		// make sure the ring is valid
		if(ringId >= ringCount) {
			revert InvalidRing();
		}

        // this is safe since the ring is valid
        KeyRing storage ring = ringRegistry[ringId];

		// check that each key is valid, not root, and on the declared ring
        for(uint256 x = 0; x < keys.length; x++) {
			if ( (keys[x] >= keyCount) 						|| // valid key?
			     (!allowRoot && keys[x] == ring.rootKeyId)  || // allow root?
			     (!ring.keys.contains(keys[x])) ) {			   // not on ring
					revert InvalidRingKeySet();
			}
        }

        // at this point, the ring is valid, the root has been minted
        // at least once, every key in the array is valid, meets the
        // allowed root criteria, and has been validated to belong
        // to the declared key ring 
        return true;
	}

	///////////////////////////////////////////////////////
    // Internal Methods 
    ///////////////////////////////////////////////////////

	/**
     * _isRootKey
     *
	 * Internal method as documented by #isRootKey.
	 *
     * @param keyId the key id in question
     * @return true if the key Id is the root key of it's associated key ring
     */
    function _isRootKey(uint256 keyId) internal view returns(bool) {
        // key is valid
        return (keyId < keyCount) &&
        // the root key for the ring is the key in question
        (keyId == ringRegistry[keyRingAssociations[keyId]].rootKeyId) &&
        // the key is on the ring list
        (ringRegistry[keyRingAssociations[keyId]].keys.contains(keyId));
    }	

	/**
     * _getRingFromRootKey
     *
     * This internal method acts as a modifier and a look-up function. It will return
     * the ring ID for a given root key ID, but will revert if the message sender
	 * does not possess the root key in question.
     *
     * @param rootKeyId The keyId used by the message sender in the function
     * @return the resolved ring id
     */
    function _getRingFromRootKey(uint256 rootKeyId) internal view returns (uint256) {
        // make sure that the message sender holds this key ID
		if (balanceOf(msg.sender, rootKeyId) < 1) {
			revert KeyNotHeld();
		}

        // make sure that the keyID is an actual rootKeyID
        uint256 ringId = keyRingAssociations[rootKeyId];
		if (ringRegistry[ringId].rootKeyId != rootKeyId) {
			revert KeyNotRoot();
		}

        return ringId;
    }

	/**
	 * _soulbind
	 *
	 * Internal helper function that will absolutely set the soulbound
	 * key amount for a given key on a specific address.
	 *
	 * @param target The target address to set the soulbinding for.
	 * @param keyId  The ID of the key you want to soulbind.
	 * @param amount The amount of keys the target must now keep.
	 */
	function _soulbind(address target, uint256 keyId, uint256 amount) internal {
        soulboundKeyAmounts[target][keyId] = amount;
        emit SetSoulboundKeyAmount(msg.sender, target, keyId, amount);
	}

	/**
     * _mintKey
     *
	 * This method is RE-ENTRANT.
	 *
     * Internal helper function that mints a key and emits an event for it.
     * Always assumes that the message sender is the creator.
	 *
	 * This method should only be called with ring/keyId pairs that are valid,
	 * as no checks are made.
	 *
     * @param ring      The ring we are minting a key onto. 
     * @param keyId     Resolved key Id we are minting.
     * @param receiver  Receiving address of the newly minted key.
     * @param bind      true if you want to bind it to the user
     */
    function _mintKey(KeyRing storage ring, uint256 keyId, address receiver, bool bind) internal {
        // index the key and ring both ways 
        keyRingAssociations[keyId] = ring.id;
        ring.keys.add(keyId);

        // we want to soulbind here
        if (bind) {
            _soulbind(receiver, keyId, soulboundKeyAmounts[receiver][keyId] + 1); 
        }

		// increment the key's supply
       	keySupply[keyId] += 1;

        // THIS IS RE-ENTRANT
        _mint(receiver, keyId, 1, ''); 
        emit KeyMinted(msg.sender, ring.id, keyId, receiver);
    }

	/**
     * _update
     *
     * This is an override for ERC1155. We are going
     * to ensure that the transfer is not tripping any
     * soulbound token amounts.
     */
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal virtual override {	
		super._update(from, to, ids, values);
        
		// here we check to see if any 'from' addresses
        // would end up with too few soulbound requirements
        // at the end of the transaction.
        for(uint256 x = 0; x < ids.length; x++) {
            // we need to allow address zero during minting,
            // and we need to allow the locksmith to violate during burning
            if ( (from != address(0)) && (to != address(0)) &&  
            	 (balanceOf(from, ids[x])) < soulboundKeyAmounts[from][ids[x]]) {
					revert SoulboundTransferBreach();
			}	

			_manageIndexes(from, to, ids[x], values[x]);
        }
	}

	/**
	 * _manageIndexes
	 *
	 * Encapsulate the index management. This does not consider supply
	 * management, which is more directly changed via #createKeyRing, #createKey, 
	 * #copyKey, and #burnKey.
	 *
	 * @param from  The address of the sender, or address(0) for minting.
	 * @param to    The address of the recipient, or address(0) for burning.
	 * @param id    The id of the key token that is being sent.
	 * @param value The number of keys that are being sent.
	 */
	function _manageIndexes(address from, address to, uint256 id, uint256 value) internal {
		// lets keep track of each key that is moving
    	if(balanceOf(from, id) == 0) {
    		addressKeys[from].remove(id);
        	keyHolders[id].remove(from);
    	}
		if(address(0) != to && 0 != value) {
			addressKeys[to].add(id);
        	keyHolders[id].add(to);
		}	
	}
}
