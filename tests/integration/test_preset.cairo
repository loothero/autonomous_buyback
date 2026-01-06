/// Integration tests for the AutonomousBuyback preset contract
///
/// These tests verify the complete contract behavior including:
/// - Component embedding and initialization
/// - Owner access control via OwnableComponent
/// - End-to-end buyback flow (where possible without real Ekubo)
use autonomous_buyback::{
    BuybackOrderConfig, IBuybackAdminDispatcher, IBuybackAdminDispatcherTrait, IBuybackDispatcher,
    IBuybackDispatcherTrait,
};
use openzeppelin_interfaces::access::ownable::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin_interfaces::token::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};
use starknet::ContractAddress;
use crate::fixtures::constants::{OWNER, TREASURY, USER1, USER2, amounts, defaults};
use crate::helpers::deployment::{deploy_autonomous_buyback, deploy_mock_erc20};
use crate::mocks::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};

/// Helper to deploy a buyback contract with default config
fn setup_buyback_contract(buyback_token: ContractAddress) -> ContractAddress {
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    deploy_autonomous_buyback(
        OWNER(),
        buyback_token,
        TREASURY(),
        mock_positions,
        mock_extension,
        defaults::default_config(),
    )
}

// ============================================================================
// Ownable Integration Tests
// ============================================================================

#[test]
fn test_owner_is_set_correctly() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let contract = setup_buyback_contract(buyback_token);

    let ownable = IOwnableDispatcher { contract_address: contract };
    assert(ownable.owner() == OWNER(), 'Wrong owner');
}

#[test]
fn test_owner_can_transfer_ownership() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let contract = setup_buyback_contract(buyback_token);

    let ownable = IOwnableDispatcher { contract_address: contract };

    start_cheat_caller_address(contract, OWNER());
    ownable.transfer_ownership(USER1());
    stop_cheat_caller_address(contract);

    assert(ownable.owner() == USER1(), 'Ownership not transferred');
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_non_owner_cannot_set_config() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let contract = setup_buyback_contract(buyback_token);

    // Use the admin dispatcher to call set_buyback_order_config
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };

    // Call as non-owner - should panic
    start_cheat_caller_address(contract, USER1());

    let new_config = BuybackOrderConfig {
        min_delay: 100, max_delay: 200, min_duration: 7200, max_duration: 86400, fee: 1000,
    };

    // This should panic because USER1 is not the owner
    admin_dispatcher.set_buyback_order_config(new_config);
    stop_cheat_caller_address(contract);
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_non_owner_cannot_set_treasury() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let contract = setup_buyback_contract(buyback_token);

    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };

    // Call as non-owner - should panic
    start_cheat_caller_address(contract, USER1());
    admin_dispatcher.set_treasury(USER2());
    stop_cheat_caller_address(contract);
}

// ============================================================================
// Component Function Integration Tests
// ============================================================================

#[test]
fn test_buyback_dispatcher_works() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let contract = setup_buyback_contract(buyback_token);

    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Test all view functions work through dispatcher
    assert(dispatcher.get_buyback_token() == buyback_token, 'Wrong buyback token');
    assert(dispatcher.get_treasury() == TREASURY(), 'Wrong treasury');

    let config = dispatcher.get_buyback_order_config();
    assert(config.min_duration == defaults::MIN_DURATION, 'Wrong min_duration');
}

#[test]
fn test_anyone_can_view_state() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let contract = setup_buyback_contract(buyback_token);

    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Any user should be able to call view functions
    start_cheat_caller_address(contract, USER1());

    let _ = dispatcher.get_buyback_token();
    let _ = dispatcher.get_treasury();
    let _ = dispatcher.get_buyback_order_config();
    let _ = dispatcher.get_positions_address();
    let _ = dispatcher.get_extension_address();
    let _ = dispatcher.get_order_count(sell_token);
    let _ = dispatcher.get_order_bookmark(sell_token);
    let _ = dispatcher.get_unclaimed_orders_count(sell_token);
    let _ = dispatcher.get_position_token_id(sell_token);
    let _ = dispatcher.get_order_key(sell_token, 0, 3600);

    stop_cheat_caller_address(contract);
}

// ============================================================================
// ERC20 Integration Tests
// ============================================================================

