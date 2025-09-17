# Test Coverage Guide for RebalanceHook.sol

This guide explains how to check test coverage for the `RebalanceHook.sol` file and how to interpret the coverage values.

## Prerequisites

- Foundry framework installed
- Project dependencies installed (`forge install`)
- Tests passing (`forge test`)

## Coverage Commands

### 1. Basic Coverage Analysis

```bash
# Run coverage for all tests
forge coverage --ir-minimum
```

### 2. Coverage for Specific Test Contract

```bash
# Focus on the main RebalanceHook test contract
forge coverage --match-contract "FhenixRebalanceHookTestFixed" --ir-minimum
```

### 3. Generate Detailed Reports

```bash
# Generate LCOV report for detailed analysis
forge coverage --ir-minimum --report lcov

# Generate both summary and LCOV reports
forge coverage --ir-minimum --report summary --report lcov
```

### 4. Coverage with Test Execution

```bash
# Run tests first to ensure they pass
forge test --match-contract "FhenixRebalanceHookTestFixed" -vv

# Then run coverage analysis
forge coverage --match-contract "FhenixRebalanceHookTestFixed" --ir-minimum
```

## Current Coverage Results

### RebalanceHook.sol Coverage Metrics

| Metric | Coverage | Covered/Total | Interpretation |
|--------|----------|---------------|----------------|
| **Lines** | **39.91%** | 93/233 | Lines of code executed during tests |
| **Statements** | **37.86%** | 106/280 | Individual statements executed |
| **Branches** | **11.43%** | 4/35 | Conditional branches taken |
| **Functions** | **55.56%** | 15/27 | Functions called during tests |

### Coverage Breakdown

#### ✅ **Well Covered Areas (Functions - 55.56%)**
- Core liquidity management functions
- FHE (Fully Homomorphic Encryption) operations
- MEV protection mechanisms
- Basic error handling
- Pool initialization and configuration

#### ⚠️ **Areas Needing Improvement**

**Branch Coverage (11.43%) - Critical Gap**
- Many conditional statements not fully tested
- Error conditions and edge cases missing
- Complex logic paths untested

**Line Coverage (39.91%) - Moderate**
- Significant portions of code not executed
- Helper functions and utilities untested
- Error handling paths incomplete

## Test Files Structure

### Primary Test File: `test/FhenixRebalanceHookTestFixed.t.sol`

**10 Test Functions:**
1. `testFhenixBasicOperations()` - Basic contract functionality
2. `testFhenixEncryptedStrategy()` - Strategy configuration with FHE
3. `testFhenixErrorHandling()` - Error scenarios
4. `testFhenixMEVProtection()` - MEV protection mechanisms
5. `test_AddLiquidityWithFhenix()` - Liquidity addition with encryption
6. `test_FhenixEncryptedDecisionMaking()` - Encrypted rebalancing decisions
7. `test_FhenixEncryptedLiquidity()` - Encrypted liquidity tracking
8. `test_FhenixEncryptedStrategy()` - Strategy management
9. `test_FhenixMEVProtection()` - Additional MEV tests
10. `test_FhenixPauseResumeEncryption()` - Pool pause/resume functionality

### Secondary Test File: `test/FhenixTest.t.sol`
- Basic FHE functionality tests (2 tests)
- Contract deployment verification

## Interpreting Coverage Values

### Coverage Metrics Explained

#### 1. **Lines Coverage (39.91%)**
- **What it measures:** Percentage of source code lines executed
- **Current:** 93 out of 233 lines covered
- **Target:** Aim for 80%+ for production code
- **Gap:** 140 lines not executed during tests

#### 2. **Statements Coverage (37.86%)**
- **What it measures:** Individual executable statements
- **Current:** 106 out of 280 statements covered
- **Target:** 80%+ for comprehensive testing
- **Gap:** 174 statements not executed

#### 3. **Branches Coverage (11.43%) - ⚠️ CRITICAL**
- **What it measures:** Conditional execution paths (if/else, switch, etc.)
- **Current:** Only 4 out of 35 branches covered
- **Target:** 70%+ for robust testing
- **Gap:** 31 branches untested - **HIGH RISK**

#### 4. **Functions Coverage (55.56%)**
- **What it measures:** Functions called during tests
- **Current:** 15 out of 27 functions covered
- **Target:** 90%+ for core functionality
- **Gap:** 12 functions never called

## Coverage Analysis Tools

### LCOV Report Analysis

```bash
# Generate LCOV report
forge coverage --ir-minimum --report lcov

# The lcov.info file contains detailed line-by-line coverage
# Can be used with tools like:
# - genhtml (from lcov package)
# - VS Code coverage extensions
# - CI/CD coverage reporting
```

### Visual Coverage Report

```bash
# Install lcov tools (if available)
# On macOS: brew install lcov
# On Ubuntu: sudo apt-get install lcov

# Generate HTML report
genhtml lcov.info --output-directory coverage-report
```

## Improving Coverage

### Priority Areas for Additional Tests

#### 1. **Branch Coverage (Critical Priority)**
```solidity
// Test these conditional paths:
if (priceThreshold == 0 || priceThreshold > MAX_PRICE_DEVIATION) {
    revert InvalidConfiguration();
}

if (rangeWidth <= 0 || rangeWidth > 2000) {
    revert InvalidConfiguration();
}

// Test error conditions:
if (!config.isActive || config.totalLiquidity < MIN_LIQUIDITY_THRESHOLD) {
    return false;
}
```

#### 2. **Error Handling Tests**
- Invalid pool configurations
- Unauthorized access attempts
- Insufficient liquidity scenarios
- Invalid tick ranges
- Price deviation edge cases

#### 3. **Edge Cases**
- Zero liquidity scenarios
- Maximum/minimum tick values
- Boundary conditions for ranges
- FHE operation failures

#### 4. **Integration Tests**
- Full rebalancing flow
- Multiple user interactions
- Complex liquidity scenarios
- Cross-function interactions

## Monitoring Coverage

### Regular Coverage Checks

```bash
# Add to your development workflow
#!/bin/bash
echo "Running test coverage analysis..."

# Run tests
forge test

# Generate coverage
forge coverage --ir-minimum --report summary

# Check if coverage meets minimum thresholds
COVERAGE=$(forge coverage --ir-minimum --report summary | grep "src/RebalanceHook.sol" | awk '{print $4}')
if (( $(echo "$COVERAGE < 50" | bc -l) )); then
    echo "❌ Coverage below 50%: $COVERAGE"
    exit 1
else
    echo "✅ Coverage acceptable: $COVERAGE"
fi
```

## Conclusion

The current test coverage for `RebalanceHook.sol` shows:
- **Good function coverage** (55.56%) indicating core functionality is tested
- **Moderate line coverage** (39.91%) with room for improvement
- **Critical gap in branch coverage** (11.43%) requiring immediate attention
- **Comprehensive FHE testing** which is excellent for this specialized contract

Focus on improving branch coverage first, as untested conditional paths represent the highest risk for production deployment.
