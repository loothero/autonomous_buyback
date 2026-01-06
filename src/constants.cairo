/// Error codes for the Autonomous Buyback component
pub mod Errors {
    pub const INVALID_BUYBACK_TOKEN: felt252 = 'Invalid buyback token';
    pub const INVALID_TREASURY: felt252 = 'Invalid treasury address';
    pub const INVALID_POSITIONS_ADDRESS: felt252 = 'Invalid positions address';
    pub const INVALID_EXTENSION_ADDRESS: felt252 = 'Invalid extension address';
    pub const INVALID_SELL_TOKEN: felt252 = 'Invalid sell token';
    pub const SELL_TOKEN_IS_BUYBACK_TOKEN: felt252 = 'Sell token is buyback token';
    pub const NO_BALANCE_TO_BUYBACK: felt252 = 'No balance to buyback';
    pub const END_TIME_IN_PAST: felt252 = 'End time must be in future';
    pub const DURATION_TOO_SHORT: felt252 = 'Duration too short';
    pub const DURATION_TOO_LONG: felt252 = 'Duration too long';
    pub const START_DELAY_TOO_SHORT: felt252 = 'Start delay too short';
    pub const START_DELAY_TOO_LONG: felt252 = 'Start delay too long';
    pub const NO_ORDERS_TO_CLAIM: felt252 = 'No orders to claim';
    pub const NO_PROCEEDS_TO_CLAIM: felt252 = 'No proceeds to claim';
    pub const POSITION_NOT_INITIALIZED: felt252 = 'Position not initialized';
    pub const ALREADY_INITIALIZED: felt252 = 'Already initialized';
    pub const NOT_INITIALIZED: felt252 = 'Not initialized';
}

/// TWAMM-related constants
/// Maximum tick spacing allowed by Ekubo TWAMM
pub const TWAMM_TICK_SPACING: u128 = 354892;
