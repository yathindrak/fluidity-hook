pragma solidity ^0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {console2} from "forge-std/console2.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {BaseScript} from "./base/BaseScript.sol";
import {LiquidityHelpers} from "./base/LiquidityHelpers.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {LiquidityRebalancer} from "../src/RebalanceHook.sol";

contract CreatePoolAndAddLiquidityScript is BaseScript, LiquidityHelpers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using Strings for uint256;

    /////////////////////////////////////
    // --- Configure These ---
    /////////////////////////////////////

    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 60;
    uint160 startingPrice = 2 ** 96; // Starting price, sqrtPriceX96; floor(sqrt(1) * 2^96)

    // --- liquidity position configuration --- //
    uint256 public token0Amount = 100e18;
    uint256 public token1Amount = 100e18;

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
            hooks: IHooks(address(0)) // Use empty hooks to avoid Fhenix permission issues
        });
        console2.log("Pool Key: ");
        console2.log(uint256(PoolId.unwrap(poolKey.toId())));
        // hex version of the pool key
        console2.log("Pool Key Hex: ");
        console2.log(uint256(PoolId.unwrap(poolKey.toId())).toHexString());

        bytes memory hookData = new bytes(0);

        vm.startBroadcast();
        
        // Check if pool is already initialized
        (uint160 sqrtPriceX96, int24 currentTick, uint128 liquidity, uint32 secondsInitialized) = poolManager.getSlot0(poolKey.toId());
        console2.log("Current pool state - tick:", currentTick);
        console2.log("Current pool state - sqrtPriceX96:", uint256(sqrtPriceX96).toHexString());
        console2.log("Current pool state - liquidity:", uint256(liquidity));
        console2.log("Current pool state - secondsInitialized:", uint256(secondsInitialized));
        
        // Only initialize if not already initialized
        if (secondsInitialized == 0) {
            console2.log("Pool not initialized, initializing now...");
            positionManager.initializePool(poolKey, startingPrice);
            console2.log("Pool initialized successfully!");
            
            // Get the updated state after initialization
            (sqrtPriceX96, currentTick, liquidity, secondsInitialized) = poolManager.getSlot0(poolKey.toId());
            console2.log("After initialization - tick:", currentTick);
            console2.log("After initialization - sqrtPriceX96:", uint256(sqrtPriceX96).toHexString());
        } else {
            console2.log("Pool already initialized, using existing state");
        }

        // Calculate tick range based on actual current tick - make it much tighter to ensure it's in range
        // Use a smaller range around the current tick to ensure the position is active
        tickLower = truncateTickSpacing((currentTick - 10 * tickSpacing), tickSpacing);
        tickUpper = truncateTickSpacing((currentTick + 10 * tickSpacing), tickSpacing);

        console2.log("Calculated tick lower:", tickLower);
        console2.log("Calculated tick upper:", tickUpper);
        console2.log("Token0 amount:", token0Amount);
        console2.log("Token1 amount:", token1Amount);

        // Approve tokens for PositionManager
        console2.log("Approving tokens for PositionManager...");
        token0.approve(address(positionManager), type(uint256).max);
        token1.approve(address(positionManager), type(uint256).max);
        console2.log("Token approvals completed!");
        
        // Set up Permit2 approvals for PositionManager
        console2.log("Setting up Permit2 approvals...");
        tokenApprovals();
        console2.log("Permit2 approvals completed!");
        
        // Calculate liquidity amount based on the token amounts and tick range
        uint128 liquidityAmount = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            token0Amount,
            token1Amount
        );
        
        console2.log("Calculated liquidity amount:", uint256(liquidityAmount));
        
        // Add liquidity to the pool using PositionManager.multicall
        console2.log("Adding liquidity to the pool...");
        
        // Slippage limits
        uint256 amount0Max = token0Amount + 1 wei;
        uint256 amount1Max = token1Amount + 1 wei;
        
        (bytes memory actions, bytes[] memory mintParams) = _mintLiquidityParams(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Max,
            amount1Max,
            deployerAddress,
            hookData
        );
        
        // Prepare multicall parameters
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encodeWithSelector(
            positionManager.modifyLiquidities.selector, 
            abi.encode(actions, mintParams), 
            block.timestamp + 60
        );
        
        // Handle ETH if needed
        uint256 valueToPass = currency0.isAddressZero() ? amount0Max : 0;
        
        // Call modifyLiquidities via multicall
        positionManager.multicall{value: valueToPass}(params);
        console2.log("Liquidity added successfully!");
        
        // Verify the liquidity was added
        (,, uint128 newLiquidity,) = poolManager.getSlot0(poolKey.toId());
        console2.log("New pool liquidity:", uint256(newLiquidity));
        
        vm.stopBroadcast();
    }
}
