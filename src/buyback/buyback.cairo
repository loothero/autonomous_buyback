/// Autonomous Buyback Component v2
///
/// A reusable Cairo component that enables permissionless buybacks of any ERC20 token
/// deposited into the contract via Ekubo's TWAMM DCA orders.
///
/// # Features
/// - Permissionless buyback execution: Anyone can trigger buybacks
/// - Per-token configuration: Different settings per sell token with global defaults
/// - Delayed start support: Orders can be scheduled for future execution
/// - Minimum amount threshold: Prevents spam/griefing attacks
/// - Multiple concurrent orders: Supports multiple DCA orders per sell token
/// - Automatic position creation: First buyback creates the Ekubo position per token
/// - Append-only design: No emergency functions, predictable behavior
///
/// # Usage
/// Embed this component in a contract with OwnableComponent for access control.
#[starknet::component]
pub mod BuybackComponent {
    use core::cmp::max;
    use core::num::traits::Zero;
    use ekubo::interfaces::extensions::twamm::OrderKey;
    use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
    use openzeppelin_interfaces::token::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_contract_address};
    use crate::buyback::interface::{
        BuybackParams, GlobalBuybackConfig, OrderInfo, TokenBuybackConfig,
    };
    use crate::constants::Errors;

    /// Storage for the Buyback component
    /// All storage keys are prefixed with `Buyback_` to avoid collisions
    #[storage]
    pub struct Storage {
        /// Global configuration defaults
        Buyback_global_config: GlobalBuybackConfig,
        /// Ekubo positions contract dispatcher
        Buyback_positions_dispatcher: IPositionsDispatcher,
        /// TWAMM extension address
        Buyback_extension_address: ContractAddress,
        /// Per-token configuration overrides (None = use global defaults)
        Buyback_token_config: Map<ContractAddress, Option<TokenBuybackConfig>>,
        /// Position token ID per sell token (0 if not created)
        Buyback_position_token_id: Map<ContractAddress, u64>,
        /// Number of orders created per sell token
        Buyback_order_counter: Map<ContractAddress, u128>,
        /// Bookmark for claiming (next order to claim) per sell token
        Buyback_order_bookmark: Map<ContractAddress, u128>,
        /// Full order info: (sell_token, index) -> OrderInfo
        Buyback_orders: Map<(ContractAddress, u128), OrderInfo>,
    }

    /// Events emitted by the Buyback component
    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        BuybackStarted: BuybackStarted,
        BuybackProceeds: BuybackProceeds,
        GlobalConfigUpdated: GlobalConfigUpdated,
        TokenConfigUpdated: TokenConfigUpdated,
    }

    /// Emitted when a new buyback order is started
    #[derive(Drop, starknet::Event)]
    pub struct BuybackStarted {
        #[key]
        pub sell_token: ContractAddress,
        pub buy_token: ContractAddress,
        pub amount: u128,
        pub start_time: u64,
        pub end_time: u64,
        pub order_index: u128,
        pub position_id: u64,
    }

    /// Emitted when buyback proceeds are claimed
    #[derive(Drop, starknet::Event)]
    pub struct BuybackProceeds {
        #[key]
        pub sell_token: ContractAddress,
        pub buy_token: ContractAddress,
        pub amount: u128,
        pub orders_claimed: u128,
        pub new_bookmark: u128,
    }

    /// Emitted when the global configuration is updated
    #[derive(Drop, starknet::Event)]
    pub struct GlobalConfigUpdated {
        pub old_config: GlobalBuybackConfig,
        pub new_config: GlobalBuybackConfig,
    }

    /// Emitted when a per-token configuration is updated
    #[derive(Drop, starknet::Event)]
    pub struct TokenConfigUpdated {
        #[key]
        pub sell_token: ContractAddress,
        pub old_config: Option<TokenBuybackConfig>,
        pub new_config: Option<TokenBuybackConfig>,
    }

    /// External implementation of IBuyback
    /// Uses `#[embeddable_as]` to allow embedding in contracts
    #[embeddable_as(BuybackImpl)]
    impl Buyback<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of crate::buyback::interface::IBuyback<ComponentState<TContractState>> {
        /// Execute a buyback using all tokens of `sell_token` in the contract
        fn buy_back(ref self: ComponentState<TContractState>, params: BuybackParams) {
            let config = self._get_effective_config(params.sell_token);
            let current_time = get_block_timestamp();
            let zero_address: ContractAddress = Zero::zero();

            // === Sell Token Validation ===
            assert(params.sell_token != zero_address, Errors::INVALID_SELL_TOKEN);
            assert(params.sell_token != config.buy_token, Errors::SELL_TOKEN_IS_BUY_TOKEN);

            // === Start Time Validation ===
            let start_time = if params.start_time == 0 {
                current_time
            } else {
                params.start_time
            };

            // If min_delay is set, order must start in the future with sufficient delay
            if config.min_delay > 0 {
                assert(start_time > current_time, Errors::START_TIME_TOO_SOON);
                assert(start_time - current_time >= config.min_delay, Errors::DELAY_TOO_SHORT);
            }

            // If start is in the future and max_delay is set, enforce maximum delay
            if start_time > current_time && config.max_delay > 0 {
                assert(start_time - current_time <= config.max_delay, Errors::DELAY_TOO_LONG);
            }

            // === End Time Validation ===
            let actual_start = max(current_time, start_time);
            assert(params.end_time > actual_start, Errors::END_TIME_INVALID);

            let duration = params.end_time - actual_start;
            assert(duration >= config.min_duration, Errors::DURATION_TOO_SHORT);
            assert(duration <= config.max_duration, Errors::DURATION_TOO_LONG);

            // === Amount Handling (always full balance, with minimum threshold) ===
            let sell_token_dispatcher = IERC20Dispatcher { contract_address: params.sell_token };
            let this_address = get_contract_address();
            let balance: u256 = sell_token_dispatcher.balance_of(this_address);
            assert(balance > 0, Errors::NO_BALANCE_TO_BUYBACK);

            let amount: u128 = balance.try_into().expect(Errors::BALANCE_OVERFLOW);
            assert(amount >= config.minimum_amount, Errors::AMOUNT_BELOW_MINIMUM);

            // === Position Handling ===
            let positions_dispatcher = self.Buyback_positions_dispatcher.read();

            // Transfer tokens to positions contract
            sell_token_dispatcher.transfer(positions_dispatcher.contract_address, balance);

            // Create order key
            let order_key = OrderKey {
                sell_token: params.sell_token,
                buy_token: config.buy_token,
                fee: config.fee,
                start_time: params.start_time,
                end_time: params.end_time,
            };

            let mut position_id = self.Buyback_position_token_id.read(params.sell_token);
            if position_id == 0 {
                // First buyback for this token - mint new position
                let (new_position_id, _sale_rate) = positions_dispatcher
                    .mint_and_increase_sell_amount(order_key, amount);
                position_id = new_position_id;
                self.Buyback_position_token_id.write(params.sell_token, position_id);
            } else {
                // Existing position - just increase sell amount
                positions_dispatcher.increase_sell_amount(position_id, order_key, amount);
            }

            // === Store Order Info ===
            let order_index = self.Buyback_order_counter.read(params.sell_token);
            let order_info = OrderInfo {
                start_time: start_time,
                end_time: params.end_time,
                amount: amount,
                buy_token: config.buy_token,
                fee: config.fee,
            };
            self.Buyback_orders.write((params.sell_token, order_index), order_info);
            self.Buyback_order_counter.write(params.sell_token, order_index + 1);

            // Emit event
            self
                .emit(
                    BuybackStarted {
                        sell_token: params.sell_token,
                        buy_token: config.buy_token,
                        amount,
                        start_time,
                        end_time: params.end_time,
                        order_index,
                        position_id,
                    },
                );
        }

        /// Claim proceeds from completed buyback orders
        fn claim_buyback_proceeds(
            ref self: ComponentState<TContractState>, sell_token: ContractAddress, limit: u16,
        ) -> u128 {
            let position_id = self.Buyback_position_token_id.read(sell_token);
            assert(position_id != 0, Errors::POSITION_NOT_INITIALIZED);

            let order_count = self.Buyback_order_counter.read(sell_token);
            let starting_bookmark = self.Buyback_order_bookmark.read(sell_token);

            // Fail fast: no NOOP claims allowed
            assert(starting_bookmark < order_count, Errors::NO_ORDERS_TO_CLAIM);

            // Calculate max index to process
            let max_index = if limit == 0 {
                order_count
            } else {
                let candidate = starting_bookmark + limit.into();
                if candidate < order_count {
                    candidate
                } else {
                    order_count
                }
            };

            let positions_dispatcher = self.Buyback_positions_dispatcher.read();
            let current_time = get_block_timestamp();

            let mut order_number = starting_bookmark;
            let mut total_proceeds: u128 = 0;
            let mut buy_token: ContractAddress = Zero::zero();

            // Iterate through orders and claim completed ones
            while order_number < max_index {
                let order_info = self.Buyback_orders.read((sell_token, order_number));

                // Only claim if order has ended
                if order_info.end_time > current_time {
                    // Orders are created sequentially, so we can break here
                    break;
                }

                // Get the effective config for treasury lookup
                let config = self._get_effective_config(sell_token);
                buy_token = order_info.buy_token;

                // Build order key from stored info
                let order_key = OrderKey {
                    sell_token: sell_token,
                    buy_token: order_info.buy_token,
                    fee: order_info.fee,
                    start_time: order_info.start_time,
                    end_time: order_info.end_time,
                };

                // Withdraw proceeds to treasury
                let proceeds = positions_dispatcher
                    .withdraw_proceeds_from_sale_to(position_id, order_key, config.treasury);

                total_proceeds += proceeds;
                order_number += 1;
            }

            // Fail if no orders were actually completed
            assert(order_number > starting_bookmark, Errors::NO_COMPLETED_ORDERS);

            // Update bookmark
            self.Buyback_order_bookmark.write(sell_token, order_number);

            // Emit event
            self
                .emit(
                    BuybackProceeds {
                        sell_token,
                        buy_token,
                        amount: total_proceeds,
                        orders_claimed: order_number - starting_bookmark,
                        new_bookmark: order_number,
                    },
                );

            total_proceeds
        }

        /// Get the global configuration defaults
        fn get_global_config(self: @ComponentState<TContractState>) -> GlobalBuybackConfig {
            self.Buyback_global_config.read()
        }

        /// Get the per-token configuration (None if not set)
        fn get_token_config(
            self: @ComponentState<TContractState>, sell_token: ContractAddress,
        ) -> Option<TokenBuybackConfig> {
            self.Buyback_token_config.read(sell_token)
        }

        /// Get the effective configuration for a sell token
        fn get_effective_config(
            self: @ComponentState<TContractState>, sell_token: ContractAddress,
        ) -> TokenBuybackConfig {
            self._get_effective_config(sell_token)
        }

        /// Get the Ekubo positions contract address
        fn get_positions_address(self: @ComponentState<TContractState>) -> ContractAddress {
            self.Buyback_positions_dispatcher.read().contract_address
        }

        /// Get the TWAMM extension address
        fn get_extension_address(self: @ComponentState<TContractState>) -> ContractAddress {
            self.Buyback_extension_address.read()
        }

        /// Get the position token ID for a sell token
        fn get_position_token_id(
            self: @ComponentState<TContractState>, sell_token: ContractAddress,
        ) -> u64 {
            self.Buyback_position_token_id.read(sell_token)
        }

        /// Get the number of orders created for a sell token
        fn get_order_count(
            self: @ComponentState<TContractState>, sell_token: ContractAddress,
        ) -> u128 {
            self.Buyback_order_counter.read(sell_token)
        }

        /// Get the bookmark for a sell token
        fn get_order_bookmark(
            self: @ComponentState<TContractState>, sell_token: ContractAddress,
        ) -> u128 {
            self.Buyback_order_bookmark.read(sell_token)
        }

        /// Get the number of unclaimed orders
        fn get_unclaimed_orders_count(
            self: @ComponentState<TContractState>, sell_token: ContractAddress,
        ) -> u128 {
            let counter = self.Buyback_order_counter.read(sell_token);
            let bookmark = self.Buyback_order_bookmark.read(sell_token);
            counter - bookmark
        }

        /// Get information about a specific order
        fn get_order_info(
            self: @ComponentState<TContractState>, sell_token: ContractAddress, index: u128,
        ) -> OrderInfo {
            self.Buyback_orders.read((sell_token, index))
        }

        /// Construct an OrderKey for a specific order index
        fn get_order_key(
            self: @ComponentState<TContractState>, sell_token: ContractAddress, index: u128,
        ) -> OrderKey {
            let order_info = self.Buyback_orders.read((sell_token, index));
            OrderKey {
                sell_token: sell_token,
                buy_token: order_info.buy_token,
                fee: order_info.fee,
                start_time: order_info.start_time,
                end_time: order_info.end_time,
            }
        }
    }

    /// Internal implementation with helper functions
    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        /// Initialize the component with required parameters
        ///
        /// # Arguments
        /// * `global_config` - Global configuration defaults
        /// * `positions_address` - Ekubo positions contract address
        /// * `extension_address` - TWAMM extension address
        fn initializer(
            ref self: ComponentState<TContractState>,
            global_config: GlobalBuybackConfig,
            positions_address: ContractAddress,
            extension_address: ContractAddress,
        ) {
            // Validate addresses
            let zero_address: ContractAddress = Zero::zero();
            assert(global_config.default_buy_token != zero_address, Errors::INVALID_BUY_TOKEN);
            assert(global_config.default_treasury != zero_address, Errors::INVALID_TREASURY);
            assert(positions_address != zero_address, Errors::INVALID_POSITIONS_ADDRESS);
            assert(extension_address != zero_address, Errors::INVALID_EXTENSION_ADDRESS);

            // Store configuration
            self.Buyback_global_config.write(global_config);
            self
                .Buyback_positions_dispatcher
                .write(IPositionsDispatcher { contract_address: positions_address });
            self.Buyback_extension_address.write(extension_address);
        }

        /// Get the effective configuration for a sell token
        /// Returns the per-token config if set, otherwise builds from global defaults
        fn _get_effective_config(
            self: @ComponentState<TContractState>, sell_token: ContractAddress,
        ) -> TokenBuybackConfig {
            match self.Buyback_token_config.read(sell_token) {
                Option::Some(config) => config,
                Option::None => {
                    // Build default config from global settings
                    // Use zero/default values for timing constraints
                    let global = self.Buyback_global_config.read();
                    TokenBuybackConfig {
                        buy_token: global.default_buy_token,
                        treasury: global.default_treasury,
                        minimum_amount: 0, // No minimum by default
                        min_delay: 0, // Can start immediately
                        max_delay: 0, // Must start immediately
                        min_duration: 0, // No minimum duration
                        max_duration: 0, // No maximum duration (will fail validation)
                        fee: 0 // Must be set via token config
                    }
                },
            }
        }

        /// Set the global configuration (internal - should be protected by embedding contract)
        fn set_global_config(
            ref self: ComponentState<TContractState>, config: GlobalBuybackConfig,
        ) {
            let zero_address: ContractAddress = Zero::zero();
            assert(config.default_buy_token != zero_address, Errors::INVALID_BUY_TOKEN);
            assert(config.default_treasury != zero_address, Errors::INVALID_TREASURY);

            let old_config = self.Buyback_global_config.read();
            self.Buyback_global_config.write(config);
            self.emit(GlobalConfigUpdated { old_config, new_config: config });
        }

        /// Set or clear per-token configuration (internal - should be protected by embedding
        /// contract)
        fn set_token_config(
            ref self: ComponentState<TContractState>,
            sell_token: ContractAddress,
            config: Option<TokenBuybackConfig>,
        ) {
            let old_config = self.Buyback_token_config.read(sell_token);
            self.Buyback_token_config.write(sell_token, config);
            self.emit(TokenConfigUpdated { sell_token, old_config, new_config: config });
        }
    }
}
