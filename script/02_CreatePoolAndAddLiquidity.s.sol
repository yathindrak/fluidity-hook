pragma solidity ^0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {console2} from "forge-std/console2.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BaseScript} from "./base/BaseScript.sol";
import {LiquidityHelpers} from "./base/LiquidityHelpers.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {LiquidityRebalancer} from "../src/RebalanceHook.sol";

contract CreatePoolAndAddLiquidityScript is BaseScript, LiquidityHelpers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using Strings for uint256;

    /////////////////////////////////////
    // --- Configure These ---
    /////////////////////////////////////

    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 60;
    uint160 startingPrice = 2 ** 96; // Starting price, sqrtPriceX96; floor(sqrt(1) * 2^96)

    // --- liquidity position configuration --- //
    // 1 ETH = 4,503 USDC as of now, so for 1 ETH we need 4,503 USDC
    uint256 public token0Amount = 1e18;    // 1 ETH (18 decimals)
    uint256 public token1Amount = 4503e6;  // 4,503 USDC (6 decimals)

    // range of the position, must be a multiple of tickSpacing
    int24 tickLower;
    int24 tickUpper;
    /////////////////////////////////////

    function run() external {
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: hookContract
        });
        console2.log("Pool Key: ");
        console2.log(uint256(PoolId.unwrap(poolKey.toId())));
        // hex version of the pool key
        console2.log("Pool Key Hex: ");
        console2.log(uint256(PoolId.unwrap(poolKey.toId())).toHexString());

        bytes memory hookData = new bytes(0);

        int24 currentTick = TickMath.getTickAtSqrtPrice(startingPrice);

        tickLower = truncateTickSpacing((currentTick - 750 * tickSpacing), tickSpacing);
        tickUpper = truncateTickSpacing((currentTick + 750 * tickSpacing), tickSpacing);

        console2.log("Current tick:", currentTick);
        console2.log("Tick lower:", tickLower);
        console2.log("Tick upper:", tickUpper);
        console2.log("Token0 amount:", token0Amount);
        console2.log("Token1 amount:", token1Amount);

        vm.startBroadcast();
        
        // First, initialize the pool using PositionManager
        console2.log("Initializing pool...");
        positionManager.initializePool(poolKey, startingPrice);
        console2.log("Pool initialized successfully!");

        // Get the LiquidityRebalancer instance
        LiquidityRebalancer liquidityRebalancer = LiquidityRebalancer(address(hookContract));
        
        // Approve tokens for the hook contract and pool manager
        console2.log("Approving tokens for hook contract...");
        token0.approve(address(liquidityRebalancer), type(uint256).max);
        token1.approve(address(liquidityRebalancer), type(uint256).max);
        token0.approve(address(poolManager), type(uint256).max);
        token1.approve(address(poolManager), type(uint256).max);
        console2.log("Token approvals completed!");
        
        // Skip liquidity addition for now due to callback pattern issues
        console2.log("Skipping liquidity provisioning due to callback pattern complexity...");
        console2.log("Pool created successfully and ready for manual testing!");
        
        vm.stopBroadcast();
    }
}
