// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UnimonEnergy} from "./UnimonEnergy.sol";
import {UnimonHook} from "./UnimonHook.sol";

contract UnimonBattles is Ownable {
    uint256 public constant MAX_REVIVES = 2;
    uint256 public constant BATTLE_CYCLE_DURATION = 1 days;
    uint256 public constant BATTLE_CUTOFF_PERIOD = 1 hours;

    UnimonEnergy public unimonEnergy;
    UnimonHook public unimonHook;
    uint256 public nextEncounterId;
    uint256 public battleStartTime;
    bool public battleTimeInitialized;
    bool public cycleInResolution;

    enum BattleStatus {
        READY,
        IN_BATTLE,
        FAINTED,
        DEAD
    }

    struct BattleData {
        BattleStatus status;
        uint256 reviveCount;
        uint256 lastBattleTimestamp;
        uint256 currentEncounterId;
    }

    struct Encounter {
        uint256 attacker;
        uint256 defender;
        bool resolved;
        uint256 winner;
    }

    mapping(uint256 => BattleData) public battleData;
    mapping(uint256 => Encounter) public encounters;
    mapping(uint256 => uint256[]) public cycleEncounters;

    error NotOwnerOfToken();
    error AlreadyInEncounter();
    error UnimonFainted();
    error UnimonDead();
    error MaxRevivesReached();
    error RevivalPeriodEnded();
    error NotFainted();
    error SameUnimon();
    error InvalidBattleCycle();
    error NoEncountersInRange();
    error CycleInResolution();
    error UnimonNotHatched();
    error UnimonNotFound();

    event EncounterResolved(uint256 indexed encounterId, uint256 indexed winnerId, uint256 indexed loserId);

    constructor(address _unimonHook) Ownable(msg.sender) {
        unimonHook = UnimonHook(_unimonHook);
    }

    function getCurrentBattleCycle() public view returns (uint256, uint256, uint256) {
        require(battleTimeInitialized, "Battle time not initialized");
        uint256 currentCycle = (block.timestamp - battleStartTime) / BATTLE_CYCLE_DURATION;
        uint256 cycleStartTime = battleStartTime + (currentCycle * BATTLE_CYCLE_DURATION);
        uint256 cycleEndTime = cycleStartTime + BATTLE_CYCLE_DURATION;
        return (currentCycle, cycleStartTime, cycleEndTime);
    }

    function getEncounterCycle(uint256 encounterId) public view returns (uint256) {
        Encounter memory encounter = encounters[encounterId];
        require(encounter.attacker != 0, "EncounterNotFound");
        BattleData memory attackerData = battleData[encounter.attacker];
        return (attackerData.lastBattleTimestamp - battleStartTime) / BATTLE_CYCLE_DURATION;
    }

    function startEncounter(uint256 attackerId, uint256 defenderId) external {
        require(battleTimeInitialized, "Battle time not initialized");
        if (cycleInResolution) revert CycleInResolution();
        if (attackerId == defenderId) revert SameUnimon();

        // Check ownership
        if (unimonHook.ownerOf(attackerId) != msg.sender) revert NotOwnerOfToken();

        (uint256 currentCycle, , uint256 cycleEndTime) = getCurrentBattleCycle();
        if (block.timestamp + BATTLE_CUTOFF_PERIOD >= cycleEndTime) revert InvalidBattleCycle();

        // Validate Unimon states from UnimonHook
        UnimonHook.UnimonData memory attackerNFTData = unimonHook.getUnimonData(attackerId);
        UnimonHook.UnimonData memory defenderNFTData = unimonHook.getUnimonData(defenderId);

        if (attackerNFTData.status != UnimonHook.Status.HATCHED) revert UnimonNotHatched();
        if (defenderNFTData.status != UnimonHook.Status.HATCHED) revert UnimonNotHatched();

        // Validate battle states
        BattleData storage attackerBattleData = battleData[attackerId];
        BattleData storage defenderBattleData = battleData[defenderId];

        if (attackerBattleData.status != BattleStatus.READY) revert UnimonFainted();
        if (defenderBattleData.status != BattleStatus.READY) revert UnimonFainted();
        if (attackerBattleData.currentEncounterId != 0) revert AlreadyInEncounter();
        if (defenderBattleData.currentEncounterId != 0) revert AlreadyInEncounter();

        // Create encounter
        uint256 encounterId = nextEncounterId++;
        encounters[encounterId] = Encounter({attacker: attackerId, defender: defenderId, resolved: false, winner: 0});
        cycleEncounters[currentCycle].push(encounterId);

        // Update battle data
        attackerBattleData.status = BattleStatus.IN_BATTLE;
        defenderBattleData.status = BattleStatus.IN_BATTLE;
        attackerBattleData.currentEncounterId = encounterId;
        defenderBattleData.currentEncounterId = encounterId;
        attackerBattleData.lastBattleTimestamp = block.timestamp;
        defenderBattleData.lastBattleTimestamp = block.timestamp;
    }

    function reviveUnimon(uint256 tokenId) external {
        if (unimonHook.ownerOf(tokenId) != msg.sender) revert NotOwnerOfToken();

        BattleData storage battleStats = battleData[tokenId];
        if (battleStats.status != BattleStatus.FAINTED) revert NotFainted();
        if (battleStats.reviveCount >= MAX_REVIVES) revert MaxRevivesReached();

        // Check if within revival period
        uint256 currentCycle = (block.timestamp - battleStartTime) / BATTLE_CYCLE_DURATION;
        uint256 nextCycleStart = battleStartTime + ((currentCycle + 1) * BATTLE_CYCLE_DURATION);
        if (block.timestamp >= nextCycleStart) revert RevivalPeriodEnded();

        // Get level from UnimonHook
        UnimonHook.UnimonData memory unimonData = unimonHook.getUnimonData(tokenId);

        // Calculate and burn revival cost
        uint256 revivalCost = unimonData.level * (10 ** unimonEnergy.decimals());
        unimonEnergy.burn(msg.sender, revivalCost);

        // Revive Unimon
        battleStats.status = BattleStatus.READY;
        battleStats.reviveCount++;
    }

    function _resolveEncounter(uint256 id, Encounter storage enc) internal {
        BattleData storage attackerBattle = battleData[enc.attacker];
        BattleData storage defenderBattle = battleData[enc.defender];

        // Get levels from UnimonHook
        UnimonHook.UnimonData memory attackerData = unimonHook.getUnimonData(enc.attacker);
        UnimonHook.UnimonData memory defenderData = unimonHook.getUnimonData(enc.defender);

        uint256 roll = uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), id))) % 100;
        uint256 attackerOdds = (attackerData.level * 100) / (attackerData.level + defenderData.level);

        (uint256 winnerId, uint256 loserId) = roll < attackerOdds
            ? (enc.attacker, enc.defender)
            : (enc.defender, enc.attacker);

        battleData[loserId].status = BattleStatus.FAINTED;
        attackerBattle.currentEncounterId = defenderBattle.currentEncounterId = 0;
        attackerBattle.status = defenderBattle.status = BattleStatus.READY;
        enc.resolved = true;
        enc.winner = winnerId;

        emit EncounterResolved(id, winnerId, loserId);
    }

    function resolveBattles(uint256 startId, uint256 endId) external onlyOwner {
        require(cycleInResolution && startId <= endId && endId < nextEncounterId);
        (uint256 currentCycle, , ) = getCurrentBattleCycle();
        uint256 resolvedCount;

        for (uint256 i = startId; i <= endId; ) {
            Encounter storage enc = encounters[i];
            if (enc.attacker != 0 && !enc.resolved && getEncounterCycle(i) < currentCycle) {
                _resolveEncounter(i, enc);
                resolvedCount++;
            }
            unchecked {
                ++i;
            }
        }

        if (resolvedCount == 0) revert NoEncountersInRange();
    }

    function resolveDailyCycle(uint256 maxTokenId) external onlyOwner {
        require(battleTimeInitialized, "Battle time not initialized");
        require(cycleInResolution, "Must be in resolution phase");

        uint256 processedCount = 0;

        for (uint256 i = 0; i < maxTokenId; i++) {
            try unimonHook.getUnimonData(i) returns (UnimonHook.UnimonData memory nftData) {
                if (nftData.status != UnimonHook.Status.HATCHED) {
                    continue;
                }

                BattleData storage battleStats = battleData[i];

                if (battleStats.status == BattleStatus.FAINTED) {
                    battleStats.status = BattleStatus.DEAD;
                    processedCount++;
                } else if (battleStats.status == BattleStatus.READY && battleStats.currentEncounterId == 0) {
                    battleStats.status = BattleStatus.FAINTED;
                    processedCount++;
                }
            } catch {
                continue;
            }
        }

        require(processedCount > 0, "No Unimons processed");
    }

    function initializeBattleTime() external onlyOwner {
        require(!battleTimeInitialized, "Battle time already initialized");
        battleStartTime = block.timestamp;
        battleTimeInitialized = true;
    }

    function setUnimonEnergy(address _unimonEnergy) external onlyOwner {
        unimonEnergy = UnimonEnergy(_unimonEnergy);
    }

    function toggleCycleResolution() external onlyOwner {
        require(battleTimeInitialized, "Battle time not initialized");
        cycleInResolution = !cycleInResolution;
    }
}
