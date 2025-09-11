pragma solidity ^0.8.26;

import {TWAPManager} from "./TWAPManager.sol";

/// Library for managing configuration parameters and validation for the LiquidityHook
/// Provides centralized configuration management.
/// 1. TWAP Concentration Strategy: Parameters for time-weighted average price-based liquidity concentration
/// 2. Rebalance Threshold: Price deviation threshold that triggers automatic rebalancing
library ConfigManager {
    /// Configuration bundle containing all hook configurations
    /// This struct serves as the single source of truth for all configurable parameters
    /// in the LiquidityHook system. It combines TWAP concentration strategy settings
    /// with rebalancing thresholds to provide a complete configuration interface.
    struct HookConfig {
        /// TWAP-based liquidity concentration strategy parameters
        /// Controls how liquidity is positioned around time-weighted average prices
        TWAPManager.ConcentrationConfig twapConcentrationConfig;
        /// Price deviation threshold in basis points that triggers automatic rebalancing
        /// Example: 50 = 0.5% deviation, 100 = 1% deviation, 500 = 5% deviation
        uint24 rebalanceThreshold;
    }

    /// @notice Sets TWAP concentration strategy parameters
    /// @param config The hook configuration bundle
    /// @param twapPeriod The period (in seconds) over which to calculate the TWAP
    /// @param tickRangeWidth The width (in ticks) around the TWAP tick for liquidity distribution
    /// @param desiredAmount The desired amount of base token for liquidity provision when minting new positions
    function setTWAPConcentrationStrategyParams(
        HookConfig storage config,
        uint32 twapPeriod,
        uint24 tickRangeWidth,
        uint256 desiredAmount
    ) internal {
        config.twapConcentrationConfig = TWAPManager.ConcentrationConfig({
            twapPeriod: twapPeriod,
            tickRangeWidth: tickRangeWidth,
            desiredAmount: desiredAmount
        });
    }

    /// @notice Sets the rebalance threshold for the hook
    /// @param config The hook configuration bundle
    /// @param threshold The percentage deviation in basis points (e.g., 50 for 0.5%, 100 for 1%) that triggers a rebalance
    function setRebalanceThreshold(HookConfig storage config, uint24 threshold) internal {
        config.rebalanceThreshold = threshold;
    }

    /// @notice Initializes the hook configuration with default values
    /// @param config The hook configuration bundle to initialize
    function initializeConfig(HookConfig storage config) internal {
        config.twapConcentrationConfig = TWAPManager.ConcentrationConfig({
            twapPeriod: 0,
            tickRangeWidth: 0,
            desiredAmount: 0
        });
        config.rebalanceThreshold = 0; // Default to 0, meaning no rebalance by default
    }
}
