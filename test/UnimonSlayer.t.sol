// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {UnimonV2} from "../contracts/v2/UnimonV2.sol";
import {UnimonItems} from "../contracts/v2/UnimonItems.sol";
import {UnimonSlayer} from "../contracts/v2/UnimonSlayer.sol";
import {UnimonEquipment} from "../contracts/v2/UnimonEquipment.sol";

contract UnimonSlayerTest is Test {
    UnimonItems public items;
    UnimonV2 public unimon;
    UnimonSlayer public slayer;
    UnimonEquipment public equipment;

    address public admin;
    address public user;
    address public minter;
    address public other;

    function setUp() public {
        admin = makeAddr("admin");
        user = makeAddr("user");
        minter = makeAddr("minter");
        other = makeAddr("other");

        vm.startPrank(admin);
        items = new UnimonItems(admin);
        unimon = new UnimonV2(address(items));
        unimon.grantRole(unimon.MINTER_ROLE(), minter);
        vm.stopPrank();

        equipment = new UnimonEquipment(address(unimon), address(items));
        slayer = new UnimonSlayer(address(equipment));
    }

    function _mintToUser(uint256 count) internal returns (uint256[] memory ids) {
        ids = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            vm.prank(minter);
            ids[i] = unimon.safeMint(user);
        }
    }

    function test_InitialMonstersConfigured() public view {
        assertEq(slayer.monsterCount(), 5);
    }

    function test_Fight_OwnershipRequired() public {
        uint256[] memory ids = _mintToUser(1);
        uint256 tokenId = ids[0];

        vm.prank(other);
        vm.expectRevert("Not token owner");
        slayer.fight(tokenId, 0);
    }

    function test_Fight_Probabilistic_BaseUnitVsGoblin() public {
        uint256[] memory ids = _mintToUser(1);
        uint256 tokenId = ids[0];

        // Base power = 2, Goblin difficulty = 5 -> probability ~ 44%
        uint256 wins;
        uint256 losses;
        for (uint256 i = 0; i < 16; i++) {
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 13);
            vm.prank(user);
            bool won = slayer.fight(tokenId, 1);
            if (won) wins++; else losses++;
        }
        assertGt(wins, 0);
        assertGt(losses, 0);
    }

    function test_Fight_CountersIncrease() public {
        uint256[] memory ids = _mintToUser(1);
        uint256 tokenId = ids[0];

        vm.prank(user);
        bool won0 = slayer.fight(tokenId, 0);
        vm.prank(user);
        bool won1 = slayer.fight(tokenId, 1);

        uint256 fights = slayer.totalFightsForToken(tokenId);
        uint256 wins = slayer.totalWinsForToken(tokenId);
        assertEq(fights, 2);
        assertEq(wins, (won0 ? 1 : 0) + (won1 ? 1 : 0));
    }
}


