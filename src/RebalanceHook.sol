// SPDX-License-Identifier: MIT
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
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {euint256, FHE, ebool, euint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {InEuint32} from "@fhenixprotocol/cofhe-contracts/ICofhe.sol";

// Uniswap V4 hook contract to automatically rebalance concentrated liquidity positions for optimal capital efficiency
contract LiquidityRebalancer is BaseHook, Ownable, IUnlockCallback {
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;
    using SafeCast for uint128;
    using StateLibrary for IPoolManager;

    error PoolNotConfigured(); // Pool is not initialized or active
    error InvalidTickSpacing(); // Pool tick spacing is not 60
    error InsufficientLiquidity(); // Not enough liquidity to perform operation
    error UnauthorizedAccess(); // Caller is not authorized
    error UnauthorizedLiquidityRemoval(); // Caller does not own the liquidity being removed
    error RebalanceCooldownActive(); // Rebalancing attempted before cooldown ends
    error InvalidConfiguration(); // Invalid strategy parameters
    error PriceDeviationTooHigh(); // Price movement exceeds allowed threshold
    error LiquidityRangeInvalid(); // Invalid tick range for liquidity

    // Constants for liquidity management and rebalancing
    int24 private constant MAX_TICK_RANGE = 887220; // Maximum tick for concentrated liquidity (tick spacing 60)
    int24 private constant MIN_TICK_RANGE = -887220; // Minimum tick for concentrated liquidity
    uint128 private constant MIN_LIQUIDITY_THRESHOLD = 1000; // Minimum liquidity to prevent negligible positions
    uint24 private constant MAX_PRICE_DEVIATION = 5000; // Maximum price deviation (50% = 5000 basis points)
    uint24 private constant DEFAULT_THRESHOLD = 300; // Default price threshold for rebalancing (3%)
    uint32 private constant DEFAULT_COOLDOWN = 180; // Default rebalancing cooldown (3 minutes)
    int24 private constant DEFAULT_RANGE_WIDTH = 100; // Default tick range width (100 ticks)
    
    // Immutable tick offset for positioning liquidity ranges
    int24 public immutable rangeOffset;
    
    // Empty bytes array for gas-optimized Uniswap V4 calls
    bytes private constant EMPTY_BYTES = "";

    // Data for Uniswap V4 callback during liquidity operations
    struct LiquidityCallback {
        address user; // Caller of the operation
        PoolKey poolKey; // Pool configuration
        ModifyLiquidityParams params; // Liquidity modification parameters
    }

    // Tracks pool configuration and state
    struct PoolConfiguration {
        bool isActive; // Whether the pool is initialized
        uint128 totalLiquidity; // Total liquidity in the pool
        int24 lastRebalanceTick; // Tick at last rebalance
        uint256 lastRebalanceTimestamp; // Timestamp of last rebalance
        bool feesAccrued; // Whether trading fees have been accrued
    }

    // Tracks current aggregated liquidity position for a pool
    struct LiquidityPosition {
        int24 lowerTick; // Lower tick of the position's range
        int24 upperTick; // Upper tick of the position's range
        int24 currentTick; // Pool's current tick (price)
        uint256 liquidityAmount; // Total liquidity in the position (aggregated from all positions)
    }

    // Parameters for adding liquidity
    struct LiquidityProvision {
        Currency token0; // token0 in the pool
        Currency token1; // token1 in the pool
        uint24 poolFee; // Pool fee tier
        uint256 amount; // Token amount
        address recipient; // Address receiving position credit
    }

    // Configures rebalancing strategy for a pool
    struct RebalancingStrategy {
        uint24 priceThreshold; // Price movement threshold (basis points, 100 = 1%)
        uint32 cooldownPeriod; // Minimum time between rebalancings (seconds)
        int24 rangeWidth; // Width of liquidity range (ticks)
        bool autoRebalance; // Whether automatic rebalancing is enabled
        uint24 maxSlippage; // Maximum acceptable slippage (basis points)
    }

    // Mappings to store pool-specific data
    mapping(PoolId => PoolConfiguration) public poolConfigurations; // Pool configuration data
    mapping(PoolId => LiquidityPosition) private liquidityPositions; // Liquidity position data (aggregated from all positions) - private for MEV protection

    // Encrypted rebalancing strategy settings to prevent MEV extraction
    mapping(PoolId => euint256) private encryptedPriceThresholds;
    mapping(PoolId => euint32) private encryptedCooldownPeriods;
    mapping(PoolId => euint32) private encryptedRangeWidths;
    mapping(PoolId => ebool) private encryptedAutoRebalancing;
    mapping(PoolId => euint32) private encryptedMaxSlippage;
    
    // Encrypted liquidity ownership to prevent position size analysis
    mapping(PoolId => mapping(address => euint256)) private encryptedLiquidityOwnership;
    mapping(PoolId => euint256) private encryptedTotalLiquidity;

    event LiquidityProvisioned(
        PoolId indexed poolId, // Pool identifier
        address indexed provider, // Liquidity provider
        uint256 amount, // Liquidity amount added
        int24 lowerTick, // Lower tick of the range
        int24 upperTick // Upper tick of the range
    );
    
    event LiquidityWithdrawn(
        PoolId indexed poolId, // Pool identifier
        address indexed provider, // Liquidity provider
        uint256 amount, // Liquidity amount withdrawn
        int24 lowerTick, // Lower tick of the range
        int24 upperTick // Upper tick of the range
    );
    
    event EncryptedLiquidityWithdrawn(
        PoolId indexed poolId, // Pool identifier
        address indexed provider, // Liquidity provider
        bytes encryptedAmount, // Encrypted liquidity amount withdrawn
        bytes encryptedLowerTick, // Encrypted lower tick of the range
        bytes encryptedUpperTick // Encrypted upper tick of the range
    );
    
    event RebalancingTriggered(
        PoolId indexed poolId, // Pool identifier
        int24 previousLowerTick, // Old range lower tick
        int24 previousUpperTick, // Old range upper tick
        int24 newLowerTick, // New range lower tick
        int24 newUpperTick, // New range upper tick
        uint256 timestamp // Rebalancing timestamp
    );
    
    event EncryptedRebalancingTriggered(
        PoolId indexed poolId, // Pool identifier
        bytes encryptedPreviousLowerTick, // Encrypted old range lower tick
        bytes encryptedPreviousUpperTick, // Encrypted old range upper tick
        bytes encryptedNewLowerTick, // Encrypted new range lower tick
        bytes encryptedNewUpperTick, // Encrypted new range upper tick
        bytes encryptedTimestamp // Encrypted rebalancing timestamp
    );

    event PoolDeactivated(
        PoolId indexed poolId // Pool identifier
    );
    
    event PoolReactivated(
        PoolId indexed poolId // Pool identifier
    );
    
    // Fhenix-specific events for encrypted operations
    event EncryptedStrategyUpdated(
        PoolId indexed poolId, // Pool identifier
        bytes encryptedThreshold, // Encrypted price threshold
        bytes encryptedCooldown, // Encrypted cooldown period
        bytes encryptedRangeWidth, // Encrypted range width
        bytes encryptedAutoRebalance // Encrypted auto-rebalancing flag
    );
    
    event EncryptedLiquidityProvisioned(
        PoolId indexed poolId, // Pool identifier
        address indexed provider, // Liquidity provider
        bytes encryptedAmount, // Encrypted liquidity amount
        bytes encryptedLowerTick, // Encrypted lower tick of the range
        bytes encryptedUpperTick // Encrypted upper tick of the range
    );
    
    event EncryptedRebalancingDecision(
        PoolId indexed poolId, // Pool identifier
        bytes encryptedDecision, // Encrypted rebalancing decision
        bytes encryptedCurrentTick, // Encrypted current tick
        bytes encryptedThreshold // Encrypted threshold comparison
    );

    // Initializes the contract with pool manager, tick offset, and initial owner
    constructor(IPoolManager _poolManager, int24 _rangeOffset, address initialOwner) 
        BaseHook(_poolManager) 
        Ownable(initialOwner) 
    {
        rangeOffset = _rangeOffset;
    }

    // Adds liquidity to a pool and returns the amount added
    function provisionLiquidity(PoolKey calldata poolKey, LiquidityProvision calldata params)
        external
        returns (uint128 liquidityAmount)
    {
        PoolId poolId = poolKey.toId();
        if (!poolConfigurations[poolId].isActive) revert PoolNotConfigured();
        
        // Fetch current pool state (price and tick)
        // TODO: use multiple similarish pools prices consensus (personally prefer due to gas savings) 
        // or use an oracle to get the price
        (uint160 sqrtPriceX96, int24 currentTick,,) = StateLibrary.getSlot0(poolManager, poolId);
        if (sqrtPriceX96 == 0) revert PoolNotConfigured();

        LiquidityPosition storage position = liquidityPositions[poolId];
        int24 lowerTick = position.lowerTick;
        int24 upperTick = position.upperTick;
        
        // Set initial range if not already defined
        if (lowerTick == 0 && upperTick == 0) {
            lowerTick = currentTick - rangeOffset;
            upperTick = currentTick + rangeOffset;
            if (lowerTick >= upperTick) revert LiquidityRangeInvalid();
            if (lowerTick < MIN_TICK_RANGE || upperTick > MAX_TICK_RANGE) revert LiquidityRangeInvalid();
            position.lowerTick = lowerTick;
            position.upperTick = upperTick;
        }

        // Calculate liquidity amount from token input
        uint128 liquidityToAdd = _calculateLiquidityAmount(
            sqrtPriceX96,
            lowerTick,
            upperTick,
            params.amount
        );

        // Prepare parameters for liquidity addition
        ModifyLiquidityParams memory modifyParams = ModifyLiquidityParams({
            tickLower: lowerTick,
            tickUpper: upperTick,
            liquidityDelta: int256(uint256(liquidityToAdd)),
            salt: bytes32(0)
        });

        // Execute liquidity addition via Uniswap V4 callback
        poolManager.unlock(abi.encode(LiquidityCallback(msg.sender, poolKey, modifyParams)));
        
        // Update position state after callback
        // aderyn-ignore-next-line(reentrancy-state-change)
        // This is safe because unlockCallback handles all external interactions
        // and we're only updating our internal state after the callback completes
        position.currentTick = currentTick;
        position.liquidityAmount += liquidityToAdd;
        
        // Track liquidity ownership with encryption
        euint256 currentUserLiquidity = encryptedLiquidityOwnership[poolId][params.recipient];
        euint256 newUserLiquidity = FHE.add(currentUserLiquidity, FHE.asEuint256(liquidityToAdd));
        encryptedLiquidityOwnership[poolId][params.recipient] = newUserLiquidity;
        
        // Update encrypted total liquidity
        euint256 currentTotalLiquidity = encryptedTotalLiquidity[poolId];
        euint256 newTotalLiquidity = FHE.add(currentTotalLiquidity, FHE.asEuint256(liquidityToAdd));
        encryptedTotalLiquidity[poolId] = newTotalLiquidity;
        
        // Update total liquidity in pool configuration (public for compatibility)
        PoolConfiguration storage config = poolConfigurations[poolId];
        config.totalLiquidity += liquidityToAdd;

        // Emit encrypted liquidity provision for MEV protection
        emit EncryptedLiquidityProvisioned(
            poolId, 
            params.recipient, 
            abi.encode(newUserLiquidity), // Encrypted amount
            abi.encode(FHE.asEuint32(uint32(int32(lowerTick)))),
            abi.encode(FHE.asEuint32(uint32(int32(upperTick))))
        );

        return liquidityToAdd;
    }

    // Removes liquidity from a pool
    function removeLiquidity(
        PoolKey calldata poolKey,
        uint128 liquidityAmount,
        address recipient
    ) external {
        PoolId poolId = poolKey.toId();
        if (!poolConfigurations[poolId].isActive) revert PoolNotConfigured();
        
        // Check if caller owns enough liquidity using encrypted comparison
        euint256 userLiquidity = encryptedLiquidityOwnership[poolId][msg.sender];
        euint256 requestedAmount = FHE.asEuint256(liquidityAmount);
        ebool hasEnoughLiquidity = FHE.gte(userLiquidity, requestedAmount);
        
        (bool hasEnough, ) = FHE.getDecryptResultSafe(hasEnoughLiquidity);
        if (!hasEnough) {
            revert UnauthorizedLiquidityRemoval();
        }
        
        LiquidityPosition storage position = liquidityPositions[poolId];
        if (position.liquidityAmount < liquidityAmount) revert InsufficientLiquidity();
        
        int24 lowerTick = position.lowerTick;
        int24 upperTick = position.upperTick;
        if (lowerTick == 0 && upperTick == 0) revert LiquidityRangeInvalid();

        // Prepare parameters for liquidity removal
        ModifyLiquidityParams memory modifyParams = ModifyLiquidityParams({
            tickLower: lowerTick,
            tickUpper: upperTick,
            liquidityDelta: -int256(uint256(liquidityAmount)),
            salt: bytes32(0)
        });

        // Execute liquidity removal via Uniswap V4 callback
        poolManager.unlock(abi.encode(LiquidityCallback(msg.sender, poolKey, modifyParams)));
        
        // Update position state after callback
        // This is safe because unlockCallback handles all external interactions
        // and we're only updating our internal state after the callback completes
        position.liquidityAmount -= liquidityAmount;
        
        // Update encrypted liquidity ownership
        euint256 currentUserLiquidity = encryptedLiquidityOwnership[poolId][msg.sender];
        euint256 newUserLiquidity = FHE.sub(currentUserLiquidity, FHE.asEuint256(liquidityAmount));
        encryptedLiquidityOwnership[poolId][msg.sender] = newUserLiquidity;
        
        // Update encrypted total liquidity
        euint256 currentTotalLiquidity = encryptedTotalLiquidity[poolId];
        euint256 newTotalLiquidity = FHE.sub(currentTotalLiquidity, FHE.asEuint256(liquidityAmount));
        encryptedTotalLiquidity[poolId] = newTotalLiquidity;
        
        // Update total liquidity in pool configuration
        PoolConfiguration storage config = poolConfigurations[poolId];
        config.totalLiquidity -= liquidityAmount;

        // Emit encrypted liquidity withdrawal for MEV protection
        emit EncryptedLiquidityWithdrawn(
            poolId, 
            recipient, 
            abi.encode(FHE.asEuint256(liquidityAmount)),
            abi.encode(FHE.asEuint32(uint32(int32(lowerTick)))),
            abi.encode(FHE.asEuint32(uint32(int32(upperTick))))
        );
    }

    
    // Internal function to get user liquidity amount (MEV-protected - no external access)
    function _getUserLiquidityAmount(PoolKey calldata poolKey, address user) internal view returns (uint256 liquidityAmount) {
        PoolId poolId = poolKey.toId();
        euint256 encryptedAmount = encryptedLiquidityOwnership[poolId][user];
        (uint256 amount, bool success) = FHE.getDecryptResultSafe(encryptedAmount);
        
        // If FHE decryption fails, return 0 for security (no public fallback)
        if (!success) {
            return 0;
        }
        
        return amount;
    }

    // Returns the liquidity amount owned by a specific user in a pool (MEV-protected)
    function getUserLiquidityAmount(PoolKey calldata poolKey, address user) external view returns (uint256 liquidityAmount) {
        // Only allow users to check their own liquidity to prevent MEV analysis
        require(msg.sender == user, "Only owner can check their liquidity");
        
        return _getUserLiquidityAmount(poolKey, user);
    }

    // Configures rebalancing strategy for a pool with ENCRYPTED parameters only (no public fallback)
    function configureEncryptedRebalancingStrategy(
        PoolKey calldata poolKey, 
        uint24 priceThreshold,
        uint32 cooldownPeriod,
        int24 rangeWidth,
        bool autoRebalance,
        uint24 maxSlippage
    ) external onlyOwner {
        // Validate strategy parameters
        if (priceThreshold == 0 || priceThreshold > MAX_PRICE_DEVIATION) {
            revert InvalidConfiguration();
        }
        if (rangeWidth <= 0 || rangeWidth > 2000) {
            revert InvalidConfiguration();
        }
        
        PoolId poolId = poolKey.toId();
        
        // Store ONLY encrypted strategy parameters (no public storage)
        encryptedPriceThresholds[poolId] = FHE.asEuint256(priceThreshold);
        encryptedCooldownPeriods[poolId] = FHE.asEuint32(cooldownPeriod);
        encryptedRangeWidths[poolId] = FHE.asEuint32(uint32(int32(rangeWidth)));
        encryptedAutoRebalancing[poolId] = FHE.asEbool(autoRebalance);
        encryptedMaxSlippage[poolId] = FHE.asEuint32(maxSlippage);
        
        // Emit ONLY encrypted events (no public strategy data leaked)
        emit EncryptedStrategyUpdated(
            poolId,
            abi.encode(encryptedPriceThresholds[poolId]),
            abi.encode(encryptedCooldownPeriods[poolId]),
            abi.encode(encryptedRangeWidths[poolId]),
            abi.encode(encryptedAutoRebalancing[poolId])
        );
    }

    // Manually triggers rebalancing for a pool
    function executeRebalancing(PoolKey calldata poolKey) external {
        _performRebalancing(poolKey);
    }
    
    // Get encrypted strategy parameters (for verification/debugging)
    function getEncryptedStrategy(PoolKey calldata poolKey) external view returns (
        bytes memory encryptedThresholdData,
        bytes memory encryptedCooldownData,
        bytes memory encryptedRangeWidthData,
        bytes memory encryptedAutoRebalanceData,
        bytes memory encryptedMaxSlippageData
    ) {
        PoolId poolId = poolKey.toId();
        return (
            abi.encode(encryptedPriceThresholds[poolId]),
            abi.encode(encryptedCooldownPeriods[poolId]),
            abi.encode(encryptedRangeWidths[poolId]),
            abi.encode(encryptedAutoRebalancing[poolId]),
            abi.encode(encryptedMaxSlippage[poolId])
        );
    }
    
    // Get encrypted liquidity amounts (for verification/debugging)
    function getEncryptedLiquidity(PoolKey calldata poolKey, address user) external view returns (
        bytes memory encryptedUserLiquidityData,
        bytes memory encryptedTotalLiquidityData
    ) {
        PoolId poolId = poolKey.toId();
        return (
            abi.encode(encryptedLiquidityOwnership[poolId][user]),
            abi.encode(encryptedTotalLiquidity[poolId])
        );
    }

    /// Emergency function to pause rebalancing for a specific pool
    /// @param poolKey The pool to pause
    function pausePoolRebalancing(PoolKey calldata poolKey) external onlyOwner {
        PoolId poolId = poolKey.toId();
        
        // Update encrypted auto-rebalancing flag only (no public storage)
        encryptedAutoRebalancing[poolId] = FHE.asEbool(false);
        
        // Emit encrypted event only
        emit EncryptedStrategyUpdated(
            poolId,
            abi.encode(encryptedPriceThresholds[poolId]),
            abi.encode(encryptedCooldownPeriods[poolId]),
            abi.encode(encryptedRangeWidths[poolId]),
            abi.encode(encryptedAutoRebalancing[poolId])
        );
    }

    /// Resumes rebalancing for a specific pool
    /// @param poolKey The pool to resume
    function resumePoolRebalancing(PoolKey calldata poolKey) external onlyOwner {
        PoolId poolId = poolKey.toId();
        
        // Update encrypted auto-rebalancing flag only (no public storage)
        encryptedAutoRebalancing[poolId] = FHE.asEbool(true);
        
        // Emit encrypted event only
        emit EncryptedStrategyUpdated(
            poolId,
            abi.encode(encryptedPriceThresholds[poolId]),
            abi.encode(encryptedCooldownPeriods[poolId]),
            abi.encode(encryptedRangeWidths[poolId]),
            abi.encode(encryptedAutoRebalancing[poolId])
        );
    }

    /// Emergency function to deactivate a pool (prevents new liquidity additions)
    /// @param poolKey The pool to deactivate
    function deactivatePool(PoolKey calldata poolKey) external onlyOwner {
        PoolId poolId = poolKey.toId();
        poolConfigurations[poolId].isActive = false;
        
        emit PoolDeactivated(poolId);
    }

    /// Reactivates a pool (allows new liquidity additions)
    /// @param poolKey The pool to reactivate
    function reactivatePool(PoolKey calldata poolKey) external onlyOwner {
        PoolId poolId = poolKey.toId();
        poolConfigurations[poolId].isActive = true;
        
        emit PoolReactivated(poolId);
    }

    // Defines Uniswap V4 hook permissions
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

    // Initializes pool configuration before pool creation
    function _beforeInitialize(address, PoolKey calldata poolKey, uint160)
        internal
        override
        returns (bytes4)
    {
        if (poolKey.tickSpacing != 60) revert InvalidTickSpacing();

        PoolId poolId = poolKey.toId();
        
        // Set default pool configuration
        poolConfigurations[poolId] = PoolConfiguration({
            isActive: true,
            totalLiquidity: 0,
            lastRebalanceTick: 0,
            lastRebalanceTimestamp: 0,
            feesAccrued: false
        });
        
        // Initialize encrypted strategy parameters only (no public storage)
        encryptedPriceThresholds[poolId] = FHE.asEuint256(DEFAULT_THRESHOLD);
        encryptedCooldownPeriods[poolId] = FHE.asEuint32(DEFAULT_COOLDOWN);
        encryptedRangeWidths[poolId] = FHE.asEuint32(uint32(int32(DEFAULT_RANGE_WIDTH)));
        encryptedAutoRebalancing[poolId] = FHE.asEbool(true);
        encryptedMaxSlippage[poolId] = FHE.asEuint32(100);
        
        // Initialize encrypted liquidity tracking
        encryptedTotalLiquidity[poolId] = FHE.asEuint256(0);

        return this.beforeInitialize.selector;
    }

    // Initializes liquidity position after pool creation
    function _afterInitialize(
        address,
        PoolKey calldata poolKey,
        uint160,
        int24 currentTick
    ) internal override returns (bytes4) {
        PoolId poolId = poolKey.toId();
        
        // Set initial liquidity position
        liquidityPositions[poolId] = LiquidityPosition({
            lowerTick: currentTick - rangeOffset,
            upperTick: currentTick + rangeOffset,
            currentTick: currentTick,
            liquidityAmount: 0
        });
        
        return this.afterInitialize.selector;
    }

    // Allows liquidity addition from any user and tracks it
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata poolKey,
        ModifyLiquidityParams calldata params,
        bytes calldata
    ) external override returns (bytes4) {
        // Track liquidity ownership when added
        if (params.liquidityDelta > 0) {
            _trackLiquidityAddition(poolKey, sender, uint128(uint256(params.liquidityDelta)), params.tickLower, params.tickUpper);
        }
        return this.beforeAddLiquidity.selector;
    }

    // Internal function to track liquidity addition
    function _trackLiquidityAddition(
        PoolKey calldata poolKey,
        address provider,
        uint128 liquidityAmount,
        int24 tickLower,
        int24 tickUpper
    ) internal {
        PoolId poolId = poolKey.toId();
        
        // Update liquidity position
        LiquidityPosition storage position = liquidityPositions[poolId];
        position.lowerTick = tickLower;
        position.upperTick = tickUpper;
        position.currentTick = 0; // Will be updated during swaps
        position.liquidityAmount += liquidityAmount;
        
        // Update pool configuration
        PoolConfiguration storage config = poolConfigurations[poolId];
        config.totalLiquidity += liquidityAmount;
        
        // Track encrypted liquidity ownership
        euint256 currentUserLiquidity = encryptedLiquidityOwnership[poolId][provider];
        euint256 newUserLiquidity = FHE.add(currentUserLiquidity, FHE.asEuint256(liquidityAmount));
        encryptedLiquidityOwnership[poolId][provider] = newUserLiquidity;
        
        // Update encrypted total liquidity
        euint256 currentTotalLiquidity = encryptedTotalLiquidity[poolId];
        euint256 newTotalLiquidity = FHE.add(currentTotalLiquidity, FHE.asEuint256(liquidityAmount));
        encryptedTotalLiquidity[poolId] = newTotalLiquidity;
        
        // Removed public fallback for true MEV protection
        
        // Emit encrypted liquidity provision for MEV protection
        emit EncryptedLiquidityProvisioned(
            poolId, 
            provider, 
            abi.encode(newUserLiquidity), // Encrypted amount
            abi.encode(FHE.asEuint32(uint32(int32(tickLower)))),
            abi.encode(FHE.asEuint32(uint32(int32(tickUpper))))
        );
    }

    // Handles swap events and triggers rebalancing if needed
    function beforeSwap(address, PoolKey calldata poolKey, SwapParams calldata, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = poolKey.toId();
        
        // Mark fees as accrued to indicate trading activity
        if (!poolConfigurations[poolId].feesAccrued) {
            poolConfigurations[poolId].feesAccrued = true;
        }

        // Trigger rebalancing using encrypted strategy parameters only
        try this._shouldTriggerRebalancing(poolKey) returns (bool shouldRebalance) {
            if (shouldRebalance) {
                _performRebalancing(poolKey);
            }
        } catch {
            // If FHE operations fail, skip rebalancing for security
            // This ensures the swap can still proceed without leaking strategy info
        }

        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    // Calculates liquidity amount from token input
    function _calculateLiquidityAmount(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount
    ) internal pure returns (uint128 liquidity) {
        if (amount == 0) return 0;
        
        // Convert ticks to square root prices
        uint160 sqrtPriceAX96 = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtPriceAtTick(tickUpper);
        
        // Ensure lower price is less than upper price
        if (sqrtPriceAX96 > sqrtPriceBX96) {
            (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        }
        
        // Calculate liquidity based on price position
        if (sqrtPriceX96 <= sqrtPriceAX96) {
            // Price below range: only token0 needed
            return _getLiquidityForAmount0(sqrtPriceAX96, sqrtPriceBX96, amount);
        } else if (sqrtPriceX96 < sqrtPriceBX96) {
            // Price in range: both tokens needed
            // For a 1:1 price ratio (sqrtPriceX96 = 2^96), both tokens need equal amounts
            // Calculate liquidity based on token0 amount only to avoid decimal issues
            return _getLiquidityForAmount0(sqrtPriceX96, sqrtPriceBX96, amount);
        } else {
            // Price above range: only token1 needed
            return _getLiquidityForAmount1(sqrtPriceAX96, sqrtPriceBX96, amount);
        }
    }
    
    // Calculates liquidity for token0 amount
    function _getLiquidityForAmount0(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint256 amount0
    ) internal pure returns (uint128) {
        if (sqrtPriceAX96 > sqrtPriceBX96) {
            (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        }
        
        uint256 intermediate = FullMath.mulDiv(sqrtPriceAX96, sqrtPriceBX96, FixedPoint96.Q96);
        return uint128(FullMath.mulDiv(amount0, intermediate, sqrtPriceBX96 - sqrtPriceAX96));
    }
    
    // Calculates liquidity for token1 amount
    function _getLiquidityForAmount1(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint256 amount1
    ) internal pure returns (uint128) {
        if (sqrtPriceAX96 > sqrtPriceBX96) {
            (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        }
        
        return uint128(FullMath.mulDiv(amount1, FixedPoint96.Q96, sqrtPriceBX96 - sqrtPriceAX96));
    }
    
    // Checks if rebalancing should be triggered using encrypted parameters
    function _shouldTriggerRebalancing(PoolKey calldata poolKey) external returns (bool) {
        PoolId poolId = poolKey.toId();
        PoolConfiguration memory config = poolConfigurations[poolId];
        
        // Early return if pool is not active or no liquidity
        if (!config.isActive || config.totalLiquidity < MIN_LIQUIDITY_THRESHOLD) {
            return false;
        }
        
        // Get encrypted strategy parameters
        euint32 encryptedCooldown = encryptedCooldownPeriods[poolId];
        euint256 encryptedTotalLiquidityAmount = encryptedTotalLiquidity[poolId];
        ebool encryptedAutoRebalance = encryptedAutoRebalancing[poolId];
        
        // Check cooldown period using encrypted comparison
        euint256 currentTime = FHE.asEuint256(block.timestamp);
        euint256 lastRebalanceTime = FHE.asEuint256(config.lastRebalanceTimestamp);
        euint256 timeSinceRebalance = FHE.sub(currentTime, lastRebalanceTime);
        
        // Convert euint32 to euint256 for comparison
        euint256 encryptedCooldown256 = FHE.asEuint256(encryptedCooldown);
        ebool cooldownPassed = FHE.gte(timeSinceRebalance, encryptedCooldown256);
        
        // Check liquidity threshold using encrypted comparison
        euint256 minLiquidityThreshold = FHE.asEuint256(MIN_LIQUIDITY_THRESHOLD);
        ebool hasEnoughLiquidity = FHE.gte(encryptedTotalLiquidityAmount, minLiquidityThreshold);
        
        // Combine all conditions using encrypted boolean operations
        ebool shouldRebalance = FHE.and(
            FHE.and(cooldownPassed, hasEnoughLiquidity),
            FHE.and(encryptedAutoRebalance, FHE.asEbool(config.feesAccrued))
        );
        
        // Decrypt the final decision with proper error handling
        (bool result, bool success) = FHE.getDecryptResultSafe(shouldRebalance);
        
        // If decryption fails, return false for security (no public fallback)
        if (!success) {
            // Emit failure event for monitoring
            emit EncryptedRebalancingDecision(
                poolId,
                abi.encode(FHE.asEbool(false)), // Encrypted false
                abi.encode(FHE.asEuint256(block.timestamp)),
                abi.encode(encryptedCooldown)
            );
            return false;
        }
        
        // Emit encrypted decision for transparency (but decision is still hidden)
        emit EncryptedRebalancingDecision(
            poolId,
            abi.encode(shouldRebalance),
            abi.encode(FHE.asEuint256(block.timestamp)),
            abi.encode(encryptedCooldown)
        );
        
        return result;
    }

    // Rebalances liquidity to a new tick range
    function _performRebalancing(PoolKey memory poolKey) internal {
        PoolId poolId = poolKey.toId();
        PoolConfiguration storage config = poolConfigurations[poolId];
        LiquidityPosition storage position = liquidityPositions[poolId];
        
        if (position.liquidityAmount == 0) return;

        // Fetch current pool tick
        (, int24 currentTick,,) = StateLibrary.getSlot0(poolManager, poolId);
        
        // Calculate new tick range
        int24 newLowerTick = currentTick - rangeOffset;
        int24 newUpperTick = currentTick + rangeOffset;
        
        int24 oldLowerTick = position.lowerTick;
        int24 oldUpperTick = position.upperTick;
        
        // Skip if range hasn't changed
        if (oldLowerTick == newLowerTick && oldUpperTick == newUpperTick) {
            return;
        }
        
        // Remove liquidity from old range if it exists
        if (oldLowerTick != 0 && oldUpperTick != 0) {
            ModifyLiquidityParams memory removeParams = ModifyLiquidityParams({
                tickLower: oldLowerTick,
                tickUpper: oldUpperTick,
                liquidityDelta: -int256(uint256(position.liquidityAmount)),
                salt: bytes32(0)
            });
            poolManager.unlock(abi.encode(LiquidityCallback(address(this), poolKey, removeParams)));
        }
        
        // Add liquidity to new range
        if (newLowerTick != newUpperTick) {
            ModifyLiquidityParams memory addParams = ModifyLiquidityParams({
                tickLower: newLowerTick,
                tickUpper: newUpperTick,
                liquidityDelta: int256(uint256(position.liquidityAmount)),
                salt: bytes32(0)
            });
            poolManager.unlock(abi.encode(LiquidityCallback(address(this), poolKey, addParams)));
        }
        
        // Update position with new range and tick
        position.lowerTick = newLowerTick;
        position.upperTick = newUpperTick;
        position.currentTick = currentTick;
        
        // Update configuration
        config.lastRebalanceTick = currentTick;
        config.lastRebalanceTimestamp = block.timestamp;
        config.feesAccrued = false;

        // Emit encrypted rebalancing event for MEV protection
        emit EncryptedRebalancingTriggered(
            poolId, 
            abi.encode(FHE.asEuint32(uint32(int32(oldLowerTick)))),
            abi.encode(FHE.asEuint32(uint32(int32(oldUpperTick)))),
            abi.encode(FHE.asEuint32(uint32(int32(newLowerTick)))),
            abi.encode(FHE.asEuint32(uint32(int32(newUpperTick)))),
            abi.encode(FHE.asEuint256(block.timestamp))
        );
    }

    // Settles token balances for negative deltas
    function _settleDeltas(address sender, PoolKey memory poolKey, BalanceDelta delta) internal {
        // Only settle tokens that have negative deltas (owe tokens to pool)
        if (delta.amount0() < 0) {
            poolKey.currency0.settle(poolManager, sender, uint256(int256(-delta.amount0())), false);
        }
        if (delta.amount1() < 0) {
            poolKey.currency1.settle(poolManager, sender, uint256(int256(-delta.amount1())), false);
        }
    }

    // Withdraws tokens for positive deltas
    function _takeDeltas(address sender, PoolKey memory poolKey, BalanceDelta delta) internal {
        poolManager.take(poolKey.currency0, sender, uint256(uint128(delta.amount0())));
        poolManager.take(poolKey.currency1, sender, uint256(uint128(delta.amount1())));
    }

    // Handles Uniswap V4 callback for liquidity operations
    function unlockCallback(bytes calldata rawData)
        external
        override(IUnlockCallback)
        onlyPoolManager
        returns (bytes memory)
    {
        LiquidityCallback memory data = abi.decode(rawData, (LiquidityCallback));
        BalanceDelta delta;

        if (data.params.liquidityDelta < 0) {
            // Remove liquidity and withdraw tokens
            (delta,) = poolManager.modifyLiquidity(data.poolKey, data.params, EMPTY_BYTES);
            _takeDeltas(data.user, data.poolKey, delta);
        } else {
            // Add liquidity and settle tokens
            (delta,) = poolManager.modifyLiquidity(data.poolKey, data.params, EMPTY_BYTES);
            _settleDeltas(data.user, data.poolKey, delta);
        }
        
        return abi.encode(delta);
    }
}