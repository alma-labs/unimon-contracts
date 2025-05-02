// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {UnimonEnergy} from "./UnimonEnergy.sol";
import {UnimonHook} from "./UnimonHook.sol";

contract UnimonBattles is AccessControl {
    bytes32 public constant RANDOMNESS_ROLE = keccak256("RANDOMNESS_ROLE");

    uint256 public constant MAX_REVIVES = 2;
    uint256 public constant CYCLE_DURATION = 24 hours;
    uint256 public constant ADMIN_GRACE_PERIOD = 1 hours;

    uint256 public startTimestamp;
    UnimonEnergy public unimonEnergy;
    UnimonHook public unimonHook;
    uint256 public currentEncounterId;
    bool public battleEnabled;

    mapping(uint256 => BattleData) public unimonBattleData;
    mapping(uint256 => Encounter) public encounters;
    mapping(uint256 => CycleData) public cycles;
    mapping(uint256 => bool) public cycleInitialized;

    enum BattleStatus {
        READY, // Able to participate in a battle
        IN_BATTLE, // In an unfinished encounter
        WON, // Won for the active cycle
        LOST, // Lost for the active cycle
        FAINTED, // Lost or did not enter a battle in the previous cycle
        DEAD // You're outta here!
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
    error NotHatched();
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

    constructor(address _unimonHook, address _unimonEnergy, uint256 _startTimestamp) {
        require(_startTimestamp > block.timestamp, "Start time must be in future");
        unimonHook = UnimonHook(_unimonHook);
        unimonEnergy = UnimonEnergy(_unimonEnergy);
        startTimestamp = _startTimestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(RANDOMNESS_ROLE, msg.sender);
    }

    ///////////////////////////////////////////////////////////////////////////////
    //                                                                           //
    //                              View Functions                               //
    //                                                                           //
    ///////////////////////////////////////////////////////////////////////////////

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

    ///////////////////////////////////////////////////////////////////////////////
    //                                                                           //
    //                              User Functions                               //
    //                                                                           //
    ///////////////////////////////////////////////////////////////////////////////

    function startBattle(uint256 attackerId, uint256 defenderId) external {
        bool isWindowActive = isWithinBattleWindow();
        if (!isWindowActive) revert OutsideBattleWindow();
        if (!battleEnabled) revert BattlesNotEnabled();
        _ensureCycleInitialized();
        if (attackerId == defenderId) revert InvalidBattleId();
        if (msg.sender != unimonHook.ownerOf(attackerId)) revert NotOwner();

        UnimonHook.UnimonData memory attackerUnimon = unimonHook.getUnimonData(attackerId);
        UnimonHook.UnimonData memory defenderUnimon = unimonHook.getUnimonData(defenderId);
        if (attackerUnimon.status != UnimonHook.Status.HATCHED || defenderUnimon.status != UnimonHook.Status.HATCHED)
            revert NotHatched();

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
            unimonHook.ownerOf(defenderId),
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

        UnimonHook.UnimonData memory unimonData = unimonHook.getUnimonData(unimonId);
        uint256 reviveCost = unimonData.level * 1 ether;

        unimonEnergy.burn(msg.sender, reviveCost);

        data.status = BattleStatus.READY;
        data.reviveCount++;

        uint256 currentCycle = getCurrentCycleNumber();
        emit UnimonRevived(unimonId, msg.sender, reviveCost, data.reviveCount, block.timestamp, currentCycle);
    }

    ///////////////////////////////////////////////////////////////////////////////
    //                                                                           //
    //                             Internal Helper Functions                     //
    //                                                                           //
    ///////////////////////////////////////////////////////////////////////////////

    function _selectWinner(uint256 battleId) internal view returns (uint256) {
        Encounter storage encounter = encounters[battleId];

        UnimonHook.UnimonData memory attackerData = unimonHook.getUnimonData(encounter.attacker);
        UnimonHook.UnimonData memory defenderData = unimonHook.getUnimonData(encounter.defender);

        uint256 totalWeight = attackerData.level + defenderData.level;
        uint256 randomValue = encounter.randomNumber % totalWeight;

        return randomValue < attackerData.level ? encounter.attacker : encounter.defender;
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

        emit EncounterResolved(
            battleId,
            winner,
            loser,
            unimonHook.ownerOf(winner),
            unimonHook.ownerOf(loser),
            block.timestamp,
            getCurrentCycleNumber()
        );
    }

    ///////////////////////////////////////////////////////////////////////////////
    //                                                                           //
    //                              Admin Functions                              //
    //                                                                           //
    ///////////////////////////////////////////////////////////////////////////////

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

    function killUnhatched(uint256 startId, uint256 endId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = startId; i <= endId; i++) {
            try unimonHook.getUnimonData(i) returns (UnimonHook.UnimonData memory data) {
                if (data.status == UnimonHook.Status.UNHATCHED) {
                    unimonBattleData[i].status = BattleStatus.DEAD;
                }
            } catch {
                continue;
            }
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
