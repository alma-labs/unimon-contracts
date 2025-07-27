// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {UnimonV2} from "./UnimonV2.sol";
import {UnimonItems} from "./UnimonItems.sol";

contract UnimonEquipment is AccessControl {
    bytes32 public constant EQUIPMENT_MANAGER_ROLE = keccak256("EQUIPMENT_MANAGER_ROLE");

    UnimonV2 public immutable unimonV2;
    UnimonItems public immutable unimonItems;

    mapping(uint256 => uint256) public equippedItems;
    mapping(uint256 => EquipmentStats) public equipmentStats;

    struct EquipmentStats {
        int256 attackModifier; // Can be positive or negative
        int256 defenseModifier; // Can be positive or negative
        int256 overallPercent; // Percentage modifier (100 = +100%, -50 = -50%)
        bool isConsumable; // Whether this is a consumable item (vs permanent equipment)
        bool isConfigured; // Whether this item can be equipped
    }

    event ItemEquipped(uint256 indexed tokenId, uint256 indexed itemId, address indexed owner);
    event ItemUnequipped(uint256 indexed tokenId, uint256 indexed itemId, address indexed owner);
    event EquipmentConfigured(
        uint256 indexed itemId,
        int256 attackModifier,
        int256 defenseModifier,
        int256 overallPercent,
        bool isConsumable
    );

    constructor(address _unimonV2, address _unimonItems) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EQUIPMENT_MANAGER_ROLE, msg.sender);

        unimonV2 = UnimonV2(_unimonV2);
        unimonItems = UnimonItems(_unimonItems);
    }

    /*
        VIEW FUNCTIONS
    */

    function getEquippedItem(uint256 tokenId) external view returns (uint256) {
        return equippedItems[tokenId];
    }

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

    function isEquipmentConfigured(uint256 itemId) external view returns (bool) {
        return equipmentStats[itemId].isConfigured;
    }

    function isConsumableItem(uint256 itemId) external view returns (bool) {
        return equipmentStats[itemId].isConsumable;
    }

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

    function unequipItem(uint256 tokenId) external {
        require(unimonV2.ownerOf(tokenId) == msg.sender, "You don't own this Unimon");
        require(equippedItems[tokenId] != 0, "No item equipped");

        _unequipItem(tokenId, msg.sender);
    }

    /*
        INTERNAL FUNCTIONS
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

    function removeEquipmentConfig(uint256 itemId) external onlyRole(EQUIPMENT_MANAGER_ROLE) {
        delete equipmentStats[itemId];
    }

    function emergencyUnequip(uint256 tokenId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(equippedItems[tokenId] != 0, "No item equipped");

        address owner = unimonV2.ownerOf(tokenId);
        _unequipItem(tokenId, owner);
    }

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

    /*
        ERC1155 RECEIVER
    */

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

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
