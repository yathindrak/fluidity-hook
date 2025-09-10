# Uniswap v4 Hook Template

**A template for writing Uniswap v4 Hooks 🦄**

### Get Started

This template provides a starting point for writing Uniswap v4 Hooks, including a simple example and preconfigured test environment. Start by creating a new repository using the "Use this template" button at the top right of this page. Alternatively you can also click this link:

[![Use this Template](https://img.shields.io/badge/Use%20this%20Template-101010?style=for-the-badge&logo=github)](https://github.com/uniswapfoundation/v4-template/generate)

1. The example hook [Counter.sol](src/Counter.sol) demonstrates the `beforeSwap()` and `afterSwap()` hooks
2. The test template [Counter.t.sol](test/Counter.t.sol) preconfigures the v4 pool manager, test tokens, and test liquidity.

<details>
<summary>Updating to v4-template:latest</summary>

This template is actively maintained -- you can update the v4 dependencies, scripts, and helpers:

```bash
git remote add template https://github.com/uniswapfoundation/v4-template
git fetch template
git merge template/main <BRANCH> --allow-unrelated-histories
```

</details>

### Deployment

This guide explains how to deploy test tokens and your liquidity hook for testing on testnets or locally with Anvil.

#### Option 1: Full Deployment (Recommended)
Deploy everything in one go:

**On Testnet:**
```bash
# Ethereum Sepolia
export PRIVATE_KEY="YOUR_PRIVATE_KEY_HERE" # Set your private key as an environment variable. DO NOT hardcode or commit this.
forge script script/FullDeployment.s.sol --rpc-url https://1rpc.io/sepolia --broadcast --private-key $PRIVATE_KEY

# Other testnets
forge script script/FullDeployment.s.sol --rpc-url <YOUR_TESTNET_RPC_URL> --broadcast --private-key $PRIVATE_KEY
```

**On Anvil (Local Development):**
```bash
# Start Anvil in one terminal
anvil

# In another terminal, run the deployment
forge script script/FullDeployment.s.sol --rpc-url http://localhost:8545 --broadcast
```

#### Option 2: Step-by-Step Deployment

1.  **Deploy Tokens Only:**

    **On Testnet:**
    ```bash
    # Ethereum Sepolia
    export PRIVATE_KEY="YOUR_PRIVATE_KEY_HERE" # Set your private key as an environment variable. DO NOT hardcode or commit this.
    forge script script/00_DeployTokens.s.sol --rpc-url https://1rpc.io/sepolia --broadcast --private-key $PRIVATE_KEY

    # Other testnets
    forge script script/00_DeployTokens.s.sol --rpc-url <YOUR_TESTNET_RPC_URL> --broadcast --private-key $PRIVATE_KEY
    ```

    **On Anvil:**
    ```bash
    forge script script/00_DeployTokens.s.sol --rpc-url http://localhost:8545 --broadcast
    ```

2.  **Update BaseScript.sol (if needed):**
    *   Copy the token addresses from the output.
    *   Update lines 31-32 in `script/base/BaseScript.sol`:
        ```solidity
        IERC20 internal constant token0 = IERC20(0x...); // Your deployed token0 address
        IERC20 internal constant token1 = IERC20(0x...); // Your deployed token1 address
        ```
    *   **Note**: For local Anvil deployment (chainId 31337), the BaseScript automatically deploys Uniswap V4 contracts locally, so no manual updates are needed for production addresses.

3.  **Deploy Hook:**

    **On Testnet:**
    ```bash
    # Ethereum Sepolia
    export PRIVATE_KEY="YOUR_PRIVATE_KEY_HERE" # Set your private key as an environment variable. DO NOT hardcode or commit this.
    forge script script/01_DeployHook.s.sol --rpc-url https://1rpc.io/sepolia --broadcast --private-key $PRIVATE_KEY

    # Other testnets
    forge script script/01_DeployHook.s.sol --rpc-url <YOUR_TESTNET_RPC_URL> --broadcast --private-key $PRIVATE_KEY
    ```

    **On Anvil:**
    ```bash
    forge script script/01_DeployHook.s.sol --rpc-url http://localhost:8545 --broadcast
    ```

4.  **Update Hook Address (if needed):**
    *   Copy the deployed hook address from the output.
    *   Update line 33 in `script/base/BaseScript.sol`:
        ```solidity
        IHooks constant hookContract = IHooks(0x...); // Your deployed hook address
        ```
    *   **Note**: For local Anvil deployment, this step is optional as the hook address will be automatically available in subsequent scripts.

5.  **Create Pool and Add Initial Liquidity:**

    **On Testnet:**
    ```bash
    # Ethereum Sepolia
    export PRIVATE_KEY="YOUR_PRIVATE_KEY_HERE" # Set your private key as an environment variable. DO NOT hardcode or commit this.
    forge script script/02_CreatePoolAndAddLiquidity.s.sol --rpc-url https://1rpc.io/sepolia --broadcast --private-key $PRIVATE_KEY

    # Other testnets
    forge script script/02_CreatePoolAndAddLiquidity.s.sol --rpc-url <YOUR_TESTNET_RPC_URL> --broadcast --private-key $PRIVATE_KEY
    ```

    **On Anvil:**
    ```bash
    forge script script/02_CreatePoolAndAddLiquidity.s.sol --rpc-url http://localhost:8545 --broadcast
    ```

6.  **Add More Liquidity (Optional):**

    **On Testnet:**
    ```bash
    # Ethereum Sepolia
    export PRIVATE_KEY="YOUR_PRIVATE_KEY_HERE" # Set your private key as an environment variable. DO NOT hardcode or commit this.
    forge script script/03_Optional_AddLiquidity.s.sol --rpc-url https://1rpc.io/sepolia --broadcast --private-key $PRIVATE_KEY

    # Other testnets
    forge script script/03_Optional_AddLiquidity.s.sol --rpc-url <YOUR_TESTNET_RPC_URL> --broadcast --private-key $PRIVATE_KEY
    ```

    **On Anvil:**
    ```bash
    forge script script/03_Optional_AddLiquidity.s.sol --rpc-url http://localhost:8545 --broadcast
    ```

7.  **Test Swaps:**

    **On Testnet:**
    ```bash
    # Ethereum Sepolia
    export PRIVATE_KEY="YOUR_PRIVATE_KEY_HERE" # Set your private key as an environment variable. DO NOT hardcode or commit this.
    forge script script/04_Swap.s.sol --rpc-url https://1rpc.io/sepolia --broadcast --private-key $PRIVATE_KEY

    # Other testnets
    forge script script/04_Swap.s.sol --rpc-url <YOUR_TESTNET_RPC_URL> --broadcast --private-key $PRIVATE_KEY
    ```

    **On Anvil:**
    ```bash
    forge script script/04_Swap.s.sol --rpc-url http://localhost:8545 --broadcast
    ```

### RPC URLs

#### Testnet RPC URLs
- **Ethereum Sepolia**: `https://1rpc.io/sepolia` (Chain ID: 11155111)
- **Sepolia (Infura)**: `https://sepolia.infura.io/v3/YOUR_PROJECT_ID`
- **Goerli**: `https://goerli.infura.io/v3/YOUR_PROJECT_ID`
- **Arbitrum Sepolia**: `https://sepolia-rollup.arbitrum.io/rpc`
- **Polygon Mumbai**: `https://polygon-mumbai.infura.io/v3/YOUR_PROJECT_ID`

#### Local Development
- **Anvil**: `http://localhost:8545` (default port)
- **Hardhat**: `http://localhost:8545` (default port)

### Verifying Deployment on Anvil

After running deployment scripts on Anvil, you can verify your contracts:

#### 1. Check Script Output
The deployment script will output contract addresses in the console. Look for:
```
Token0 deployed at: 0x5FbDB2315678afecb367f032d93F642f64180aa3
Token1 deployed at: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
```

#### 2. Verify Contracts with Cast
```bash
# Check token names
cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "name()" --rpc-url http://localhost:8545
cast call 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 "name()" --rpc-url http://localhost:8545

# Check token symbols  
cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "symbol()" --rpc-url http://localhost:8545
cast call 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 "symbol()" --rpc-url http://localhost:8545

# Check token balances (replace with your wallet address)
cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "balanceOf(address)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url http://localhost:8545
cast call 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 "balanceOf(address)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url http://localhost:8545

# Check token decimals
cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "decimals()" --rpc-url http://localhost:8545
cast call 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 "decimals()" --rpc-url http://localhost:8545

# Check total supply
cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "totalSupply()" --rpc-url http://localhost:8545
cast call 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 "totalSupply()" --rpc-url http://localhost:8545
```

#### 3. Update BaseScript.sol
After deployment, update `script/base/BaseScript.sol` with the deployed addresses:
```solidity
IERC20 internal constant token0 = IERC20(0x5FbDB2315678afecb367f032d93F642f64180aa3); // mWETH
IERC20 internal constant token1 = IERC20(0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512); // mUSDC
```

### Troubleshooting

<details>

#### Scripts Not Broadcasting
Always use `--private-key` flag for Anvil deployments, and ensure `PRIVATE_KEY` environment variable is set for testnet deployments.

#### Contracts Show Empty Code
This happens when scripts run in simulation mode without `--private-key`.

#### Insufficient Funds
Make sure you have testnet ETH for gas fees.

#### Token Not Found
Verify token addresses are correctly updated in BaseScript.sol.

#### Hook Address Mismatch
Ensure the hook address matches the pool configuration.

#### Wrong Address
Verify addresses match between script output and BaseScript.sol.

#### Hook Deployment Fails with Error 0xc08c7297
This was a known issue with local deployment that has been fixed. The BaseScript now automatically deploys Uniswap V4 contracts locally for chainId 31337.

#### UnsupportedChainId Error
This occurs when trying to use production addresses on local testnet. The BaseScript now handles this automatically for local development.

#### Swap Transaction Failure (Deadline Exceeded)
If a swap transaction reverts with an unclear error or a deadline-related revert, ensure the `deadline` in your swap script is sufficiently large (e.g., `block.timestamp + 3600`). Network congestion or RPC latency can cause transactions to exceed short deadlines.

</details>

### Requirements

This template is designed to work with Foundry (stable). If you are using Foundry Nightly, you may encounter compatibility issues. You can update your Foundry installation to the latest stable version by running:

```
foundryup
```

To set up the project, run the following commands in your terminal to install dependencies and run the tests:

```
forge install
forge test
```

### Local Development

Other than writing unit tests (recommended!), you can only deploy & test hooks on [anvil](https://book.getfoundry.sh/anvil/) locally. Scripts are available in the `script/` directory, which can be used to deploy hooks, create pools, provide liquidity and swap tokens. The scripts support both local `anvil`