pragma solidity ^0.8.26;

import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

/// Library for managing TWAP-based liquidity concentration strategies.
/// Leverages Time-Weighted Average Price (TWAP) to provide a more robust
/// and reliable price signal for automated liquidity management. By averaging prices over a
/// specified period (`twapPeriod`), the strategies implemented here aim to:
/// 1. Reduce susceptibility to short-term price volatility and ephemeral market noise.
/// 2. Mitigate risks from price manipulation attempts, as an attacker would need to sustain
///    a price deviation for the entire TWAP period, making it economically unfeasible.
/// This ensures that liquidity rebalancing and positioning decisions are based on a more
/// stable and accurate reflection of market sentiment.
library TWAPManager {
    /// Configuration for TWAP concentration strategy
    struct ConcentrationConfig {
        /// Period in seconds for TWAP calculation.
        /// This duration is crucial for smoothing out price volatility and resisting short-term manipulation.
        /// Instead of reacting to a momentary spot price, the hook uses an average price over this period.
        /// A longer `twapPeriod` provides a more stable and reliable price signal, leading to fewer
        /// unnecessary rebalances and better-informed liquidity positioning.
        uint32 twapPeriod;
        /// Width in ticks around TWAP tick for liquidity distribution.
        /// For example, if the TWAP tick is 5000 and our tickRangeWidth is 200, 
        /// the hook will attempt to place liquidity from tickLower = 4900 to tickUpper = 5100 (5000 - 100 to 5000 + 100).
        /// This value must be a multiple of the pool's `tickSpacing` for optimal placement.
        uint24 tickRangeWidth;
        /// Desired amount of base token for liquidity provision. Help maintaining a consistent amount of capital deployed across rebalances. 
        /// This represents the target amount of a base token (e.g., USD stablecoin) that the hook aims to deploy
        /// as liquidity within the calculated optimal tick range. This can be used by external mechanisms
        /// to determine how much liquidity to provide or rebalance.
        uint256 desiredAmount;
    }

    /// Tick range for optimal liquidity positioning
    struct TickRange {
        /// The lower tick boundary of the concentrated liquidity position.
        int24 tickLower;
        /// The upper tick boundary of the concentrated liquidity position.
        int24 tickUpper;
    }

    /// Thrown when the calculated tick range is invalid (tickLower >= tickUpper).
    /// This typically indicates a configuration issue with tickRangeWidth or pool boundaries.
    error InvalidTickRange();

    /// Checks if the TWAP concentration strategy is enabled.
    /// The strategy is considered "enabled" if both `tickRangeWidth` and `desiredAmount` are set to non-zero values.
    /// If either is zero, it implies the strategy is not intended to be used or is not fully configured.
    /// @param config The concentration configuration bundle.
    /// @return True if concentration is enabled (non-zero `tickRangeWidth` and `desiredAmount`); otherwise, false.
    function isConcentrationEnabled(ConcentrationConfig memory config) internal pure returns (bool) {
        return config.tickRangeWidth > 0 && config.desiredAmount > 0;
    }

    /// Calculates the optimal tick range for concentrated liquidity based on a TWAP price.
    /// This function determines the ideal lower and upper tick boundaries for placing liquidity,
    /// centered around the `twapSqrtPriceX96` and constrained by the `tickRangeWidth`.
    /// @param config The concentration configuration bundle, including `tickRangeWidth`.
    /// @param twapSqrtPriceX96 The Time-Weighted Average Price (TWAP) as a square root price in Q96 format.
    /// @return optimalRange A `TickRange` struct containing the calculated `tickLower` and `tickUpper`.
    function calculateOptimalTickRange(
        ConcentrationConfig memory config,
        uint160 twapSqrtPriceX96
    ) internal pure returns (TickRange memory optimalRange) {
        // Convert the square root price to its corresponding tick.
        int24 twapTick = TickMath.getTickAtSqrtPrice(twapSqrtPriceX96);
        
        // Calculate the raw lower and upper ticks by spanning half the `tickRangeWidth` around the TWAP tick.
        int24 tickLower = twapTick - int24(config.tickRangeWidth) / 2;
        int24 tickUpper = twapTick + int24(config.tickRangeWidth) / 2;
        
        // Ensure the calculated ticks are within the absolute minimum and maximum valid tick bounds
        // for Uniswap V4 pools (TickMath.MIN_TICK and TickMath.MAX_TICK).
        tickLower = tickLower < TickMath.MIN_TICK ? TickMath.MIN_TICK : tickLower;
        tickUpper = tickUpper > TickMath.MAX_TICK ? TickMath.MAX_TICK : tickUpper;
        
        // handles edge cases where the width might be too small or near pool boundaries.
        if (tickLower >= tickUpper) {
            // This should never happen with proper configuration
            // If it does, it indicates a serious configuration issue that needs to be fixed
            revert InvalidTickRange();
        }
        
        return TickRange({
            tickLower: tickLower,
            tickUpper: tickUpper
        });
    }

    /// Determines if a rebalance of liquidity is necessary based on the current price deviation
    /// @param currentPriceX96 The current market square root price in Q96 format.
    /// @param targetPriceX96 The target square root price (e.g., a TWAP) in Q96 format to compare against.
    /// @param rebalanceThreshold The percentage deviation threshold in basis points (e.g., 500 for 0.5%, 100 for 0.1%, 50 for 0.05%).
    /// This value is in basis points, multiplied by 10000 to allow for two decimal places of precision.
    /// @return True if the absolute price deviation is greater than or equal to the `rebalanceThreshold`; otherwise, false.
    function isRebalanceNeeded(
        uint160 currentPriceX96,
        uint160 targetPriceX96,
        uint24 rebalanceThreshold
    ) internal pure returns (bool) {
        // Avoid division by zero if the target price is zero (e.g., during initial setup or in error states).
        if (targetPriceX96 == 0) return false;
        
        // Calculate the absolute difference between the current and target prices.
        uint256 priceDiff = currentPriceX96 > targetPriceX96
            ? currentPriceX96 - targetPriceX96
            : targetPriceX96 - currentPriceX96;
        
        // Calculate the percentage deviation relative to the target price.
        // The `10000` factor scales the comparison to handle `rebalanceThreshold` as
        // a value representing hundredths of a percent (e.g., 500 for 0.5%, 100 for 0.1%, 50 for 0.05%).
        return (priceDiff * 10000) / targetPriceX96 >= rebalanceThreshold;
    }
}
