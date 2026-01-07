use ekubo::interfaces::extensions::twamm::OrderKey;
use starknet::ContractAddress;

/// Global configuration defaults that apply when no per-token override exists
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq, Debug)]
pub struct GlobalBuybackConfig {
    /// Default token to acquire (can be overridden per sell token)
    pub default_buy_token: ContractAddress,
    /// Default treasury address where proceeds are sent
    pub default_treasury: ContractAddress,
}

/// Per-token configuration for buyback orders
/// Allows different settings per sell token with flexible overrides
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq, Debug)]
pub struct TokenBuybackConfig {
    /// Token to acquire through buybacks
    pub buy_token: ContractAddress,
    /// Where proceeds are sent
    pub treasury: ContractAddress,
    /// Minimum balance required to start a buyback (prevents spam/griefing)
    pub minimum_amount: u128,
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

/// Parameters for creating a buyback order
#[derive(Copy, Drop, Serde)]
pub struct BuybackParams {
    /// The token to sell
    pub sell_token: ContractAddress,
    /// When the order should start (0 = start immediately)
    pub start_time: u64,
    /// When the DCA order should complete
    pub end_time: u64,
}

/// Information about a specific buyback order
/// Stored for each order to enable proper claiming
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq, Debug)]
pub struct OrderInfo {
    /// When the order started
    pub start_time: u64,
    /// When the order ends
    pub end_time: u64,
    /// Amount of sell token in the order
    pub amount: u128,
    /// Token being acquired
    pub buy_token: ContractAddress,
    /// Pool fee tier
    pub fee: u128,
}

/// Permissionless interface for the Autonomous Buyback component
/// These functions can be called by anyone
#[starknet::interface]
pub trait IBuyback<TContractState> {
    /// Execute a buyback using all tokens of `sell_token` in the contract
    /// Creates a TWAMM DCA order to swap sell_token for the configured buy_token
    ///
    /// # Arguments
    /// * `params` - Buyback parameters (sell_token, start_time, end_time)
    ///
    /// # Panics
    /// - If sell_token equals the configured buy_token
    /// - If contract balance is below minimum_amount
    /// - If timing constraints are violated
    fn buy_back(ref self: TContractState, params: BuybackParams);

    /// Claim proceeds from completed buyback orders and send to treasury
    ///
    /// # Arguments
    /// * `sell_token` - The sell token whose orders to claim
    /// * `limit` - Maximum number of orders to claim (0 = claim all completed)
    ///
    /// # Returns
    /// Total amount of buy_token claimed
    ///
    /// # Panics
    /// - If no orders exist for the sell token
    /// - If no orders have completed yet
    fn claim_buyback_proceeds(
        ref self: TContractState, sell_token: ContractAddress, limit: u16,
    ) -> u128;

    /// Get the global configuration defaults
    fn get_global_config(self: @TContractState) -> GlobalBuybackConfig;

    /// Get the per-token configuration (None if not set)
    fn get_token_config(
        self: @TContractState, sell_token: ContractAddress,
    ) -> Option<TokenBuybackConfig>;

    /// Get the effective configuration for a sell token
    /// Returns the per-token config if set, otherwise builds from global defaults
    fn get_effective_config(
        self: @TContractState, sell_token: ContractAddress,
    ) -> TokenBuybackConfig;

    /// Get the Ekubo positions contract address
    fn get_positions_address(self: @TContractState) -> ContractAddress;

    /// Get the TWAMM extension address
    fn get_extension_address(self: @TContractState) -> ContractAddress;

    /// Get the position token ID for a sell token (0 if not created)
    fn get_position_token_id(self: @TContractState, sell_token: ContractAddress) -> u64;

    /// Get the number of orders created for a sell token
    fn get_order_count(self: @TContractState, sell_token: ContractAddress) -> u128;

    /// Get the bookmark (next order to claim) for a sell token
    fn get_order_bookmark(self: @TContractState, sell_token: ContractAddress) -> u128;

    /// Get the number of unclaimed orders for a sell token
    fn get_unclaimed_orders_count(self: @TContractState, sell_token: ContractAddress) -> u128;

    /// Get information about a specific order
    fn get_order_info(self: @TContractState, sell_token: ContractAddress, index: u128) -> OrderInfo;

    /// Construct an OrderKey for a specific order index
    fn get_order_key(self: @TContractState, sell_token: ContractAddress, index: u128) -> OrderKey;
}

/// Admin interface for the Autonomous Buyback component
/// These functions should be protected by access control in the embedding contract
#[starknet::interface]
pub trait IBuybackAdmin<TContractState> {
    /// Set the global configuration defaults
    fn set_global_config(ref self: TContractState, config: GlobalBuybackConfig);

    /// Set or clear per-token configuration
    /// None = use global defaults, Some = override with specific config
    fn set_token_config(
        ref self: TContractState, sell_token: ContractAddress, config: Option<TokenBuybackConfig>,
    );
}
