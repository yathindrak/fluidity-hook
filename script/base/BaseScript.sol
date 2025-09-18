pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {console} from "forge-std/console.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";
import {AddressConstants} from "hookmate/constants/AddressConstants.sol";

import {Permit2Deployer} from "hookmate/artifacts/Permit2.sol";
import {V4PoolManagerDeployer} from "hookmate/artifacts/V4PoolManager.sol";
import {V4PositionManagerDeployer} from "hookmate/artifacts/V4PositionManager.sol";
import {V4RouterDeployer} from "hookmate/artifacts/V4Router.sol";

/// @notice Shared configuration between scripts
contract BaseScript is Script {
    IPermit2 immutable permit2 = IPermit2(AddressConstants.getPermit2Address());
    IPoolManager immutable poolManager;
    IPositionManager immutable positionManager;
    IUniswapV4Router04 immutable swapRouter;
    address immutable deployerAddress;

    /////////////////////////////////////
    // --- Configure These ---
    /////////////////////////////////////
    IERC20 internal constant token0 = IERC20(0xabc0Afb70F325F4119cFCA4083EA2A580Ec40D3F); // mTokenA
    IERC20 internal constant token1 = IERC20(0x3e68f0F304314495fa45907170a59D0BA5218bCc); // mTokenB
    IHooks constant hookContract = IHooks(address(0x54Ce5e7351BF259604F3DB6D79fC3653A15EF880));
    /////////////////////////////////////

    Currency immutable currency0;
    Currency immutable currency1;

    constructor() {
        uint256 chainId = block.chainid;
        console.log("=== BaseScript Configuration ===");
        console.log("Chain ID:", chainId);
        
        address poolManagerAddr;
        address positionManagerAddr;
        address swapRouterAddr;
        
        // I partially look into anvil config bt couldnt fully test due to slowness running some scripts.
        if (chainId == 31337) {
            // Deploy contracts locally for testing
            console.log("Deploying contracts locally for chainId 31337...");
            
            // Deploy Permit2
            address permit2Addr = AddressConstants.getPermit2Address();
            if (permit2Addr.code.length == 0) {
                address tempPermit2 = address(Permit2Deployer.deploy());
                vm.etch(permit2Addr, tempPermit2.code);
            }
            
            // Deploy PoolManager
            poolManagerAddr = address(V4PoolManagerDeployer.deploy(address(0x4444)));
            
            // Deploy PositionManager
            positionManagerAddr = address(V4PositionManagerDeployer.deploy(
                poolManagerAddr, 
                permit2Addr, 
                300_000, 
                address(0), 
                address(0)
            ));
            
            // Deploy Router
            swapRouterAddr = address(V4RouterDeployer.deploy(poolManagerAddr, permit2Addr));
            
            console.log("Local deployments completed");
        } else {
            // Use production addresses
            poolManagerAddr = AddressConstants.getPoolManagerAddress(chainId);
            positionManagerAddr = AddressConstants.getPositionManagerAddress(chainId);
            swapRouterAddr = AddressConstants.getV4SwapRouterAddress(chainId);
        }
        
        console.log("PoolManager Address:", poolManagerAddr);
        console.log("PositionManager Address:", positionManagerAddr);
        console.log("SwapRouter Address:", swapRouterAddr);
        console.log("Permit2 Address:", AddressConstants.getPermit2Address());
        
        poolManager = IPoolManager(poolManagerAddr);
        positionManager = IPositionManager(payable(positionManagerAddr));
        swapRouter = IUniswapV4Router04(payable(swapRouterAddr));

        deployerAddress = getDeployer();
        console.log("Deployer Address:", deployerAddress);

        (currency0, currency1) = getCurrencies();
        console.log("Currency0 (Token0):", Currency.unwrap(currency0));
        console.log("Currency1 (Token1):", Currency.unwrap(currency1));
        console.log("Token0 Address:", address(token0));
        console.log("Token1 Address:", address(token1));
        console.log("Hook Contract Address:", address(hookContract));
        console.log("================================");

        vm.label(address(token0), "Token0");
        vm.label(address(token1), "Token1");

        vm.label(address(deployerAddress), "Deployer");
        vm.label(address(poolManager), "PoolManager");
        vm.label(address(positionManager), "PositionManager");
        vm.label(address(swapRouter), "SwapRouter");
        vm.label(address(hookContract), "HookContract");
    }

    function getCurrencies() public pure returns (Currency, Currency) {
        require(address(token0) != address(token1));

        if (token0 < token1) {
            return (Currency.wrap(address(token0)), Currency.wrap(address(token1)));
        } else {
            return (Currency.wrap(address(token1)), Currency.wrap(address(token0)));
        }
    }

    function getDeployer() public returns (address) {
        return address(0x3e723f6B81431f325E3F08e75544F254C182AFE2);
        // address[] memory wallets = vm.getWallets();

        // require(wallets.length > 0, "No wallets found");

        // return wallets[0];
    }
}
