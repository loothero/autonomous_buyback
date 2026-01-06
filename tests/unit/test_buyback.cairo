/// Unit tests for the BuybackComponent
///
/// These tests verify the component's behavior in isolation using mock contracts
/// and direct component state testing where possible.
use autonomous_buyback::{
    BuybackOrderConfig, IBuybackAdminDispatcher, IBuybackAdminDispatcherTrait, IBuybackDispatcher,
    IBuybackDispatcherTrait,
};
use openzeppelin_interfaces::token::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    EventSpyTrait, spy_events, start_cheat_block_timestamp_global, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;
use crate::fixtures::constants::{OWNER, TREASURY, USER1, USER2, ZERO_ADDRESS, amounts, defaults};
use crate::helpers::deployment::{deploy_autonomous_buyback, deploy_mock_erc20};
use crate::mocks::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};

/// Helper to deploy a buyback contract with default config
fn setup_buyback_contract(
    buyback_token: ContractAddress, positions: ContractAddress, extension: ContractAddress,
) -> ContractAddress {
    deploy_autonomous_buyback(
        OWNER(), buyback_token, TREASURY(), positions, extension, defaults::default_config(),
    )
}

// ============================================================================
// Initialization Tests
// ============================================================================

#[test]
fn test_initialization_sets_buyback_token() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    assert(dispatcher.get_buyback_token() == buyback_token, 'Wrong buyback token');
}

#[test]
fn test_initialization_sets_treasury() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    assert(dispatcher.get_treasury() == TREASURY(), 'Wrong treasury');
}

#[test]
fn test_initialization_sets_positions_address() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    assert(dispatcher.get_positions_address() == mock_positions, 'Wrong positions address');
}

#[test]
fn test_initialization_sets_extension_address() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    assert(dispatcher.get_extension_address() == mock_extension, 'Wrong extension address');
}

#[test]
fn test_initialization_sets_order_config() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    let config = dispatcher.get_buyback_order_config();
    let expected = defaults::default_config();

    assert(config.min_duration == expected.min_duration, 'Wrong min_duration');
    assert(config.max_duration == expected.max_duration, 'Wrong max_duration');
    assert(config.fee == expected.fee, 'Wrong fee');
}

#[test]
fn test_initial_order_count_is_zero() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    assert(dispatcher.get_order_count(sell_token) == 0, 'Order count should be 0');
    assert(dispatcher.get_order_bookmark(sell_token) == 0, 'Bookmark should be 0');
    assert(dispatcher.get_position_token_id(sell_token) == 0, 'Position ID should be 0');
}

// ============================================================================
// Configuration Update Tests
// ============================================================================

#[test]
fn test_owner_can_update_config() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let dispatcher = IBuybackDispatcher { contract_address: contract };
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };

    let new_config = BuybackOrderConfig {
        min_delay: 100, max_delay: 200, min_duration: 7200, max_duration: 86400, fee: 1000,
    };

    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.set_buyback_order_config(new_config);
    stop_cheat_caller_address(contract);

    let updated_config = dispatcher.get_buyback_order_config();
    assert(updated_config.min_delay == 100, 'Wrong min_delay');
    assert(updated_config.max_delay == 200, 'Wrong max_delay');
    assert(updated_config.min_duration == 7200, 'Wrong min_duration');
    assert(updated_config.max_duration == 86400, 'Wrong max_duration');
    assert(updated_config.fee == 1000, 'Wrong fee');
}

#[test]
fn test_owner_can_update_treasury() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let dispatcher = IBuybackDispatcher { contract_address: contract };
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };

    let new_treasury = USER2();

    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.set_treasury(new_treasury);
    stop_cheat_caller_address(contract);

    assert(dispatcher.get_treasury() == new_treasury, 'Treasury not updated');
}

#[test]
#[should_panic(expected: 'Invalid treasury address')]
fn test_set_treasury_rejects_zero_address() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };

    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.set_treasury(ZERO_ADDRESS());
}

// ============================================================================
// View Function Tests
// ============================================================================

#[test]
fn test_get_unclaimed_orders_count() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Initially should be 0
    assert(dispatcher.get_unclaimed_orders_count(sell_token) == 0, 'Should be 0 unclaimed');
}

#[test]
fn test_get_order_key_constructs_correctly() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    let start_time: u64 = 0;
    let end_time: u64 = 3600;

    let order_key = dispatcher.get_order_key(sell_token, start_time, end_time);

    assert(order_key.sell_token == sell_token, 'Wrong sell_token');
    assert(order_key.buy_token == buyback_token, 'Wrong buy_token');
    assert(order_key.start_time == start_time, 'Wrong start_time');
    assert(order_key.end_time == end_time, 'Wrong end_time');

    let config = dispatcher.get_buyback_order_config();
    assert(order_key.fee == config.fee, 'Wrong fee');
}

