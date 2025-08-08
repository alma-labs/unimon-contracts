// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {UnimonV2} from "./UnimonV2.sol";
import {UnimonEquipment} from "./UnimonEquipment.sol";

/**
 * @title UnimonSlayer
 * @notice Super simple contract to fight monsters in the wild.
 * @dev Fully on-chain, no external randomness. Randomness uses block contextual values and is not secure.
 *
 * Features:
 * - fight(tokenId, monsterId): rolls a biased-random outcome based on token's power vs monster difficulty
 * - msg.sender must own tokenId
 * - 5 predefined monsters with names and difficulty levels
 * - Tracks total fights and wins per token
 * - On-chain queries: get single or multiple monster records by ID
 */
contract UnimonSlayer {
    UnimonV2 public immutable unimon;
    UnimonEquipment public immutable equipment;
    address public owner;

    struct Monster {
        string name;         // Monster display name
        uint8 difficulty;    // 1-20 scale (Unimon power is attack+defense; max 20)
        bool active;         // Whether the monster can be fought
    }

    Monster[] public monsters;

    /// @notice Per-token fight stats
    mapping(uint256 => uint256) public totalFightsForToken;
    mapping(uint256 => uint256) public totalWinsForToken;

    /// @notice Emitted after each fight
    /// @param user The fighter (must own tokenId)
    /// @param tokenId The Unimon used to fight
    /// @param monsterId The monster being fought
    /// @param won True if the roll succeeded
    /// @param power Current Unimon power (attack+defense)
    /// @param difficulty Monster difficulty used for the roll
    event MonsterFought(
        address indexed user,
        uint256 indexed tokenId,
        uint256 indexed monsterId,
        bool won,
        uint256 power,
        uint8 difficulty
    );

    constructor(address _equipment) {
        equipment = UnimonEquipment(_equipment);
        unimon = equipment.unimonV2();
        owner = msg.sender;
        // Preconfigure 5 monsters with increasing difficulty (max power is 20)
        monsters.push(Monster({name: "Impling", difficulty: 2, active: true}));
        monsters.push(Monster({name: "Slime", difficulty: 5, active: true}));
        monsters.push(Monster({name: "Swarm", difficulty: 8, active: true}));
        monsters.push(Monster({name: "Ogre", difficulty: 12, active: true}));
        monsters.push(Monster({name: "Dragon", difficulty: 16, active: true}));
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero owner");
        owner = newOwner;
    }

    /**
     * @notice Returns total number of configured monsters
     */
    function monsterCount() external view returns (uint256) {
        return monsters.length;
    }

    /**
     * @notice Get a monster by ID
     * @param monsterId The monster ID to fetch
     * @return name The monster name
     * @return difficulty The monster difficulty (1-20)
     * @return active Whether the monster is active
     */
    function getMonster(
        uint256 monsterId
    ) external view returns (string memory name, uint8 difficulty, bool active) {
        require(monsterId < monsters.length, "Invalid monster");
        Monster memory m = monsters[monsterId];
        return (m.name, m.difficulty, m.active);
    }

    /**
     * @notice Batch fetch monsters by IDs
     * @param ids Array of monster IDs to fetch
     * @return out Array of Monster records (name, difficulty, active)
     */
    function getMonstersByIds(uint256[] calldata ids) external view returns (Monster[] memory out) {
        out = new Monster[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            require(ids[i] < monsters.length, "Invalid monster");
            out[i] = monsters[ids[i]];
        }
    }

    function addMonster(string calldata name, uint8 difficulty, bool active) external onlyOwner returns (uint256 monsterId) {
        require(bytes(name).length > 0, "Name empty");
        require(difficulty > 0 && difficulty <= 20, "Bad diff");
        monsterId = monsters.length;
        monsters.push(Monster({name: name, difficulty: difficulty, active: active}));
    }

    function updateMonster(uint256 monsterId, string calldata name, uint8 difficulty, bool active) external onlyOwner {
        require(monsterId < monsters.length, "Invalid monster");
        require(bytes(name).length > 0, "Name empty");
        require(difficulty > 0 && difficulty <= 20, "Bad diff");
        monsters[monsterId] = Monster({name: name, difficulty: difficulty, active: active});
    }

    function setMonsterActive(uint256 monsterId, bool active) external onlyOwner {
        require(monsterId < monsters.length, "Invalid monster");
        monsters[monsterId].active = active;
    }

    function removeMonster(uint256 monsterId) external onlyOwner {
        require(monsterId < monsters.length, "Invalid monster");
        monsters[monsterId].name = "";
        monsters[monsterId].difficulty = 0;
        monsters[monsterId].active = false;
    }

    /**
     * @notice Returns current Unimon power as attack+defense.
     * @dev Reads stats from UnimonV2.
     */
    function getUnimonPower(uint256 tokenId) public view returns (uint256) {
        (int256 attackLevel, int256 defenseLevel, ) = equipment.getModifiedStats(tokenId);
        uint256 atk = attackLevel <= 0 ? 1 : uint256(attackLevel);
        uint256 def = defenseLevel <= 0 ? 1 : uint256(defenseLevel);
        return atk + def;
    }

    /**
     * @notice Fight a monster. Fully random outcome biased slightly by (power - difficulty).
     * - Win probability p = clamp(50 + 3*(power - difficulty), 10..90)%
     *   This gives ~3% per point advantage/disadvantage, capped at 10%-90%.
     * @param tokenId Unimon token to fight with (must be owned by msg.sender)
     * @param monsterId Monster to fight
     * @return won True if fight succeeded
     */
    function fight(uint256 tokenId, uint256 monsterId) external returns (bool won) {
        require(unimon.ownerOf(tokenId) == msg.sender, "Not token owner");
        require(monsterId < monsters.length && monsters[monsterId].active, "Invalid monster");

        uint256 power = getUnimonPower(tokenId);
        uint8 difficulty = monsters[monsterId].difficulty;

        // Compute probability in percent (0-100) with slight slope and equipment overall percent bonus
        ( , , int256 overallPercent) = equipment.getModifiedStats(tokenId);
        int256 diff = int256(power) - int256(uint256(difficulty));
        int256 p = 50 + (diff * 3) + overallPercent; // add overall % directly
        if (p < 10) p = 10;
        if (p > 90) p = 90;
        uint256 chance = uint256(int256(p));

        uint256 rand = _random(tokenId) % 100; // 0-99
        won = rand < chance;

        totalFightsForToken[tokenId] += 1;
        if (won) totalWinsForToken[tokenId] += 1;

        emit MonsterFought(msg.sender, tokenId, monsterId, won, power, difficulty);
        return won;
    }

    /**
     * @notice Pseudo-random generator; DO NOT use for security-critical randomness.
     * @dev Uses block.prevrandao and other contextual data to vary results between calls.
     */
    function _random(uint256 tokenId) internal view returns (uint256) {
        // NOTE: Not secure randomness; adequate for gamey mechanics.
        // Uses changing inputs to avoid trivial predictability.
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.prevrandao,
                        block.timestamp,
                        msg.sender,
                        tokenId,
                        totalFightsForToken[tokenId]
                    )
                )
            );
    }
}
