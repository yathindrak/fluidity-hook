pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract CheckPositions is Script {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    function run() external {
        IPositionManager positionManager = IPositionManager(0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4);
        
        // Use the same pool key as our script
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(0x0E42Efc341d5ef175dB4CE9516d13eecC379e9Ec),
            currency1: Currency.wrap(0xf7eC23380BB7adEdaf4c69239B66e444B4aaffDb),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        
        console.log("Checking positions for pool ID:", uint256(PoolId.unwrap(poolKey.toId())));
        
        // Check next token ID (this tells us how many tokens have been minted)
        uint256 nextTokenId = positionManager.nextTokenId();
        console.log("Next token ID:", nextTokenId);
        console.log("Total positions minted:", nextTokenId - 1);
        
        // Check if we have any positions
        if (nextTokenId > 1) {
            console.log("Found", nextTokenId - 1, "position(s)");
            
            // Check the last few positions (most recent ones)
            uint256 startId = nextTokenId > 5 ? nextTokenId - 5 : 1;
            for (uint256 i = startId; i < nextTokenId; i++) {
                console.log("Checking Token ID:", i);
                
                // Get position liquidity
                uint128 liquidity = positionManager.getPositionLiquidity(i);
                console.log("  Liquidity:", uint256(liquidity));
                
                // Get position info
                (PoolKey memory posPoolKey, ) = positionManager.getPoolAndPositionInfo(i);
                console.log("  Pool ID:", uint256(PoolId.unwrap(posPoolKey.toId())));
            }
        } else {
            console.log("No positions found");
        }
    }
}
