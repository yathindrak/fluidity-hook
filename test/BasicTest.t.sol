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

contract BasicTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // Contracts
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

        // Initialize pool without hook
        (key, ) = initPool(currency0, currency1, IHooks(address(0)), 3000, SQRT_PRICE_1_1);
        poolKey = key;
    }

    function test_basicSetup() public {
        // Test that basic setup works
        assertTrue(address(token0) != address(0), "Token0 should be deployed");
        assertTrue(address(token1) != address(0), "Token1 should be deployed");
        assertTrue(address(Currency.unwrap(poolKey.currency0)) != address(0), "Currency0 should be set");
        assertTrue(address(Currency.unwrap(poolKey.currency1)) != address(0), "Currency1 should be set");
    }
}
