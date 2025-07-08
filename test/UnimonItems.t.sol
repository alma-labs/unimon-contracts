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
} 