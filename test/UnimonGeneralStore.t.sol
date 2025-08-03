// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {UnimonGeneralStore} from "../contracts/v2/UnimonGeneralStore.sol";
import {UnimonItems} from "../contracts/v2/UnimonItems.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract UnimonGeneralStoreTest is Test {
    UnimonGeneralStore public store;
    UnimonItems public items;
    MockERC20 public token1;
    MockERC20 public token2;

    address public admin;
    address public user;
    address public user2;

    uint256 constant ENERGY_ID = 0;
    uint256 constant UNIKEY_ID = 1;
    uint256 constant MINT_COUPON_ID = 2;
    uint256 constant CUSTOM_ITEM_ID = 100;

    function setUp() public {
        admin = makeAddr("admin");
        user = makeAddr("user");
        user2 = makeAddr("user2");

        vm.startPrank(admin);

        // Deploy contracts
        items = new UnimonItems(admin);
        store = new UnimonGeneralStore(address(items));
        token1 = new MockERC20("Test Token 1", "TT1");
        token2 = new MockERC20("Test Token 2", "TT2");

        // Grant store permission to spend items
        items.grantSpenderRole(address(store));

        // Grant admin and test contract minter roles for testing
        items.grantMinterRole(admin);
        items.grantMinterRole(address(this));

        // Fund store with tokens for redemptions
        token1.transfer(address(store), 10000 * 10**18);
        token2.transfer(address(store), 5000 * 10**18);

        vm.stopPrank();
    }

    function testInitialState() public view {
        assertEq(address(store.items()), address(items));
        assertEq(address(store.owner()), admin);
    }

    function testSetTokenRedemption() public {
        uint256 itemId = UNIKEY_ID;
        uint256 tokenAmount = 100 * 10**18;

        vm.expectEmit(true, true, false, true);
        emit UnimonGeneralStore.TokenRedemptionSet(itemId, address(token1), tokenAmount);

        vm.prank(admin);
        store.setTokenRedemption(itemId, address(token1), tokenAmount);

        (address token, uint256 amount, bool isActive) = store.tokenRedemptions(itemId);
        assertEq(token, address(token1));
        assertEq(amount, tokenAmount);
        assertTrue(isActive);
    }

    function testSetBulkTokenRedemptions() public {
        uint256[] memory itemIds = new uint256[](3);
        address[] memory tokens = new address[](3);
        uint256[] memory amounts = new uint256[](3);

        itemIds[0] = ENERGY_ID;
        itemIds[1] = UNIKEY_ID;
        itemIds[2] = MINT_COUPON_ID;
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        tokens[2] = address(token1);
        amounts[0] = 50 * 10**18;
        amounts[1] = 100 * 10**18;
        amounts[2] = 75 * 10**18;

        vm.prank(admin);
        store.setBulkTokenRedemptions(itemIds, tokens, amounts);

        // Check all redemptions were set
        for (uint256 i = 0; i < itemIds.length; i++) {
            (address token, uint256 amount, bool isActive) = store.tokenRedemptions(itemIds[i]);
            assertEq(token, tokens[i]);
            assertEq(amount, amounts[i]);
            assertTrue(isActive);
        }
    }

    function testRedeemForToken() public {
        uint256 itemId = UNIKEY_ID;
        uint256 redeemAmount = 5;
        uint256 tokenAmount = 100 * 10**18;

        // Setup redemption
        vm.prank(admin);
        store.setTokenRedemption(itemId, address(token1), tokenAmount);

        // Give user items to redeem
        items.mint(user, itemId, redeemAmount);

        uint256 userTokenBalanceBefore = token1.balanceOf(user);
        uint256 userItemBalanceBefore = items.balanceOf(user, itemId);

        vm.expectEmit(true, true, false, true);
        emit UnimonGeneralStore.TokensRedeemed(user, itemId, redeemAmount, redeemAmount * tokenAmount, address(token1));

        // Redeem items
        vm.prank(user);
        store.redeemForToken(itemId, redeemAmount);

        // Check balances
        assertEq(token1.balanceOf(user), userTokenBalanceBefore + (redeemAmount * tokenAmount));
        assertEq(items.balanceOf(user, itemId), userItemBalanceBefore - redeemAmount);
    }

    function testBulkRedeemForToken() public {
        // Setup multiple redemptions
        vm.startPrank(admin);
        store.setTokenRedemption(ENERGY_ID, address(token1), 50 * 10**18);
        store.setTokenRedemption(UNIKEY_ID, address(token2), 100 * 10**18);
        vm.stopPrank();

        // Give user items
        items.mint(user, ENERGY_ID, 10);
        items.mint(user, UNIKEY_ID, 3);

        uint256[] memory itemIds = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        itemIds[0] = ENERGY_ID;
        itemIds[1] = UNIKEY_ID;
        amounts[0] = 4;
        amounts[1] = 2;

        uint256 token1BalanceBefore = token1.balanceOf(user);
        uint256 token2BalanceBefore = token2.balanceOf(user);

        // Bulk redeem
        vm.prank(user);
        store.bulkRedeemForToken(itemIds, amounts);

        // Check final balances
        assertEq(token1.balanceOf(user), token1BalanceBefore + (4 * 50 * 10**18));
        assertEq(token2.balanceOf(user), token2BalanceBefore + (2 * 100 * 10**18));
        assertEq(items.balanceOf(user, ENERGY_ID), 6); // 10 - 4
        assertEq(items.balanceOf(user, UNIKEY_ID), 1); // 3 - 2
    }

    function testGetTokenRedemptionInfo() public {
        uint256 itemId = UNIKEY_ID;
        uint256 tokenAmount = 100 * 10**18;

        vm.prank(admin);
        store.setTokenRedemption(itemId, address(token1), tokenAmount);

        UnimonGeneralStore.TokenRedemptionInfo memory info = store.getTokenRedemptionInfo(itemId);
        assertEq(info.token, address(token1));
        assertEq(info.amount, tokenAmount);
        assertTrue(info.isActive);
        assertEq(info.tokenSymbol, "TT1");
        assertEq(info.contractBalance, token1.balanceOf(address(store)));
    }

    function testGetBulkTokenRedemptionInfo() public {
        // Setup redemptions
        vm.startPrank(admin);
        store.setTokenRedemption(ENERGY_ID, address(token1), 50 * 10**18);
        store.setTokenRedemption(UNIKEY_ID, address(token2), 100 * 10**18);
        vm.stopPrank();

        uint256[] memory itemIds = new uint256[](2);
        itemIds[0] = ENERGY_ID;
        itemIds[1] = UNIKEY_ID;

        UnimonGeneralStore.TokenRedemptionInfo[] memory infos = store.getBulkTokenRedemptionInfo(itemIds);

        assertEq(infos.length, 2);
        assertEq(infos[0].token, address(token1));
        assertEq(infos[0].amount, 50 * 10**18);
        assertEq(infos[1].token, address(token2));
        assertEq(infos[1].amount, 100 * 10**18);
    }

    function testDeleteTokenRedemptions() public {
        // Setup redemptions
        vm.startPrank(admin);
        store.setTokenRedemption(ENERGY_ID, address(token1), 50 * 10**18);
        store.setTokenRedemption(UNIKEY_ID, address(token2), 100 * 10**18);

        uint256[] memory itemIds = new uint256[](2);
        itemIds[0] = ENERGY_ID;
        itemIds[1] = UNIKEY_ID;

        vm.expectEmit(false, false, false, true);
        emit UnimonGeneralStore.TokenRedemptionsDeleted(itemIds);

        store.deleteTokenRedemptions(itemIds);
        vm.stopPrank();

        // Check redemptions were deleted
        (address tokenAddr1, uint256 amount1, bool isActive1) = store.tokenRedemptions(ENERGY_ID);
        (address tokenAddr2, uint256 amount2, bool isActive2) = store.tokenRedemptions(UNIKEY_ID);

        assertEq(tokenAddr1, address(0));
        assertEq(amount1, 0);
        assertFalse(isActive1);
        assertEq(tokenAddr2, address(0));
        assertEq(amount2, 0);
        assertFalse(isActive2);
    }

    function testToggleRedemptionStatus() public {
        uint256 itemId = UNIKEY_ID;

        // Setup redemption
        vm.prank(admin);
        store.setTokenRedemption(itemId, address(token1), 100 * 10**18);

        // Toggle to inactive
        vm.prank(admin);
        store.toggleRedemptionStatus(itemId, false);

        (,, bool isActive) = store.tokenRedemptions(itemId);
        assertFalse(isActive);

        // Toggle back to active
        vm.prank(admin);
        store.toggleRedemptionStatus(itemId, true);

        (,, isActive) = store.tokenRedemptions(itemId);
        assertTrue(isActive);
    }

    function testWithdrawERC20() public {
        uint256 withdrawAmount = 1000 * 10**18;
        uint256 adminBalanceBefore = token1.balanceOf(admin);

        vm.prank(admin);
        store.withdrawERC20(address(token1), admin, withdrawAmount);

        assertEq(token1.balanceOf(admin), adminBalanceBefore + withdrawAmount);
    }

    function testWithdrawETH() public {
        uint256 withdrawAmount = 1 ether;

        // Send ETH to contract
        vm.deal(address(store), 2 ether);

        uint256 adminBalanceBefore = admin.balance;

        vm.prank(admin);
        store.withdrawETH(admin, withdrawAmount);

        assertEq(admin.balance, adminBalanceBefore + withdrawAmount);
        assertEq(address(store).balance, 1 ether);
    }

    // ===== REVERT TESTS =====

    function test_RevertWhen_NonOwnerSetsRedemption() public {
        vm.prank(user);
        vm.expectRevert();
        store.setTokenRedemption(UNIKEY_ID, address(token1), 100 * 10**18);
    }

    function test_RevertWhen_InvalidTokenAddress() public {
        vm.prank(admin);
        vm.expectRevert("Invalid token address");
        store.setTokenRedemption(UNIKEY_ID, address(0), 100 * 10**18);
    }

    function test_RevertWhen_ZeroAmount() public {
        vm.prank(admin);
        vm.expectRevert("Amount must be greater than 0");
        store.setTokenRedemption(UNIKEY_ID, address(token1), 0);
    }

    function test_RevertWhen_RedeemZeroAmount() public {
        vm.prank(admin);
        store.setTokenRedemption(UNIKEY_ID, address(token1), 100 * 10**18);

        vm.prank(user);
        vm.expectRevert("Amount must be greater than 0");
        store.redeemForToken(UNIKEY_ID, 0);
    }

    function test_RevertWhen_RedemptionNotActive() public {
        vm.prank(user);
        vm.expectRevert("Token redemption not active for this item");
        store.redeemForToken(UNIKEY_ID, 1);
    }

    function test_RevertWhen_InsufficientTokenBalance() public {
        uint256 itemId = CUSTOM_ITEM_ID;
        uint256 tokenAmount = 20000 * 10**18; // More than contract has

        vm.prank(admin);
        store.setTokenRedemption(itemId, address(token1), tokenAmount);

        items.mint(user, itemId, 1);

        vm.prank(user);
        vm.expectRevert("Insufficient token balance");
        store.redeemForToken(itemId, 1);
    }

    function test_RevertWhen_BulkArrayLengthMismatch() public {
        uint256[] memory itemIds = new uint256[](2);
        uint256[] memory amounts = new uint256[](1);

        vm.prank(user);
        vm.expectRevert("Array lengths must match");
        store.bulkRedeemForToken(itemIds, amounts);
    }

    function test_RevertWhen_BulkRedeemEmpty() public {
        uint256[] memory itemIds = new uint256[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.prank(user);
        vm.expectRevert("Must redeem at least one item");
        store.bulkRedeemForToken(itemIds, amounts);
    }

    function test_RevertWhen_NonOwnerDeletesRedemptions() public {
        uint256[] memory itemIds = new uint256[](1);
        itemIds[0] = UNIKEY_ID;

        vm.prank(user);
        vm.expectRevert();
        store.deleteTokenRedemptions(itemIds);
    }

    function test_RevertWhen_DeleteEmptyArray() public {
        uint256[] memory itemIds = new uint256[](0);

        vm.prank(admin);
        vm.expectRevert("Must provide at least one item ID");
        store.deleteTokenRedemptions(itemIds);
    }

    function test_RevertWhen_ToggleNonExistentRedemption() public {
        vm.prank(admin);
        vm.expectRevert("Redemption not configured");
        store.toggleRedemptionStatus(CUSTOM_ITEM_ID, false);
    }

    function test_RevertWhen_NonOwnerWithdraws() public {
        vm.prank(user);
        vm.expectRevert();
        store.withdrawERC20(address(token1), user, 100);

        vm.prank(user);
        vm.expectRevert();
        store.withdrawETH(user, 1 ether);
    }

    // ===== EDGE CASES =====

    function testRedeemDisabledRedemption() public {
        uint256 itemId = UNIKEY_ID;

        // Setup and then disable redemption
        vm.startPrank(admin);
        store.setTokenRedemption(itemId, address(token1), 100 * 10**18);
        store.toggleRedemptionStatus(itemId, false);
        vm.stopPrank();

        items.mint(user, itemId, 1);

        vm.prank(user);
        vm.expectRevert("Token redemption not active for this item");
        store.redeemForToken(itemId, 1);
    }

    function testLargeRedemption() public {
        uint256 itemId = UNIKEY_ID;
        uint256 redeemAmount = 1000;
        uint256 tokenAmount = 1 * 10**18;

        vm.prank(admin);
        store.setTokenRedemption(itemId, address(token1), tokenAmount);

        items.mint(user, itemId, redeemAmount);

        uint256 userTokenBalanceBefore = token1.balanceOf(user);

        vm.prank(user);
        store.redeemForToken(itemId, redeemAmount);

        assertEq(token1.balanceOf(user), userTokenBalanceBefore + (redeemAmount * tokenAmount));
        assertEq(items.balanceOf(user, itemId), 0);
    }

    function testReceiveETH() public {
        uint256 balanceBefore = address(store).balance;

        vm.deal(address(user), 1 ether);

        vm.prank(user);
        (bool success, ) = address(store).call{value: 1 ether}("");
        assertTrue(success);

        assertEq(address(store).balance, balanceBefore + 1 ether);
    }

    function testRedemptionWithNoSymbol() public {
        // Test with a token that might not have symbol() - using a simple contract
        MockERC20 noSymbolToken = new MockERC20("", "");
        noSymbolToken.transfer(address(store), 1000 * 10**18);

        uint256 itemId = CUSTOM_ITEM_ID;

        vm.prank(admin);
        store.setTokenRedemption(itemId, address(noSymbolToken), 100 * 10**18);

        UnimonGeneralStore.TokenRedemptionInfo memory info = store.getTokenRedemptionInfo(itemId);
        assertEq(info.tokenSymbol, ""); // Should handle gracefully
    }
}