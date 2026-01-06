# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

```bash
# Build the project
scarb build

# Run all tests
scarb test

# Run a specific test by name
snforge test test_initialization_sets_buyback_token

# Run tests matching a pattern
snforge test test_buy_back

# Run tests with verbose output
snforge test -v

# Format code
scarb fmt

# Check formatting without modifying
scarb fmt --check
```

## Architecture Overview

This is a Cairo library for Starknet that provides autonomous token buybacks via Ekubo's TWAMM (Time-Weighted Average Market Maker). The core design follows OpenZeppelin's component pattern.

### Component Structure

**BuybackComponent** (`src/buyback/buyback.cairo`) - The reusable component containing all buyback logic:
- Creates TWAMM DCA orders on Ekubo to swap any ERC20 for a configured buyback token
- Tracks multiple concurrent orders per sell token using a counter/bookmark pattern
- First buyback for a token mints an Ekubo position; subsequent buybacks reuse it
- Permissionless execution: anyone can call `buy_back()` and `claim_buyback_proceeds()`

**AutonomousBuyback Preset** (`src/presets/autonomous_buyback.cairo`) - A deployable contract combining:
- `BuybackComponent` for buyback functionality
- `OwnableComponent` (OpenZeppelin) for admin access control
- Admin functions (config updates, emergency withdraw) require owner

### Key Interfaces

- `IBuyback` - Permissionless functions: `buy_back()`, `claim_buyback_proceeds()`, view functions
- `IBuybackAdmin` - Owner-only: `set_buyback_order_config()`, `set_treasury()`, `emergency_withdraw_erc20()`

### Storage Naming Convention

All component storage keys are prefixed with `Buyback_` to avoid collisions when embedded.

### Test Organization

- `tests/unit/` - Component behavior tests with mock Ekubo addresses
- `tests/integration/` - Full contract tests including ownership/access control
- `tests/helpers/deployment.cairo` - Contract deployment utilities
- `tests/fixtures/constants.cairo` - Test addresses, mainnet addresses for fork testing, default configs
- `tests/mocks/` - Mock ERC20 for testing

### Dependencies

- `ekubo` - Ekubo Protocol contracts (TWAMM, Positions interfaces)
- `openzeppelin_access` - OwnableComponent
- `openzeppelin_token` - ERC20 interfaces
- `snforge_std` - Testing framework
