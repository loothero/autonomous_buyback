use ekubo::interfaces::extensions::twamm::OrderKey;
use starknet::ContractAddress;

/// Configuration for buyback orders
/// Controls timing constraints and pool fee for DCA orders
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq, Debug)]
pub struct BuybackOrderConfig {
    /// Minimum delay before order can start (0 = can start immediately)
    pub min_delay: u64,
    /// Maximum delay before order must start (0 = must start immediately)
    pub max_delay: u64,
    /// Minimum duration of the buyback order
    pub min_duration: u64,
    /// Maximum duration of the buyback order
    pub max_duration: u64,
    /// Fee tier for the buyback pool
    pub fee: u128,
}

/// Permissionless interface for the Autonomous Buyback component
/// These functions can be called by anyone
#[starknet::interface]
pub trait IBuyback<TContractState> {
    /// Execute a buyback using all tokens of `sell_token` in the contract
    /// Creates a TWAMM DCA order to swap sell_token for the configured buyback_token
    ///
    /// # Arguments
    /// * `sell_token` - The token to sell (must be present in contract balance)
    /// * `end_time` - When the DCA order should complete
    ///
    /// # Panics
    /// - If sell_token equals buyback_token
    /// - If contract has no balance of sell_token
    /// - If end_time violates duration constraints
    fn buy_back(ref self: TContractState, sell_token: ContractAddress, end_time: u64);

    /// Claim proceeds from completed buyback orders and send to treasury
    ///
    /// # Arguments
    /// * `sell_token` - The sell token whose orders to claim
    /// * `limit` - Maximum number of orders to claim (0 = claim all completed)
    ///
    /// # Returns
    /// Total amount of buyback_token claimed
    fn claim_buyback_proceeds(
        ref self: TContractState, sell_token: ContractAddress, limit: u16,
    ) -> u128;

    /// Get the token that will be acquired through buybacks
    fn get_buyback_token(self: @TContractState) -> ContractAddress;

    /// Get the treasury address where proceeds are sent
    fn get_treasury(self: @TContractState) -> ContractAddress;

    /// Get the buyback order configuration
    fn get_buyback_order_config(self: @TContractState) -> BuybackOrderConfig;

    /// Get the Ekubo positions contract address
    fn get_positions_address(self: @TContractState) -> ContractAddress;

    /// Get the TWAMM extension address
    fn get_extension_address(self: @TContractState) -> ContractAddress;

    /// Get the number of orders created for a sell token
    fn get_order_count(self: @TContractState, sell_token: ContractAddress) -> u128;

    /// Get the bookmark (next order to claim) for a sell token
    fn get_order_bookmark(self: @TContractState, sell_token: ContractAddress) -> u128;

    /// Get the number of unclaimed orders for a sell token
    fn get_unclaimed_orders_count(self: @TContractState, sell_token: ContractAddress) -> u128;

    /// Get the position token ID for a sell token (0 if not created)
    fn get_position_token_id(self: @TContractState, sell_token: ContractAddress) -> u64;

    /// Get the end time of a specific order
    fn get_order_end_time(self: @TContractState, sell_token: ContractAddress, index: u128) -> u64;

    /// Construct an OrderKey for a specific order
    fn get_order_key(
        self: @TContractState, sell_token: ContractAddress, start_time: u64, end_time: u64,
    ) -> OrderKey;
}

/// Admin interface for the Autonomous Buyback component
/// These functions should be protected by access control in the embedding contract
#[starknet::interface]
pub trait IBuybackAdmin<TContractState> {
    /// Set the buyback order configuration
    fn set_buyback_order_config(ref self: TContractState, config: BuybackOrderConfig);

    /// Set the treasury address where proceeds are sent
    fn set_treasury(ref self: TContractState, treasury: ContractAddress);

    /// Emergency withdraw ERC20 tokens from the contract
    /// Note: Should only be used for stuck tokens, not mid-DCA orders
    fn emergency_withdraw_erc20(
        ref self: TContractState, token: ContractAddress, amount: u256, recipient: ContractAddress,
    );
}
