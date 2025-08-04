// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../contracts/v2/UnimonBattlesV2.sol";
import "../contracts/v2/UnimonV2.sol";
import "../contracts/v2/UnimonEquipment.sol";
import "../contracts/v2/UnimonItems.sol";

contract UnimonBattlesV2Test is Test {
    UnimonBattlesV2 public battles;
    UnimonV2 public unimon;
    UnimonEquipment public equipment;
    UnimonItems public items;

    address public admin = address(1);
    address public player1 = address(2);
    address public player2 = address(3);
    address public randomnessProvider = address(4);

    uint256 public constant SWORD_ID = 10; // +5 attack
    uint256 public constant SHIELD_ID = 11; // +3 defense
    uint256 public constant CURSE_ID = 12; // -2 attack, -1 defense, -25% overall
    uint256 public constant POTION_ID = 13; // +1 attack, +1 defense, +10% overall, consumable

    uint256 public startTime;

    function setUp() public {
        startTime = block.timestamp + 1 hours; // Start battles in 1 hour

        vm.startPrank(admin);

        // Deploy all contracts
        items = new UnimonItems(admin);
        unimon = new UnimonV2(address(items));
        equipment = new UnimonEquipment(address(unimon), address(items));
        battles = new UnimonBattlesV2(address(unimon), address(equipment), address(items), startTime);

        // Grant necessary roles
        unimon.grantRole(unimon.MINTER_ROLE(), admin);
        items.grantRole(items.MINTER_ROLE(), admin);
        items.grantRole(items.SPENDER_ROLE(), admin); // Admin needs to spend energy in tests
        items.grantRole(items.SPENDER_ROLE(), address(this)); // Test contract needs to spend energy in tests
        items.grantRole(items.SPENDER_ROLE(), address(unimon)); // UnimonV2 needs to spend energy for evolution
        items.grantRole(items.SPENDER_ROLE(), address(battles));
        items.grantRole(items.EQUIPMENT_ROLE(), address(equipment));
        items.grantRole(items.SPENDER_ROLE(), address(equipment));
        equipment.grantRole(equipment.EQUIPMENT_MANAGER_ROLE(), address(battles));
        battles.grantRole(battles.RANDOMNESS_ROLE(), randomnessProvider);

        // Configure equipment
        equipment.configureEquipment(SWORD_ID, 5, 0, 0, false); // +5 attack
        equipment.configureEquipment(SHIELD_ID, 0, 3, 0, false); // +3 defense
        equipment.configureEquipment(CURSE_ID, -2, -1, -25, false); // -2 attack, -1 defense, -25% overall
        equipment.configureEquipment(POTION_ID, 1, 1, 10, true); // +1 attack, +1 defense, +10% overall, consumable

        // Enable battles
        battles.toggleBattles(true);

        vm.stopPrank();

        // Mint some Unimon to players with different stats
        vm.prank(admin);
        unimon.safeMint(player1); // tokenId 0
        vm.prank(admin);
        unimon.safeMint(player2); // tokenId 1
        vm.prank(admin);
        uint256 tokenId3 = unimon.safeMint(player1); // tokenId 2

        // Evolve one Unimon to have higher stats
        vm.startPrank(admin);
        items.mint(player1, items.ENERGY_ID(), 10);
        vm.stopPrank();

        vm.startPrank(player1);
        unimon.evolve(tokenId3, 5); // This should give higher stats
        vm.stopPrank();

        // Give players some equipment and energy
        vm.startPrank(admin);
        items.mint(player1, SWORD_ID, 2);
        items.mint(player1, POTION_ID, 2);
        items.mint(player2, SHIELD_ID, 2);
        items.mint(player2, CURSE_ID, 2);
        items.mint(player1, items.ENERGY_ID(), 20);
        items.mint(player2, items.ENERGY_ID(), 20);
        vm.stopPrank();
    }

    function testInitialState() public view {
        assertEq(battles.battleEnabled(), true);
        assertEq(battles.startTimestamp(), startTime);
        assertEq(battles.getCurrentCycleNumber(), 0); // Not started yet
        assertFalse(battles.isWithinBattleWindow());
        assertFalse(battles.isWithinSpecialAttackPeriod());
    }

    function testCycleManagement() public {
        // Fast forward to battle start
        vm.warp(startTime);
        
        assertEq(battles.getCurrentCycleNumber(), 1);
        assertTrue(battles.isWithinBattleWindow());
        assertTrue(battles.isWithinSpecialAttackPeriod());

        // Check special attack level range for day 1
        (uint256 minLevel, uint256 maxLevel) = battles.getSpecialAttackLevelRange();
        assertEq(minLevel, 1);
        assertEq(maxLevel, 2);

        // Fast forward 30 minutes (end of special attack period)
        vm.warp(startTime + 31 minutes);
        assertFalse(battles.isWithinSpecialAttackPeriod());
        assertTrue(battles.isWithinBattleWindow());

        // Fast forward to admin period (23 hours + 1 second from cycle start)
        vm.warp(startTime + 23 hours + 1);
        assertFalse(battles.isWithinBattleWindow());

        // Fast forward to next day
        vm.warp(startTime + 24 hours);
        assertEq(battles.getCurrentCycleNumber(), 2);
        assertTrue(battles.isWithinSpecialAttackPeriod());
        
        // Check level range for day 2
        (minLevel, maxLevel) = battles.getSpecialAttackLevelRange();
        assertEq(minLevel, 1);
        assertEq(maxLevel, 4);
    }

    function testSpecialAttackLevelRangeProgression() public {
        vm.warp(startTime);
        
        uint256 minLevel;
        uint256 maxLevel;

        // Test first 10 days
        for (uint256 day = 1; day <= 10; day++) {
            vm.warp(startTime + (day - 1) * 24 hours);
            (minLevel, maxLevel) = battles.getSpecialAttackLevelRange();
            assertEq(minLevel, 1);
            assertEq(maxLevel, day * 2);
        }

        // Test day 10+
        vm.warp(startTime + 10 * 24 hours);
        (minLevel, maxLevel) = battles.getSpecialAttackLevelRange();
        assertEq(minLevel, 1);
        assertEq(maxLevel, 20);
    }

    function testBasicBattle() public {
        vm.warp(startTime + 1 hours); // Skip special attack period

        // Start a battle
        vm.prank(player1);
        battles.startBattle(0, 1); // tokenId 0 attacks tokenId 1

        // Check encounter was created
        assertEq(battles.currentEncounterId(), 1);
        
        (
            uint256 battleCycle,
            uint256 attacker,
            uint256 defender,
            bool resolved,
            uint256 winner,
            ,
            bool randomnessRequested,
            bool randomnessFulfilled,
            uint256 randomNumber
        ) = battles.encounters(1);

        assertEq(battleCycle, 1);
        assertEq(attacker, 0);
        assertEq(defender, 1);
        assertFalse(resolved);
        assertEq(winner, 0);
        assertTrue(randomnessRequested);
        assertFalse(randomnessFulfilled);
        assertEq(randomNumber, 0);

        // Check Unimon are now in battle
        (UnimonBattlesV2.BattleStatus status1, , uint256 encounterId1) = battles.unimonBattleData(0);
        (UnimonBattlesV2.BattleStatus status2, , uint256 encounterId2) = battles.unimonBattleData(1);
        
        assertEq(uint256(status1), uint256(UnimonBattlesV2.BattleStatus.IN_BATTLE));
        assertEq(uint256(status2), uint256(UnimonBattlesV2.BattleStatus.IN_BATTLE));
        assertEq(encounterId1, 1);
        assertEq(encounterId2, 1);
    }

    function testBattleWithRandomnessAndResolution() public {
        vm.warp(startTime + 1 hours); // Skip special attack period

        // Start a battle
        vm.prank(player1);
        battles.startBattle(0, 1);

        // Provide randomness
        uint256[] memory battleIds = new uint256[](1);
        uint256[] memory randomNumbers = new uint256[](1);
        battleIds[0] = 1;
        randomNumbers[0] = 12345;

        vm.prank(randomnessProvider);
        battles.fulfillRandomness(battleIds, randomNumbers);

        // Check randomness was fulfilled
        (, , , , , , , bool randomnessFulfilled, uint256 randomNumber) = battles.encounters(1);
        assertTrue(randomnessFulfilled);
        assertGt(randomNumber, 0); // Should be hash of input

        // Resolve the battle
        battles.finishThem(1);

        // Check battle was resolved
        (, , , bool resolved, uint256 winner, , , , ) = battles.encounters(1);
        assertTrue(resolved);
        assertTrue(winner == 0 || winner == 1); // Winner should be one of the participants

        // Check final statuses
        (UnimonBattlesV2.BattleStatus status1, , ) = battles.unimonBattleData(0);
        (UnimonBattlesV2.BattleStatus status2, , ) = battles.unimonBattleData(1);
        
        if (winner == 0) {
            assertEq(uint256(status1), uint256(UnimonBattlesV2.BattleStatus.WON));
            assertEq(uint256(status2), uint256(UnimonBattlesV2.BattleStatus.LOST));
        } else {
            assertEq(uint256(status1), uint256(UnimonBattlesV2.BattleStatus.LOST));
            assertEq(uint256(status2), uint256(UnimonBattlesV2.BattleStatus.WON));
        }
    }

    function testBattleWithEquipment() public {
        vm.warp(startTime + 1 hours);

        // Equip items to modify stats
        vm.prank(player1);
        equipment.equipItem(0, SWORD_ID); // +5 attack

        vm.prank(player2);
        equipment.equipItem(1, SHIELD_ID); // +3 defense

        // Check modified stats
        (int256 attack1, int256 defense1, int256 percent1) = equipment.getModifiedStats(0);
        (int256 attack2, int256 defense2, int256 percent2) = equipment.getModifiedStats(1);
        
        assertEq(attack1, 6); // 1 base + 5 from sword
        assertEq(defense1, 1); // 1 base
        assertEq(percent1, 0);
        assertEq(attack2, 1); // 1 base
        assertEq(defense2, 4); // 1 base + 3 from shield
        assertEq(percent2, 0);

        // Start and resolve battle
        vm.prank(player1);
        battles.startBattle(0, 1);

        uint256[] memory battleIds = new uint256[](1);
        uint256[] memory randomNumbers = new uint256[](1);
        battleIds[0] = 1;
        randomNumbers[0] = 12345; // Random input (will be hashed)

        vm.prank(randomnessProvider);
        battles.fulfillRandomness(battleIds, randomNumbers);

        battles.finishThem(1);

        // Battle should be resolved with either participant winning
        (, , , , uint256 winner, , , , ) = battles.encounters(1);
        assertTrue(winner == 0 || winner == 1); // Either participant can win
    }

    function testBattleWithConsumableEquipment() public {
        vm.warp(startTime + 1 hours);

        // Equip consumable potion
        vm.prank(player1);
        equipment.equipItem(0, POTION_ID);

        // Verify item is equipped and consumable
        assertEq(equipment.getEquippedItem(0), POTION_ID);
        assertTrue(equipment.hasConsumableEquipped(0));

        // Start and resolve battle
        vm.prank(player1);
        battles.startBattle(0, 1);

        uint256[] memory battleIds = new uint256[](1);
        uint256[] memory randomNumbers = new uint256[](1);
        battleIds[0] = 1;
        randomNumbers[0] = 5000;

        vm.prank(randomnessProvider);
        battles.fulfillRandomness(battleIds, randomNumbers);

        battles.finishThem(1);

        // Potion should be consumed after battle regardless of outcome
        assertEq(equipment.getEquippedItem(0), 0);
        assertFalse(equipment.hasConsumableEquipped(0));
    }

    function testNegativeStatsFromEquipment() public {
        vm.warp(startTime + 1 hours);

        // Equip curse that reduces stats
        vm.prank(player2);
        equipment.equipItem(1, CURSE_ID); // -2 attack, -1 defense, -25% overall

        // Check stats (should be clamped to minimum 1)
        (int256 attack, int256 defense, int256 percent) = equipment.getModifiedStats(1);
        assertEq(attack, -1); // 1 base - 2 curse = -1
        assertEq(defense, 0); // 1 base - 1 curse = 0
        assertEq(percent, -25);

        // Start battle - stats should be clamped to 1 in battle calculations
        vm.prank(player1);
        battles.startBattle(0, 1);

        uint256[] memory battleIds = new uint256[](1);
        uint256[] memory randomNumbers = new uint256[](1);
        battleIds[0] = 1;
        randomNumbers[0] = 2500; // 25% roll

        vm.prank(randomnessProvider);
        battles.fulfillRandomness(battleIds, randomNumbers);

        battles.finishThem(1);

        // Should not revert due to negative stats
        (, , , bool resolved, , , , , ) = battles.encounters(1);
        assertTrue(resolved);
    }

    function testRevivalMechanics() public {
        vm.warp(startTime + 1 hours);

        // Set up a Unimon as FAINTED
        vm.prank(admin);
        battles.bulkUpdateBattleStates(
            _toArray(0),
            _toBattleStatusArray(UnimonBattlesV2.BattleStatus.FAINTED)
        );

        // Get current energy balance
        uint256 energyBefore = items.balanceOf(player1, items.ENERGY_ID());

        // Calculate expected revival cost (base stats: 1+1=2, so cost = (2+1)/2 = 1)
        uint256 expectedCost = 1; // (2+1)/2 rounded down

        // Revive the Unimon
        vm.prank(player1);
        battles.revive(0);

        // Check energy was spent
        uint256 energyAfter = items.balanceOf(player1, items.ENERGY_ID());
        assertEq(energyBefore - energyAfter, expectedCost);

        // Check Unimon is now READY
        (UnimonBattlesV2.BattleStatus status, uint256 reviveCount, ) = battles.unimonBattleData(0);
        assertEq(uint256(status), uint256(UnimonBattlesV2.BattleStatus.READY));
        assertEq(reviveCount, 1);
    }

    function testRevivalWithEvolvedUnimon() public {
        vm.warp(startTime + 1 hours);

        // Tokenid 2 was evolved in setup, check its stats
        (uint256 attack, uint256 defense, , ) = unimon.getUnimonStats(2);
        uint256 totalLevel = attack + defense;
        uint256 expectedCost = (totalLevel + 1) / 2;

        // Set as FAINTED
        vm.prank(admin);
        battles.bulkUpdateBattleStates(
            _toArray(2),
            _toBattleStatusArray(UnimonBattlesV2.BattleStatus.FAINTED)
        );

        uint256 energyBefore = items.balanceOf(player1, items.ENERGY_ID());

        // Revive
        vm.prank(player1);
        battles.revive(2);

        uint256 energyAfter = items.balanceOf(player1, items.ENERGY_ID());
        assertEq(energyBefore - energyAfter, expectedCost);
    }

    function testSpecialAttackPeriodRestrictions() public {
        vm.warp(startTime); // Start of special attack period, day 1 (levels 1-2)

        // Try to attack with level 2 Unimon (tokenId 0: base stats 1+1=2)
        vm.prank(player1);
        battles.startBattle(0, 1); // Should work: level 2 can attack level 2

        // Reset for next test
        vm.prank(admin);
        battles.bulkUpdateBattleStates(
            _toArray(0, 1),
            _toBattleStatusArray(UnimonBattlesV2.BattleStatus.READY, UnimonBattlesV2.BattleStatus.READY)
        );

        // Try to attack with evolved Unimon (higher level)
        uint256 totalLevel = battles.getTotalLevel(2);
        if (totalLevel > 2) {
            vm.prank(player1);
            vm.expectRevert(UnimonBattlesV2.SpecialAttackLevelNotAllowed.selector);
            battles.startBattle(2, 1); // Should fail: evolved Unimon too high level
        }

        // Try to attack lower level opponent (should fail)
        // First equip something to make defender weaker
        vm.prank(player2);
        equipment.equipItem(1, CURSE_ID); // This might make defender level lower

        uint256 attackerLevel = battles.getTotalLevel(0);
        uint256 defenderLevel = battles.getTotalLevel(1);
        
        if (defenderLevel < attackerLevel) {
            vm.prank(player1);
            vm.expectRevert(UnimonBattlesV2.InvalidSpecialAttackTarget.selector);
            battles.startBattle(0, 1);
        }
    }

    function testOutsideBattleWindow() public {
        // Try to battle before start time
        vm.expectRevert(UnimonBattlesV2.OutsideBattleWindow.selector);
        vm.prank(player1);
        battles.startBattle(0, 1);

        // Try to battle during admin period (23 hours + 1 second)
        vm.warp(startTime + 23 hours + 1);
        vm.expectRevert(UnimonBattlesV2.OutsideBattleWindow.selector);
        vm.prank(player1);
        battles.startBattle(0, 1);
    }

    function testInsufficientEnergyForRevival() public {
        vm.warp(startTime + 1 hours);

        // Set up FAINTED Unimon
        vm.prank(admin);
        battles.bulkUpdateBattleStates(
            _toArray(0),
            _toBattleStatusArray(UnimonBattlesV2.BattleStatus.FAINTED)
        );

        // Remove all energy from player
        uint256 currentEnergy = items.balanceOf(player1, items.ENERGY_ID());
        vm.prank(admin);
        items.spendItem(player1, items.ENERGY_ID(), currentEnergy);

        // Try to revive - should fail
        vm.expectRevert(UnimonBattlesV2.InsufficientEnergy.selector);
        vm.prank(player1);
        battles.revive(0);
    }

    function testMaxRevives() public {
        vm.warp(startTime + 1 hours);

        // Set up FAINTED Unimon
        vm.prank(admin);
        battles.bulkUpdateBattleStates(
            _toArray(0),
            _toBattleStatusArray(UnimonBattlesV2.BattleStatus.FAINTED)
        );

        // Revive twice (MAX_REVIVES = 2)
        vm.startPrank(player1);
        battles.revive(0);
        
        // Set back to FAINTED for second revive
        vm.stopPrank();
        vm.prank(admin);
        battles.bulkUpdateBattleStates(
            _toArray(0),
            _toBattleStatusArray(UnimonBattlesV2.BattleStatus.FAINTED)
        );
        
        vm.prank(player1);
        battles.revive(0);

        // Try third revive - should fail
        vm.prank(admin);
        battles.bulkUpdateBattleStates(
            _toArray(0),
            _toBattleStatusArray(UnimonBattlesV2.BattleStatus.FAINTED)
        );

        vm.expectRevert(UnimonBattlesV2.TooManyRevives.selector);
        vm.prank(player1);
        battles.revive(0);
    }

    // Helper functions
    function _toArray(uint256 a) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](1);
        arr[0] = a;
        return arr;
    }

    function _toArray(uint256 a, uint256 b) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](2);
        arr[0] = a;
        arr[1] = b;
        return arr;
    }

    function _toBattleStatusArray(UnimonBattlesV2.BattleStatus a) internal pure returns (UnimonBattlesV2.BattleStatus[] memory) {
        UnimonBattlesV2.BattleStatus[] memory arr = new UnimonBattlesV2.BattleStatus[](1);
        arr[0] = a;
        return arr;
    }

    function _toBattleStatusArray(UnimonBattlesV2.BattleStatus a, UnimonBattlesV2.BattleStatus b) internal pure returns (UnimonBattlesV2.BattleStatus[] memory) {
        UnimonBattlesV2.BattleStatus[] memory arr = new UnimonBattlesV2.BattleStatus[](2);
        arr[0] = a;
        arr[1] = b;
        return arr;
    }
}