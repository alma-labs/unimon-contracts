// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UnimonHook} from "../contracts/mock/CoreGameLogic.sol";
import {UnimonEnergy} from "../contracts/UnimonEnergy.sol";

contract CoreGameLogicTest is Test {
    UnimonHook public hook;
    UnimonEnergy public energy;
    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy contracts
        energy = new UnimonEnergy();
        hook = new UnimonHook();
        hook.setUnimonEnergy(address(energy));
        energy.setGameManager(address(hook), true);

        // Setup initial state
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // Transfer some energy tokens to users from owner
        energy.transfer(user1, 20000 ether);
        energy.transfer(user2, 20000 ether);
    }

    function testInitialState() public view {
        assertEq(hook.name(), "Unimon");
        assertEq(hook.symbol(), "UNIMON");
        assertEq(hook.MAX_SUPPLY(), 10000);
        assertEq(hook.MINT_PRICE(), 0.00000111 ether);
        assertEq(hook.hatchingEnabled(), false);
    }

    function testMint() public {
        uint256 amount = 5;
        uint256 cost = amount * hook.MINT_PRICE();

        vm.prank(user1);
        hook.mint{value: cost}(amount);

        assertEq(hook.balanceOf(user1), amount);
    }

    function testHatch() public {
        // Mint a token first
        uint256 amount = 1;
        uint256 cost = amount * hook.MINT_PRICE();

        vm.prank(user1);
        hook.mint{value: cost}(amount);

        // Enable hatching
        hook.setHatchingEnabled(true);

        // Hatch the token
        vm.prank(user1);
        hook.hatch(0, 5); // Using 5 tokens for hatching

        // Check status
        UnimonHook.UnimonData memory data = hook.getUnimonData(0);
        assertEq(uint256(data.status), uint256(UnimonHook.Status.HATCHED));
        assertTrue(data.level >= 1 && data.level <= 10);
    }

    function test_RevertWhen_NotOwner() public {
        // Mint a token first
        uint256 amount = 1;
        uint256 cost = amount * hook.MINT_PRICE();

        vm.prank(user1);
        hook.mint{value: cost}(amount);

        // Enable hatching
        hook.setHatchingEnabled(true);

        // Try to hatch from different account
        vm.prank(user2);
        vm.expectRevert(UnimonHook.NotOwnerOfToken.selector);
        hook.hatch(0, 5);
    }

    function test_RevertWhen_HatchingNotEnabled() public {
        // Mint a token first
        uint256 amount = 1;
        uint256 cost = amount * hook.MINT_PRICE();

        vm.prank(user1);
        hook.mint{value: cost}(amount);

        // Try to hatch without enabling
        vm.prank(user1);
        vm.expectRevert(UnimonHook.HatchingDisabled.selector);
        hook.hatch(0, 5);
    }

    function test_RevertWhen_InvalidTokenAmount() public {
        // Mint a token first
        uint256 amount = 1;
        uint256 cost = amount * hook.MINT_PRICE();
        vm.prank(user1);
        hook.mint{value: cost}(amount);

        // Enable hatching
        hook.setHatchingEnabled(true);

        // Try to hatch with invalid amounts
        vm.prank(user1);
        vm.expectRevert(UnimonHook.InvalidTokenAmount.selector);
        hook.hatch(0, 0);

        vm.prank(user1);
        vm.expectRevert(UnimonHook.InvalidTokenAmount.selector);
        hook.hatch(0, 11);
    }

    function test_RevertWhen_AlreadyHatched() public {
        // Mint a token first
        uint256 amount = 1;
        uint256 cost = amount * hook.MINT_PRICE();
        vm.prank(user1);
        hook.mint{value: cost}(amount);

        // Enable hatching
        hook.setHatchingEnabled(true);

        // Hatch first time
        vm.prank(user1);
        hook.hatch(0, 5);

        // Try to hatch again
        vm.prank(user1);
        vm.expectRevert(UnimonHook.AlreadyHatched.selector);
        hook.hatch(0, 5);
    }

    function test_RevertWhen_InsufficientTokenBalance() public {
        // Mint a token first
        uint256 amount = 1;
        uint256 cost = amount * hook.MINT_PRICE();
        vm.prank(user1);
        hook.mint{value: cost}(amount);

        // Enable hatching
        hook.setHatchingEnabled(true);

        // Try to hatch with more tokens than balance
        vm.prank(user1);
        vm.expectRevert(UnimonHook.InvalidTokenAmount.selector);
        hook.hatch(0, 1000);
    }

    function test_RevertWhen_MintExceedsMaxSupply() public {
        uint256 amount = hook.MAX_SUPPLY() + 1;
        uint256 cost = amount * hook.MINT_PRICE();
        vm.deal(user1, cost);

        vm.prank(user1);
        vm.expectRevert(UnimonHook.InvalidTokenAmount.selector);
        hook.mint{value: cost}(amount);
    }

    function test_RevertWhen_MintExceedsMaxPerSwap() public {
        uint256 amount = hook.MAX_PER_SWAP() + 1;
        uint256 cost = amount * hook.MINT_PRICE();
        vm.deal(user1, cost);

        vm.prank(user1);
        vm.expectRevert(UnimonHook.InvalidTokenAmount.selector);
        hook.mint{value: cost}(amount);
    }

    function test_RevertWhen_IncorrectMintValue() public {
        uint256 amount = 5;
        uint256 correctCost = amount * hook.MINT_PRICE();
        uint256 wrongCost = correctCost + 0.1 ether;
        vm.deal(user1, wrongCost);

        vm.prank(user1);
        vm.expectRevert(UnimonHook.InvalidTokenAmount.selector);
        hook.mint{value: wrongCost}(amount);
    }

    function testHatchLevelDistribution() public {
        // Enable hatching
        hook.setHatchingEnabled(true);

        // Mint 1000 tokens (100 for each input amount)
        uint256 totalTokens = 1000;
        uint256 cost = totalTokens * hook.MINT_PRICE();
        vm.prank(user1);
        hook.mint{value: cost}(totalTokens);

        // Print results table
        console2.log("\nLevel Distribution for Each Input Amount:");
        console2.log("----------------------------------------");

        for (uint256 i = 0; i < 10; i++) {
            uint256 inputAmount = i + 1;
            uint256[11] memory levelCounts; // 0-10 levels

            // Hatch and count occurrences of each level
            for (uint256 j = 0; j < 100; j++) {
                uint256 tokenId = i * 100 + j;
                vm.prank(user1);
                hook.hatch(tokenId, inputAmount); // Hatch with different input amounts
                uint256 level = hook.getUnimonData(tokenId).level;
                levelCounts[level]++;
            }

            // Print distribution
            string memory line = string(
                abi.encodePacked("Input ", inputAmount < 10 ? " " : "", vm.toString(inputAmount), ": ")
            );
            console2.log(line);

            for (uint256 level = 1; level <= 10; level++) {
                if (levelCounts[level] > 0) {
                    string memory levelLine = string(
                        abi.encodePacked(
                            "  Level ",
                            level < 10 ? " " : "",
                            vm.toString(level),
                            ": ",
                            levelCounts[level] < 10 ? " " : "",
                            vm.toString(levelCounts[level]),
                            " (",
                            vm.toString((levelCounts[level] * 100) / 100),
                            "%)\n"
                        )
                    );
                    console2.log(levelLine);
                }
            }
            console2.log("\n");
        }
    }
}
