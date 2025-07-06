// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UnimonPrizes} from "../contracts/UnimonPrizes.sol";

contract UnimonPrizesTest is Test {
    UnimonPrizes public prizes;
    
    address public owner;
    address public user1;
    address public user2;
    address public user3;

    function setUp() public {
        // Create addresses first
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Start all operations as owner
        vm.startPrank(owner);

        // Deploy contract
        prizes = new UnimonPrizes();
        
        vm.stopPrank();
        
        // Fund the prize contract
        vm.deal(address(prizes), 100 ether);
        
        // Fund users
        vm.deal(owner, 100 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
    }

    function testInitialState() public view {
        assertEq(prizes.claimsEnabled(), false);
        assertEq(prizes.prizesForAddress(user1), 0);
        assertEq(prizes.hasClaimed(user1), false);
    }

    function testSetPrizes() public {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;

        vm.prank(owner);
        prizes.setPrizes(users, amounts);

        assertEq(prizes.prizesForAddress(user1), 1 ether);
        assertEq(prizes.prizesForAddress(user2), 2 ether);
        assertEq(prizes.prizesForAddress(user3), 3 ether);
    }

    function testClaimPrize() public {
        // Set prize
        address[] memory users = new address[](1);
        users[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.prank(owner);
        prizes.setPrizes(users, amounts);

        // Enable claims
        vm.prank(owner);
        prizes.toggleClaims(true);

        // Record balance before
        uint256 balanceBefore = user1.balance;

        // Claim prize
        vm.prank(user1);
        prizes.claimPrize();

        // Verify
        assertTrue(prizes.hasClaimed(user1));
        assertEq(user1.balance, balanceBefore + 1 ether);
    }

    function test_RevertWhen_ClaimingTwice() public {
        // Set prize
        address[] memory users = new address[](1);
        users[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.prank(owner);
        prizes.setPrizes(users, amounts);

        // Enable claims
        vm.prank(owner);
        prizes.toggleClaims(true);

        // First claim
        vm.prank(user1);
        prizes.claimPrize();

        // Second claim should fail
        vm.prank(user1);
        vm.expectRevert(UnimonPrizes.AlreadyClaimed.selector);
        prizes.claimPrize();
    }

    function test_RevertWhen_ClaimsDisabled() public {
        // Set prize
        address[] memory users = new address[](1);
        users[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.prank(owner);
        prizes.setPrizes(users, amounts);

        // Try to claim while disabled
        vm.prank(user1);
        vm.expectRevert(UnimonPrizes.ClaimsDisabled.selector);
        prizes.claimPrize();
    }

    function test_RevertWhen_NoPrize() public {
        // Enable claims
        vm.prank(owner);
        prizes.toggleClaims(true);

        // Try to claim without having a prize
        vm.prank(user1);
        vm.expectRevert(UnimonPrizes.NoPrize.selector);
        prizes.claimPrize();
    }

    function testEmergencyWithdraw() public {
        uint256 contractBalance = address(prizes).balance;
        uint256 ownerBalanceBefore = owner.balance;

        vm.prank(owner);
        prizes.emergencyWithdraw();

        assertEq(address(prizes).balance, 0);
        assertEq(owner.balance, ownerBalanceBefore + contractBalance);
    }

    function test_RevertWhen_NonOwnerEmergencyWithdraw() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        prizes.emergencyWithdraw();
    }

    function test_RevertWhen_InsufficientBalance() public {
        // Set large prize
        address[] memory users = new address[](1);
        users[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 ether; // More than contract balance

        vm.prank(owner);
        prizes.setPrizes(users, amounts);

        // Enable claims
        vm.prank(owner);
        prizes.toggleClaims(true);

        // Try to claim
        vm.prank(user1);
        vm.expectRevert(UnimonPrizes.InsufficientContractBalance.selector);
        prizes.claimPrize();
    }

    function testGetClaimStatus() public {
        // Test initial state
        (bool canClaim, uint256 amount, string memory reason) = prizes.getClaimStatus(user1);
        assertEq(canClaim, false);
        assertEq(amount, 0);
        assertEq(reason, "Claims are disabled");

        // Set prize and enable claims
        address[] memory users = new address[](1);
        users[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.prank(owner);
        prizes.setPrizes(users, amounts);
        
        vm.prank(owner);
        prizes.toggleClaims(true);

        // Test ready to claim
        (canClaim, amount, reason) = prizes.getClaimStatus(user1);
        assertEq(canClaim, true);
        assertEq(amount, 1 ether);
        assertEq(reason, "Ready to claim");

        // Test after claiming
        vm.prank(user1);
        prizes.claimPrize();

        (canClaim, amount, reason) = prizes.getClaimStatus(user1);
        assertEq(canClaim, false);
        assertEq(amount, 0);
        assertEq(reason, "Already claimed");

        // Test insufficient balance
        users[0] = user2;
        amounts[0] = 1000 ether;
        vm.prank(owner);
        prizes.setPrizes(users, amounts);

        (canClaim, amount, reason) = prizes.getClaimStatus(user2);
        assertEq(canClaim, false);
        assertEq(amount, 1000 ether);
        assertEq(reason, "Insufficient contract balance");
    }
} 