// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LiquidityRebalancer} from "../src/RebalanceHook.sol";
import {CoFheTest} from "@fhenixprotocol/cofhe-mock-contracts/CoFheTest.sol";

contract SimpleHookTest is Test, Deployers, CoFheTest {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // Contracts
    LiquidityRebalancer hook;
    MockERC20 token0;
    MockERC20 token1;

    // Pool data
    PoolKey poolKey;

    function setUp() public {
        // Deploy PoolManager and routers
        deployFreshManagerAndRouters();

        // Deploy tokens
        token0 = new MockERC20("Token0", "TKN0", 18);
        token1 = new MockERC20("Token1", "TKN1", 18);

        // Sort tokens to ensure correct currency0/currency1 assignment
        if (address(token0) < address(token1)) {
            currency0 = Currency.wrap(address(token0));
            currency1 = Currency.wrap(address(token1));
        } else {
            currency0 = Currency.wrap(address(token1));
            currency1 = Currency.wrap(address(token0));
        }

        // Mint tokens
        token0.mint(address(this), 1000 ether);
        token1.mint(address(this), 1000 ether);

        // Deploy hook with correct flags
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.AFTER_INITIALIZE_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.BEFORE_SWAP_FLAG
        );
        address hookAddress = address(flags);

        // Get hook deployment bytecode
        deployCodeTo(
            "RebalanceHook.sol:LiquidityRebalancer",
            abi.encode(manager, 60, address(this)),
            hookAddress
        );

        // Deploy the hook to a deterministic address with the hook flags
        hook = LiquidityRebalancer(hookAddress);

        // Initialize pool
        (key, ) = initPool(currency0, currency1, hook, 3000, SQRT_PRICE_1_1);
        poolKey = key;
    }

    function test_hookDeployment() public {
        // Test that hook was deployed correctly
        assertTrue(address(hook) != address(0), "Hook should be deployed");
        
        // Test hook permissions
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.beforeInitialize, "Should have beforeInitialize permission");
        assertTrue(permissions.afterInitialize, "Should have afterInitialize permission");
        assertTrue(permissions.beforeAddLiquidity, "Should have beforeAddLiquidity permission");
        assertTrue(permissions.beforeSwap, "Should have beforeSwap permission");
    }

    function test_poolConfiguration() public {
        // Test that pool configuration was set
        (bool isActive, uint128 totalLiquidity, , , ) = hook.poolConfigurations(poolKey.toId());
        assertTrue(isActive, "Pool should be active");
        assertEq(totalLiquidity, 0, "Initial liquidity should be 0");
    }
}
