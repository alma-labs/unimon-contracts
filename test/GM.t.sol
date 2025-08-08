// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {GM} from "../contracts/v2/GM.sol";
import {UnimonV2} from "../contracts/v2/UnimonV2.sol";
import {UnimonItems} from "../contracts/v2/UnimonItems.sol";

contract GMTest is Test {
    UnimonItems public items;
    UnimonV2 public unimon;
    GM public gm;

    address public admin;
    address public user;
    address public minter;
    address public other;

    uint256 public tokenId;

    function setUp() public {
        admin = makeAddr("admin");
        user = makeAddr("user");
        minter = makeAddr("minter");
        other = makeAddr("other");

        // Deploy core contracts
        vm.startPrank(admin);
        items = new UnimonItems(admin);
        unimon = new UnimonV2(address(items));
        unimon.grantRole(unimon.MINTER_ROLE(), minter);
        vm.stopPrank();

        // Mint a Unimon to user
        vm.prank(minter);
        tokenId = unimon.safeMint(user); // tokenId == 0 initially

        // Deploy GM pointing at UnimonV2
        gm = new GM(address(unimon));
    }

    function _currentPeriod() internal view returns (uint32) {
        return uint32(block.timestamp / gm.periodSeconds());
    }

    function test_GM_BasicAndDailyLimit() public {
        // Initially can GM
        assertTrue(gm.canGM(user, tokenId));
        vm.prank(user);
        gm.gm(tokenId);

        // Post-GM checks
        (uint32 currentStreak, uint32 bestStreak, uint32 lastDay) = gm.getStreak(tokenId);
        assertEq(currentStreak, 1);
        assertEq(bestStreak, 1);
        assertEq(lastDay, _currentPeriod());
        assertEq(gm.timeUntilNextGM(tokenId) > 0, true);
        assertEq(gm.timeUntilNextGM(tokenId) <= gm.periodSeconds(), true);
        assertEq(gm.totalGMsForUser(user), 1);

        // Daily limit enforced
        vm.prank(user);
        vm.expectRevert("Token already GM'd today");
        gm.gm(tokenId);
    }

    function test_GM_ConsecutiveDays_StreakIncrements() public {
        // Day 0
        vm.prank(user);
        gm.gm(tokenId);
        (uint32 currentStreak, uint32 bestStreak, ) = gm.getStreak(tokenId);
        assertEq(currentStreak, 1);
        assertEq(bestStreak, 1);

        // Next day
        uint256 nextStart = (uint256(_currentPeriod()) + 1) * uint256(gm.periodSeconds());
        vm.warp(nextStart + 1);

        vm.prank(user);
        gm.gm(tokenId);
        (currentStreak, bestStreak, ) = gm.getStreak(tokenId);
        assertEq(currentStreak, 2);
        assertEq(bestStreak, 2);

        // Another next day
        nextStart = (uint256(_currentPeriod()) + 1) * uint256(gm.periodSeconds());
        vm.warp(nextStart + 1);

        vm.prank(user);
        gm.gm(tokenId);
        (currentStreak, bestStreak, ) = gm.getStreak(tokenId);
        assertEq(currentStreak, 3);
        assertEq(bestStreak, 3);
    }

    function test_GM_SkipDay_ResetsCurrentStreak_KeepsBest() public {
        // Two-day streak
        vm.prank(user);
        gm.gm(tokenId);
        uint256 nextStart = (uint256(_currentPeriod()) + 1) * uint256(gm.periodSeconds());
        vm.warp(nextStart + 1);
        vm.prank(user);
        gm.gm(tokenId);
        (uint32 currentStreak, uint32 bestStreak, ) = gm.getStreak(tokenId);
        assertEq(currentStreak, 2);
        assertEq(bestStreak, 2);

        // Skip a day (warp 2 days forward)
        nextStart = (uint256(_currentPeriod()) + 2) * uint256(gm.periodSeconds());
        vm.warp(nextStart + 1);

        vm.prank(user);
        gm.gm(tokenId);
        (currentStreak, bestStreak, ) = gm.getStreak(tokenId);
        assertEq(currentStreak, 1);
        assertEq(bestStreak, 2);
    }

    function test_Revert_NotOwner() public {
        vm.prank(other);
        vm.expectRevert("Not token owner");
        gm.gm(tokenId);
    }

    function test_CanGM_OwnerOnly() public {
        // Non-owner cannot GM and canGM should be false for them
        assertFalse(gm.canGM(other, tokenId));
        assertTrue(gm.canGM(user, tokenId));
    }

    function test_Counters_NoStream() public {
        // First GM on token 0
        vm.prank(user);
        gm.gm(tokenId);

        // Mint second token and GM next day
        vm.prank(minter);
        uint256 tokenId1 = unimon.safeMint(user);

        uint256 nextStart = (uint256(_currentPeriod()) + 1) * uint256(gm.periodSeconds());
        vm.warp(nextStart + 1);

        vm.prank(user);
        gm.gm(tokenId1);

        // Check counters instead of stream
        assertEq(gm.totalGMsForUser(user), 2);
        assertEq(gm.totalGMsForToken(tokenId), 1);
        assertEq(gm.totalGMsForToken(tokenId1), 1);
    }
}


