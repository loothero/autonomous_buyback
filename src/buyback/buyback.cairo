/// Autonomous Buyback Component
///
/// A reusable Cairo component that enables permissionless buybacks of any ERC20 token
/// deposited into the contract via Ekubo's TWAMM DCA orders.
///
/// # Features
/// - Permissionless buyback execution: Anyone can trigger buybacks
/// - Multiple concurrent orders: Supports multiple DCA orders per sell token
/// - Automatic position creation: First buyback creates the Ekubo position
/// - Treasury destination: Proceeds sent to configurable treasury address
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
    use crate::buyback::interface::BuybackOrderConfig;
    use crate::constants::Errors;

    /// Storage for the Buyback component
    /// All storage keys are prefixed with `Buyback_` to avoid collisions
    #[storage]
    pub struct Storage {
        /// Token to acquire through buybacks
        Buyback_buyback_token: ContractAddress,
        /// Address where proceeds are sent
        Buyback_treasury: ContractAddress,
        /// Ekubo positions contract dispatcher
        Buyback_positions_dispatcher: IPositionsDispatcher,
        /// TWAMM extension address
        Buyback_extension_address: ContractAddress,
        /// Configuration for buyback orders (duration/fee constraints)
        Buyback_order_config: BuybackOrderConfig,
        /// Position token ID per sell token (0 if not created)
        Buyback_position_token_id: Map<ContractAddress, u64>,
        /// Number of orders created per sell token
        Buyback_order_counter: Map<ContractAddress, u128>,
        /// Bookmark for claiming (next order to claim) per sell token
        Buyback_order_bookmark: Map<ContractAddress, u128>,
        /// End time of each order: (sell_token, index) -> end_time
        Buyback_order_end_times: Map<(ContractAddress, u128), u64>,
    }

    /// Events emitted by the Buyback component
    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        BuybackStarted: BuybackStarted,
        BuybackProceeds: BuybackProceeds,
        ConfigUpdated: ConfigUpdated,
        TreasuryUpdated: TreasuryUpdated,
    }

    /// Emitted when a new buyback order is started
    #[derive(Drop, starknet::Event)]
    pub struct BuybackStarted {
        #[key]
        pub sell_token: ContractAddress,
        pub amount: u128,
        pub end_time: u64,
        pub order_index: u128,
        pub position_id: u64,
    }

    /// Emitted when buyback proceeds are claimed
    #[derive(Drop, starknet::Event)]
    pub struct BuybackProceeds {
        #[key]
        pub sell_token: ContractAddress,
        pub amount: u128,
        pub orders_claimed: u128,
        pub new_bookmark: u128,
    }

    /// Emitted when the configuration is updated
    #[derive(Drop, starknet::Event)]
    pub struct ConfigUpdated {
        pub old_config: BuybackOrderConfig,
        pub new_config: BuybackOrderConfig,
    }

    /// Emitted when the treasury address is updated
    #[derive(Drop, starknet::Event)]
    pub struct TreasuryUpdated {
        pub old_treasury: ContractAddress,
        pub new_treasury: ContractAddress,
    }

    /// External implementation of IBuyback
    /// Uses `#[embeddable_as]` to allow embedding in contracts
    #[embeddable_as(BuybackImpl)]
    impl Buyback<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of crate::buyback::interface::IBuyback<ComponentState<TContractState>> {
        /// Execute a buyback using all tokens of `sell_token` in the contract
        fn buy_back(
            ref self: ComponentState<TContractState>, sell_token: ContractAddress, end_time: u64,
        ) {
            // Validate sell token
            let buyback_token = self.Buyback_buyback_token.read();
            let zero_address: ContractAddress = Zero::zero();
            assert(sell_token != zero_address, Errors::INVALID_SELL_TOKEN);
            assert(sell_token != buyback_token, Errors::SELL_TOKEN_IS_BUYBACK_TOKEN);

            // Validate timing constraints
            let config = self.Buyback_order_config.read();
            let current_time = get_block_timestamp();
            assert(end_time > current_time, Errors::END_TIME_IN_PAST);

            // Calculate effective start time (order starts immediately, start_time=0)
            let start_time: u64 = 0;
            let actual_start = max(current_time, start_time);
            let duration = end_time - actual_start;

            // Validate duration constraints
            assert(duration >= config.min_duration, Errors::DURATION_TOO_SHORT);
            assert(duration <= config.max_duration, Errors::DURATION_TOO_LONG);

            // Get the amount of sell_token in the contract
            let sell_token_dispatcher = IERC20Dispatcher { contract_address: sell_token };
            let this_address = get_contract_address();
            let balance: u256 = sell_token_dispatcher.balance_of(this_address);
            assert(balance > 0, Errors::NO_BALANCE_TO_BUYBACK);

            // Convert balance to u128 (safe for TWAMM amounts)
            let amount: u128 = balance.try_into().expect('Balance overflow');

            // Get or create position for this sell token
            let positions_dispatcher = self.Buyback_positions_dispatcher.read();
            let mut position_id = self.Buyback_position_token_id.read(sell_token);

            // Transfer tokens to positions contract
            sell_token_dispatcher.transfer(positions_dispatcher.contract_address, balance);

            // Create order key
            let order_key = self._build_order_key(sell_token, start_time, end_time);

            if position_id == 0 {
                // First buyback for this token - mint new position
                let (new_position_id, _sale_rate) = positions_dispatcher
                    .mint_and_increase_sell_amount(order_key, amount);
                position_id = new_position_id;
                self.Buyback_position_token_id.write(sell_token, position_id);
            } else {
                // Existing position - just increase sell amount
                positions_dispatcher.increase_sell_amount(position_id, order_key, amount);
            }

            // Store order info
            let order_index = self.Buyback_order_counter.read(sell_token);
            self.Buyback_order_end_times.write((sell_token, order_index), end_time);
            self.Buyback_order_counter.write(sell_token, order_index + 1);

            // Emit event
            self.emit(BuybackStarted { sell_token, amount, end_time, order_index, position_id });
        }

        /// Claim proceeds from completed buyback orders
        fn claim_buyback_proceeds(
            ref self: ComponentState<TContractState>, sell_token: ContractAddress, limit: u16,
        ) -> u128 {
            let position_id = self.Buyback_position_token_id.read(sell_token);
            assert(position_id != 0, Errors::POSITION_NOT_INITIALIZED);

            let order_count = self.Buyback_order_counter.read(sell_token);
            let starting_bookmark = self.Buyback_order_bookmark.read(sell_token);
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

            let treasury = self.Buyback_treasury.read();
            let positions_dispatcher = self.Buyback_positions_dispatcher.read();
            let current_time = get_block_timestamp();

            let mut order_number = starting_bookmark;
            let mut total_proceeds: u128 = 0;

            // Iterate through orders and claim completed ones
            while order_number < max_index {
                let order_end_time = self.Buyback_order_end_times.read((sell_token, order_number));

                // Only claim if order has ended
                if order_end_time > current_time {
                    // Orders are created sequentially, so we can break here
                    break;
                }

                // Build order key for this specific order
                let order_key = self._build_order_key(sell_token, 0, order_end_time);

                // Withdraw proceeds to treasury
                let proceeds = positions_dispatcher
                    .withdraw_proceeds_from_sale_to(position_id, order_key, treasury);

                total_proceeds += proceeds;
                order_number += 1;
            }

            assert(total_proceeds > 0, Errors::NO_PROCEEDS_TO_CLAIM);

            // Update bookmark
            self.Buyback_order_bookmark.write(sell_token, order_number);

            // Emit event
            self
                .emit(
                    BuybackProceeds {
                        sell_token,
                        amount: total_proceeds,
                        orders_claimed: order_number - starting_bookmark,
                        new_bookmark: order_number,
                    },
                );

            total_proceeds
        }

        /// Get the buyback token address
        fn get_buyback_token(self: @ComponentState<TContractState>) -> ContractAddress {
            self.Buyback_buyback_token.read()
        }

        /// Get the treasury address
        fn get_treasury(self: @ComponentState<TContractState>) -> ContractAddress {
            self.Buyback_treasury.read()
        }

        /// Get the buyback order configuration
        fn get_buyback_order_config(self: @ComponentState<TContractState>) -> BuybackOrderConfig {
            self.Buyback_order_config.read()
        }

        /// Get the Ekubo positions contract address
        fn get_positions_address(self: @ComponentState<TContractState>) -> ContractAddress {
            self.Buyback_positions_dispatcher.read().contract_address
        }

        /// Get the TWAMM extension address
        fn get_extension_address(self: @ComponentState<TContractState>) -> ContractAddress {
            self.Buyback_extension_address.read()
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

        /// Get the position token ID for a sell token
        fn get_position_token_id(
            self: @ComponentState<TContractState>, sell_token: ContractAddress,
        ) -> u64 {
            self.Buyback_position_token_id.read(sell_token)
        }

        /// Get the end time of a specific order
        fn get_order_end_time(
            self: @ComponentState<TContractState>, sell_token: ContractAddress, index: u128,
        ) -> u64 {
            self.Buyback_order_end_times.read((sell_token, index))
        }

        /// Construct an OrderKey for a specific order
        fn get_order_key(
            self: @ComponentState<TContractState>,
            sell_token: ContractAddress,
            start_time: u64,
            end_time: u64,
        ) -> OrderKey {
            self._build_order_key(sell_token, start_time, end_time)
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
        /// * `buyback_token` - Token to acquire through buybacks
        /// * `treasury` - Address where proceeds are sent
        /// * `positions_address` - Ekubo positions contract address
        /// * `extension_address` - TWAMM extension address
        /// * `order_config` - Configuration for buyback orders
        fn initializer(
            ref self: ComponentState<TContractState>,
            buyback_token: ContractAddress,
            treasury: ContractAddress,
            positions_address: ContractAddress,
            extension_address: ContractAddress,
            order_config: BuybackOrderConfig,
        ) {
            // Validate addresses
            let zero_address: ContractAddress = Zero::zero();
            assert(buyback_token != zero_address, Errors::INVALID_BUYBACK_TOKEN);
            assert(treasury != zero_address, Errors::INVALID_TREASURY);
            assert(positions_address != zero_address, Errors::INVALID_POSITIONS_ADDRESS);
            assert(extension_address != zero_address, Errors::INVALID_EXTENSION_ADDRESS);

            // Store configuration
            self.Buyback_buyback_token.write(buyback_token);
            self.Buyback_treasury.write(treasury);
            self
                .Buyback_positions_dispatcher
                .write(IPositionsDispatcher { contract_address: positions_address });
            self.Buyback_extension_address.write(extension_address);
            self.Buyback_order_config.write(order_config);
        }

        /// Build an OrderKey for a TWAMM order
        fn _build_order_key(
            self: @ComponentState<TContractState>,
            sell_token: ContractAddress,
            start_time: u64,
            end_time: u64,
        ) -> OrderKey {
            let buyback_token = self.Buyback_buyback_token.read();
            let config = self.Buyback_order_config.read();

            OrderKey {
                sell_token: sell_token,
                buy_token: buyback_token,
                fee: config.fee,
                start_time: start_time,
                end_time: end_time,
            }
        }

        /// Set the buyback order configuration (internal - should be protected by embedding
        /// contract)
        fn set_buyback_order_config(
            ref self: ComponentState<TContractState>, config: BuybackOrderConfig,
        ) {
            let old_config = self.Buyback_order_config.read();
            self.Buyback_order_config.write(config);
            self.emit(ConfigUpdated { old_config, new_config: config });
        }

        /// Set the treasury address (internal - should be protected by embedding contract)
        fn set_treasury(ref self: ComponentState<TContractState>, treasury: ContractAddress) {
            let zero_address: ContractAddress = Zero::zero();
            assert(treasury != zero_address, Errors::INVALID_TREASURY);

            let old_treasury = self.Buyback_treasury.read();
            self.Buyback_treasury.write(treasury);
            self.emit(TreasuryUpdated { old_treasury, new_treasury: treasury });
        }

        /// Emergency withdraw ERC20 tokens (internal - should be protected by embedding contract)
        fn emergency_withdraw_erc20(
            ref self: ComponentState<TContractState>,
            token: ContractAddress,
            amount: u256,
            recipient: ContractAddress,
        ) {
            let zero_address: ContractAddress = Zero::zero();
            assert(recipient != zero_address, Errors::INVALID_TREASURY);

            let token_dispatcher = IERC20Dispatcher { contract_address: token };
            token_dispatcher.transfer(recipient, amount);
        }
    }
}
