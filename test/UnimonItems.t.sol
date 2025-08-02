// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {UnimonItems} from "../contracts/v2/UnimonItems.sol";

contract UnimonItemsTest is Test {
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
        items.grantMinterRole(minter);
        items.grantSpenderRole(minter);
        items.grantMinterRole(address(this));
        items.grantSpenderRole(address(this));
        vm.stopPrank();
    }

    function testInitialState() public view {
        assertEq(items.ENERGY_ID(), 0);
        assertEq(items.UNIKEY_ID(), 1);
        assertEq(items.MINT_COUPON_ID(), 2);
        assertEq(items.balanceOf(user, 0), 0);
    }

    function testMintItems() public {
        items.mint(user, items.ENERGY_ID(), 10);

        assertEq(items.balanceOf(user, items.ENERGY_ID()), 10);
    }

    function testMintBatch() public {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);

        ids[0] = items.ENERGY_ID();
        ids[1] = items.UNIKEY_ID();
        amounts[0] = 5;
        amounts[1] = 3;

        items.mintBatch(user, ids, amounts);

        assertEq(items.balanceOf(user, items.ENERGY_ID()), 5);
        assertEq(items.balanceOf(user, items.UNIKEY_ID()), 3);
    }

    function testSpendItem() public {
        // First mint some items
        items.mint(user, items.ENERGY_ID(), 10);

        // Spend items using test contract which has spender role
        items.spendItem(user, items.ENERGY_ID(), 3);

        assertEq(items.balanceOf(user, items.ENERGY_ID()), 7);
    }

    function testGetBalances() public {
        // Mint some items
        uint256[] memory ids = new uint256[](3);
        uint256[] memory amounts = new uint256[](3);

        ids[0] = items.ENERGY_ID();
        ids[1] = items.UNIKEY_ID();
        ids[2] = items.MINT_COUPON_ID();
        amounts[0] = 10;
        amounts[1] = 5;
        amounts[2] = 2;

        items.mintBatch(user, ids, amounts);

        uint256[] memory balances = items.getBalances(user, ids);
        assertEq(balances[0], 10);
        assertEq(balances[1], 5);
        assertEq(balances[2], 2);
    }

    function test_RevertWhen_NonMinterMints() public {
        uint256 energyId = items.ENERGY_ID();
        vm.prank(user);
        vm.expectRevert();
        items.mint(user, energyId, 10);
    }

    function test_RevertWhen_NonSpenderSpends() public {
        uint256 energyId = items.ENERGY_ID();
        items.mint(user, energyId, 10);

        vm.prank(user);
        vm.expectRevert();
        items.spendItem(user, energyId, 5);
    }

    // v1Airdrop Tests
    function testV1Airdrop() public {
        address[] memory recipients = new address[](3);
        uint256[] memory amounts = new uint256[](3);

        recipients[0] = makeAddr("user1");
        recipients[1] = makeAddr("user2");
        recipients[2] = makeAddr("user3");
        amounts[0] = 5;
        amounts[1] = 10;
        amounts[2] = 3;

        items.v1Airdrop(recipients, amounts);

        // Check unikeys
        assertEq(items.balanceOf(recipients[0], items.UNIKEY_ID()), 5);
        assertEq(items.balanceOf(recipients[1], items.UNIKEY_ID()), 10);
        assertEq(items.balanceOf(recipients[2], items.UNIKEY_ID()), 3);

        // Check mint coupons
        assertEq(items.balanceOf(recipients[0], items.MINT_COUPON_ID()), 5);
        assertEq(items.balanceOf(recipients[1], items.MINT_COUPON_ID()), 10);
        assertEq(items.balanceOf(recipients[2], items.MINT_COUPON_ID()), 3);

        // Check airdrop executed flag
        assertTrue(items.airdropExecuted());
    }

    function testV1AirdropWithZeroAmounts() public {
        address[] memory recipients = new address[](3);
        uint256[] memory amounts = new uint256[](3);

        recipients[0] = makeAddr("user1");
        recipients[1] = makeAddr("user2");
        recipients[2] = makeAddr("user3");
        amounts[0] = 5;
        amounts[1] = 0; // Should be skipped
        amounts[2] = 3;

        items.v1Airdrop(recipients, amounts);

        // Check unikeys
        assertEq(items.balanceOf(recipients[0], items.UNIKEY_ID()), 5);
        assertEq(items.balanceOf(recipients[1], items.UNIKEY_ID()), 0);
        assertEq(items.balanceOf(recipients[2], items.UNIKEY_ID()), 3);

        // Check mint coupons
        assertEq(items.balanceOf(recipients[0], items.MINT_COUPON_ID()), 5);
        assertEq(items.balanceOf(recipients[1], items.MINT_COUPON_ID()), 0);
        assertEq(items.balanceOf(recipients[2], items.MINT_COUPON_ID()), 3);
    }

    function testV1AirdropRevertWhenArrayLengthMismatch() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](3);

        recipients[0] = makeAddr("user1");
        recipients[1] = makeAddr("user2");
        amounts[0] = 5;
        amounts[1] = 10;
        amounts[2] = 3;

        vm.expectRevert("Arrays length mismatch");
        items.v1Airdrop(recipients, amounts);
    }

    function testV1AirdropRevertWhenAlreadyExecuted() public {
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        recipients[0] = makeAddr("user1");
        amounts[0] = 5;

        // First call should succeed
        items.v1Airdrop(recipients, amounts);

        // Second call should revert
        vm.expectRevert("Airdrop already executed");
        items.v1Airdrop(recipients, amounts);
    }

    function testV1AirdropRevertWhenNonMinter() public {
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        recipients[0] = makeAddr("user1");
        amounts[0] = 5;

        vm.prank(user); // user doesn't have minter role
        vm.expectRevert();
        items.v1Airdrop(recipients, amounts);
    }

    function testV1AirdropLargeBatch() public {
        // Test with 10 recipients to simulate larger airdrop
        address[] memory recipients = new address[](1000);
        uint256[] memory amounts = new uint256[](1000);

        for (uint256 i = 0; i < 1000; i++) {
            recipients[i] = makeAddr(string(abi.encodePacked("user", vm.toString(i))));
            amounts[i] = i + 1; // Different amounts for each user
        }

        items.v1Airdrop(recipients, amounts);

        // Verify all recipients got correct amounts
        for (uint256 i = 0; i < 1000; i++) {
            assertEq(items.balanceOf(recipients[i], items.UNIKEY_ID()), i + 1);
            assertEq(items.balanceOf(recipients[i], items.MINT_COUPON_ID()), i + 1);
        }
    }
}
