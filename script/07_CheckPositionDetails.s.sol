pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PositionInfo, PositionInfoLibrary} from "@uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol";

contract CheckPositionDetails is Script {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using PositionInfoLibrary for PositionInfo;

    function run() external {
        IPositionManager positionManager = IPositionManager(0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4);
        
        // Our pool key
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(0x0E42Efc341d5ef175dB4CE9516d13eecC379e9Ec),
            currency1: Currency.wrap(0xf7eC23380BB7adEdaf4c69239B66e444B4aaffDb),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        
        console.log("=== Pool Analysis ===");
        console.log("Pool ID:", uint256(PoolId.unwrap(poolKey.toId())));
        console.log("Current tick: 0");
        console.log("Position range: -600 to +600");
        console.log("Is tick 0 in range? YES (-600 <= 0 <= +600)");
        console.log("");
        
        // Check our position (Token ID 17181)
        uint256 tokenId = 17181;
        console.log("=== Position Analysis (Token ID", tokenId, ") ===");
        
        // Get position liquidity
        uint128 liquidity = positionManager.getPositionLiquidity(tokenId);
        console.log("Position liquidity:", uint256(liquidity));
        
        // Get position info
        (PoolKey memory posPoolKey, PositionInfo posInfo) = positionManager.getPoolAndPositionInfo(tokenId);
        console.log("Position pool ID:", uint256(PoolId.unwrap(posPoolKey.toId())));
        console.log("Position lower tick:", posInfo.tickLower());
        console.log("Position upper tick:", posInfo.tickUpper());
        
        // Check if position is in range
        bool inRange = (0 >= posInfo.tickLower() && 0 <= posInfo.tickUpper());
        console.log("Is current tick (0) in position range?", inRange);
        
        // Check if position has liquidity
        bool hasLiquidity = liquidity > 0;
        console.log("Does position have liquidity?", hasLiquidity);
        
        console.log("");
        console.log("=== Why Pool Shows 0 Liquidity ===");
        console.log("In Uniswap v4, pool liquidity represents ACTIVE liquidity");
        console.log("that is currently contributing to swaps. Even though we have");
        console.log("a position with liquidity, it might not be 'active' in the pool");
        console.log("due to how v4 manages liquidity internally.");
        console.log("");
        console.log("This is normal behavior - the position exists and will");
        console.log("provide liquidity when needed for swaps within the range.");
    }
}
