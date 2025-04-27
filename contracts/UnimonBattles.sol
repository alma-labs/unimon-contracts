// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UnimonEnergy} from "./UnimonEnergy.sol";
import {UnimonHook} from "./UnimonHook.sol";

contract UnimonBattles is Ownable {
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
        uint256 lastBattleCycle;
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
        uint256 timestamp
    );
    event EncounterResolved(
        uint256 indexed encounterId,
        uint256 indexed winnerId,
        uint256 indexed loserId,
        address winnerPlayer,
        address loserPlayer,
        uint256 timestamp
    );
    event CycleCompleted(uint256 indexed cycleId, uint256 indexed winner);
    event UnimonRevived(
        uint256 indexed unimonId,
        address indexed player,
        uint256 reviveCost,
        uint256 newReviveCount,
        uint256 timestamp
    );
    event RandomnessRequested(uint256 indexed encounterId, uint256 timestamp);
    event RandomnessFulfilled(uint256 indexed encounterId, uint256 timestamp);

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

    constructor(address _unimonHook, address _unimonEnergy, uint256 _startTimestamp) Ownable(msg.sender) {
        require(_startTimestamp > block.timestamp, "Start time must be in future");
        unimonHook = UnimonHook(_unimonHook);
        unimonEnergy = UnimonEnergy(_unimonEnergy);
        startTimestamp = _startTimestamp;
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

    function isWithinBattleWindow() public view returns (bool) {
        if (block.timestamp < startTimestamp) return false;

        uint256 timeElapsed = block.timestamp - startTimestamp;
        uint256 currentCycleElapsed = timeElapsed % CYCLE_DURATION;
        return currentCycleElapsed <= (CYCLE_DURATION - ADMIN_GRACE_PERIOD);
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
        if (!isWithinBattleWindow()) revert OutsideBattleWindow();
        if (!battleEnabled) revert BattlesNotEnabled();
        ensureCycleInitialized();
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
        encounters[encounterId] = Encounter({
            attacker: attackerId,
            defender: defenderId,
            resolved: false,
            winner: 0,
            timestamp: block.timestamp,
            randomnessRequested: true,
            randomnessFulfilled: false,
            battleCycle: getCurrentCycleNumber(),
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
            block.timestamp
        );
        emit RandomnessRequested(encounterId, block.timestamp);
    }

    function finishThem(uint256 battleId) external {
        if (!isWithinBattleWindow()) revert OutsideBattleWindow();
        Encounter storage encounter = encounters[battleId];
        if (!encounter.randomnessFulfilled) revert RandomnessNotFulfilled();
        if (encounter.resolved) revert BattleNotResolved();

        uint256 winner = selectWinner(battleId);
        uint256 loser = winner == encounter.attacker ? encounter.defender : encounter.attacker;

        encounter.resolved = true;
        encounter.winner = winner;

        // Simple status updates
        unimonBattleData[winner].status = BattleStatus.WON;
        unimonBattleData[loser].status = BattleStatus.LOST;

        emit EncounterResolved(
            battleId,
            winner,
            loser,
            unimonHook.ownerOf(winner),
            unimonHook.ownerOf(loser),
            block.timestamp
        );
    }

    function revive(uint256 unimonId) external {
        BattleData storage data = unimonBattleData[unimonId];
        if (data.status != BattleStatus.FAINTED) revert InvalidBattleState();
        if (data.reviveCount >= MAX_REVIVES) revert TooManyRevives();

        UnimonHook.UnimonData memory unimonData = unimonHook.getUnimonData(unimonId);
        uint256 reviveCost = unimonData.level * 1 ether;

        unimonEnergy.burn(msg.sender, reviveCost);

        data.status = BattleStatus.READY;
        data.reviveCount++;

        emit UnimonRevived(unimonId, msg.sender, reviveCost, data.reviveCount, block.timestamp);
    }

    ///////////////////////////////////////////////////////////////////////////////
    //                                                                           //
    //                             Internal Helper Functions                     //
    //                                                                           //
    ///////////////////////////////////////////////////////////////////////////////

    function selectWinner(uint256 battleId) internal view returns (uint256) {
        Encounter storage encounter = encounters[battleId];

        UnimonHook.UnimonData memory attackerData = unimonHook.getUnimonData(encounter.attacker);
        UnimonHook.UnimonData memory defenderData = unimonHook.getUnimonData(encounter.defender);

        uint256 totalWeight = attackerData.level + defenderData.level;
        uint256 randomValue = encounter.randomNumber % totalWeight;

        return randomValue < attackerData.level ? encounter.attacker : encounter.defender;
    }

    function ensureCycleInitialized() internal {
        uint256 cycle = getCurrentCycleNumber();
        if (!cycleInitialized[cycle]) {
            cycleInitialized[cycle] = true;
            cycles[cycle].startTime = startTimestamp + ((cycle - 1) * CYCLE_DURATION);
            cycles[cycle].cycleComplete = false;
            emit CycleStarted(cycle, cycles[cycle].startTime);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////
    //                                                                           //
    //                              Admin Functions                              //
    //                                                                           //
    ///////////////////////////////////////////////////////////////////////////////

    function toggleBattles(bool enable) external onlyOwner {
        battleEnabled = enable;
    }

    function fulfillRandomness(uint256[] calldata battleIds, uint256[] calldata randomNumbers) external onlyOwner {
        require(battleIds.length == randomNumbers.length, "Length mismatch");
        for (uint256 i = 0; i < battleIds.length; i++) {
            Encounter storage encounter = encounters[battleIds[i]];
            if (!encounter.randomnessRequested || encounter.randomnessFulfilled) continue;

            encounter.randomNumber = uint256(keccak256(abi.encodePacked(randomNumbers[i], battleIds[i])));
            encounter.randomnessFulfilled = true;
            emit RandomnessFulfilled(battleIds[i], block.timestamp);
        }
    }

    function resolveAnyIncompleteBattles(uint256 startId, uint256 endId) external onlyOwner {
        require(startId <= endId && endId <= currentEncounterId, "Invalid encounter range");

        for (uint256 i = startId; i <= endId; i++) {
            Encounter storage encounter = encounters[i];
            if (encounter.battleCycle != getCurrentCycleNumber()) continue;
            if (encounter.resolved) continue;
            if (!encounter.randomnessFulfilled) continue;

            uint256 winner = selectWinner(i);
            uint256 loser = winner == encounter.attacker ? encounter.defender : encounter.attacker;

            encounter.resolved = true;
            encounter.winner = winner;

            unimonBattleData[winner].status = BattleStatus.WON;
            unimonBattleData[loser].status = BattleStatus.LOST;

            emit EncounterResolved(
                i,
                winner,
                loser,
                unimonHook.ownerOf(winner),
                unimonHook.ownerOf(loser),
                block.timestamp
            );
        }
    }

    function updateStatusesForNextCycle(uint256 startId, uint256 endId) external onlyOwner {
        if (isWithinBattleWindow()) revert BattleWindowActive();

        require(startId <= endId && endId <= currentEncounterId, "Invalid encounter range");

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
}