#[test]
fn test_contract_can_receive_tokens() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let contract = setup_buyback_contract(buyback_token);

    let sell_token_dispatcher = IERC20Dispatcher { contract_address: sell_token };
    let mock_erc20 = IMockERC20Dispatcher { contract_address: sell_token };

    // Mint tokens to a user
    let deposit_amount: u256 = amounts::THOUSAND_TOKENS;
    mock_erc20.mint(USER1(), deposit_amount);

    // User transfers to contract
    start_cheat_caller_address(sell_token, USER1());
    sell_token_dispatcher.transfer(contract, deposit_amount);
    stop_cheat_caller_address(sell_token);

    // Verify contract received tokens
    assert(
        sell_token_dispatcher.balance_of(contract) == deposit_amount, 'Contract should have tokens',
    );
}

#[test]
fn test_emergency_withdraw_works_e2e() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token = deploy_mock_erc20("Sell", "SELL");
    let contract = setup_buyback_contract(buyback_token);

    let sell_token_dispatcher = IERC20Dispatcher { contract_address: sell_token };
    let mock_erc20 = IMockERC20Dispatcher { contract_address: sell_token };
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };

    // Deposit tokens to contract
    let deposit_amount: u256 = amounts::HUNDRED_TOKENS;
    mock_erc20.mint(contract, deposit_amount);

    // Owner emergency withdraws
    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.emergency_withdraw_erc20(sell_token, deposit_amount, USER2());
    stop_cheat_caller_address(contract);

    // Verify withdrawal
    assert(sell_token_dispatcher.balance_of(contract) == 0, 'Contract should be empty');
    assert(sell_token_dispatcher.balance_of(USER2()) == deposit_amount, 'User2 should have tokens');
}

// ============================================================================
// Multiple Token Tests
// ============================================================================

#[test]
fn test_can_track_multiple_sell_tokens() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let sell_token_1 = deploy_mock_erc20("Sell1", "SELL1");
    let sell_token_2 = deploy_mock_erc20("Sell2", "SELL2");
    let contract = setup_buyback_contract(buyback_token);

    let dispatcher = IBuybackDispatcher { contract_address: contract };

    // Each sell token should have independent state
    assert(dispatcher.get_order_count(sell_token_1) == 0, 'Token1 count should be 0');
    assert(dispatcher.get_order_count(sell_token_2) == 0, 'Token2 count should be 0');
    assert(dispatcher.get_position_token_id(sell_token_1) == 0, 'Token1 pos should be 0');
    assert(dispatcher.get_position_token_id(sell_token_2) == 0, 'Token2 pos should be 0');

    // Order keys should be different for different sell tokens
    let key1 = dispatcher.get_order_key(sell_token_1, 0, 3600);
    let key2 = dispatcher.get_order_key(sell_token_2, 0, 3600);

    assert(key1.sell_token != key2.sell_token, 'Keys should differ');
    assert(key1.buy_token == key2.buy_token, 'Buy token should match');
}

// ============================================================================
// Configuration Boundary Tests
// ============================================================================

#[test]
fn test_config_allows_zero_delays() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let contract = setup_buyback_contract(buyback_token);

    let dispatcher = IBuybackDispatcher { contract_address: contract };
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };

    // Config with zero delays (orders can/must start immediately)
    let config_zero_delays = BuybackOrderConfig {
        min_delay: 0, max_delay: 0, min_duration: 3600, max_duration: 86400, fee: 1000,
    };

    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.set_buyback_order_config(config_zero_delays);
    stop_cheat_caller_address(contract);

    let updated = dispatcher.get_buyback_order_config();
    assert(updated.min_delay == 0, 'min_delay should be 0');
    assert(updated.max_delay == 0, 'max_delay should be 0');
}

#[test]
fn test_config_allows_equal_min_max_duration() {
    let buyback_token = deploy_mock_erc20("Buyback", "BUY");
    let contract = setup_buyback_contract(buyback_token);

    let dispatcher = IBuybackDispatcher { contract_address: contract };
    let admin_dispatcher = IBuybackAdminDispatcher { contract_address: contract };

    // Config where min == max duration (exact duration required)
    let exact_duration: u64 = 7200;
    let config_exact = BuybackOrderConfig {
        min_delay: 0,
        max_delay: 0,
        min_duration: exact_duration,
        max_duration: exact_duration,
        fee: 1000,
    };

    start_cheat_caller_address(contract, OWNER());
    admin_dispatcher.set_buyback_order_config(config_exact);
    stop_cheat_caller_address(contract);

    let updated = dispatcher.get_buyback_order_config();
    assert(updated.min_duration == exact_duration, 'min wrong');
    assert(updated.max_duration == exact_duration, 'max wrong');
}
