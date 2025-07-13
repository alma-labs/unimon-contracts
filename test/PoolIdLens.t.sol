// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {PoolIdLens} from "../contracts/PoolIdLens.sol";

contract PoolIdLensTest is Test {
    PoolIdLens public lens;

    function setUp() public {
        lens = new PoolIdLens();
    }

    function testSpecificPoolId() public {
        // Pool key details from user:
        // currency0: 0x0000000000000000000000000000000000000000 (ETH)
        // currency1: 0xa388D639CCe30d68Cc3783eD57665Ebb61F32418
        // fee: 30000 (3%)
        // tickSpacing: 200
        // hooks: 0x9ea932730A7787000042e34390B8E435dD839040

        address currency0 = 0x0000000000000000000000000000000000000000;
        address currency1 = 0xa388D639CCe30d68Cc3783eD57665Ebb61F32418;
        uint24 fee = 30000;
        int24 tickSpacing = 200;
        address hooks = 0x9ea932730A7787000042e34390B8E435dD839040;

        bytes32 poolId = lens.getPoolId(currency0, currency1, fee, tickSpacing, hooks);

        console.log("Pool Key Details:");
        console.log("Currency0:", currency0);
        console.log("Currency1:", currency1);
        console.log("Fee:", fee);
        console.log("Tick Spacing:", uint256(int256(tickSpacing)));
        console.log("Hooks:", hooks);
        console.log("");
        console.log("Generated Pool ID:");
        console.logBytes32(poolId);
    }
} 