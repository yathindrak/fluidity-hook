pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract CheckPoolSlot0 is Script {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using Strings for uint256;
    using Strings for int256;

    function run() external {
        IPoolManager poolManager = IPoolManager(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543);
        
        // Use the same pool key as our script (with empty hooks)
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(0x0E42Efc341d5ef175dB4CE9516d13eecC379e9Ec),
            currency1: Currency.wrap(0xf7eC23380BB7adEdaf4c69239B66e444B4aaffDb),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0)) // Empty hooks to match our script
        });
        
        PoolId poolId = poolKey.toId();
        console.log("Pool ID:", uint256(PoolId.unwrap(poolId)));
        console.log("Pool ID Hex:", uint256(PoolId.unwrap(poolId)).toHexString());
        
        (uint160 sqrtPriceX96, int24 tick, uint128 liquidity, uint32 secondsInitialized) = poolManager.getSlot0(poolId);

        console.log("Pool Slot0 Data:");
        console.log(string.concat("  sqrtPriceX96:", uint256(sqrtPriceX96).toHexString()));
        console.log(string.concat("  tick:", Strings.toStringSigned(int256(tick))));
        console.log(string.concat("  liquidity:", uint256(liquidity).toString()));
        console.log(string.concat("  secondsInitialized:", uint256(secondsInitialized).toString()));
    }
}
