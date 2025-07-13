// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

/**
 * @title PoolIdLens
 * @notice A lens contract for generating Uniswap V4 pool IDs from pool key details
 * @dev This contract provides utilities to compute pool IDs deterministically
 */
contract PoolIdLens {
    /**
     * @notice Generates a pool ID from individual pool key components
     * @param currency0 The first currency address
     * @param currency1 The second currency address
     * @param fee The swap fee
     * @param tickSpacing The tick spacing
     * @param hooks The hook contract address
     * @return poolId The generated pool ID
     */
    function getPoolId(
        address currency0,
        address currency1,
        uint24 fee,
        int24 tickSpacing,
        address hooks
    ) public pure returns (bytes32 poolId) {
        // Ensure currency0 < currency1 for deterministic pool ID
        if (currency0 > currency1) {
            (currency0, currency1) = (currency1, currency0);
        }
        
        poolId = keccak256(
            abi.encode(
                currency0,
                currency1,
                fee,
                tickSpacing,
                hooks
            )
        );
    }

    /**
     * @notice Generates a pool ID from a PoolKey struct
     * @param key The pool key
     * @return poolId The generated pool ID
     */
    function getPoolIdFromKey(PoolKey calldata key) public pure returns (bytes32 poolId) {
        return getPoolId(
            Currency.unwrap(key.currency0),
            Currency.unwrap(key.currency1),
            key.fee,
            key.tickSpacing,
            address(key.hooks)
        );
    }

    /**
     * @notice Batch generates pool IDs from multiple pool keys
     * @param keys Array of pool keys
     * @return poolIds Array of generated pool IDs
     */
    function batchGetPoolIds(PoolKey[] calldata keys) public pure returns (bytes32[] memory poolIds) {
        poolIds = new bytes32[](keys.length);
        for (uint256 i = 0; i < keys.length; i++) {
            poolIds[i] = getPoolIdFromKey(keys[i]);
        }
    }

    /**
     * @notice Batch generates pool IDs from multiple sets of pool key components
     * @param currencies0 Array of first currency addresses
     * @param currencies1 Array of second currency addresses
     * @param fees Array of swap fees
     * @param tickSpacings Array of tick spacings
     * @param hooks Array of hook contract addresses
     * @return poolIds Array of generated pool IDs
     */
    function batchGetPoolIdsFromComponents(
        address[] calldata currencies0,
        address[] calldata currencies1,
        uint24[] calldata fees,
        int24[] calldata tickSpacings,
        address[] calldata hooks
    ) public pure returns (bytes32[] memory poolIds) {
        require(
            currencies0.length == currencies1.length &&
            currencies1.length == fees.length &&
            fees.length == tickSpacings.length &&
            tickSpacings.length == hooks.length,
            "Array lengths must match"
        );

        poolIds = new bytes32[](currencies0.length);
        for (uint256 i = 0; i < currencies0.length; i++) {
            poolIds[i] = getPoolId(
                currencies0[i],
                currencies1[i],
                fees[i],
                tickSpacings[i],
                hooks[i]
            );
        }
    }
} 