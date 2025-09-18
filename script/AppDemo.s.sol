// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityRebalancer} from "../src/RebalanceHook.sol";
import {BaseScript} from "./base/BaseScript.sol";

contract AppDemo is BaseScript {
    function run() external {
        // Create pool key
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: hookContract
        });
        
        PoolId poolId = poolKey.toId();

        // Step 1: Show Current App State
        console.log("1. CURRENT APP STATE");
        console.log("===================");
        console.log("Hook Address:", address(hookContract));
        console.log("Pool ID:", uint256(PoolId.unwrap(poolId)));
        
        (uint160 sqrtPriceX96, int24 tick, , ) = 
            StateLibrary.getSlot0(poolManager, poolId);
        console.log("Current Price:", sqrtPriceX96);
        console.log("Current Tick:", tick);

        // Step 2: Show Hook Permissions (What the app can do)
        console.log("2. APP CAPABILITIES");
        console.log("===================");
        Hooks.Permissions memory permissions = LiquidityRebalancer(address(hookContract)).getHookPermissions();
        console.log("Can Initialize Pools:", permissions.beforeInitialize);
        console.log("Can Manage Liquidity:", permissions.beforeAddLiquidity);
        console.log("Can Intercept Swaps:", permissions.beforeSwap);

        // Step 3: Show Encrypted Strategy (What MEV bots can't see)
        console.log("3. ENCRYPTED STRATEGY (MEV BOTS CAN'T READ THIS)");
        console.log("================================================");
        (bytes memory encryptedThreshold, bytes memory encryptedCooldown, bytes memory encryptedRangeWidth, bytes memory encryptedAutoRebalance, bytes memory encryptedMaxSlippage) = 
            LiquidityRebalancer(address(hookContract)).getEncryptedStrategy(poolKey);
        
        console.log("Strategy Parameters (Encrypted):");
        console.log("- Threshold:", encryptedThreshold.length, "bytes (encrypted)");
        console.log("- Cooldown:", encryptedCooldown.length, "bytes (encrypted)");
        console.log("- Range Width:", encryptedRangeWidth.length, "bytes (encrypted)");
        console.log("- Auto Rebalance:", encryptedAutoRebalance.length, "bytes (encrypted)");
        console.log("- Max Slippage:", encryptedMaxSlippage.length, "bytes (encrypted)");

        // Step 4: Show Encrypted Liquidity Tracking
        console.log("4. ENCRYPTED LIQUIDITY TRACKING");
        console.log("===============================");
        (bytes memory encryptedUserLiquidity, bytes memory encryptedTotalLiquidity) = 
            LiquidityRebalancer(address(hookContract)).getEncryptedLiquidity(poolKey, deployerAddress);
        
        console.log("Liquidity Data (Encrypted):");
        console.log("- User Liquidity:", encryptedUserLiquidity.length, "bytes (encrypted)");
        console.log("- Total Liquidity:", encryptedTotalLiquidity.length, "bytes (encrypted)");
        console.log("Position sizes are private - MEV bots can't see them!");

        // Step 5: Show Pool Management Status
        console.log("5. POOL MANAGEMENT STATUS");
        console.log("=========================");
        (bool isActive,, , , ) = LiquidityRebalancer(address(hookContract)).poolConfigurations(poolId);
        console.log("Pool Active:", isActive);

        // Step 6: Demonstrate Actual Liquidity Operations
        console.log("6. DEMONSTRATING LIQUIDITY OPERATIONS");
        console.log("=====================================");
        
        // First, ensure we have tokens and approve them
        vm.startBroadcast();
        
        // Mint some tokens for the deployer if needed
        if (token0.balanceOf(deployerAddress) == 0) {
            // For demo purposes, we'll show the operation without actually executing
            console.log("Token0 balance:", token0.balanceOf(deployerAddress));
            console.log("Token1 balance:", token1.balanceOf(deployerAddress));
        }
        
        // Approve tokens for the hook
        token0.approve(address(hookContract), 1 ether);
        token1.approve(address(hookContract), 1 ether);
        
        vm.stopBroadcast();
        
        // Try to provision liquidity
        try LiquidityRebalancer(address(hookContract)).provisionLiquidity(poolKey, LiquidityRebalancer.LiquidityProvision({
            token0: currency0,
            token1: currency1,
            poolFee: 3000,
            amount: 0.01 ether, // Small amount for demo
            recipient: deployerAddress
        })) returns (uint128 liquidityAmount) {
            console.log("Liquidity provisioned:", liquidityAmount);
            
            // Check pool state after liquidity provision
            (bool isActiveAfter, uint128 totalLiquidityAfter, , , ) = LiquidityRebalancer(address(hookContract)).poolConfigurations(poolId);
            console.log("Pool active after provision:", isActiveAfter);
            console.log("Total liquidity after provision:", totalLiquidityAfter);
            
            // Now try rebalancing with actual liquidity
            try LiquidityRebalancer(address(hookContract)).executeRebalancing(poolKey) {
                console.log("Rebalancing executed successfully");
            } catch {
                console.log("Rebalancing skipped (no rebalancing needed)");
            }
            
        } catch Error(string memory reason) {
            console.log("Liquidity provision failed:", reason);
        } catch {
            console.log("Liquidity provision requires ownership or pool setup");
        }
        console.log("");

        // Step 7: Demonstrate Pool Management
        console.log("7. DEMONSTRATING POOL MANAGEMENT");
        console.log("================================");
        
        // Pause rebalancing
        try LiquidityRebalancer(address(hookContract)).pausePoolRebalancing(poolKey) {
            console.log("Pool rebalancing paused");
        } catch Error(string memory reason) {
            console.log("Pause failed:", reason);
        } catch {
            console.log("Pool management requires ownership");
        }
        
        // Resume rebalancing
        try LiquidityRebalancer(address(hookContract)).resumePoolRebalancing(poolKey) {
            console.log("Pool rebalancing resumed");
        } catch Error(string memory reason) {
            console.log("Resume failed:", reason);
        } catch {
            console.log("Pool management requires ownership");
        }
        console.log("");

        // Step 8: Demonstrate Rebalancing Functionality
        console.log("8. DEMONSTRATING REBALANCING FUNCTIONALITY");
        console.log("==========================================");
        
        // Try to execute rebalancing
        try LiquidityRebalancer(address(hookContract)).executeRebalancing(poolKey) {
            console.log("Rebalancing executed successfully");
            
            // Check if rebalancing was actually performed
            (bool isActiveAfterRebalance, uint128 totalLiquidityAfterRebalance, , , ) = 
                LiquidityRebalancer(address(hookContract)).poolConfigurations(poolId);
            console.log("Pool active after rebalance:", isActiveAfterRebalance);
            console.log("Total liquidity after rebalance:", totalLiquidityAfterRebalance);
            
        } catch Error(string memory reason) {
            console.log("Rebalancing failed:", reason);
        } catch {
            console.log("Rebalancing skipped (no liquidity to rebalance)");
        }
        console.log("");

        // Step 9: Show Actual Hook Permissions
        console.log("9. HOOK PERMISSIONS VERIFICATION");
        console.log("=================================");
        console.log("Hook can intercept:");
        console.log("- Pool initialization:", permissions.beforeInitialize);
        console.log("- Liquidity changes:", permissions.beforeAddLiquidity);
        console.log("- Swap transactions:", permissions.beforeSwap);
    }
}
