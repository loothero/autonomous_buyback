/// Error codes for the Autonomous Buyback component
pub mod Errors {
    // Initialization errors
    pub const INVALID_BUY_TOKEN: felt252 = 'Invalid buy token';
    pub const INVALID_TREASURY: felt252 = 'Invalid treasury address';
    pub const INVALID_POSITIONS_ADDRESS: felt252 = 'Invalid positions address';
    pub const INVALID_EXTENSION_ADDRESS: felt252 = 'Invalid extension address';
    pub const ALREADY_INITIALIZED: felt252 = 'Already initialized';
    pub const NOT_INITIALIZED: felt252 = 'Not initialized';

    // Buy back errors
    pub const INVALID_SELL_TOKEN: felt252 = 'Invalid sell token';
    pub const SELL_TOKEN_IS_BUY_TOKEN: felt252 = 'Sell token is buy token';
    pub const NO_BALANCE_TO_BUYBACK: felt252 = 'No balance to buyback';
    pub const AMOUNT_BELOW_MINIMUM: felt252 = 'Amount below minimum';
    pub const BALANCE_OVERFLOW: felt252 = 'Balance overflow';

    // Timing errors
    pub const END_TIME_IN_PAST: felt252 = 'End time must be in future';
    pub const END_TIME_INVALID: felt252 = 'End time invalid';
    pub const DURATION_TOO_SHORT: felt252 = 'Duration too short';
    pub const DURATION_TOO_LONG: felt252 = 'Duration too long';
    pub const START_TIME_TOO_SOON: felt252 = 'Start time too soon';
    pub const DELAY_TOO_SHORT: felt252 = 'Delay too short';
    pub const DELAY_TOO_LONG: felt252 = 'Delay too long';

    // Claim errors
    pub const NO_ORDERS_TO_CLAIM: felt252 = 'No orders to claim';
    pub const NO_COMPLETED_ORDERS: felt252 = 'No completed orders';
    pub const POSITION_NOT_INITIALIZED: felt252 = 'Position not initialized';
}

/// TWAMM-related constants
/// Maximum tick spacing allowed by Ekubo TWAMM
pub const TWAMM_TICK_SPACING: u128 = 354892;
