// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import "../contracts/UnimonBattles.sol";
import "../contracts/UnimonEnergy.sol";
import {UnimonHook as MockUnimonHook} from "../contracts/mock/CoreGameLogic.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract UnimonBattlesTest is Test, IERC721Receiver {
    UnimonBattles public battles;
    UnimonEnergy public energy;
    MockUnimonHook public hook;

    address public owner = makeAddr("owner");
    address public player1 = makeAddr("player1");
    address public player2 = makeAddr("player2");
    address public player3 = makeAddr("player3");
    address public player4 = makeAddr("player4");
    address public player5 = makeAddr("player5");

    uint256 public constant START_DELAY = 1 hours;
    uint256 public constant CYCLE_DURATION = 24 hours;
    uint256 public constant ADMIN_GRACE_PERIOD = 1 minutes;

    function setUp() public {
        // Setup ERC721 receiver for test addresses
        vm.etch(player1, address(this).code);
        vm.etch(player2, address(this).code);

        vm.startPrank(owner);

        // Deploy contracts
        hook = new MockUnimonHook();
        energy = new UnimonEnergy();
        battles = new UnimonBattles(address(hook), address(energy), block.timestamp + START_DELAY);

        // Setup initial state
        hook.setHatchingEnabled(true);
        hook.setUnimonEnergy(address(energy));
        battles.toggleBattles(true);

        // Set game manager permissions
        energy.setGameManager(address(battles), true);
        energy.setGameManager(address(hook), true);

        vm.stopPrank();

        // Give players some energy
        vm.startPrank(owner);
        energy.transfer(player1, 1000 ether);
        energy.transfer(player2, 1000 ether);
        vm.stopPrank();
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function _mintAndHatchUnimon(address player, uint256 tokenId, uint256 level) internal {
        vm.deal(player, 0.01 ether);

        vm.startPrank(player);
        hook.mint{value: hook.MINT_PRICE()}(1);
        hook.hatch(tokenId, level);
        vm.stopPrank();
    }

    function _warpToBattleStart() internal {
        vm.warp(block.timestamp + START_DELAY);
    }

    function _warpToEndOfCycle() internal {
        // Warp to exactly when battle window ends and grace period begins
        vm.warp(block.timestamp + (CYCLE_DURATION - (ADMIN_GRACE_PERIOD - 1)));
    }

    function _setupMultiPlayerBattles() internal {
        // Setup ERC721 receiver for all players
        vm.etch(player3, address(this).code);
        vm.etch(player4, address(this).code);
        vm.etch(player5, address(this).code);

        // Give energy to all players first
        vm.startPrank(owner);
        energy.transfer(player3, 1000 ether);
        energy.transfer(player4, 1000 ether);
        energy.transfer(player5, 1000 ether);
        vm.stopPrank();

        // Player 1: Levels 1-2
        _mintAndHatchUnimon(player1, 0, 1);
        _mintAndHatchUnimon(player1, 1, 2);
        _mintAndHatchUnimon(player1, 2, 2);
        _mintAndHatchUnimon(player1, 3, 2);
        _mintAndHatchUnimon(player1, 4, 2);

        // Player 2: Levels 3-4
        _mintAndHatchUnimon(player2, 5, 3);
        _mintAndHatchUnimon(player2, 6, 4);
        _mintAndHatchUnimon(player2, 7, 4);
        _mintAndHatchUnimon(player2, 8, 4);
        _mintAndHatchUnimon(player2, 9, 4);

        // Player 3: Levels 5-6
        _mintAndHatchUnimon(player3, 10, 5);
        _mintAndHatchUnimon(player3, 11, 6);
        _mintAndHatchUnimon(player3, 12, 6);
        _mintAndHatchUnimon(player3, 13, 6);
        _mintAndHatchUnimon(player3, 14, 6);

        // Player 4: Levels 7-8
        _mintAndHatchUnimon(player4, 15, 7);
        _mintAndHatchUnimon(player4, 16, 8);
        _mintAndHatchUnimon(player4, 17, 8);
        _mintAndHatchUnimon(player4, 18, 8);
        _mintAndHatchUnimon(player4, 19, 8);

        // Player 5: Levels 9-10
        _mintAndHatchUnimon(player5, 20, 9);
        _mintAndHatchUnimon(player5, 21, 10);
        _mintAndHatchUnimon(player5, 22, 10);
        _mintAndHatchUnimon(player5, 23, 10);
        _mintAndHatchUnimon(player5, 24, 10);
    }

    function test_BattleFlow() public {
        _setupMultiPlayerBattles();
        _warpToBattleStart();

        // Start battle between player1's first Unimon and player2's first Unimon
        vm.prank(player1);
        battles.startBattle(0, 5);

        // Admin fulfills randomness
        uint256[] memory battleIds = new uint256[](1);
        uint256[] memory randomNumbers = new uint256[](1);
        battleIds[0] = 1;
        randomNumbers[0] = 123; // Fixed random number for test

        vm.prank(owner);
        battles.fulfillRandomness(battleIds, randomNumbers);

        // Finish battle
        battles.finishThem(1);

        // Get battle data
        (UnimonBattles.BattleStatus status1, , uint256 encounterId1) = battles.unimonBattleData(0);
        (UnimonBattles.BattleStatus status2, , uint256 encounterId2) = battles.unimonBattleData(5);

        // Assert one won and one lost
        assertTrue(
            (status1 == UnimonBattles.BattleStatus.WON && status2 == UnimonBattles.BattleStatus.LOST) ||
                (status1 == UnimonBattles.BattleStatus.LOST && status2 == UnimonBattles.BattleStatus.WON)
        );

        // Assert encounter IDs match
        assertEq(encounterId1, encounterId2);
    }

    function test_ReviveFlow() public {
        _setupMultiPlayerBattles();
        _warpToBattleStart();

        // Warp to outside battle window to set status
        vm.warp(block.timestamp + (CYCLE_DURATION - (ADMIN_GRACE_PERIOD - 1)));

        // Set Unimon to FAINTED status
        vm.startPrank(owner);
        battles.updateStatusesForNextCycle(0, 0);
        vm.stopPrank();

        // Warp back to battle window
        _warpToBattleStart();

        vm.startPrank(player1);
        battles.revive(0);
        vm.stopPrank();

        // Check status is READY
        (UnimonBattles.BattleStatus status, , ) = battles.unimonBattleData(0);
        assertEq(uint256(status), uint256(UnimonBattles.BattleStatus.READY));
    }

    function test_MultiPlayerSetup() public {
        _setupMultiPlayerBattles();

        // Verify player1's Unimons (tokenIncrement 1-2)
        assertEq(hook.ownerOf(0), player1);
        (, uint256 level0) = hook.unimons(0);
        assertEq(level0, 1); // tokenIncrement 1 always gives level 1

        for (uint256 i = 1; i < 5; i++) {
            assertEq(hook.ownerOf(i), player1);
            (, uint256 level) = hook.unimons(i);
            assertTrue(level >= 2 && level <= 3); // tokenIncrement 2 gives level 2-3
        }

        // Verify player2's Unimons (tokenIncrement 3-4)
        assertEq(hook.ownerOf(5), player2);
        (, uint256 level5) = hook.unimons(5);
        assertTrue(level5 >= 2 && level5 <= 3); // tokenIncrement 3 gives level 2-3

        for (uint256 i = 6; i < 10; i++) {
            assertEq(hook.ownerOf(i), player2);
            (, uint256 level) = hook.unimons(i);
            assertTrue(level >= 3 && level <= 4); // tokenIncrement 4 gives level 3-4
        }

        // Verify player3's Unimons (tokenIncrement 5-6)
        assertEq(hook.ownerOf(10), player3);
        (, uint256 level10) = hook.unimons(10);
        assertTrue(level10 >= 3 && level10 <= 5); // tokenIncrement 5 gives level 3-5

        for (uint256 i = 11; i < 15; i++) {
            assertEq(hook.ownerOf(i), player3);
            (, uint256 level) = hook.unimons(i);
            assertTrue(level >= 4 && level <= 6); // tokenIncrement 6 gives level 4-6
        }

        // Verify player4's Unimons (tokenIncrement 7-8)
        assertEq(hook.ownerOf(15), player4);
        (, uint256 level15) = hook.unimons(15);
        assertTrue(level15 >= 4 && level15 <= 7); // tokenIncrement 7 gives level 4-7

        for (uint256 i = 16; i < 20; i++) {
            assertEq(hook.ownerOf(i), player4);
            (, uint256 level) = hook.unimons(i);
            assertTrue(level >= 5 && level <= 8); // tokenIncrement 8 gives level 5-8
        }

        // Verify player5's Unimons (tokenIncrement 9-10)
        assertEq(hook.ownerOf(20), player5);
        (, uint256 level20) = hook.unimons(20);
        assertTrue(level20 >= 5 && level20 <= 9); // tokenIncrement 9 gives level 5-9

        for (uint256 i = 21; i < 25; i++) {
            assertEq(hook.ownerOf(i), player5);
            (, uint256 level) = hook.unimons(i);
            assertTrue(level >= 6 && level <= 10); // tokenIncrement 10 gives level 6-10
        }

        // Verify all players have correct remaining energy after hatching
        assertEq(energy.balanceOf(player1), 991 ether); // 1000 - (1 + 4*2)
        assertEq(energy.balanceOf(player2), 981 ether); // 1000 - (3 + 4*4)
        assertEq(energy.balanceOf(player3), 971 ether); // 1000 - (5 + 4*6)
        assertEq(energy.balanceOf(player4), 961 ether); // 1000 - (7 + 4*8)
        assertEq(energy.balanceOf(player5), 951 ether); // 1000 - (9 + 4*10)
    }

    function test_RevertWhen_StartBattleBeforeStart() public {
        _setupMultiPlayerBattles();

        // Try to start battle before start time (should revert)
        vm.prank(player1);
        vm.expectRevert(UnimonBattles.OutsideBattleWindow.selector);
        battles.startBattle(0, 1);
    }

    function test_RevertWhen_UnauthorizedBattle() public {
        _mintAndHatchUnimon(player1, 0, 5);
        _warpToBattleStart();

        // Try to start battle with player1's Unimon as player2 (should revert)
        vm.prank(player2);
        vm.expectRevert(UnimonBattles.NotOwner.selector);
        battles.startBattle(0, 1);
    }
}
