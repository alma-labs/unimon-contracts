// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {UnimonV2} from "./UnimonV2.sol";
import {UnimonEquipment} from "./UnimonEquipment.sol";
import {UnimonItems} from "./UnimonItems.sol";

contract UnimonBattlesV2 is AccessControl {
    bytes32 public constant RANDOMNESS_ROLE = keccak256("RANDOMNESS_ROLE");

    uint256 public constant MAX_REVIVES = 2;
    uint256 public constant CYCLE_DURATION = 24 hours;
    uint256 public constant ADMIN_GRACE_PERIOD = 1 hours;
    uint256 public constant SPECIAL_ATTACK_DURATION = 30 minutes;

    uint256 public startTimestamp;
    UnimonV2 public unimonV2;
    UnimonEquipment public unimonEquipment;
    UnimonItems public unimonItems;
    uint256 public currentEncounterId;
    bool public battleEnabled;

    mapping(uint256 => BattleData) public unimonBattleData;
    mapping(uint256 => Encounter) public encounters;
    mapping(uint256 => CycleData) public cycles;
    mapping(uint256 => bool) public cycleInitialized;

    enum BattleStatus {
        READY,
        IN_BATTLE,
        WON,
        LOST,
        FAINTED,
        DEAD
    }

    struct BattleData {
        BattleStatus status;
        uint256 reviveCount;
        uint256 currentEncounterId;
    }

    struct Encounter {
        uint256 battleCycle;
        uint256 attacker;
        uint256 defender;
        bool resolved;
        uint256 winner;
        uint256 timestamp;
        bool randomnessRequested;
        bool randomnessFulfilled;
        uint256 randomNumber;
    }

    struct CycleData {
        uint256 startTime;
        bool cycleComplete;
        mapping(uint256 => bool) isActive;
    }

    event CycleStarted(uint256 indexed cycleId, uint256 startTime);
    event EncounterStarted(
        uint256 indexed encounterId,
        uint256 indexed attackerId,
        uint256 indexed defenderId,
        address attackerPlayer,
        address defenderPlayer,
        uint256 timestamp,
        uint256 battleCycle
    );
    event EncounterResolved(
        uint256 indexed encounterId,
        uint256 indexed winnerId,
        uint256 indexed loserId,
        address winnerPlayer,
        address loserPlayer,
        uint256 timestamp,
        uint256 battleCycle
    );
    event CycleCompleted(uint256 indexed cycleId);
    event UnimonRevived(
        uint256 indexed unimonId,
        address indexed player,
        uint256 reviveCost,
        uint256 newReviveCount,
        uint256 timestamp,
        uint256 battleCycle
    );
    event RandomnessRequested(uint256 indexed encounterId, uint256 timestamp, uint256 battleCycle);
    event RandomnessFulfilled(uint256 indexed encounterId, uint256 timestamp, uint256 battleCycle);

    error NotOwner();
    error NotReady();
    error InvalidBattleState();
    error TooManyRevives();
    error BattleNotResolved();
    error RandomnessNotFulfilled();
    error InvalidBattleId();
    error CycleNotActive();
    error AlreadyParticipated();
    error OutsideBattleWindow();
    error BattleWindowActive();
    error OpponentNotReady();
    error BattlesNotEnabled();
    error InvalidSpecialAttackTarget();
    error SpecialAttackLevelNotAllowed();
    error InsufficientEnergy();

    constructor(address _unimonV2, address _unimonEquipment, address _unimonItems, uint256 _startTimestamp) {
        require(_startTimestamp > block.timestamp, "Start time must be in future");
        unimonV2 = UnimonV2(_unimonV2);
        unimonEquipment = UnimonEquipment(_unimonEquipment);
        unimonItems = UnimonItems(_unimonItems);
        startTimestamp = _startTimestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(RANDOMNESS_ROLE, msg.sender);
    }

    /*
     * View functions
     */

    function getCurrentCycleInfo() external view returns (uint256 cycleId, uint256 startTime, bool cycleComplete) {
        uint256 cycle = getCurrentCycleNumber();
        uint256 cycleStartTime = startTimestamp + ((cycle - 1) * CYCLE_DURATION);
        return (cycle, cycleStartTime, cycles[cycle].cycleComplete);
    }

    function getBulkUnimonStatuses(uint256[] calldata unimonIds) external view returns (BattleData[] memory statuses) {
        statuses = new BattleData[](unimonIds.length);
        for (uint256 i = 0; i < unimonIds.length; i++) {
            statuses[i] = unimonBattleData[unimonIds[i]];
        }
        return statuses;
    }

    function isWithinBattleWindow() public view returns (bool) {
        if (block.timestamp < startTimestamp) return false;
        uint256 timeElapsed = block.timestamp - startTimestamp;
        uint256 currentCycleElapsed = timeElapsed % CYCLE_DURATION;
        return currentCycleElapsed <= (CYCLE_DURATION - ADMIN_GRACE_PERIOD);
    }

    function getNextCycleStartTime() public view returns (uint256) {
        return startTimestamp + (getCurrentCycleNumber() * CYCLE_DURATION);
    }

    function getCurrentCycleNumber() public view returns (uint256) {
        if (block.timestamp < startTimestamp) return 0;
        return ((block.timestamp - startTimestamp) / CYCLE_DURATION) + 1;
    }

    function isWithinSpecialAttackPeriod() public view returns (bool) {
        if (block.timestamp < startTimestamp) return false;
        uint256 timeElapsed = block.timestamp - startTimestamp;
        uint256 currentCycleElapsed = timeElapsed % CYCLE_DURATION;
        return currentCycleElapsed <= SPECIAL_ATTACK_DURATION;
    }

    function getSpecialAttackLevelRange() public view returns (uint256 minLevel, uint256 maxLevel) {
        uint256 currentCycle = getCurrentCycleNumber();
        if (currentCycle == 0) return (0, 0);

        if (currentCycle >= 10) {
            return (1, 20);
        }

        // Day 1: 1-2, Day 2: 1-4, Day 3: 1-6, etc.
        minLevel = 1;
        maxLevel = currentCycle * 2;
        if (maxLevel > 20) maxLevel = 20;
    }

    function getTotalLevel(uint256 tokenId) public view returns (uint256) {
        (uint256 baseAttack, uint256 baseDefense, , ) = unimonV2.getUnimonStats(tokenId);
        return baseAttack + baseDefense;
    }

    /*
     * User functions
     */

    function startBattle(uint256 attackerId, uint256 defenderId) external {
        bool isWindowActive = isWithinBattleWindow();
        if (!isWindowActive) revert OutsideBattleWindow();
        if (!battleEnabled) revert BattlesNotEnabled();
        _ensureCycleInitialized();
        if (attackerId == defenderId) revert InvalidBattleId();
        if (msg.sender != unimonV2.ownerOf(attackerId)) revert NotOwner();

        // Special attack period validation
        if (isWithinSpecialAttackPeriod()) {
            uint256 attackerTotalLevel = getTotalLevel(attackerId);
            uint256 defenderTotalLevel = getTotalLevel(defenderId);
            (, uint256 maxLevel) = getSpecialAttackLevelRange();

            if (attackerTotalLevel > maxLevel) {
                revert SpecialAttackLevelNotAllowed();
            }

            if (defenderTotalLevel < attackerTotalLevel) {
                revert InvalidSpecialAttackTarget();
            }
        }

        BattleData storage attackerData = unimonBattleData[attackerId];
        BattleData storage defenderData = unimonBattleData[defenderId];

        if (attackerData.status != BattleStatus.READY) revert NotReady();
        if (defenderData.status != BattleStatus.READY) revert OpponentNotReady();

        uint256 encounterId = ++currentEncounterId;
        uint256 currentCycle = getCurrentCycleNumber();
        encounters[encounterId] = Encounter({
            attacker: attackerId,
            defender: defenderId,
            resolved: false,
            winner: 0,
            timestamp: block.timestamp,
            randomnessRequested: true,
            randomnessFulfilled: false,
            battleCycle: currentCycle,
            randomNumber: 0
        });

        attackerData.status = BattleStatus.IN_BATTLE;
        attackerData.currentEncounterId = encounterId;
        defenderData.status = BattleStatus.IN_BATTLE;
        defenderData.currentEncounterId = encounterId;

        emit EncounterStarted(
            encounterId,
            attackerId,
            defenderId,
            msg.sender,
            unimonV2.ownerOf(defenderId),
            block.timestamp,
            currentCycle
        );
        emit RandomnessRequested(encounterId, block.timestamp, currentCycle);
    }

    function finishThem(uint256 battleId) external {
        if (!isWithinBattleWindow()) revert OutsideBattleWindow();
        Encounter storage encounter = encounters[battleId];
        if (!encounter.randomnessFulfilled) revert RandomnessNotFulfilled();
        if (encounter.resolved) revert BattleNotResolved();

        _resolveBattle(battleId);
    }

    function revive(uint256 unimonId) external {
        bool isWindowActive = isWithinBattleWindow();
        if (!isWindowActive) revert OutsideBattleWindow();
        BattleData storage data = unimonBattleData[unimonId];
        if (data.status != BattleStatus.FAINTED) revert InvalidBattleState();
        if (data.reviveCount >= MAX_REVIVES) revert TooManyRevives();

        (uint256 baseAttack, uint256 baseDefense, , ) = unimonV2.getUnimonStats(unimonId);
        uint256 totalLevel = baseAttack + baseDefense;
        uint256 reviveCost = (totalLevel + 1) / 2; // Half rounded up

        uint256 energyId = unimonItems.ENERGY_ID();
        uint256 userEnergyBalance = unimonItems.balanceOf(msg.sender, energyId);
        if (userEnergyBalance < reviveCost) revert InsufficientEnergy();

        unimonItems.spendItem(msg.sender, energyId, reviveCost);

        data.status = BattleStatus.READY;
        data.reviveCount++;

        uint256 currentCycle = getCurrentCycleNumber();
        emit UnimonRevived(unimonId, msg.sender, reviveCost, data.reviveCount, block.timestamp, currentCycle);
    }

    /*
     * Internal functions
     */

    function _selectWinner(uint256 battleId) internal view returns (uint256) {
        Encounter storage encounter = encounters[battleId];

        // Get modified stats (always use equipment-modified stats)
        (int256 attackerTotalAttack, , int256 attackerOverallPercent) = unimonEquipment.getModifiedStats(
            encounter.attacker
        );
        (, int256 defenderTotalDefense, int256 defenderOverallPercent) = unimonEquipment.getModifiedStats(
            encounter.defender
        );

        // Handle negative/zero values properly - clamp to minimum 1
        uint256 finalAttackerAttack = attackerTotalAttack <= 0 ? 1 : uint256(attackerTotalAttack);
        uint256 finalDefenderDefense = defenderTotalDefense <= 0 ? 1 : uint256(defenderTotalDefense);

        // Calculate base odds
        uint256 totalCombatPower = finalAttackerAttack + finalDefenderDefense;
        uint256 attackerBaseChance = (finalAttackerAttack * 10000) / totalCombatPower; // in basis points

        // Apply overall percentage modifiers
        int256 netOverallModifier = defenderOverallPercent - attackerOverallPercent;
        int256 finalAttackerChance = int256(attackerBaseChance) - (netOverallModifier * 100); // convert % to basis points

        // Clamp between 100 (1%) and 9900 (99%)
        if (finalAttackerChance < 100) finalAttackerChance = 100;
        if (finalAttackerChance > 9900) finalAttackerChance = 9900;

        // Use random number to determine winner
        uint256 randomValue = encounter.randomNumber % 10000;
        return randomValue < uint256(finalAttackerChance) ? encounter.attacker : encounter.defender;
    }

    function _ensureCycleInitialized() internal {
        uint256 cycle = getCurrentCycleNumber();
        if (!cycleInitialized[cycle]) {
            cycleInitialized[cycle] = true;
            cycles[cycle].startTime = startTimestamp + ((cycle - 1) * CYCLE_DURATION);
            cycles[cycle].cycleComplete = false;
            emit CycleStarted(cycle, cycles[cycle].startTime);
        }
    }

    function _resolveBattle(uint256 battleId) internal {
        Encounter storage encounter = encounters[battleId];
        uint256 winner = _selectWinner(battleId);
        uint256 loser = winner == encounter.attacker ? encounter.defender : encounter.attacker;

        encounter.resolved = true;
        encounter.winner = winner;

        unimonBattleData[winner].status = BattleStatus.WON;
        unimonBattleData[loser].status = BattleStatus.LOST;

        // Consume equipment if consumable
        if (unimonEquipment.hasConsumableEquipped(winner)) {
            unimonEquipment.consumeUponBattle(winner);
        }
        if (unimonEquipment.hasConsumableEquipped(loser)) {
            unimonEquipment.consumeUponBattle(loser);
        }

        emit EncounterResolved(
            battleId,
            winner,
            loser,
            unimonV2.ownerOf(winner),
            unimonV2.ownerOf(loser),
            block.timestamp,
            getCurrentCycleNumber()
        );
    }

    /*
     * Admin functions
     */

    function toggleBattles(bool enable) external onlyRole(DEFAULT_ADMIN_ROLE) {
        battleEnabled = enable;
    }

    function fulfillRandomness(
        uint256[] calldata battleIds,
        uint256[] calldata randomNumbers
    ) external onlyRole(RANDOMNESS_ROLE) {
        require(battleIds.length == randomNumbers.length, "Length mismatch");
        uint256 currentCycle = getCurrentCycleNumber();
        for (uint256 i = 0; i < battleIds.length; i++) {
            Encounter storage encounter = encounters[battleIds[i]];
            if (!encounter.randomnessRequested || encounter.randomnessFulfilled) continue;

            encounter.randomNumber = uint256(keccak256(abi.encodePacked(randomNumbers[i], battleIds[i])));
            encounter.randomnessFulfilled = true;
            emit RandomnessFulfilled(battleIds[i], block.timestamp, currentCycle);
        }
    }

    function resolveAnyIncompleteBattles(uint256 startId, uint256 endId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(startId <= endId && endId <= currentEncounterId, "Invalid encounter range");

        for (uint256 i = startId; i <= endId; i++) {
            Encounter storage encounter = encounters[i];
            if (encounter.resolved) continue;
            if (!encounter.randomnessFulfilled) {
                encounter.randomNumber = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, i)));
                encounter.randomnessFulfilled = true;
                emit RandomnessFulfilled(i, block.timestamp, encounter.battleCycle);
            }

            _resolveBattle(i);
        }
    }

    function updateStatusesForNextCycle(uint256 startId, uint256 endId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = startId; i <= endId; i++) {
            BattleData storage data = unimonBattleData[i];

            if (data.status == BattleStatus.READY) {
                data.status = BattleStatus.FAINTED;
            } else if (data.status == BattleStatus.WON) {
                data.status = BattleStatus.READY;
            } else if (data.status == BattleStatus.LOST) {
                data.status = BattleStatus.FAINTED;
            } else if (data.status == BattleStatus.FAINTED) {
                data.status = BattleStatus.DEAD;
            }
        }
    }

    function completeCycle(uint256 cycleId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!cycleInitialized[cycleId]) revert CycleNotActive();
        cycles[cycleId].cycleComplete = true;
        emit CycleCompleted(cycleId);
    }

    function bulkGrantRandomness(address[] calldata addresses) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < addresses.length; i++) {
            _grantRole(RANDOMNESS_ROLE, addresses[i]);
        }
    }

    function bulkUpdateBattleStates(
        uint256[] calldata unimonIds,
        BattleStatus[] calldata newStates
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(unimonIds.length == newStates.length, "Length mismatch");

        for (uint256 i = 0; i < unimonIds.length; i++) {
            unimonBattleData[unimonIds[i]].status = newStates[i];
        }
    }
}
