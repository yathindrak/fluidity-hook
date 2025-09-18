# Fluidity - MEV-Resistant Uniswap V4 Rebalancing Hook with FHE

A Uniswap V4 hook that uses **Fully Homomorphic Encryption (FHE)** to encrypt strategy configurations, price thresholds, and liquidity parameters protecting them from MEV extraction while providing intelligent liquidity rebalancing. Built in partnership with **Fhenix**.

## 🎯 Problems We Solve

Fluidity solves two key problems in DeFi: **strategy privacy** and **liquidity rebalancing**. 

1. Sensitive strategy parameters (price thresholds, rebalancing logic, position sizes) are visible in smart contract storage and events, allowing bots to analyze and replicate successful strategies. 
2. Manual liquidity management is inefficient - positions need constant rebalancing to maintain optimal capital efficiency. Fluidity addresses both by encrypting strategy configurations using **FHE** to prevent analysis, while providing automated rebalancing that works on encrypted data, maintaining full Uniswap V4 compatibility.

## 💡 Our Solution

**Fluidity uses Fhenix's FHE technology to encrypt sensitive configuration data during smart contract execution:**

- **🔐 Encrypted Strategy Configurations**: Price thresholds, cooldown periods, and range widths stored as encrypted types (`euint256`, `euint32`, `ebool`)
- **🛡️ Encrypted Liquidity Parameters**: Position sizes, ownership, and amounts encrypted to prevent analysis
- **⚡ Private Rebalancing Logic**: Rebalancing decisions made on encrypted data using FHE operations
- **🎯 Capital Efficiency**: Intelligent rebalancing without exposing any strategy details to MEV bots

## 🌍 Benefits & Impact

Strategy privacy through encrypted parameters and automated liquidity rebalancing.

## 🏆 Technical Innovations

**Fhenix FHE Integration**: Using Fully Homomorphic Encryption to perform encrypted computations on strategy parameters and liquidity data.

**Intelligent Rebalancing**: Automated liquidity management that works on encrypted data, including threshold comparisons and arithmetic operations.

**MEV Protection**: Strategy parameters and position data encrypted using `euint256`, `euint32`, and `ebool` types, making them invisible to MEV bots during contract execution.

### Why FHE Beyond Private Mappings?

While `private` mappings prevent direct access, MEV bots can still extract information through:

- **Transaction Analysis**: Function parameters visible in transaction data
- **Event Monitoring**: Strategy updates exposed in event logs
- **Gas Pattern Analysis**: Different parameters cause different gas costs
- **Internal Call Tracing**: Function behavior analysis through internal calls
- **Side-Channel Attacks**: Timing and execution pattern analysis

### Current Limitations

- **Rebalancing Verificaiton**: Limited verification of rebalancing flow due to liquidity provision challenges

### 🔧 Next Steps

1. **Mainnet Integration**: Deploy on Unichain mainnet
2. **Gas Optimization**: Analyze gas costs and optimization
4. **Price Oracle Integration**: Multi-pool price consensus or Chainlink integration with TWAP for better accuracy

All parameters are stored as encrypted types and operations are performed on encrypted data to prevent MEV extraction.

## Events

The Fluidity hook emits comprehensive events for monitoring with MEV protection:

**Standard Events**:
- `LiquidityProvisioned`: When liquidity is provisioned to a pool
- `LiquidityWithdrawn`: When liquidity is withdrawn from a pool
- `RebalancingTriggered`: When a rebalancing operation is performed

**Encrypted Events**:
- `EncryptedStrategyUpdated`: Strategy parameters updated as encrypted data
- `EncryptedLiquidityProvisioned`: Liquidity amounts stored as encrypted data
- `EncryptedRebalancingDecision`: Rebalancing decisions made on encrypted data

All sensitive information is emitted as encrypted data to prevent MEV bots from analyzing trading patterns and strategies.

## Deployment

### Prerequisites

1. **Foundry Installation**: Install Foundry for Solidity development
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

2. **Environment Setup**: Set up your environment variables
   ```bash
   export PRIVATE_KEY="your_private_key_here"
   export RPC_URL="https://ethereum-sepolia-rpc.publicnode.com"
   ```

3. **Dependencies**: Install project dependencies
   ```bash
   forge install
   ```

### Step-by-Step Deployment

**Important**: After each deployment step, you must update the contract addresses in `script/base/BaseScript.sol` before running the next step.

