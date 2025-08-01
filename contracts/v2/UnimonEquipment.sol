// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {UnimonV2} from "./UnimonV2.sol";
import {UnimonItems} from "./UnimonItems.sol";

/**
 * @title UnimonEquipment
 * @author Unimon Team
 * @notice Manages equipment system for Unimon NFTs, allowing players to equip items that modify their stats
 * @dev This contract handles the equipping/unequipping of items and tracks equipment configurations.
 *      Items are stored as ERC1155 tokens and can provide stat modifiers to Unimon NFTs.
 *      Only configured items can be equipped, and the contract supports both permanent and consumable equipment.
 */
contract UnimonEquipment is AccessControl {
    bytes32 public constant EQUIPMENT_MANAGER_ROLE = keccak256("EQUIPMENT_MANAGER_ROLE");

    UnimonV2 public immutable unimonV2;
    UnimonItems public immutable unimonItems;

    mapping(uint256 => uint256) public equippedItems;
    mapping(uint256 => EquipmentStats) public equipmentStats;

    /**
     * @notice Equipment statistics and configuration for items
     * @param attackModifier Flat attack modifier (can be positive or negative)
     * @param defenseModifier Flat defense modifier (can be positive or negative)
     * @param overallPercent Percentage modifier (100 = +100%, -50 = -50%)
     * @param isConsumable Whether this is a consumable item (vs permanent equipment)
     * @param isConfigured Whether this item can be equipped (must be true to equip)
     */
    struct EquipmentStats {
        int256 attackModifier; // Can be positive or negative
        int256 defenseModifier; // Can be positive or negative
        int256 overallPercent; // Percentage modifier (100 = +100%, -50 = -50%)
        bool isConsumable; // Whether this is a consumable item (vs permanent equipment)
        bool isConfigured; // Whether this item can be equipped
    }

    /**
     * @notice Emitted when an item is equipped to a Unimon
     * @param tokenId The Unimon token ID
     * @param itemId The item ID that was equipped
     * @param owner The owner of the Unimon
     */
    event ItemEquipped(uint256 indexed tokenId, uint256 indexed itemId, address indexed owner);
    
    /**
     * @notice Emitted when an item is unequipped from a Unimon
     * @param tokenId The Unimon token ID
     * @param itemId The item ID that was unequipped
     * @param owner The owner of the Unimon
     */
    event ItemUnequipped(uint256 indexed tokenId, uint256 indexed itemId, address indexed owner);
    
    /**
     * @notice Emitted when equipment configuration is set for an item
     * @param itemId The item ID being configured
     * @param attackModifier The attack modifier value
     * @param defenseModifier The defense modifier value
     * @param overallPercent The overall percentage modifier
     * @param isConsumable Whether the item is consumable
     */
    event EquipmentConfigured(
        uint256 indexed itemId,
        int256 attackModifier,
        int256 defenseModifier,
        int256 overallPercent,
        bool isConsumable
    );

    /**
     * @notice Constructor to initialize the equipment system
     * @param _unimonV2 Address of the UnimonV2 NFT contract
     * @param _unimonItems Address of the UnimonItems ERC1155 contract
     * @dev Grants DEFAULT_ADMIN_ROLE and EQUIPMENT_MANAGER_ROLE to the deployer.
     *      SPENDER_ROLE should be granted to this contract separately for burning consumable items.
     */
    constructor(address _unimonV2, address _unimonItems) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EQUIPMENT_MANAGER_ROLE, msg.sender);

        unimonV2 = UnimonV2(_unimonV2);
        unimonItems = UnimonItems(_unimonItems);
    }

    /*
        VIEW FUNCTIONS
    */

    /**
     * @notice Get the currently equipped item ID for a Unimon
     * @param tokenId The Unimon token ID
     * @return The equipped item ID (0 if no item is equipped)
     */
    function getEquippedItem(uint256 tokenId) external view returns (uint256) {
        return equippedItems[tokenId];
    }

    /**
     * @notice Get the modified stats for a Unimon including equipment bonuses
     * @param tokenId The Unimon token ID
     * @return attackLevel The modified attack level (base + equipment modifier)
     * @return defenseLevel The modified defense level (base + equipment modifier)
     * @return overallPercent The overall percentage modifier from equipment
     * @dev Returns base stats if no item is equipped or if the equipped item is not configured
     */
    function getModifiedStats(
        uint256 tokenId
    ) external view returns (int256 attackLevel, int256 defenseLevel, int256 overallPercent) {
        (uint256 baseAttack, uint256 baseDefense, , ) = unimonV2.getUnimonStats(tokenId);

        uint256 equippedItemId = equippedItems[tokenId];
        if (equippedItemId == 0) {
            return (int256(baseAttack), int256(baseDefense), 0);
        }

        EquipmentStats memory equipment = equipmentStats[equippedItemId];
        if (!equipment.isConfigured) {
            return (int256(baseAttack), int256(baseDefense), 0);
        }

        // Apply flat modifiers only - can be negative
        attackLevel = int256(baseAttack) + equipment.attackModifier;
        defenseLevel = int256(baseDefense) + equipment.defenseModifier;

        // Return percentage modifier separately
        overallPercent = equipment.overallPercent;
    }

    /**
     * @notice Check if an item is configured as equipment
     * @param itemId The item ID to check
     * @return True if the item is configured as equipment
     */
    function isEquipmentConfigured(uint256 itemId) external view returns (bool) {
        return equipmentStats[itemId].isConfigured;
    }

    /**
     * @notice Check if an item is consumable
     * @param itemId The item ID to check
     * @return True if the item is consumable
     */
    function isConsumableItem(uint256 itemId) external view returns (bool) {
        return equipmentStats[itemId].isConsumable;
    }

    /**
     * @notice Check if a Unimon has a consumable item equipped
     * @param tokenId The Unimon token ID to check
     * @return True if the Unimon has a consumable item equipped
     */
    function hasConsumableEquipped(uint256 tokenId) public view returns (bool) {
        uint256 equippedItemId = equippedItems[tokenId];
        if (equippedItemId == 0) {
            return false;
        }
        return equipmentStats[equippedItemId].isConsumable;
    }

    /**
     * @notice Get modified stats for all Unimon owned by a user with pagination
     * @param user The user address to get stats for
     * @param offset The starting index for pagination
     * @param limit The maximum number of results to return
     * @return tokenIds Array of Unimon token IDs
     * @return attackLevels Array of modified attack levels
     * @return defenseLevels Array of modified defense levels
     * @return overallPercents Array of overall percentage modifiers
     * @return equippedItemIds Array of equipped item IDs (0 if none equipped)
     * @return totalOwned Total number of Unimon owned by the user
     * @dev Returns empty arrays if user owns no Unimon or limit is 0
     */
    function getAllModifiedStatsForUser(
        address user,
        uint256 offset,
        uint256 limit
    )
        external
        view
        returns (
            uint256[] memory tokenIds,
            int256[] memory attackLevels,
            int256[] memory defenseLevels,
            int256[] memory overallPercents,
            uint256[] memory equippedItemIds,
            uint256 totalOwned
        )
    {
        totalOwned = unimonV2.balanceOf(user);
        require(offset < totalOwned || totalOwned == 0, "Offset exceeds total owned");

        if (totalOwned == 0 || limit == 0) {
            return (new uint256[](0), new int256[](0), new int256[](0), new int256[](0), new uint256[](0), totalOwned);
        }

        uint256 end = offset + limit;
        if (end > totalOwned) {
            end = totalOwned;
        }

        uint256 resultLength = end - offset;
        tokenIds = new uint256[](resultLength);
        attackLevels = new int256[](resultLength);
        defenseLevels = new int256[](resultLength);
        overallPercents = new int256[](resultLength);
        equippedItemIds = new uint256[](resultLength);

        for (uint256 i = 0; i < resultLength; i++) {
            uint256 tokenId = unimonV2.tokenOfOwnerByIndex(user, offset + i);
            tokenIds[i] = tokenId;

            (int256 attack, int256 defense, int256 percent) = this.getModifiedStats(tokenId);
            attackLevels[i] = attack;
            defenseLevels[i] = defense;
            overallPercents[i] = percent;

            equippedItemIds[i] = equippedItems[tokenId];
        }
    }

    /*
        USER FUNCTIONS
    */

    /**
     * @notice Equip an item to a Unimon
     * @param tokenId The Unimon token ID to equip the item to
     * @param itemId The item ID to equip
     * @dev Automatically unequips any currently equipped item before equipping the new one.
     *      Transfers the item from the user to this contract. Requires the user to own both
     *      the Unimon and the item, and the item must be configured as equipment.
     */
    function equipItem(uint256 tokenId, uint256 itemId) external {
        require(unimonV2.ownerOf(tokenId) == msg.sender, "You don't own this Unimon");
        require(equipmentStats[itemId].isConfigured, "Item is not configurable as equipment");
        require(unimonItems.balanceOf(msg.sender, itemId) > 0, "You don't own this item");

        // Auto-unequip current item if one is equipped
        if (equippedItems[tokenId] != 0) {
            _unequipItem(tokenId, msg.sender);
        }

        // Transfer item from user to this contract (no approval needed - equipment role)
        unimonItems.whitelistTransfer(msg.sender, address(this), itemId, 1);

        // Equip the item
        equippedItems[tokenId] = itemId;

        emit ItemEquipped(tokenId, itemId, msg.sender);
    }

    /**
     * @notice Unequip the currently equipped item from a Unimon
     * @param tokenId The Unimon token ID to unequip the item from
     * @dev Returns the item to the Unimon owner. Requires the user to own the Unimon
     *      and have an item currently equipped.
     */
    function unequipItem(uint256 tokenId) external {
        require(unimonV2.ownerOf(tokenId) == msg.sender, "You don't own this Unimon");
        require(equippedItems[tokenId] != 0, "No item equipped");

        _unequipItem(tokenId, msg.sender);
    }

    /*
        INTERNAL FUNCTIONS
    */

    /**
     * @notice Internal function to unequip an item from a Unimon
     * @param tokenId The Unimon token ID
     * @param owner The owner of the Unimon
     * @dev Clears the equipped item mapping and transfers the item back to the owner
     */
    function _unequipItem(uint256 tokenId, address owner) internal {
        uint256 equippedItemId = equippedItems[tokenId];
        equippedItems[tokenId] = 0;
        unimonItems.whitelistTransfer(address(this), owner, equippedItemId, 1);

        emit ItemUnequipped(tokenId, equippedItemId, owner);
    }

    /*
        ADMIN FUNCTIONS
    */

    /**
     * @notice Configure an item as equipment with stat modifiers
     * @param itemId The item ID to configure
     * @param attackModifier The attack modifier value (can be negative)
     * @param defenseModifier The defense modifier value (can be negative)
     * @param overallPercent The overall percentage modifier (100 = +100%, -50 = -50%)
     * @param isConsumable Whether the item is consumable
     * @dev Only callable by accounts with EQUIPMENT_MANAGER_ROLE
     */
    function configureEquipment(
        uint256 itemId,
        int256 attackModifier,
        int256 defenseModifier,
        int256 overallPercent,
        bool isConsumable
    ) external onlyRole(EQUIPMENT_MANAGER_ROLE) {
        equipmentStats[itemId] = EquipmentStats({
            attackModifier: attackModifier,
            defenseModifier: defenseModifier,
            overallPercent: overallPercent,
            isConsumable: isConsumable,
            isConfigured: true
        });

        emit EquipmentConfigured(itemId, attackModifier, defenseModifier, overallPercent, isConsumable);
    }

    /**
     * @notice Configure multiple items as equipment in a single transaction
     * @param itemIds Array of item IDs to configure
     * @param attackModifiers Array of attack modifier values
     * @param defenseModifiers Array of defense modifier values
     * @param overallPercents Array of overall percentage modifiers
     * @param isConsumables Array of consumable flags
     * @dev Only callable by accounts with EQUIPMENT_MANAGER_ROLE. All arrays must have the same length.
     */
    function configureBulkEquipment(
        uint256[] memory itemIds,
        int256[] memory attackModifiers,
        int256[] memory defenseModifiers,
        int256[] memory overallPercents,
        bool[] memory isConsumables
    ) external onlyRole(EQUIPMENT_MANAGER_ROLE) {
        require(
            itemIds.length == attackModifiers.length &&
                itemIds.length == defenseModifiers.length &&
                itemIds.length == overallPercents.length &&
                itemIds.length == isConsumables.length,
            "Array lengths must match"
        );

        for (uint256 i = 0; i < itemIds.length; i++) {
            equipmentStats[itemIds[i]] = EquipmentStats({
                attackModifier: attackModifiers[i],
                defenseModifier: defenseModifiers[i],
                overallPercent: overallPercents[i],
                isConsumable: isConsumables[i],
                isConfigured: true
            });

            emit EquipmentConfigured(itemIds[i], attackModifiers[i], defenseModifiers[i], overallPercents[i], isConsumables[i]);
        }
    }

    /**
     * @notice Remove equipment configuration for an item
     * @param itemId The item ID to remove configuration for
     * @dev Only callable by accounts with EQUIPMENT_MANAGER_ROLE. This will prevent the item from being equipped.
     */
    function removeEquipmentConfig(uint256 itemId) external onlyRole(EQUIPMENT_MANAGER_ROLE) {
        delete equipmentStats[itemId];
    }

    /**
     * @notice Emergency unequip function for admin use
     * @param tokenId The Unimon token ID to unequip
     * @dev Only callable by accounts with DEFAULT_ADMIN_ROLE. Returns the equipped item to the Unimon owner.
     */
    function emergencyUnequip(uint256 tokenId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(equippedItems[tokenId] != 0, "No item equipped");

        address owner = unimonV2.ownerOf(tokenId);
        _unequipItem(tokenId, owner);
    }

    /**
     * @notice Remove equipment from a Unimon with option to burn the item
     * @param tokenId The Unimon token ID to remove equipment from
     * @param burnItem Whether to burn the item (true) or return it to the owner (false)
     * @dev Only callable by accounts with EQUIPMENT_MANAGER_ROLE. If burnItem is true, the item is transferred
     *      to the zero address, effectively burning it.
     */
    function removeEquipment(uint256 tokenId, bool burnItem) external onlyRole(EQUIPMENT_MANAGER_ROLE) {
        require(equippedItems[tokenId] != 0, "No item equipped");

        uint256 equippedItemId = equippedItems[tokenId];
        address owner = unimonV2.ownerOf(tokenId);

        // Clear the equipped item
        equippedItems[tokenId] = 0;

        if (burnItem) {
            // Burn the item by transferring to zero address
            unimonItems.whitelistTransfer(address(this), address(0), equippedItemId, 1);
        } else {
            // Return item to owner
            unimonItems.whitelistTransfer(address(this), owner, equippedItemId, 1);
        }

        emit ItemUnequipped(tokenId, equippedItemId, owner);
    }

    /**
     * @notice Consume and burn the equipped item from a Unimon after battle
     * @param tokenId The Unimon token ID to consume equipment from
     * @dev Only callable by accounts with EQUIPMENT_MANAGER_ROLE. This function is designed to be called
     *      after battles to consume consumable equipment. The item is burned and the Unimon is left with
     *      no equipment equipped.
     */
    function consumeUponBattle(uint256 tokenId) external onlyRole(EQUIPMENT_MANAGER_ROLE) {
        require(equippedItems[tokenId] != 0, "No item equipped");
        require(hasConsumableEquipped(tokenId), "Equipped item is not consumable");

        uint256 equippedItemId = equippedItems[tokenId];
        address owner = unimonV2.ownerOf(tokenId);

        // Clear the equipped item
        equippedItems[tokenId] = 0;

        // Burn the item using the proper burn function
        unimonItems.spendItem(address(this), equippedItemId, 1);

        emit ItemUnequipped(tokenId, equippedItemId, owner);
    }

    /*
        ERC1155 RECEIVER
    */

    /**
     * @notice ERC1155 receiver function to accept item transfers
     * @return The function selector to confirm receipt
     * @dev Required for the contract to receive ERC1155 tokens (items)
     */
    function onERC1155Received(address, address, uint256, uint256, bytes memory) public pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /**
     * @notice ERC1155 batch receiver function to accept multiple item transfers
     * @return The function selector to confirm receipt
     * @dev Required for the contract to receive batch ERC1155 token transfers
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}
