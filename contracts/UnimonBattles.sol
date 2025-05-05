// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {UnimonEnergy} from "./UnimonEnergy.sol";
import {UnimonHook} from "./UnimonHook.sol";

/// @title UnimonBattles
/// @notice Manages battle mechanics and lifecycle for Unimon
/// @dev Implements battle system with randomness, cycle management, and revival mechanics
contract UnimonBattles is AccessControl {
    /// @notice Role identifier for accounts that can provide randomness
    bytes32 public constant RANDOMNESS_ROLE = keccak256("RANDOMNESS_ROLE");

    /// @notice Maximum number of times a Unimon can be revived
    uint256 public constant MAX_REVIVES = 2;
    /// @notice Duration of each battle cycle in seconds
    uint256 public constant CYCLE_DURATION = 24 hours;
    /// @notice Grace period at the end of each cycle for admin operations
    uint256 public constant ADMIN_GRACE_PERIOD = 1 hours;

    /// @notice Timestamp when the battle system starts
    uint256 public startTimestamp;
    /// @notice Reference to the UnimonEnergy contract
    UnimonEnergy public unimonEnergy;
    /// @notice Reference to the UnimonHook contract
    UnimonHook public unimonHook;
    /// @notice Counter for tracking encounter IDs
    uint256 public currentEncounterId;
    /// @notice Flag to enable/disable battle functionality
    bool public battleEnabled;

    /// @notice Maps Unimon ID to their battle data
    mapping(uint256 => BattleData) public unimonBattleData;
    /// @notice Maps encounter ID to encounter data
    mapping(uint256 => Encounter) public encounters;
    /// @notice Maps cycle ID to cycle data
    mapping(uint256 => CycleData) public cycles;
    /// @notice Maps cycle ID to initialization status
    mapping(uint256 => bool) public cycleInitialized;

    /// @notice Represents the different states a Unimon can be in
    enum BattleStatus {
        READY, // Able to participate in a battle
        IN_BATTLE, // In an unfinished encounter
        WON, // Won for the active cycle
        LOST, // Lost for the active cycle
        FAINTED, // Lost or did not enter a battle in the previous cycle
        DEAD // Permanently out of the game
    }

    /// @notice Stores battle-related data for each Unimon
    struct BattleData {
        BattleStatus status;
        uint256 reviveCount;
        uint256 currentEncounterId;
    }

    /// @notice Stores data for each battle encounter
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

    /// @notice Stores data for each battle cycle
    struct CycleData {
        uint256 startTime;
        bool cycleComplete;
        mapping(uint256 => bool) isActive;
    }

    /// @notice Emitted when a new cycle starts
    /// @param cycleId The ID of the started cycle
    /// @param startTime The timestamp when the cycle started
    event CycleStarted(uint256 indexed cycleId, uint256 startTime);

    /// @notice Emitted when a battle encounter begins
    /// @param encounterId Unique identifier for the encounter
    /// @param attackerId ID of the attacking Unimon
    /// @param defenderId ID of the defending Unimon
    /// @param attackerPlayer Address of the attacker's owner
    /// @param defenderPlayer Address of the defender's owner
    /// @param timestamp When the encounter started
    /// @param battleCycle Current cycle number
    event EncounterStarted(
        uint256 indexed encounterId,
        uint256 indexed attackerId,
        uint256 indexed defenderId,
        address attackerPlayer,
        address defenderPlayer,
        uint256 timestamp,
        uint256 battleCycle
    );

    /// @notice Emitted when a battle encounter is resolved
    /// @param encounterId Unique identifier for the encounter
    /// @param winnerId ID of the winning Unimon
    /// @param loserId ID of the losing Unimon
    /// @param winnerPlayer Address of the winner's owner
    /// @param loserPlayer Address of the loser's owner
    /// @param timestamp When the encounter was resolved
    /// @param battleCycle Current cycle number
    event EncounterResolved(
        uint256 indexed encounterId,
        uint256 indexed winnerId,
        uint256 indexed loserId,
        address winnerPlayer,
        address loserPlayer,
        uint256 timestamp,
        uint256 battleCycle
    );

    /// @notice Emitted when a cycle is completed
    /// @param cycleId The ID of the completed cycle
    event CycleCompleted(uint256 indexed cycleId);

    /// @notice Emitted when a Unimon is revived
    /// @param unimonId ID of the revived Unimon
    /// @param player Address of the player who revived the Unimon
    /// @param reviveCost Amount of energy spent on revival
    /// @param newReviveCount Updated count of revivals for this Unimon
    /// @param timestamp When the revival occurred
    /// @param battleCycle Current cycle number
    event UnimonRevived(
        uint256 indexed unimonId,
        address indexed player,
        uint256 reviveCost,
        uint256 newReviveCount,
        uint256 timestamp,
        uint256 battleCycle
    );

    /// @notice Emitted when randomness is requested for a battle
    /// @param encounterId ID of the encounter requiring randomness
    /// @param timestamp When randomness was requested
    /// @param battleCycle Current cycle number
    event RandomnessRequested(uint256 indexed encounterId, uint256 timestamp, uint256 battleCycle);

    /// @notice Emitted when randomness is fulfilled for a battle
    /// @param encounterId ID of the encounter receiving randomness
    /// @param timestamp When randomness was fulfilled
    /// @param battleCycle Current cycle number
    event RandomnessFulfilled(uint256 indexed encounterId, uint256 timestamp, uint256 battleCycle);

    /// @notice Caller is not the owner of the Unimon
    error NotOwner();
    /// @notice Unimon is not hatched yet
    error NotHatched();
    /// @notice Unimon is not in READY state
    error NotReady();
    /// @notice Invalid battle state for the requested operation
    error InvalidBattleState();
    /// @notice Unimon has exceeded maximum revival attempts
    error TooManyRevives();
    /// @notice Battle is not yet resolved
    error BattleNotResolved();
    /// @notice Randomness not yet provided for the battle
    error RandomnessNotFulfilled();
    /// @notice Invalid battle ID provided
    error InvalidBattleId();
    /// @notice Cycle is not active
    error CycleNotActive();
    /// @notice Unimon has already participated in this cycle
    error AlreadyParticipated();
    /// @notice Operation attempted outside battle window
    error OutsideBattleWindow();
    /// @notice Operation attempted during active battle window
    error BattleWindowActive();
    /// @notice Opponent Unimon is not ready for battle
    error OpponentNotReady();
    /// @notice Battles are currently disabled
    error BattlesNotEnabled();

    /// @notice Initializes the battle contract
    /// @param _unimonHook Address of the UnimonHook contract
    /// @param _unimonEnergy Address of the UnimonEnergy contract
    /// @param _startTimestamp When the battle system should start
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

    /// @notice Get information about the current battle cycle
    /// @return cycleId The current cycle number
    /// @return startTime The start time of the current cycle
    /// @return cycleComplete Whether the current cycle is complete
    function getCurrentCycleInfo() external view returns (uint256 cycleId, uint256 startTime, bool cycleComplete) {
        uint256 cycle = getCurrentCycleNumber();
        uint256 cycleStartTime = startTimestamp + ((cycle - 1) * CYCLE_DURATION);
        return (cycle, cycleStartTime, cycles[cycle].cycleComplete);
    }

    /// @notice Get battle statuses for multiple Unimons in bulk
    /// @param unimonIds Array of Unimon IDs to query
    /// @return statuses Array of BattleData structs containing status information
    function getBulkUnimonStatuses(uint256[] calldata unimonIds) external view returns (BattleData[] memory statuses) {
        statuses = new BattleData[](unimonIds.length);
        for (uint256 i = 0; i < unimonIds.length; i++) {
            statuses[i] = unimonBattleData[unimonIds[i]];
        }
        return statuses;
    }

    /// @notice Check if current time is within the active battle window
    /// @return bool True if within battle window, false otherwise
    function isWithinBattleWindow() public view returns (bool) {
        if (block.timestamp < startTimestamp) return false;

        uint256 timeElapsed = block.timestamp - startTimestamp;
        uint256 currentCycleElapsed = timeElapsed % CYCLE_DURATION;
        return currentCycleElapsed <= (CYCLE_DURATION - ADMIN_GRACE_PERIOD);
    }

    /// @notice Calculate the start time of the next battle cycle
    /// @return uint256 Timestamp when the next cycle will start
    function getNextCycleStartTime() public view returns (uint256) {
        return startTimestamp + (getCurrentCycleNumber() * CYCLE_DURATION);
    }

    /// @notice Get the current cycle number
    /// @return uint256 Current cycle number (0 if battle system hasn't started)
    function getCurrentCycleNumber() public view returns (uint256) {
        if (block.timestamp < startTimestamp) return 0;
        return ((block.timestamp - startTimestamp) / CYCLE_DURATION) + 1;
    }

    ///////////////////////////////////////////////////////////////////////////////
    //                                                                           //
    //                              User Functions                               //
    //                                                                           //
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Start a battle between two Unimons
    /// @dev Initiates a battle encounter and requests randomness for resolution
    /// @param attackerId ID of the attacking Unimon
    /// @param defenderId ID of the defending Unimon
    /// @custom:requirements
    /// - Caller must own the attacking Unimon
    /// - Both Unimons must be hatched and in READY state
    /// - Battle system must be enabled
    /// - Must be within battle window
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

    /// @notice Resolve a battle after randomness has been fulfilled
    /// @dev Finalizes the battle outcome and updates Unimon statuses
    /// @param battleId ID of the battle encounter to resolve
    /// @custom:requirements
    /// - Must be within battle window
    /// - Randomness must be fulfilled
    /// - Battle must not be already resolved
    function finishThem(uint256 battleId) external {
        if (!isWithinBattleWindow()) revert OutsideBattleWindow();
        Encounter storage encounter = encounters[battleId];
        if (!encounter.randomnessFulfilled) revert RandomnessNotFulfilled();
        if (encounter.resolved) revert BattleNotResolved();

        _resolveBattle(battleId);
    }

    /// @notice Revive a fainted Unimon using energy
    /// @dev Burns energy tokens to revive a Unimon, limited by MAX_REVIVES
    /// @param unimonId ID of the Unimon to revive
    /// @custom:requirements
    /// - Must be within battle window
    /// - Unimon must be in FAINTED state
    /// - Must not exceed MAX_REVIVES
    /// - Must have sufficient energy tokens
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

    /// @notice Determines the winner of a battle based on Unimon levels and random number
    /// @dev Uses weighted randomness based on Unimon levels
    /// @param battleId ID of the battle encounter
    /// @return uint256 ID of the winning Unimon
    function _selectWinner(uint256 battleId) internal view returns (uint256) {
        Encounter storage encounter = encounters[battleId];

        UnimonHook.UnimonData memory attackerData = unimonHook.getUnimonData(encounter.attacker);
        UnimonHook.UnimonData memory defenderData = unimonHook.getUnimonData(encounter.defender);

        uint256 totalWeight = attackerData.level + defenderData.level;
        uint256 randomValue = encounter.randomNumber % totalWeight;

        return randomValue < attackerData.level ? encounter.attacker : encounter.defender;
    }

    /// @notice Ensures the current cycle is properly initialized
    /// @dev Creates cycle data if not already initialized
    function _ensureCycleInitialized() internal {
        uint256 cycle = getCurrentCycleNumber();
        if (!cycleInitialized[cycle]) {
            cycleInitialized[cycle] = true;
            cycles[cycle].startTime = startTimestamp + ((cycle - 1) * CYCLE_DURATION);
            cycles[cycle].cycleComplete = false;
            emit CycleStarted(cycle, cycles[cycle].startTime);
        }
    }

    /// @notice Resolves a battle encounter and updates Unimon statuses
    /// @dev Determines winner and updates battle states
    /// @param battleId ID of the battle encounter to resolve
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

    /// @notice Enable or disable the battle system
    /// @dev Only callable by admin role
    /// @param enable True to enable battles, false to disable
    function toggleBattles(bool enable) external onlyRole(DEFAULT_ADMIN_ROLE) {
        battleEnabled = enable;
    }

    /// @notice Fulfill randomness for multiple battle encounters
    /// @dev Only callable by randomness provider role
    /// @param battleIds Array of battle IDs to fulfill randomness for
    /// @param randomNumbers Array of random numbers to use
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

    /// @notice Force resolve incomplete battles in a range
    /// @dev Only callable by admin role, uses timestamp-based randomness as fallback
    /// @param startId Start of the battle ID range
    /// @param endId End of the battle ID range (inclusive)
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

    /// @notice Update Unimon statuses for the next cycle
    /// @dev Only callable by admin role
    /// @param startId Start of the Unimon ID range
    /// @param endId End of the Unimon ID range (inclusive)
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

    /// @notice Mark a cycle as complete
    /// @dev Only callable by admin role
    /// @param cycleId ID of the cycle to complete
    function completeCycle(uint256 cycleId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!cycleInitialized[cycleId]) revert CycleNotActive();

        cycles[cycleId].cycleComplete = true;
        emit CycleCompleted(cycleId);
    }

    /// @notice Grant randomness provider role to multiple addresses
    /// @dev Only callable by admin role
    /// @param addresses Array of addresses to grant role to
    function bulkGrantRandomness(address[] calldata addresses) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < addresses.length; i++) {
            _grantRole(RANDOMNESS_ROLE, addresses[i]);
        }
    }

    /// @notice Set unhatched Unimons to DEAD status
    /// @dev Only callable by admin role
    /// @param startId Start of the Unimon ID range
    /// @param endId End of the Unimon ID range (inclusive)
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

    /// @notice Update battle states for multiple Unimons
    /// @dev Only callable by admin role
    /// @param unimonIds Array of Unimon IDs to update
    /// @param newStates Array of new battle states to set
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
