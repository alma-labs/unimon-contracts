// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {UnimonMinter} from "../contracts/v2/UnimonMinter.sol";
import {UnimonV2} from "../contracts/v2/UnimonV2.sol";
import {UnimonItems} from "../contracts/v2/UnimonItems.sol";

contract UnimonMinterTest is Test {
    UnimonMinter public minter;
    UnimonV2 public unimon;
    UnimonItems public items;

    address public admin;
    address public user;

    function setUp() public {
        admin = makeAddr("admin");
        user = makeAddr("user");

        vm.startPrank(admin);

        // Deploy contracts
        items = new UnimonItems(admin);
        unimon = new UnimonV2(address(items));
        minter = new UnimonMinter(address(unimon), address(items), admin);

        // Grant necessary roles
        unimon.grantRole(unimon.MINTER_ROLE(), address(minter));
        items.grantMinterRole(address(minter));
        items.grantSpenderRole(address(minter));
        // Also grant admin and test contract the minter and spender roles for testing
        items.grantMinterRole(admin);
        items.grantSpenderRole(admin);
        items.grantMinterRole(address(this));
        items.grantSpenderRole(address(this));

        vm.stopPrank();

        // Fund user
        vm.deal(user, 10 ether);
    }

    function testInitialState() public view {
        assertEq(minter.MINT_PRICE(), 0.0000111 ether);
        assertEq(minter.MAX_MINT_PER_TX(), 100);
        assertEq(minter.totalMinted(), 0);
    }

    function testMintSingle() public {
        uint256 price = minter.MINT_PRICE();

        vm.prank(user);
        minter.mint{value: price}(1);

        // Check Unimon was minted
        assertEq(unimon.balanceOf(user), 1);
        assertEq(unimon.ownerOf(0), user);
        assertEq(minter.totalMinted(), 1);

        // Check items were given (4 energy + 1 key per mint)
        assertEq(items.balanceOf(user, items.ENERGY_ID()), 4);
        assertEq(items.balanceOf(user, items.UNIKEY_ID()), 1);
    }

    function testMintMultiple() public {
        uint256 amount = 3;
        uint256 totalPrice = minter.MINT_PRICE() * amount;

        vm.prank(user);
        minter.mint{value: totalPrice}(amount);

        // Check Unimons were minted
        assertEq(unimon.balanceOf(user), amount);
        assertEq(minter.totalMinted(), amount);

        // Check items (4 energy + 1 key per mint)
        assertEq(items.balanceOf(user, items.ENERGY_ID()), 12); // 4 * 3
        assertEq(items.balanceOf(user, items.UNIKEY_ID()), 3); // 1 * 3
    }

    function testMintWithCoupons() public {
        uint256 amount = 2;

        // Give user coupons
        vm.prank(admin);
        items.mint(user, items.MINT_COUPON_ID(), amount);

        // Mint with coupons (half price)
        uint256 discountedPrice = (minter.MINT_PRICE() * amount) / 2;

        vm.prank(user);
        minter.mintWithCoupons{value: discountedPrice}(amount);

        // Check Unimons were minted
        assertEq(unimon.balanceOf(user), amount);
        assertEq(minter.totalMinted(), amount);

        // Check coupons were spent
        assertEq(items.balanceOf(user, items.MINT_COUPON_ID()), 0);

        // Check items were given
        assertEq(items.balanceOf(user, items.ENERGY_ID()), 8); // 4 * 2
        assertEq(items.balanceOf(user, items.UNIKEY_ID()), 2); // 1 * 2
    }

    function testWithdrawPrizePool() public {
        // Add some ETH to contract
        vm.deal(address(minter), 5 ether);

        uint256 adminBalanceBefore = admin.balance;
        uint256 withdrawAmount = 2 ether;

        vm.prank(admin);
        minter.withdrawPrizePool(admin, withdrawAmount);

        assertEq(admin.balance, adminBalanceBefore + withdrawAmount);
        assertEq(address(minter).balance, 3 ether);
    }

    function test_RevertWhen_InsufficientETH() public {
        uint256 price = minter.MINT_PRICE();

        vm.prank(user);
        vm.expectRevert("Insufficient ETH");
        minter.mint{value: price - 1}(1);
    }

    function test_RevertWhen_InvalidMintAmount() public {
        vm.prank(user);
        vm.expectRevert("Invalid mint amount");
        minter.mint{value: 1 ether}(0);

        vm.prank(user);
        vm.expectRevert("Invalid mint amount");
        minter.mint{value: 1 ether}(101); // Over MAX_MINT_PER_TX
    }

    function test_RevertWhen_InsufficientCoupons() public {
        uint256 amount = 2;
        uint256 price = (minter.MINT_PRICE() * amount) / 2;

        // Give user only 1 coupon but try to mint 2
        vm.prank(admin);
        items.mint(user, items.MINT_COUPON_ID(), 1);

        vm.prank(user);
        vm.expectRevert("Insufficient coupons");
        minter.mintWithCoupons{value: price}(amount);
    }

    function test_RevertWhen_InsufficientETHWithCoupons() public {
        uint256 amount = 2;

        // Give user coupons
        vm.prank(admin);
        items.mint(user, items.MINT_COUPON_ID(), amount);

        // Try to pay less than discounted price
        uint256 discountedPrice = (minter.MINT_PRICE() * amount) / 2;

        vm.prank(user);
        vm.expectRevert("Insufficient ETH");
        minter.mintWithCoupons{value: discountedPrice - 1}(amount);
    }

    function test_RevertWhen_NonAdminWithdraws() public {
        vm.deal(address(minter), 1 ether);

        vm.prank(user);
        vm.expectRevert();
        minter.withdrawPrizePool(user, 1 ether);
    }

    function test_RevertWhen_WithdrawTooMuch() public {
        vm.deal(address(minter), 1 ether);

        vm.prank(admin);
        vm.expectRevert("Insufficient contract balance");
        minter.withdrawPrizePool(admin, 2 ether);
    }

    function testReceiveETH() public {
        uint256 balanceBefore = address(minter).balance;

        vm.prank(user);
        (bool success, ) = address(minter).call{value: 1 ether}("");
        assertTrue(success);

        assertEq(address(minter).balance, balanceBefore + 1 ether);
    }

    // ===== PRIZE FUNCTIONALITY TESTS =====

    function testSetPrizes() public {
        address[] memory users = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        users[0] = user;
        users[1] = makeAddr("user2");
        amounts[0] = 1 ether;
        amounts[1] = 0.5 ether;

        vm.prank(admin);
        minter.setPrizes(users, amounts);

        assertEq(minter.prizesForAddress(user), 1 ether);
        assertEq(minter.prizesForAddress(users[1]), 0.5 ether);
    }

    function testToggleClaims() public {
        // Claims should be disabled by default
        assertFalse(minter.claimsEnabled());

        vm.prank(admin);
        minter.toggleClaims(true);
        assertTrue(minter.claimsEnabled());

        vm.prank(admin);
        minter.toggleClaims(false);
        assertFalse(minter.claimsEnabled());
    }

    function testClaimPrize() public {
        // Setup: give contract ETH and user a prize
        vm.deal(address(minter), 5 ether);

        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = user;
        amounts[0] = 2 ether;

        vm.prank(admin);
        minter.setPrizes(users, amounts);

        vm.prank(admin);
        minter.toggleClaims(true);

        uint256 userBalanceBefore = user.balance;

        // User claims prize
        vm.prank(user);
        minter.claimPrize();

        assertEq(user.balance, userBalanceBefore + 2 ether);
        assertTrue(minter.hasClaimed(user));
        assertEq(address(minter).balance, 3 ether);
    }

    function testGetClaimStatus() public {
        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = user;
        amounts[0] = 1 ether;

        // Test: Claims disabled
        (bool canClaim, uint256 amount, string memory reason) = minter.getClaimStatus(user);
        assertFalse(canClaim);
        assertEq(amount, 0);
        assertEq(reason, "Claims are disabled");

        vm.prank(admin);
        minter.toggleClaims(true);

        // Test: No prize
        (canClaim, amount, reason) = minter.getClaimStatus(user);
        assertFalse(canClaim);
        assertEq(amount, 0);
        assertEq(reason, "No prize available");

        // Set prize
        vm.prank(admin);
        minter.setPrizes(users, amounts);

        // Test: Insufficient contract balance
        (canClaim, amount, reason) = minter.getClaimStatus(user);
        assertFalse(canClaim);
        assertEq(amount, 1 ether);
        assertEq(reason, "Insufficient contract balance");

        // Fund contract
        vm.deal(address(minter), 2 ether);

        // Test: Ready to claim
        (canClaim, amount, reason) = minter.getClaimStatus(user);
        assertTrue(canClaim);
        assertEq(amount, 1 ether);
        assertEq(reason, "Ready to claim");

        // Claim prize
        vm.prank(user);
        minter.claimPrize();

        // Test: Already claimed
        (canClaim, amount, reason) = minter.getClaimStatus(user);
        assertFalse(canClaim);
        assertEq(amount, 0);
        assertEq(reason, "Already claimed");
    }

    // ===== PRIZE FUNCTIONALITY REVERTS =====

    function test_RevertWhen_ClaimsDisabled() public {
        // Setup prize but keep claims disabled
        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = user;
        amounts[0] = 1 ether;

        vm.prank(admin);
        minter.setPrizes(users, amounts);
        vm.deal(address(minter), 2 ether);

        vm.prank(user);
        vm.expectRevert(UnimonMinter.ClaimsDisabled.selector);
        minter.claimPrize();
    }

    function test_RevertWhen_AlreadyClaimed() public {
        // Setup and first claim
        vm.deal(address(minter), 5 ether);

        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = user;
        amounts[0] = 1 ether;

        vm.prank(admin);
        minter.setPrizes(users, amounts);

        vm.prank(admin);
        minter.toggleClaims(true);

        vm.prank(user);
        minter.claimPrize();

        // Try to claim again
        vm.prank(user);
        vm.expectRevert(UnimonMinter.AlreadyClaimed.selector);
        minter.claimPrize();
    }

    function test_RevertWhen_NoPrize() public {
        vm.prank(admin);
        minter.toggleClaims(true);

        vm.prank(user);
        vm.expectRevert(UnimonMinter.NoPrize.selector);
        minter.claimPrize();
    }

    function test_RevertWhen_InsufficientContractBalanceForPrize() public {
        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = user;
        amounts[0] = 5 ether;

        vm.prank(admin);
        minter.setPrizes(users, amounts);

        vm.prank(admin);
        minter.toggleClaims(true);

        // Contract has no ETH
        vm.prank(user);
        vm.expectRevert(UnimonMinter.InsufficientContractBalance.selector);
        minter.claimPrize();
    }

    function test_RevertWhen_NonAdminSetsPrizes() public {
        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = user;
        amounts[0] = 1 ether;

        vm.prank(user);
        vm.expectRevert();
        minter.setPrizes(users, amounts);
    }

    function test_RevertWhen_NonAdminTogglesClaims() public {
        vm.prank(user);
        vm.expectRevert();
        minter.toggleClaims(true);
    }

    function test_RevertWhen_SetPrizesLengthMismatch() public {
        address[] memory users = new address[](2);
        uint256[] memory amounts = new uint256[](1);
        users[0] = user;
        users[1] = makeAddr("user2");
        amounts[0] = 1 ether;

        vm.prank(admin);
        vm.expectRevert("Length mismatch");
        minter.setPrizes(users, amounts);
    }

    function testPrizeClaimEvent() public {
        vm.deal(address(minter), 5 ether);

        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = user;
        amounts[0] = 2 ether;

        vm.prank(admin);
        minter.setPrizes(users, amounts);

        vm.prank(admin);
        minter.toggleClaims(true);

        vm.expectEmit(true, false, false, true);
        emit UnimonMinter.PrizeClaimed(user, 2 ether);

        vm.prank(user);
        minter.claimPrize();
    }
}
