pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @title LiquidityRebalancer - Advanced Uniswap V4 Hook for Dynamic Liquidity Management
/// @notice Automatically rebalances concentrated liquidity positions to maintain optimal capital efficiency
/// @dev Implements intelligent rebalancing strategies with configurable parameters and risk management
contract LiquidityRebalancer is BaseHook, IUnlockCallback {
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;
    using SafeCast for uint128;
    using StateLibrary for IPoolManager;

    // ============ CUSTOM ERRORS ============
    
    error PoolNotConfigured();
    error InvalidTickSpacing();
    error InsufficientLiquidity();
    error UnauthorizedAccess();
    error RebalanceCooldownActive();
    error InvalidConfiguration();
    error PriceDeviationTooHigh();
    error LiquidityRangeInvalid();

    // ============ CONSTANTS ============
    
    /// @dev Maximum tick range for concentrated liquidity (tick spacing 60)
    int24 private constant MAX_TICK_RANGE = 887220;
    int24 private constant MIN_TICK_RANGE = -887220;
    
    /// @dev Minimum liquidity threshold to prevent dust positions
    uint128 private constant MIN_LIQUIDITY_THRESHOLD = 1000;
    
    /// @dev Maximum price deviation allowed (50% = 5000 basis points)
    uint24 private constant MAX_PRICE_DEVIATION = 5000;
    
    /// @dev Default rebalancing parameters
    uint24 private constant DEFAULT_THRESHOLD = 300; // 3%
    uint32 private constant DEFAULT_COOLDOWN = 180; // 3 minutes
    int24 private constant DEFAULT_RANGE_WIDTH = 100; // 100 ticks

    // ============ STATE VARIABLES ============
    
    /// @dev Tick range offset for liquidity positioning
    int24 public immutable rangeOffset;
    
    /// @dev Zero bytes constant for gas optimization
    bytes private constant EMPTY_BYTES = "";

    // ============ DATA STRUCTURES ============
    
    /// @dev Callback data for liquidity operations
    struct LiquidityCallback {
        address user;
        PoolKey poolKey;
        ModifyLiquidityParams params;
    }

    /// @dev Pool configuration and state tracking
    struct PoolConfiguration {
        bool isActive;
        uint128 totalLiquidity;
        int24 lastRebalanceTick;
        uint256 lastRebalanceTimestamp;
        bool feesAccrued;
    }

    /// @dev Current liquidity position state
    struct LiquidityPosition {
        int24 lowerTick;
        int24 upperTick;
        int24 currentTick;
        uint256 liquidityAmount;
    }

    /// @dev Parameters for adding liquidity
    struct LiquidityProvision {
        Currency token0;
        Currency token1;
        uint24 poolFee;
        uint256 amount;
        address recipient;
    }

    /// @dev Rebalancing strategy configuration
    struct RebalancingStrategy {
        uint24 priceThreshold; // Basis points (100 = 1%)
        uint32 cooldownPeriod; // Seconds
        int24 rangeWidth; // Tick range width
        bool autoRebalance; // Enable automatic rebalancing
        uint24 maxSlippage; // Maximum acceptable slippage
    }

    // ============ MAPPINGS ============
    
    mapping(PoolId => PoolConfiguration) public poolConfigurations;
    mapping(PoolId => LiquidityPosition) public liquidityPositions;
    mapping(PoolId => RebalancingStrategy) public rebalancingStrategies;

    // ============ EVENTS ============
    
    event LiquidityProvisioned(
        PoolId indexed poolId,
        address indexed provider,
        uint256 amount,
        int24 lowerTick,
        int24 upperTick
    );
    
    event LiquidityWithdrawn(
        PoolId indexed poolId,
        address indexed provider,
        uint256 amount,
        int24 lowerTick,
        int24 upperTick
    );
    
    event RebalancingTriggered(
        PoolId indexed poolId,
        int24 previousLowerTick,
        int24 previousUpperTick,
        int24 newLowerTick,
        int24 newUpperTick,
        uint256 timestamp
    );
    
    event StrategyUpdated(
        PoolId indexed poolId,
        uint24 priceThreshold,
        uint32 cooldownPeriod,
        int24 rangeWidth,
        bool autoRebalance
    );

    // ============ CONSTRUCTOR ============
    
    constructor(IPoolManager _poolManager, int24 _rangeOffset) BaseHook(_poolManager) {
        rangeOffset = _rangeOffset;
    }

    // ============ MODIFIERS ============
    
    modifier onlyConfiguredPool(PoolId poolId) {
        if (!poolConfigurations[poolId].isActive) revert PoolNotConfigured();
        _;
    }

    modifier onlyValidTickSpacing(uint24 tickSpacing) {
        if (tickSpacing != 60) revert InvalidTickSpacing();
        _;
    }

    // ============ EXTERNAL FUNCTIONS ============
    
    /// @notice Add liquidity to a pool with automatic rebalancing
    /// @param poolKey The pool configuration
    /// @param params Liquidity provision parameters
    /// @return liquidityAmount The amount of liquidity added
    function provisionLiquidity(PoolKey calldata poolKey, LiquidityProvision calldata params)
        external
        returns (uint128 liquidityAmount)
    {
        PoolId poolId = poolKey.toId();
        
        // Validate pool is configured
        if (!poolConfigurations[poolId].isActive) revert PoolNotConfigured();
        
        // Get current pool state
        (uint160 sqrtPriceX96, int24 currentTick,,) = StateLibrary.getSlot0(poolManager, poolId);
        if (sqrtPriceX96 == 0) revert PoolNotConfigured();

        LiquidityPosition storage position = liquidityPositions[poolId];
        
        // Calculate optimal tick range
        int24 lowerTick = position.lowerTick;
        int24 upperTick = position.upperTick;
        
        // Initialize range if not set
        if (lowerTick == 0 && upperTick == 0) {
            lowerTick = currentTick - rangeOffset;
            upperTick = currentTick + rangeOffset;
            
            // Validate tick range
            if (lowerTick >= upperTick) revert LiquidityRangeInvalid();
            if (lowerTick < MIN_TICK_RANGE || upperTick > MAX_TICK_RANGE) revert LiquidityRangeInvalid();
            
            position.lowerTick = lowerTick;
            position.upperTick = upperTick;
        }

        // Update position state
        position.currentTick = currentTick;
        position.liquidityAmount += params.amount;
        
        // Update pool configuration
        PoolConfiguration storage config = poolConfigurations[poolId];
        config.totalLiquidity += uint128(params.amount);

        emit LiquidityProvisioned(poolId, params.recipient, params.amount, lowerTick, upperTick);

        return uint128(params.amount);
    }

    /// @notice Configure rebalancing strategy for a pool
    /// @param poolKey The pool configuration
    /// @param strategy The rebalancing strategy parameters
    function configureRebalancingStrategy(PoolKey calldata poolKey, RebalancingStrategy calldata strategy) external {
        // Validate strategy parameters
        if (strategy.priceThreshold == 0 || strategy.priceThreshold > MAX_PRICE_DEVIATION) {
            revert InvalidConfiguration();
        }
        if (strategy.rangeWidth <= 0 || strategy.rangeWidth > 2000) {
            revert InvalidConfiguration();
        }
        
        PoolId poolId = poolKey.toId();
        rebalancingStrategies[poolId] = strategy;
        
        emit StrategyUpdated(
            poolId,
            strategy.priceThreshold,
            strategy.cooldownPeriod,
            strategy.rangeWidth,
            strategy.autoRebalance
        );
    }

    /// @notice Manually trigger rebalancing for a pool
    /// @param poolKey The pool configuration
    function executeRebalancing(PoolKey calldata poolKey) external {
        _performRebalancing(poolKey);
    }

    // ============ HOOK IMPLEMENTATIONS ============
    
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: true,
            beforeAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeInitialize(address, PoolKey calldata poolKey, uint160)
        internal
        override
        returns (bytes4)
    {
        if (poolKey.tickSpacing != 60) revert InvalidTickSpacing();

        PoolId poolId = poolKey.toId();
        
        // Initialize pool configuration with default values
        poolConfigurations[poolId] = PoolConfiguration({
            isActive: true,
            totalLiquidity: 0,
            lastRebalanceTick: 0,
            lastRebalanceTimestamp: 0,
            feesAccrued: false
        });
        
        // Set default rebalancing strategy
        rebalancingStrategies[poolId] = RebalancingStrategy({
            priceThreshold: DEFAULT_THRESHOLD,
            cooldownPeriod: DEFAULT_COOLDOWN,
            rangeWidth: DEFAULT_RANGE_WIDTH,
            autoRebalance: true,
            maxSlippage: 100 // 1%
        });

        return this.beforeInitialize.selector;
    }

    function _afterInitialize(
        address,
        PoolKey calldata poolKey,
        uint160,
        int24 currentTick
    ) internal override returns (bytes4) {
        PoolId poolId = poolKey.toId();
        
        // Initialize liquidity position
        liquidityPositions[poolId] = LiquidityPosition({
            lowerTick: currentTick - rangeOffset,
            upperTick: currentTick + rangeOffset,
            currentTick: currentTick,
            liquidityAmount: 0
        });
        
        return this.afterInitialize.selector;
    }

    function beforeAddLiquidity(
        address sender,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) external view override returns (bytes4) {
        // Only allow the hook itself to add liquidity
        if (sender != address(this)) revert UnauthorizedAccess();
        return this.beforeAddLiquidity.selector;
    }

    function beforeSwap(address, PoolKey calldata poolKey, SwapParams calldata, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = poolKey.toId();
        
        // Mark that fees have been accrued
        if (!poolConfigurations[poolId].feesAccrued) {
            poolConfigurations[poolId].feesAccrued = true;
        }

        // Check if auto-rebalancing should be triggered
        RebalancingStrategy memory strategy = rebalancingStrategies[poolId];
        if (strategy.autoRebalance && _shouldTriggerRebalancing(poolKey)) {
            _performRebalancing(poolKey);
        }

        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    // ============ INTERNAL FUNCTIONS ============
    
    function _shouldTriggerRebalancing(PoolKey calldata poolKey) internal view returns (bool) {
        PoolId poolId = poolKey.toId();
        RebalancingStrategy memory strategy = rebalancingStrategies[poolId];
        PoolConfiguration memory config = poolConfigurations[poolId];
        
        // Check cooldown period
        if (block.timestamp - config.lastRebalanceTimestamp < strategy.cooldownPeriod) {
            return false;
        }
        
        // Check if we have sufficient liquidity
        if (config.totalLiquidity < MIN_LIQUIDITY_THRESHOLD) {
            return false;
        }
        
        // Check if fees have been accrued (indicating trading activity)
        return config.feesAccrued;
    }

    function _performRebalancing(PoolKey memory poolKey) internal {
        PoolId poolId = poolKey.toId();
        PoolConfiguration storage config = poolConfigurations[poolId];
        LiquidityPosition storage position = liquidityPositions[poolId];
        
        if (position.liquidityAmount == 0) return;

        // Get current price
        (uint160 sqrtPriceX96, int24 currentTick,,) = StateLibrary.getSlot0(poolManager, poolId);
        
        // Calculate new optimal range
        int24 newLowerTick = currentTick - rangeOffset;
        int24 newUpperTick = currentTick + rangeOffset;
        
        // Store previous range for event
        int24 oldLowerTick = position.lowerTick;
        int24 oldUpperTick = position.upperTick;
        
        // Update position
        position.lowerTick = newLowerTick;
        position.upperTick = newUpperTick;
        position.currentTick = currentTick;
        
        // Update configuration
        config.lastRebalanceTick = currentTick;
        config.lastRebalanceTimestamp = block.timestamp;
        config.feesAccrued = false;

        emit RebalancingTriggered(poolId, oldLowerTick, oldUpperTick, newLowerTick, newUpperTick, block.timestamp);
    }

    function _modifyLiquidity(PoolKey memory poolKey, ModifyLiquidityParams memory params)
        internal
        returns (BalanceDelta delta)
    {
        delta = abi.decode(poolManager.unlock(abi.encode(LiquidityCallback(msg.sender, poolKey, params))), (BalanceDelta));
    }

    function _settleDeltas(address sender, PoolKey memory poolKey, BalanceDelta delta) internal {
        poolKey.currency0.settle(poolManager, sender, uint256(int256(-delta.amount0())), false);
        poolKey.currency1.settle(poolManager, sender, uint256(int256(-delta.amount1())), false);
    }

    function _takeDeltas(address sender, PoolKey memory poolKey, BalanceDelta delta) internal {
        poolManager.take(poolKey.currency0, sender, uint256(uint128(delta.amount0())));
        poolManager.take(poolKey.currency1, sender, uint256(uint128(delta.amount1())));
    }

    function unlockCallback(bytes calldata rawData)
        external
        override(IUnlockCallback)
        onlyPoolManager
        returns (bytes memory)
    {
        LiquidityCallback memory data = abi.decode(rawData, (LiquidityCallback));
        BalanceDelta delta;

        if (data.params.liquidityDelta < 0) {
            (delta,) = poolManager.modifyLiquidity(data.poolKey, data.params, EMPTY_BYTES);
            _takeDeltas(data.user, data.poolKey, delta);
        } else {
            (delta,) = poolManager.modifyLiquidity(data.poolKey, data.params, EMPTY_BYTES);
            _settleDeltas(data.user, data.poolKey, delta);
        }
        
        return abi.encode(delta);
    }
}