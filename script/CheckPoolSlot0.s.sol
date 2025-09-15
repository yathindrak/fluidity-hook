pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract CheckPoolSlot0 is Script {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolId;
    using Strings for uint256;
    using Strings for int256;

    function run() external {
        IPoolManager poolManager = IPoolManager(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543);
        PoolId poolId = PoolId.wrap(0x5dc638b2d38ca34ca2fbe00f2b975e38acaa7ed5b40f63ca657b1fa47e6fae5e);
        
        (uint160 sqrtPriceX96, int24 tick, uint128 liquidity, uint32 secondsInitialized) = poolManager.getSlot0(poolId);

        console.log("Pool Slot0 Data:");
        console.log(string.concat("  sqrtPriceX96:", uint256(sqrtPriceX96).toHexString()));
        console.log(string.concat("  tick:", Strings.toStringSigned(int256(tick))));
        console.log(string.concat("  liquidity:", uint256(liquidity).toString()));
        console.log(string.concat("  secondsInitialized:", uint256(secondsInitialized).toString()));
    }
}
