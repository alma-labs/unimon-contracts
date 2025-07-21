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
        equipment.configureEquipment(SWORD_ID, 5, 0, 0); // +5 attack
        equipment.configureEquipment(SHIELD_ID, 0, 3, 0); // +3 defense
        equipment.configureEquipment(CURSE_ID, -2, -1, -25); // -2 attack, -1 defense, -25% overall

        // Grant equipment role for seamless transfers
        unimonItems.grantRole(unimonItems.EQUIPMENT_ROLE(), address(equipment));

        vm.stopPrank();
    }

    function testConfigureEquipment() public {
        vm.prank(admin);
        equipment.configureEquipment(100, 10, -5, 50);

        (int256 attack, int256 defense, int256 percent, bool configured) = equipment.equipmentStats(100);
        assertEq(attack, 10);
        assertEq(defense, -5);
        assertEq(percent, 50);
        assertTrue(configured);
    }

    function testConfigureEquipmentOnlyManager() public {
        vm.prank(user1);
        vm.expectRevert();
        equipment.configureEquipment(100, 10, -5, 50);
    }

    function testConfigureBulkEquipment() public {
        uint256[] memory itemIds = new uint256[](3);
        int256[] memory attackMods = new int256[](3);
        int256[] memory defenseMods = new int256[](3);
        int256[] memory overallMods = new int256[](3);

        itemIds[0] = 100;
        attackMods[0] = 10;
        defenseMods[0] = 5;
        overallMods[0] = 0;
        itemIds[1] = 101;
        attackMods[1] = 0;
        defenseMods[1] = 8;
        overallMods[1] = 15;
        itemIds[2] = 102;
        attackMods[2] = -2;
        defenseMods[2] = -3;
        overallMods[2] = -10;

        vm.prank(admin);
        equipment.configureBulkEquipment(itemIds, attackMods, defenseMods, overallMods);

        // Verify all items were configured correctly
        for (uint256 i = 0; i < itemIds.length; i++) {
            (int256 attack, int256 defense, int256 percent, bool configured) = equipment.equipmentStats(itemIds[i]);
            assertEq(attack, attackMods[i]);
            assertEq(defense, defenseMods[i]);
            assertEq(percent, overallMods[i]);
            assertTrue(configured);
        }
    }

    function testConfigureBulkEquipmentArrayLengthMismatch() public {
        uint256[] memory itemIds = new uint256[](2);
        int256[] memory attackMods = new int256[](3); // Different length
        int256[] memory defenseMods = new int256[](2);
        int256[] memory overallMods = new int256[](2);

        vm.prank(admin);
        vm.expectRevert("Array lengths must match");
        equipment.configureBulkEquipment(itemIds, attackMods, defenseMods, overallMods);
    }

    function testConfigureBulkEquipmentOnlyManager() public {
        uint256[] memory itemIds = new uint256[](1);
        int256[] memory attackMods = new int256[](1);
        int256[] memory defenseMods = new int256[](1);
        int256[] memory overallMods = new int256[](1);

        vm.prank(user1);
        vm.expectRevert();
        equipment.configureBulkEquipment(itemIds, attackMods, defenseMods, overallMods);
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

        // Check evolved stats (should be 11, 11)
        (uint256 baseAttack, uint256 baseDefense, , ) = unimonV2.getUnimonStats(tokenId);
        assertEq(baseAttack, 11);
        assertEq(baseDefense, 11);

        // Equip curse (-2 attack, -1 defense, -25% overall)
        equipment.equipItem(tokenId, CURSE_ID);
        vm.stopPrank();

        (int256 cursedAttack, int256 cursedDefense, int256 cursedPercent) = equipment.getModifiedStats(tokenId);
        // Flat modifiers: 11-2=9 attack, 11-1=10 defense, -25% modifier returned separately
        assertEq(cursedAttack, 9); // 11 - 2
        assertEq(cursedDefense, 10); // 11 - 1
        assertEq(cursedPercent, -25); // -25% modifier
    }

    function testStatsCanBeNegative() public {
        // Configure a very negative equipment
        vm.prank(admin);
        equipment.configureEquipment(200, -100, -100, -99);

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
}
