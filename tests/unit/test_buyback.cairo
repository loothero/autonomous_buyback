/// Unit tests for the BuybackComponent v2
///
/// These tests verify the component's behavior in isolation using mock contracts
/// and direct component state testing where possible.
use autonomous_buyback::{
    BuybackParams, GlobalBuybackConfig, IBuybackAdminDispatcher, IBuybackAdminDispatcherTrait,
    IBuybackDispatcher, IBuybackDispatcherTrait, TokenBuybackConfig,
};
use snforge_std::{
    EventSpyTrait, spy_events, start_cheat_block_timestamp_global, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;
use crate::fixtures::constants::{OWNER, TREASURY, ZERO_ADDRESS, amounts, defaults};
use crate::helpers::deployment::{deploy_autonomous_buyback, deploy_mock_erc20};
use crate::mocks::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};

/// Helper to deploy a buyback contract with default config
fn setup_buyback_contract(buyback_token: ContractAddress) -> ContractAddress {
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let global_config = defaults::global_config_with(buyback_token, TREASURY());
    deploy_autonomous_buyback(OWNER(), global_config, mock_positions, mock_extension)
}

/// Helper to setup a buyback contract with default token config for a sell token
/// This is needed for tests that require duration validation
fn setup_buyback_with_token_config(
    buyback_token: ContractAddress, sell_token: ContractAddress,
) -> ContractAddress {
    let contract = setup_buyback_contract(buyback_token);
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };

    // Set default token config with proper duration limits
    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.set_token_config(sell_token, Option::Some(defaults::default_token_config()));
    stop_cheat_caller_address(contract);

    contract
}

// ============================================================================
// Initialization Tests
// ============================================================================

#[test]
fn test_initialization_sets_buyback_token() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    let config = dispatcher.get_global_config();
    assert(config.default_buy_token == buyback_token, 'Wrong buyback token');
}

#[test]
fn test_initialization_sets_treasury() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    let config = dispatcher.get_global_config();
    assert(config.default_treasury == TREASURY(), 'Wrong treasury');
}

#[test]
fn test_initialization_sets_positions_address() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    assert(dispatcher.get_positions_address() == mock_positions, 'Wrong positions address');
}

#[test]
fn test_initialization_sets_extension_address() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();
    assert(dispatcher.get_extension_address() == mock_extension, 'Wrong extension address');
}

#[test]
fn test_initial_order_count_is_zero() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    assert(dispatcher.get_order_count(sell_token) == 0, 'Order count should be 0');
    assert(dispatcher.get_order_bookmark(sell_token) == 0, 'Bookmark should be 0');
    assert(dispatcher.get_position_token_id(sell_token) == 0, 'Position ID should be 0');
}

#[test]
fn test_initial_token_config_is_none() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    assert(dispatcher.get_token_config(sell_token).is_none(), 'Should have no token config');
}

// ============================================================================
// Global Configuration Tests
// ============================================================================

#[test]
fn test_owner_can_update_global_config() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };

    let new_treasury: ContractAddress = 'NEW_TREASURY'.try_into().unwrap();
    let new_config = GlobalBuybackConfig {
        default_buy_token: buyback_token, default_treasury: new_treasury,
    };

    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.set_global_config(new_config);
    stop_cheat_caller_address(contract);

    let updated_config = dispatcher.get_global_config();
    assert(updated_config.default_treasury == new_treasury, 'Treasury not updated');
}

#[test]
fn test_global_config_update_emits_event() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let contract = setup_buyback_contract(buyback_token);
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };

    let mut spy = spy_events();

    let new_treasury: ContractAddress = 'NEW_TREASURY'.try_into().unwrap();
    let new_config = GlobalBuybackConfig {
        default_buy_token: buyback_token, default_treasury: new_treasury,
    };

    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.set_global_config(new_config);
    stop_cheat_caller_address(contract);

    let events = spy.get_events();
    assert(events.events.len() > 0, 'Should emit event');
}

// ============================================================================
// Per-Token Configuration Tests
// ============================================================================

#[test]
fn test_owner_can_set_token_config() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };

    let token_config = defaults::token_config_with_minimum(1000);

    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.set_token_config(sell_token, Option::Some(token_config));
    stop_cheat_caller_address(contract);

    let retrieved = dispatcher.get_token_config(sell_token);
    assert(retrieved.is_some(), 'Should have token config');

    let config = retrieved.unwrap();
    assert(config.minimum_amount == 1000, 'Wrong minimum amount');
}

#[test]
fn test_owner_can_clear_token_config() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };

    // Set then clear
    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.set_token_config(sell_token, Option::Some(defaults::default_token_config()));
    admin_dispatcher.set_token_config(sell_token, Option::None);
    stop_cheat_caller_address(contract);

    assert(dispatcher.get_token_config(sell_token).is_none(), 'Should be None after clear');
}

