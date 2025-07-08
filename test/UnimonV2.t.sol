// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {UnimonV2} from "../contracts/v2/UnimonV2.sol";
import {UnimonItems} from "../contracts/v2/UnimonItems.sol";

contract UnimonV2Test is Test {
    UnimonV2 public unimon;
    UnimonItems public items;

    address public admin;
    address public user;
    address public minter;

    function setUp() public {
        admin = makeAddr("admin");
        user = makeAddr("user");
        minter = makeAddr("minter");

        vm.startPrank(admin);
        items = new UnimonItems(admin);
        unimon = new UnimonV2(address(items));

        // Grant roles
        unimon.grantRole(unimon.MINTER_ROLE(), minter);
        items.grantMinterRole(address(unimon));
        items.grantSpenderRole(address(unimon));
        // Also grant admin and test contract the minter and spender roles for testing
        items.grantMinterRole(admin);
        items.grantSpenderRole(admin);
        items.grantMinterRole(address(this));
        items.grantSpenderRole(address(this));
        vm.stopPrank();
    }

    function testInitialState() public view {
        assertEq(unimon.name(), "UnimonV2");
        assertEq(unimon.symbol(), "UNIMON");
        assertEq(unimon.balanceOf(user), 0);
    }

    function testMintUnimon() public {
        vm.prank(minter);
        uint256 tokenId = unimon.safeMint(user);

        assertEq(unimon.ownerOf(tokenId), user);
        assertEq(unimon.balanceOf(user), 1);
        assertEq(tokenId, 0); // First token should be 0

        // Check initial stats
        (uint256 attack, uint256 defense, bool evolved, string memory name) = unimon.getUnimonStats(tokenId);
        assertEq(attack, 1);
        assertEq(defense, 1);
        assertEq(evolved, false);
        assertEq(bytes(name).length, 0);
    }

    function testMultipleMints() public {
        vm.startPrank(minter);
        uint256 tokenId1 = unimon.safeMint(user);
        uint256 tokenId2 = unimon.safeMint(user);
        vm.stopPrank();

        assertEq(tokenId1, 0);
        assertEq(tokenId2, 1);
        assertEq(unimon.balanceOf(user), 2);
        assertEq(unimon.ownerOf(tokenId1), user);
        assertEq(unimon.ownerOf(tokenId2), user);
    }

    function testEvolveUnimon() public {
        // Mint a Unimon
        vm.prank(minter);
        uint256 tokenId = unimon.safeMint(user);

        // Give user energy
        vm.prank(admin);
        items.mint(user, items.ENERGY_ID(), 10);

        // Evolve
        vm.prank(user);
        unimon.evolve(tokenId, 3);

        // Check new stats
        (uint256 attack, uint256 defense, bool evolved, string memory name) = unimon.getUnimonStats(tokenId);
        assertEq(attack, 4); // 1 + 3
        assertEq(defense, 4); // 1 + 3
        assertEq(evolved, true);
        assertEq(bytes(name).length, 0);

        // Check energy was spent
        assertEq(items.balanceOf(user, items.ENERGY_ID()), 9);
    }

    function testGetAllUnimonForAddress() public {
        // Mint two Unimons
        vm.startPrank(minter);
        unimon.safeMint(user);
        unimon.safeMint(user);
        vm.stopPrank();

        // Give energy and evolve first one
        vm.prank(admin);
        items.mint(user, items.ENERGY_ID(), 10);

        vm.prank(user);
        unimon.evolve(0, 2);

        // Get all Unimon for user
        (
            uint256[] memory tokenIds,
            uint256[] memory attackLevels,
            uint256[] memory defenseLevels,
            bool[] memory evolvedStates,
        ) = unimon.getAllUnimonForAddress(user);

        assertEq(tokenIds.length, 2);
        assertEq(tokenIds[0], 0);
        assertEq(tokenIds[1], 1);

        assertEq(attackLevels[0], 3); // evolved
        assertEq(attackLevels[1], 1); // not evolved

        assertEq(defenseLevels[0], 3); // evolved
        assertEq(defenseLevels[1], 1); // not evolved

        assertEq(evolvedStates[0], true); // evolved
        assertEq(evolvedStates[1], false); // not evolved
    }

    function test_RevertWhen_NonMinterMints() public {
        vm.prank(user);
        vm.expectRevert();
        unimon.safeMint(user);
    }

    function test_RevertWhen_NonOwnerEvolves() public {
        vm.prank(minter);
        uint256 tokenId = unimon.safeMint(user);

        vm.prank(admin);
        items.mint(user, items.ENERGY_ID(), 10);

        address otherUser = makeAddr("other");
        vm.prank(otherUser);
        vm.expectRevert("You don't own this Unimon");
        unimon.evolve(tokenId, 1);
    }

    function test_RevertWhen_InsufficientEnergy() public {
        vm.prank(minter);
        uint256 tokenId = unimon.safeMint(user);

        vm.prank(user);
        vm.expectRevert("Insufficient energy");
        unimon.evolve(tokenId, 1);
    }

    function test_RevertWhen_InvalidEnergyAmount() public {
        vm.prank(minter);
        uint256 tokenId = unimon.safeMint(user);

        vm.prank(admin);
        items.mint(user, items.ENERGY_ID(), 10);

        vm.prank(user);
        vm.expectRevert("Energy amount must be 1-10");
        unimon.evolve(tokenId, 11);

        vm.prank(user);
        vm.expectRevert("Energy amount must be 1-10");
        unimon.evolve(tokenId, 0);
    }
}
