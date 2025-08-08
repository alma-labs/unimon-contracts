// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {UnimonV2} from "./UnimonV2.sol";

/**
 * @title GM
 * @notice Simple onchain GM per Unimon token (no global stream)
 * - Each Unimon tokenId can GM once per configurable time period
 * - Sender must own the tokenId
 * - Shows time until next GM per token
 * - Emits events for each GM (no index)
 * - Query helpers for availability and streaks
 */
contract GM {
    /// @notice Unimon V2 collection reference for ownership checks
    UnimonV2 public immutable unimon;

    /// @notice Contract owner for configuration
    address public owner;

    /// @notice Length of the GM period window in seconds (default: 1 hour)
    uint32 public periodSeconds;

    /// @notice Emitted when a user GMs with a specific token
    /// @param user The address that GM'd
    /// @param tokenId The Unimon token used to GM
    /// @param day The current period index (block.timestamp / periodSeconds)
    /// @param timestamp The timestamp of the GM
    /// @param currentStreak The new current streak for this token after this GM
    /// @param bestStreak The best historical streak for this token after this GM
    event GoodMorning(
        address indexed user,
        uint256 indexed tokenId,
        uint256 indexed day,
        uint40 timestamp,
        uint32 currentStreak,
        uint32 bestStreak
    );

    /// @notice Tracks the last period index a token GM'd, stored as (period + 1); 0 means never GM'd
    mapping(uint256 => uint32) public lastGmDayPlusOneForToken;

    /// @notice Total number of GMs per user
    mapping(address => uint256) public totalGMsForUser;

    /// @notice Total number of GMs per token
    mapping(uint256 => uint256) public totalGMsForToken;

    /// @notice Current consecutive-day streak per token
    mapping(uint256 => uint32) public currentStreakForToken;

    /// @notice Best (max) consecutive-day streak per token
    mapping(uint256 => uint32) public bestStreakForToken;

    constructor(address _unimonV2) {
        unimon = UnimonV2(_unimonV2);
        owner = msg.sender;
        periodSeconds = 1 hours;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /// @notice Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero owner");
        owner = newOwner;
    }

    /// @notice Set the GM period length in seconds
    function setPeriodSeconds(uint32 newPeriodSeconds) external onlyOwner {
        require(newPeriodSeconds >= 60 && newPeriodSeconds <= 30 days, "Invalid period");
        periodSeconds = newPeriodSeconds;
    }

    /**
     * @notice Returns the current UTC day index
     */
    function currentDay() public view returns (uint32) {
        // Backwards-compatible name; represents current period index
        return uint32(block.timestamp / periodSeconds);
    }

    /**
     * @notice Returns the timestamp for the start of the next UTC day
     */
    function nextDayStartTimestamp() public view returns (uint256) {
        // Backwards-compatible name; returns next period start timestamp
        return (uint256(currentDay()) + 1) * uint256(periodSeconds);
    }

    /**
     * @notice Returns whether `user` can GM right now with `tokenId`
     */
    function canGM(address user, uint256 tokenId) public view returns (bool) {
        if (unimon.ownerOf(tokenId) != user) return false;
        uint32 day = currentDay();
        return lastGmDayPlusOneForToken[tokenId] < day + 1;
    }

    /**
     * @notice Returns whether msg.sender can GM right now with `tokenId`
     */
    function canGM(uint256 tokenId) external view returns (bool) {
        return canGM(msg.sender, tokenId);
    }

    /**
     * @notice Returns the number of seconds until `tokenId` can GM again (0 if available now)
     */
    function timeUntilNextGM(uint256 tokenId) public view returns (uint256) {
        uint32 day = currentDay();
        if (lastGmDayPlusOneForToken[tokenId] < day + 1) return 0;
        return nextDayStartTimestamp() - block.timestamp;
    }

    /**
     * @notice Do a GM for today with `tokenId`; reverts if already GM'd this UTC day
     *         or if msg.sender does not own the token
     */
    function gm(uint256 tokenId) public {
        require(unimon.ownerOf(tokenId) == msg.sender, "Not token owner");
        uint32 day = currentDay();
        require(lastGmDayPlusOneForToken[tokenId] < day + 1, "Token already GM'd today");

        // Update streak
        uint32 prevDay = lastGmDayPlusOneForToken[tokenId] == 0
            ? 0
            : lastGmDayPlusOneForToken[tokenId] - 1;
        uint32 newStreak = (prevDay + 1 == day) ? currentStreakForToken[tokenId] + 1 : 1;
        currentStreakForToken[tokenId] = newStreak;
        if (newStreak > bestStreakForToken[tokenId]) {
            bestStreakForToken[tokenId] = newStreak;
        }

        lastGmDayPlusOneForToken[tokenId] = day + 1;
        totalGMsForUser[msg.sender] += 1;
        totalGMsForToken[tokenId] += 1;

        uint40 ts = uint40(block.timestamp);
        emit GoodMorning(msg.sender, tokenId, day, ts, newStreak, bestStreakForToken[tokenId]);
    }

    /**
     * @notice GM with multiple tokenIds in one call
     * @param tokenIds Array of tokenIds to GM with
     */
    function gmAll(uint256[] calldata tokenIds) external {
        uint256 length = tokenIds.length;
        require(length > 0, "Empty");
        for (uint256 i = 0; i < length; i++) {
            gm(tokenIds[i]);
        }
    }

    /**
     * @notice Get current and best streak data for a token
     */
    function getStreak(uint256 tokenId)
        external
        view
        returns (uint32 currentStreak, uint32 bestStreak, uint32 lastDay)
    {
        uint32 lastPlusOne = lastGmDayPlusOneForToken[tokenId];
        uint32 last = lastPlusOne == 0 ? 0 : lastPlusOne - 1;
        return (currentStreakForToken[tokenId], bestStreakForToken[tokenId], last);
    }
}