#[test]
fn test_token_config_update_emits_event() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let contract = setup_buyback_contract(buyback_token);
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };

    let mut spy = spy_events();

    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.set_token_config(sell_token, Option::Some(defaults::default_token_config()));
    stop_cheat_caller_address(contract);

    let events = spy.get_events();
    assert(events.events.len() > 0, 'Should emit event');
}

// ============================================================================
// Effective Configuration Tests
// ============================================================================

#[test]
fn test_effective_config_uses_global_defaults() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    let effective = dispatcher.get_effective_config(sell_token);

    // Should use global defaults
    assert(effective.buy_token == buyback_token, 'Should use global buy token');
    assert(effective.treasury == TREASURY(), 'Should use global treasury');
}

#[test]
fn test_effective_config_uses_override_when_set() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let new_treasury: ContractAddress = 'NEW_TREASURY'.try_into().unwrap();
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };

    // Set per-token override
    let token_config = TokenBuybackConfig {
        buy_token: buyback_token,
        treasury: new_treasury,
        minimum_amount: 500,
        min_delay: 0,
        max_delay: 0,
        min_duration: 3600,
        max_duration: 86400,
        fee: defaults::DEFAULT_FEE,
    };

    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.set_token_config(sell_token, Option::Some(token_config));
    stop_cheat_caller_address(contract);

    let effective = dispatcher.get_effective_config(sell_token);

    // Should use override
    assert(effective.treasury == new_treasury, 'Should use override treasury');
    assert(effective.minimum_amount == 500, 'Should use override minimum');
}

// ============================================================================
// View Function Tests
// ============================================================================

#[test]
fn test_get_unclaimed_orders_count() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Initially should be 0
    assert(dispatcher.get_unclaimed_orders_count(sell_token) == 0, 'Should be 0 unclaimed');
}

// ============================================================================
// Buy Back Validation Tests (using BuybackParams)
// ============================================================================

#[test]
#[should_panic(expected: 'Invalid sell token')]
fn test_buy_back_rejects_zero_sell_token() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Set block timestamp
    start_cheat_block_timestamp_global(1000);

    let params = BuybackParams {
        sell_token: ZERO_ADDRESS(), start_time: 0, end_time: 1000 + defaults::MIN_DURATION + 100,
    };
    dispatcher.buy_back(params);
}

#[test]
#[should_panic(expected: 'Sell token is buy token')]
fn test_buy_back_rejects_same_tokens() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Set block timestamp
    start_cheat_block_timestamp_global(1000);

    let params = BuybackParams {
        sell_token: buyback_token, start_time: 0, end_time: 1000 + defaults::MIN_DURATION + 100,
    };
    // Try to use buyback_token as sell_token (should fail)
    dispatcher.buy_back(params);
}

#[test]
#[should_panic(expected: 'End time invalid')]
fn test_buy_back_rejects_past_end_time() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let contract = setup_buyback_with_token_config(buyback_token, sell_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Set block timestamp to 2000
    start_cheat_block_timestamp_global(2000);

    // Try with end_time in the past (end_time <= actual_start)
    let params = BuybackParams { sell_token, start_time: 0, end_time: 1000 };
    dispatcher.buy_back(params);
}

#[test]
#[should_panic(expected: 'Duration too short')]
fn test_buy_back_rejects_duration_too_short() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let contract = setup_buyback_with_token_config(buyback_token, sell_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Set block timestamp
    start_cheat_block_timestamp_global(1000);

    // End time that creates duration less than min_duration
    let params = BuybackParams {
        sell_token, start_time: 0, end_time: 1000 + defaults::MIN_DURATION - 1,
    };
    dispatcher.buy_back(params);
}

#[test]
#[should_panic(expected: 'Duration too long')]
fn test_buy_back_rejects_duration_too_long() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let contract = setup_buyback_with_token_config(buyback_token, sell_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Set block timestamp
    start_cheat_block_timestamp_global(1000);

    // End time that creates duration more than max_duration
    let params = BuybackParams {
        sell_token, start_time: 0, end_time: 1000 + defaults::MAX_DURATION + 1,
    };
    dispatcher.buy_back(params);
}

#[test]
#[should_panic(expected: 'No balance to buyback')]
fn test_buy_back_rejects_zero_balance() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let contract = setup_buyback_with_token_config(buyback_token, sell_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Set block timestamp
    start_cheat_block_timestamp_global(1000);

    // Valid end time but no balance
    let params = BuybackParams {
        sell_token, start_time: 0, end_time: 1000 + defaults::MIN_DURATION + 100,
    };
    dispatcher.buy_back(params);
}

#[test]
#[should_panic(expected: 'Amount below minimum')]
fn test_buy_back_rejects_amount_below_minimum() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };
    let mock_erc20 = IMockERC20Dispatcher { contract_address: sell_token };

    // Set a minimum amount requirement
    let token_config = defaults::token_config_with_minimum(1000);
    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.set_token_config(sell_token, Option::Some(token_config));
    stop_cheat_caller_address(contract);

    // Mint less than minimum
    mock_erc20.mint(contract, 500);

    // Set block timestamp
    start_cheat_block_timestamp_global(1000);

    // Should fail due to amount below minimum
    let params = BuybackParams {
        sell_token, start_time: 0, end_time: 1000 + defaults::MIN_DURATION + 100,
    };
    dispatcher.buy_back(params);
}

