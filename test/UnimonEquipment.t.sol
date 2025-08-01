// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../contracts/v2/UnimonEquipment.sol";
import "../contracts/v2/UnimonV2.sol";
import "../contracts/v2/UnimonItems.sol";

contract UnimonEquipmentTest is Test {
    UnimonEquipment public equipment;
    UnimonV2 public unimonV2;
    UnimonItems public unimonItems;

    address public admin = address(1);
    address public user1 = address(2);
    address public user2 = address(3);

    uint256 public constant SWORD_ID = 10;
    uint256 public constant SHIELD_ID = 11;
    uint256 public constant CURSE_ID = 12;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy contracts
        unimonItems = new UnimonItems(admin);
        unimonV2 = new UnimonV2(address(unimonItems));
        equipment = new UnimonEquipment(address(unimonV2), address(unimonItems));

        // Grant roles
        unimonV2.grantRole(unimonV2.MINTER_ROLE(), admin);
        unimonItems.grantRole(unimonItems.MINTER_ROLE(), admin);

        // Configure equipment
        equipment.configureEquipment(SWORD_ID, 5, 0, 0, false); // +5 attack (equipable)
        equipment.configureEquipment(SHIELD_ID, 0, 3, 0, false); // +3 defense (equipable)
        equipment.configureEquipment(CURSE_ID, -2, -1, -25, false); // -2 attack, -1 defense, -25% overall (equipable)

        // Grant equipment role for seamless transfers
        unimonItems.grantRole(unimonItems.EQUIPMENT_ROLE(), address(equipment));
        // Grant spender role for burning consumable items
        unimonItems.grantRole(unimonItems.SPENDER_ROLE(), address(equipment));

        vm.stopPrank();
    }

    function testConfigureEquipment() public {
        vm.prank(admin);
        equipment.configureEquipment(100, 10, -5, 50, true);

        (int256 attack, int256 defense, int256 percent, bool consumable, bool configured) = equipment.equipmentStats(100);
        assertEq(attack, 10);
        assertEq(defense, -5);
        assertEq(percent, 50);
        assertTrue(consumable);
        assertTrue(configured);
        assertTrue(equipment.isConsumableItem(100));
    }

    function testConfigureEquipmentOnlyManager() public {
        vm.prank(user1);
        vm.expectRevert();
        equipment.configureEquipment(100, 10, -5, 50, true);
    }

    function testConfigureBulkEquipment() public {
        uint256[] memory itemIds = new uint256[](3);
        int256[] memory attackMods = new int256[](3);
        int256[] memory defenseMods = new int256[](3);
        int256[] memory overallMods = new int256[](3);
        bool[] memory isConsumables = new bool[](3);

        itemIds[0] = 100;
        attackMods[0] = 10;
        defenseMods[0] = 5;
        overallMods[0] = 0;
        isConsumables[0] = false;
        itemIds[1] = 101;
        attackMods[1] = 0;
        defenseMods[1] = 8;
        overallMods[1] = 15;
        isConsumables[1] = true;
        itemIds[2] = 102;
        attackMods[2] = -2;
        defenseMods[2] = -3;
        overallMods[2] = -10;
        isConsumables[2] = false;

        vm.prank(admin);
        equipment.configureBulkEquipment(itemIds, attackMods, defenseMods, overallMods, isConsumables);

        // Verify all items were configured correctly
        for (uint256 i = 0; i < itemIds.length; i++) {
            (int256 attack, int256 defense, int256 percent, bool consumable, bool configured) = equipment.equipmentStats(itemIds[i]);
            assertEq(attack, attackMods[i]);
            assertEq(defense, defenseMods[i]);
            assertEq(percent, overallMods[i]);
            assertEq(consumable, isConsumables[i]);
            assertTrue(configured);
        }
    }

    function testConfigureBulkEquipmentArrayLengthMismatch() public {
        uint256[] memory itemIds = new uint256[](2);
        int256[] memory attackMods = new int256[](3); // Different length
        int256[] memory defenseMods = new int256[](2);
        int256[] memory overallMods = new int256[](2);
        bool[] memory isConsumables = new bool[](2);

        vm.prank(admin);
        vm.expectRevert("Array lengths must match");
        equipment.configureBulkEquipment(itemIds, attackMods, defenseMods, overallMods, isConsumables);
    }

    function testConfigureBulkEquipmentOnlyManager() public {
        uint256[] memory itemIds = new uint256[](1);
        int256[] memory attackMods = new int256[](1);
        int256[] memory defenseMods = new int256[](1);
        int256[] memory overallMods = new int256[](1);
        bool[] memory isConsumables = new bool[](1);

        vm.prank(user1);
        vm.expectRevert();
        equipment.configureBulkEquipment(itemIds, attackMods, defenseMods, overallMods, isConsumables);
    }

    function testEquipItem() public {
        // Setup: mint unimon and items
        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        unimonItems.mint(user1, SWORD_ID, 1);
        vm.stopPrank();

        // User equips sword (no approval needed - equipment has EQUIPMENT_ROLE)
        vm.prank(user1);
        equipment.equipItem(tokenId, SWORD_ID);

        // Verify equipped
        assertEq(equipment.getEquippedItem(tokenId), SWORD_ID);
        assertEq(unimonItems.balanceOf(address(equipment), SWORD_ID), 1);
        assertEq(unimonItems.balanceOf(user1, SWORD_ID), 0);
    }

    function testEquipItemRequiresOwnership() public {
        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        unimonItems.mint(user2, SWORD_ID, 1);
        vm.stopPrank();

        vm.prank(user2);
        vm.expectRevert("You don't own this Unimon");
        equipment.equipItem(tokenId, SWORD_ID);
    }

    function testCannotEquipUnconfiguredItem() public {
        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        unimonItems.mint(user1, 999, 1);
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert("Item is not configurable as equipment");
        equipment.equipItem(tokenId, 999);
    }

    function testAutoUnequipWhenEquippingNew() public {
        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        unimonItems.mint(user1, SWORD_ID, 1);
        unimonItems.mint(user1, SHIELD_ID, 1);
        vm.stopPrank();

        vm.startPrank(user1);
        // Equip sword first
        equipment.equipItem(tokenId, SWORD_ID);
        assertEq(equipment.getEquippedItem(tokenId), SWORD_ID);
        assertEq(unimonItems.balanceOf(user1, SWORD_ID), 0);
        assertEq(unimonItems.balanceOf(address(equipment), SWORD_ID), 1);

        // Equip shield - should auto-unequip sword and equip shield
        equipment.equipItem(tokenId, SHIELD_ID);
        assertEq(equipment.getEquippedItem(tokenId), SHIELD_ID);
        assertEq(unimonItems.balanceOf(user1, SWORD_ID), 1); // Sword returned to user
        assertEq(unimonItems.balanceOf(user1, SHIELD_ID), 0); // Shield now held by contract
        assertEq(unimonItems.balanceOf(address(equipment), SWORD_ID), 0);
        assertEq(unimonItems.balanceOf(address(equipment), SHIELD_ID), 1);
        vm.stopPrank();
    }

    function testUnequipItem() public {
        // Setup and equip
        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        unimonItems.mint(user1, SWORD_ID, 1);
        vm.stopPrank();

        vm.startPrank(user1);
        equipment.equipItem(tokenId, SWORD_ID);

        // Unequip
        equipment.unequipItem(tokenId);
        vm.stopPrank();

        // Verify unequipped
        assertEq(equipment.getEquippedItem(tokenId), 0);
        assertEq(unimonItems.balanceOf(address(equipment), SWORD_ID), 0);
        assertEq(unimonItems.balanceOf(user1, SWORD_ID), 1);
    }

    function testGetModifiedStatsWithSword() public {
        // Setup
        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        unimonItems.mint(user1, SWORD_ID, 1);
        vm.stopPrank();

        // Check base stats (should be 1, 1, 0%)
        (int256 baseAttack, int256 baseDefense, int256 basePercent) = equipment.getModifiedStats(tokenId);
        assertEq(baseAttack, 1);
        assertEq(baseDefense, 1);
        assertEq(basePercent, 0);

        // Equip sword (+5 attack)
        vm.prank(user1);
        equipment.equipItem(tokenId, SWORD_ID);

        // Check modified stats
        (int256 modAttack, int256 modDefense, int256 modPercent) = equipment.getModifiedStats(tokenId);
        assertEq(modAttack, 6); // 1 + 5
        assertEq(modDefense, 1); // unchanged
        assertEq(modPercent, 0); // no percentage modifier
    }

    function testGetModifiedStatsWithShield() public {
        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        unimonItems.mint(user1, SHIELD_ID, 1);
        vm.stopPrank();

        vm.prank(user1);
        equipment.equipItem(tokenId, SHIELD_ID);

        (int256 attack, int256 defense, int256 percent) = equipment.getModifiedStats(tokenId);
        assertEq(attack, 1); // unchanged
        assertEq(defense, 4); // 1 + 3
        assertEq(percent, 0); // no percentage modifier
    }

    function testGetModifiedStatsWithCurse() public {
        // First evolve the unimon to have higher stats
        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        unimonItems.mint(user1, unimonItems.ENERGY_ID(), 10);
        unimonItems.mint(user1, CURSE_ID, 1);
        unimonV2.grantRole(unimonV2.MINTER_ROLE(), address(unimonV2));
        unimonItems.grantRole(unimonItems.SPENDER_ROLE(), address(unimonV2));
        vm.stopPrank();

        vm.startPrank(user1);
        // Evolve to get higher base stats
        unimonV2.evolve(tokenId, 10);

        // Check evolved stats (should be higher than base 1,1)
        (uint256 baseAttack, uint256 baseDefense, , ) = unimonV2.getUnimonStats(tokenId);
        assertTrue(baseAttack > 1);
        assertTrue(baseDefense > 1);

        // Equip curse (-2 attack, -1 defense, -25% overall)
        equipment.equipItem(tokenId, CURSE_ID);
        vm.stopPrank();

        (int256 cursedAttack, int256 cursedDefense, int256 cursedPercent) = equipment.getModifiedStats(tokenId);
        // Flat modifiers: baseAttack-2, baseDefense-1, -25% modifier returned separately
        assertEq(cursedAttack, int256(baseAttack) - 2);
        assertEq(cursedDefense, int256(baseDefense) - 1);
        assertEq(cursedPercent, -25); // -25% modifier
    }

    function testStatsCanBeNegative() public {
        // Configure a very negative equipment
        vm.prank(admin);
        equipment.configureEquipment(200, -100, -100, -99, false);

        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        unimonItems.mint(user1, 200, 1);
        vm.stopPrank();

        vm.prank(user1);
        equipment.equipItem(tokenId, 200);

        (int256 attack, int256 defense, int256 percent) = equipment.getModifiedStats(tokenId);
        assertEq(attack, -99); // Can go negative (1 - 100 = -99)
        assertEq(defense, -99); // Can go negative (1 - 100 = -99)
        assertEq(percent, -99); // Very negative percentage modifier
    }

    function testEmergencyUnequip() public {
        // Setup and equip
        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        unimonItems.mint(user1, SWORD_ID, 1);
        vm.stopPrank();

        vm.prank(user1);
        equipment.equipItem(tokenId, SWORD_ID);

        // Admin emergency unequip
        vm.prank(admin);
        equipment.emergencyUnequip(tokenId);

        // Verify unequipped and item returned to user
        assertEq(equipment.getEquippedItem(tokenId), 0);
        assertEq(unimonItems.balanceOf(user1, SWORD_ID), 1);
    }

    function testRemoveEquipmentConfig() public {
        assertTrue(equipment.isEquipmentConfigured(SWORD_ID));

        vm.prank(admin);
        equipment.removeEquipmentConfig(SWORD_ID);

        assertFalse(equipment.isEquipmentConfigured(SWORD_ID));
    }

    function testEvents() public {
        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        unimonItems.mint(user1, SWORD_ID, 1);
        vm.stopPrank();

        vm.startPrank(user1);

        // Test equip event
        vm.expectEmit(true, true, true, false);
        emit UnimonEquipment.ItemEquipped(tokenId, SWORD_ID, user1);
        equipment.equipItem(tokenId, SWORD_ID);

        // Test unequip event
        vm.expectEmit(true, true, true, false);
        emit UnimonEquipment.ItemUnequipped(tokenId, SWORD_ID, user1);
        equipment.unequipItem(tokenId);
        vm.stopPrank();
    }

    function testAutoUnequipEvents() public {
        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        unimonItems.mint(user1, SWORD_ID, 1);
        unimonItems.mint(user1, SHIELD_ID, 1);
        vm.stopPrank();

        vm.startPrank(user1);
        equipment.equipItem(tokenId, SWORD_ID);

        // When equipping shield, should emit unequip event for sword then equip event for shield
        vm.expectEmit(true, true, true, false);
        emit UnimonEquipment.ItemUnequipped(tokenId, SWORD_ID, user1);
        vm.expectEmit(true, true, true, false);
        emit UnimonEquipment.ItemEquipped(tokenId, SHIELD_ID, user1);
        equipment.equipItem(tokenId, SHIELD_ID);
        vm.stopPrank();
    }

    // Tests for hasConsumableEquipped view function
    function testHasConsumableEquippedNoItem() public {
        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        vm.stopPrank();

        assertFalse(equipment.hasConsumableEquipped(tokenId));
    }

    function testHasConsumableEquippedNonConsumable() public {
        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        unimonItems.mint(user1, SWORD_ID, 1);
        vm.stopPrank();

        vm.prank(user1);
        equipment.equipItem(tokenId, SWORD_ID);

        assertFalse(equipment.hasConsumableEquipped(tokenId));
    }

    function testHasConsumableEquippedConsumable() public {
        // Configure a consumable item
        vm.prank(admin);
        equipment.configureEquipment(999, 5, 3, 10, true); // Consumable potion

        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        unimonItems.mint(user1, 999, 1);
        vm.stopPrank();

        vm.prank(user1);
        equipment.equipItem(tokenId, 999);

        assertTrue(equipment.hasConsumableEquipped(tokenId));
    }

    // Tests for consumeUponBattle function
    function testConsumeUponBattle() public {
        // Configure a consumable item
        vm.prank(admin);
        equipment.configureEquipment(999, 5, 3, 10, true); // Consumable potion

        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        unimonItems.mint(user1, 999, 1);
        vm.stopPrank();

        vm.prank(user1);
        equipment.equipItem(tokenId, 999);

        // Verify item is equipped
        assertEq(equipment.getEquippedItem(tokenId), 999);
        assertTrue(equipment.hasConsumableEquipped(tokenId));

        // Consume the item
        vm.prank(admin);
        equipment.consumeUponBattle(tokenId);

        // Verify item is consumed (burned) and unequipped
        assertEq(equipment.getEquippedItem(tokenId), 0);
        assertFalse(equipment.hasConsumableEquipped(tokenId));
        assertEq(unimonItems.balanceOf(address(equipment), 999), 0);
        assertEq(unimonItems.balanceOf(user1, 999), 0); // Item was burned, not returned
    }

    function testConsumeUponBattleOnlyManager() public {
        // Configure a consumable item
        vm.prank(admin);
        equipment.configureEquipment(999, 5, 3, 10, true);

        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        unimonItems.mint(user1, 999, 1);
        vm.stopPrank();

        vm.prank(user1);
        equipment.equipItem(tokenId, 999);

        // Non-manager cannot consume
        vm.prank(user1);
        vm.expectRevert();
        equipment.consumeUponBattle(tokenId);
    }

    function testConsumeUponBattleNoItemEquipped() public {
        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert("No item equipped");
        equipment.consumeUponBattle(tokenId);
    }

    function testConsumeUponBattleNonConsumableItem() public {
        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        unimonItems.mint(user1, SWORD_ID, 1);
        vm.stopPrank();

        vm.prank(user1);
        equipment.equipItem(tokenId, SWORD_ID);

        // Cannot consume non-consumable item
        vm.prank(admin);
        vm.expectRevert("Equipped item is not consumable");
        equipment.consumeUponBattle(tokenId);
    }

    function testConsumeUponBattleEmitsEvent() public {
        // Configure a consumable item
        vm.prank(admin);
        equipment.configureEquipment(999, 5, 3, 10, true);

        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        unimonItems.mint(user1, 999, 1);
        vm.stopPrank();

        vm.prank(user1);
        equipment.equipItem(tokenId, 999);

        // Consume should emit ItemUnequipped event
        vm.prank(admin);
        vm.expectEmit(true, true, true, false);
        emit UnimonEquipment.ItemUnequipped(tokenId, 999, user1);
        equipment.consumeUponBattle(tokenId);
    }

    function testConsumeUponBattleMultipleConsumables() public {
        // Configure multiple consumable items
        vm.startPrank(admin);
        equipment.configureEquipment(100, 5, 0, 0, true); // Consumable attack potion
        equipment.configureEquipment(101, 0, 5, 0, true); // Consumable defense potion
        equipment.configureEquipment(102, 3, 3, 10, true); // Consumable all-around potion
        vm.stopPrank();

        vm.startPrank(admin);
        uint256 tokenId = unimonV2.safeMint(user1);
        unimonItems.mint(user1, 100, 1);
        unimonItems.mint(user1, 101, 1);
        unimonItems.mint(user1, 102, 1);
        vm.stopPrank();

        vm.startPrank(user1);
        // Equip first consumable
        equipment.equipItem(tokenId, 100);
        assertTrue(equipment.hasConsumableEquipped(tokenId));

        // Consume it
        vm.stopPrank();
        vm.prank(admin);
        equipment.consumeUponBattle(tokenId);
        assertFalse(equipment.hasConsumableEquipped(tokenId));

        // Equip second consumable
        vm.prank(user1);
        equipment.equipItem(tokenId, 101);
        assertTrue(equipment.hasConsumableEquipped(tokenId));

        // Consume it
        vm.prank(admin);
        equipment.consumeUponBattle(tokenId);
        assertFalse(equipment.hasConsumableEquipped(tokenId));

        // Equip third consumable
        vm.prank(user1);
        equipment.equipItem(tokenId, 102);
        assertTrue(equipment.hasConsumableEquipped(tokenId));

        // Consume it
        vm.prank(admin);
        equipment.consumeUponBattle(tokenId);
        assertFalse(equipment.hasConsumableEquipped(tokenId));
        vm.stopPrank();
    }
}