// ============================================================================
// Emergency Withdrawal Tests
// ============================================================================

#[test]
fn test_owner_can_emergency_withdraw() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };
    let sell_token_dispatcher = IERC20Dispatcher { contract_address: sell_token };
    let mock_erc20 = IMockERC20Dispatcher { contract_address: sell_token };

    // Mint some tokens to the contract
    let deposit_amount: u256 = amounts::HUNDRED_TOKENS;
    mock_erc20.mint(contract, deposit_amount);

    assert(sell_token_dispatcher.balance_of(contract) == deposit_amount, 'Wrong initial balance');

    // Emergency withdraw
    let recipient = USER1();
    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.emergency_withdraw_erc20(sell_token, deposit_amount, recipient);
    stop_cheat_caller_address(contract);

    assert(sell_token_dispatcher.balance_of(contract) == 0, 'Contract should be empty');
    assert(
        sell_token_dispatcher.balance_of(recipient) == deposit_amount,
        'Recipient should have tokens',
    );
}

#[test]
#[should_panic(expected: 'Invalid treasury address')]
fn test_emergency_withdraw_rejects_zero_recipient() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };

    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.emergency_withdraw_erc20(sell_token, amounts::ONE_TOKEN, ZERO_ADDRESS());
}

// ============================================================================
// Buy Back Validation Tests
// ============================================================================

#[test]
#[should_panic(expected: 'Invalid sell token')]
fn test_buy_back_rejects_zero_sell_token() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Set block timestamp
    start_cheat_block_timestamp_global(1000);

    let end_time: u64 = 1000 + defaults::MIN_DURATION + 100;
    dispatcher.buy_back(ZERO_ADDRESS(), end_time);
}

#[test]
#[should_panic(expected: 'Sell token is buyback token')]
fn test_buy_back_rejects_same_tokens() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Set block timestamp
    start_cheat_block_timestamp_global(1000);

    let end_time: u64 = 1000 + defaults::MIN_DURATION + 100;

    // Try to use buyback_token as sell_token (should fail)
    dispatcher.buy_back(buyback_token, end_time);
}

#[test]
#[should_panic(expected: 'End time must be in future')]
fn test_buy_back_rejects_past_end_time() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Set block timestamp to 2000
    start_cheat_block_timestamp_global(2000);

    // Try with end_time in the past
    let end_time: u64 = 1000;
    dispatcher.buy_back(sell_token, end_time);
}

#[test]
#[should_panic(expected: 'Duration too short')]
fn test_buy_back_rejects_duration_too_short() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Set block timestamp
    start_cheat_block_timestamp_global(1000);

    // End time that creates duration less than min_duration
    let end_time: u64 = 1000 + defaults::MIN_DURATION - 1;
    dispatcher.buy_back(sell_token, end_time);
}

#[test]
#[should_panic(expected: 'Duration too long')]
fn test_buy_back_rejects_duration_too_long() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Set block timestamp
    start_cheat_block_timestamp_global(1000);

    // End time that creates duration more than max_duration
    let end_time: u64 = 1000 + defaults::MAX_DURATION + 1;
    dispatcher.buy_back(sell_token, end_time);
}

#[test]
#[should_panic(expected: 'No balance to buyback')]
fn test_buy_back_rejects_zero_balance() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Set block timestamp
    start_cheat_block_timestamp_global(1000);

    // Valid end time but no balance
    let end_time: u64 = 1000 + defaults::MIN_DURATION + 100;
    dispatcher.buy_back(sell_token, end_time);
}

// ============================================================================
// Claim Proceeds Validation Tests
// ============================================================================

#[test]
#[should_panic(expected: 'Position not initialized')]
fn test_claim_proceeds_rejects_uninitialized_position() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Try to claim without any buyback orders
    dispatcher.claim_buyback_proceeds(sell_token, 0);
}

// ============================================================================
// Event Emission Tests
// ============================================================================

#[test]
fn test_config_update_emits_event() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };

    let mut spy = spy_events();

    let new_config = BuybackOrderConfig {
        min_delay: 100, max_delay: 200, min_duration: 7200, max_duration: 86400, fee: 1000,
    };

    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.set_buyback_order_config(new_config);
    stop_cheat_caller_address(contract);

    // Verify event was emitted (we can check it was emitted without exact matching)
    let events = spy.get_events();
    assert(events.events.len() > 0, 'Should emit event');
}

#[test]
fn test_treasury_update_emits_event() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    let contract = setup_buyback_contract(buyback_token, mock_positions, mock_extension);
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };

    let mut spy = spy_events();

    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.set_treasury(USER2());
    stop_cheat_caller_address(contract);

    // Verify event was emitted
    let events = spy.get_events();
    assert(events.events.len() > 0, 'Should emit event');
}