// ============================================================================
// Delayed Start Validation Tests
// ============================================================================

#[test]
#[should_panic(expected: 'Start time too soon')]
fn test_buy_back_rejects_start_too_soon_when_min_delay_set() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };
    let mock_erc20 = IMockERC20Dispatcher { contract_address: sell_token };

    // Set a min_delay requirement
    let token_config = defaults::token_config_with_delay(100, 1000);
    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.set_token_config(sell_token, Option::Some(token_config));
    stop_cheat_caller_address(contract);

    // Mint tokens
    mock_erc20.mint(contract, amounts::THOUSAND_TOKENS);

    // Set block timestamp
    start_cheat_block_timestamp_global(1000);

    // Try to start immediately (start_time = 0) when min_delay is set
    let params = BuybackParams {
        sell_token, start_time: 0, end_time: 1000 + defaults::MIN_DURATION + 100,
    };
    dispatcher.buy_back(params);
}

#[test]
#[should_panic(expected: 'Delay too short')]
fn test_buy_back_rejects_delay_too_short() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };
    let mock_erc20 = IMockERC20Dispatcher { contract_address: sell_token };

    // Set a min_delay requirement of 100 seconds
    let token_config = defaults::token_config_with_delay(100, 1000);
    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.set_token_config(sell_token, Option::Some(token_config));
    stop_cheat_caller_address(contract);

    // Mint tokens
    mock_erc20.mint(contract, amounts::THOUSAND_TOKENS);

    // Set block timestamp
    start_cheat_block_timestamp_global(1000);

    // Try to start with only 50 second delay (less than min_delay of 100)
    let params = BuybackParams {
        sell_token,
        start_time: 1050, // only 50 seconds in future
        end_time: 1050 + defaults::MIN_DURATION + 100,
    };
    dispatcher.buy_back(params);
}

#[test]
#[should_panic(expected: 'Delay too long')]
fn test_buy_back_rejects_delay_too_long() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };
    let mock_erc20 = IMockERC20Dispatcher { contract_address: sell_token };

    // Set a max_delay requirement of 1000 seconds
    let token_config = defaults::token_config_with_delay(100, 1000);
    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.set_token_config(sell_token, Option::Some(token_config));
    stop_cheat_caller_address(contract);

    // Mint tokens
    mock_erc20.mint(contract, amounts::THOUSAND_TOKENS);

    // Set block timestamp
    start_cheat_block_timestamp_global(1000);

    // Try to start with 2000 second delay (more than max_delay of 1000)
    let params = BuybackParams {
        sell_token,
        start_time: 3000, // 2000 seconds in future
        end_time: 3000 + defaults::MIN_DURATION + 100,
    };
    dispatcher.buy_back(params);
}

// ============================================================================
// Claim Proceeds Validation Tests
// ============================================================================

#[test]
#[should_panic(expected: 'Position not initialized')]
fn test_claim_proceeds_rejects_uninitialized_position() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Try to claim without any buyback orders
    dispatcher.claim_buyback_proceeds(sell_token, 0);
}

// ============================================================================
// Multiple Token Isolation Tests
// ============================================================================

#[test]
fn test_different_tokens_have_separate_order_counts() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token_1 = deploy_mock_erc20("Sell1", "SELL1");
    let sell_token_2 = deploy_mock_erc20("Sell2", "SELL2");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Each sell token should have independent counters
    assert(dispatcher.get_order_count(sell_token_1) == 0, 'Token1 count should be 0');
    assert(dispatcher.get_order_count(sell_token_2) == 0, 'Token2 count should be 0');
    assert(dispatcher.get_order_bookmark(sell_token_1) == 0, 'Token1 bookmark should be 0');
    assert(dispatcher.get_order_bookmark(sell_token_2) == 0, 'Token2 bookmark should be 0');
}

#[test]
fn test_different_tokens_can_have_different_configs() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token_1 = deploy_mock_erc20("Sell1", "SELL1");
    let sell_token_2 = deploy_mock_erc20("Sell2", "SELL2");
    let contract = setup_buyback_contract(buyback_token);
    let dispatcher = IBuybackDispatcher { contract_address: contract };
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };

    // Set different configs for each token
    let config_1 = defaults::token_config_with_minimum(100);
    let config_2 = defaults::token_config_with_minimum(500);

    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.set_token_config(sell_token_1, Option::Some(config_1));
    admin_dispatcher.set_token_config(sell_token_2, Option::Some(config_2));
    stop_cheat_caller_address(contract);

    // Verify each token has its own config
    let effective_1 = dispatcher.get_effective_config(sell_token_1);
    let effective_2 = dispatcher.get_effective_config(sell_token_2);

    assert(effective_1.minimum_amount == 100, 'Token1 wrong minimum');
    assert(effective_2.minimum_amount == 500, 'Token2 wrong minimum');
}
