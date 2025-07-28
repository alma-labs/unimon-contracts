// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
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
        assertEq(name, "Unimon #0"); // Default name should be "Unimon #TOKENID"
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
        assertTrue(attack > 1); // Should have gained some attack
        assertTrue(defense > 1); // Should have gained some defense
        assertTrue((attack - 1) + (defense - 1) >= 3); // Total gain should be at least the energy amount
        assertEq(evolved, true);
        assertEq(name, "Unimon #0"); // Name should still be default after evolution

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

        assertTrue(attackLevels[0] > 1); // evolved
        assertEq(attackLevels[1], 1); // not evolved

        assertTrue(defenseLevels[0] > 1); // evolved
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

    function testEvolutionDistribution() public {
        vm.prank(admin);
        items.mint(user, items.ENERGY_ID(), 100);

        // Test energy amount 6 - should show good distribution
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(minter);
            uint256 tokenId = unimon.safeMint(user);

            vm.prank(user);
            unimon.evolve(tokenId, 6);

            (uint256 attack, uint256 defense, , ) = unimon.getUnimonStats(tokenId);
            uint256 totalGain = (attack - 1) + (defense - 1);

            // Verify reasonable distribution with 10 cap per skill
            assertTrue(attack >= 1 && attack <= 10, "Attack should be 1-10");
            assertTrue(defense >= 1 && defense <= 10, "Defense should be 1-10");
            assertTrue(totalGain >= 6, "Total gain should be at least energy amount");
            assertTrue(totalGain <= 20, "Total gain should not exceed cap");
        }
    }

    function testEvolutionToggleDefaultEnabled() public view {
        assertTrue(unimon.evolutionsEnabled(), "Evolutions should be enabled by default");
    }

    function testAdminCanToggleEvolutionsOff() public {
        vm.prank(admin);
        unimon.toggleEvolutions(false);

        assertFalse(unimon.evolutionsEnabled(), "Evolutions should be disabled after toggle");
    }

    function testAdminCanToggleEvolutionsOn() public {
        // First disable
        vm.prank(admin);
        unimon.toggleEvolutions(false);

        // Then re-enable
        vm.prank(admin);
        unimon.toggleEvolutions(true);

        assertTrue(unimon.evolutionsEnabled(), "Evolutions should be enabled after toggle");
    }

    function test_RevertWhen_EvolutionsDisabled() public {
        // Mint a Unimon and give user energy
        vm.prank(minter);
        uint256 tokenId = unimon.safeMint(user);

        vm.prank(admin);
        items.mint(user, items.ENERGY_ID(), 10);

        // Disable evolutions
        vm.prank(admin);
        unimon.toggleEvolutions(false);

        // Try to evolve - should fail
        vm.prank(user);
        vm.expectRevert("Evolutions are currently disabled");
        unimon.evolve(tokenId, 3);
    }

    function testEvolutionWorksAfterReEnabled() public {
        // Mint a Unimon and give user energy
        vm.prank(minter);
        uint256 tokenId = unimon.safeMint(user);

        vm.prank(admin);
        items.mint(user, items.ENERGY_ID(), 10);

        // Disable then re-enable evolutions
        vm.prank(admin);
        unimon.toggleEvolutions(false);

        vm.prank(admin);
        unimon.toggleEvolutions(true);

        // Evolution should work again
        vm.prank(user);
        unimon.evolve(tokenId, 3);

        (uint256 attack, uint256 defense, bool evolved, ) = unimon.getUnimonStats(tokenId);
        assertTrue(attack > 1);
        assertTrue(defense > 1);
        assertTrue(evolved);
    }

    function test_RevertWhen_NonAdminToggleEvolutions() public {
        vm.prank(user);
        vm.expectRevert();
        unimon.toggleEvolutions(false);
    }
}
