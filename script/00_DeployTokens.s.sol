pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {TestToken} from "./TestToken.sol";

/// @title DeployTokensScript
/// @notice Deploys test tokens for liquidity hook testing
contract DeployTokensScript is Script {
    // Token configurations
    struct TokenConfig {
        string name;
        string symbol;
        uint8 decimals;
        uint256 initialSupply;
    }

    // Deployed token instances
    TestToken public token0;
    TestToken public token1;

    // Default token configurations
    TokenConfig public token0Config = TokenConfig({
        name: "Mock TokenA",
        symbol: "mTokenA",
        decimals: 18,
        initialSupply: 1_000_000 * 10**18 // 1M tokens
    });

    TokenConfig public token1Config = TokenConfig({
        name: "Mock TokenB", 
        symbol: "mTokenB",
        decimals: 18,
        initialSupply: 1_000_000 * 10**18 // 1M tokens
    });

    function run() public {
        uint256 chainId = block.chainid;
        console2.log("=== Token Deployment Script ===");
        console2.log("Chain ID:", chainId);
        console2.log("Deployer:", msg.sender);
        console2.log("===============================");

        vm.startBroadcast();

        // Deploy Token0
        console2.log("\n--- Deploying Token0 ---");
        token0 = new TestToken(
            token0Config.name,
            token0Config.symbol,
            token0Config.decimals,
            token0Config.initialSupply
        );
        console2.log("Token0 deployed at:", address(token0));
        console2.log("Token0 name:", token0.name());
        console2.log("Token0 symbol:", token0.symbol());
        console2.log("Token0 decimals:", token0.decimals());
        console2.log("Token0 total supply:", token0.totalSupply() / (10 ** token0.decimals()));

        // Deploy Token1
        console2.log("\n--- Deploying Token1 ---");
        token1 = new TestToken(
            token1Config.name,
            token1Config.symbol,
            token1Config.decimals,
            token1Config.initialSupply
        );
        console2.log("Token1 deployed at:", address(token1));
        console2.log("Token1 name:", token1.name());
        console2.log("Token1 symbol:", token1.symbol());
        console2.log("Token1 decimals:", token1.decimals());
        console2.log("Token1 total supply:", token1.totalSupply() / (10 ** token1.decimals()));

        vm.stopBroadcast();

        // Display configuration for BaseScript
        console2.log("\n=== BaseScript Configuration ===");
        console2.log("Update your BaseScript.sol with these addresses:");
        console2.log("IERC20 internal constant token0 = IERC20(", address(token0), ");");
        console2.log("IERC20 internal constant token1 = IERC20(", address(token1), ");");
        console2.log("=================================");

        // Verify token balances
        console2.log("\n=== Token Balances ===");
        console2.log("Deployer Token0 balance:", token0.balanceOf(msg.sender) / (10 ** token0.decimals()));
        console2.log("Deployer Token1 balance:", token1.balanceOf(msg.sender) / (10 ** token1.decimals()));
        console2.log("======================");
    }
}
