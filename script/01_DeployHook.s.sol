pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {console2} from "forge-std/console2.sol";

import {BaseScript} from "./base/BaseScript.sol";

import {LiquidityRebalancer} from "../src/RebalanceHook.sol";

/// @notice Mines the address and deploys the RebalanceHook.sol Hook contract
contract DeployHookScript is BaseScript {
    function run() public {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        int24 tickOffset = 60;
        bytes memory constructorArgs = abi.encode(poolManager, tickOffset);
            (address hookAddress, bytes32 salt) =
                HookMiner.find(CREATE2_FACTORY, flags, type(LiquidityRebalancer).creationCode, constructorArgs);

            // Deploy the hook using CREATE2
            vm.startBroadcast();
            LiquidityRebalancer liquidityRebalancer = new LiquidityRebalancer{salt: salt}(poolManager, tickOffset);
            vm.stopBroadcast();

            require(address(liquidityRebalancer) == hookAddress, "DeployHookScript: Hook Address Mismatch");
            
            console2.log("LiquidityRebalancer deployed at:", address(liquidityRebalancer));
        console2.log("Tick offset:", tickOffset);
    }
}