#### 1. Deploy Test Tokens
Deploy mock tokens for testing on Sepolia testnet:
```bash
forge script script/00_DeployTokens.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
```

**After deployment, update BaseScript.sol with the new token addresses:**
```solidity
// Update these addresses in script/base/BaseScript.sol
IERC20 internal constant token0 = IERC20(0x[TOKEN0_ADDRESS]); // mTokenA
IERC20 internal constant token1 = IERC20(0x[TOKEN1_ADDRESS]); // mTokenB
```

#### 2. Deploy Fluidity Hook
Deploy the main Fluidity hook contract:
```bash
forge script script/01_DeployHook.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
```

**After deployment, update BaseScript.sol with the new hook address:**
```solidity
// Update this address in script/base/BaseScript.sol
IHooks constant hookContract = IHooks(address(0x[HOOK_ADDRESS]));
```

#### 3. Create Pool and Add Liquidity
Create a Uniswap V4 pool with the Fluidity hook and add initial liquidity:
```bash
forge script script/02_CreatePoolAndAddLiquidity.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
```

#### 4. (Optional) Add Additional Liquidity
Add more liquidity to existing pools if needed:
```bash
forge script script/03_Optional_AddLiquidity.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
```

#### 5. Test Swap Functionality
Test the swap functionality with MEV protection:
```bash
forge script script/04_Swap.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
```

#### 6. Run Complete Test Suite
Execute the comprehensive test suite to verify all functionality:
```bash
forge script script/05_CompleteFluidityTest.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
```

### Address Update Workflow

Each deployment script will output the deployed contract addresses. You must update `script/base/BaseScript.sol` with these addresses before running subsequent scripts:

1. **After Token Deployment**: Update `token0` and `token1` addresses
2. **After Hook Deployment**: Update `hookContract` address
3. **Verify Addresses**: Check that all addresses are correctly updated before proceeding

**Example Address Update Process:**
```bash
# 1. Deploy tokens
forge script script/00_DeployTokens.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY

# 2. Copy the deployed addresses from the output
# 3. Update BaseScript.sol with the new addresses
# 4. Deploy hook
forge script script/01_DeployHook.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY

# 5. Copy the hook address from the output
# 6. Update BaseScript.sol with the hook address
# 7. Continue with remaining scripts
```

### Current Deployed Addresses (Sepolia Testnet)

**Latest Deployment (as of current session):**
- **Token0 (mTokenA)**: `0xabc0Afb70F325F4119cFCA4083EA2A580Ec40D3F`
- **Token1 (mTokenB)**: `0x3e68f0F304314495fa45907170a59D0BA5218bCc`
- **Fluidity Hook**: `0x98FB6Db4104dF971db052a2fc8B7CB760135F880`

**BaseScript.sol Configuration:**
```solidity
IERC20 internal constant token0 = IERC20(0xabc0Afb70F325F4119cFCA4083EA2A580Ec40D3F); // mTokenA
IERC20 internal constant token1 = IERC20(0x3e68f0F304314495fa45907170a59D0BA5218bCc); // mTokenB
IHooks constant hookContract = IHooks(address(0x98FB6Db4104dF971db052a2fc8B7CB760135F880));
```

**Note**: These addresses are from the latest deployment. If you're deploying fresh, you'll get different addresses and need to update BaseScript.sol accordingly.

### Verification Scripts

#### Check Pool State
Verify pool configuration and liquidity:
```bash
forge script script/06_CheckPoolSlot0.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
```

#### Check Position Details
Inspect specific liquidity positions:
```bash
forge script script/07_CheckPositionDetails.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
```

#### Check All Positions
View all liquidity positions in the system:
```bash
forge script script/08_CheckPositions.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
```

Run the full test suite:

```bash
forge test -vv
```

Run the complete integration test:

```bash
forge script script/05_CompleteFluidityTest.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
```

## 🚀 Deployed Addresses

Contract Addresses (Sepolia Testnet):
- **Token0 (mTokenA)**: `0xabc0Afb70F325F4119cFCA4083EA2A580Ec40D3F`
- **Token1 (mTokenB)**: `0x3e68f0F304314495fa45907170a59D0BA5218bCc`
- **Fluidity Hook**: `0x54Ce5e7351BF259604F3DB6D79fC3653A15EF880`

### Quick Start
```bash
# Demo script
forge script script/AppDemo.s.sol --rpc-url https://ethereum-sepolia-rpc.publicnode.com --broadcast --private-key $PRIVATE_KEY
```

