/// Autonomous Buyback Preset Contract
///
/// A deployable contract that combines BuybackComponent with OwnableComponent
/// to provide a complete autonomous buyback system.
///
/// # Features
/// - Permissionless buyback execution via `buy_back()`
/// - Permissionless proceeds claiming via `claim_buyback_proceeds()`
/// - Owner-only configuration updates
/// - Owner-only emergency withdrawal
///
/// # Deployment
/// Constructor requires:
/// - owner: Contract owner address
/// - buyback_token: Token to acquire through buybacks
/// - treasury: Address to receive acquired tokens
/// - positions_address: Ekubo positions contract
/// - extension_address: TWAMM extension address
/// - order_config: BuybackOrderConfig with timing/fee constraints
#[starknet::contract]
pub mod AutonomousBuyback {
    use openzeppelin_access::ownable::OwnableComponent;
    use starknet::ContractAddress;
    use crate::buyback::buyback::BuybackComponent;
    use crate::buyback::interface::{BuybackOrderConfig, IBuybackAdmin};

    // Embed components
    component!(path: BuybackComponent, storage: buyback, event: BuybackEvent);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    // Expose Buyback permissionless external functions only
    #[abi(embed_v0)]
    impl BuybackImpl = BuybackComponent::BuybackImpl<ContractState>;
    impl BuybackInternalImpl = BuybackComponent::InternalImpl<ContractState>;

    // Expose Ownable external functions
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        buyback: BuybackComponent::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        BuybackEvent: BuybackComponent::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    /// Initialize the Autonomous Buyback contract
    ///
    /// # Arguments
    /// * `owner` - Contract owner who can update config and perform emergency actions
    /// * `buyback_token` - The token to acquire through all buybacks
    /// * `treasury` - Address where acquired buyback_tokens are sent
    /// * `positions_address` - Ekubo positions contract address
    /// * `extension_address` - TWAMM extension contract address
    /// * `order_config` - Configuration for buyback orders (durations, fee)
    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        buyback_token: ContractAddress,
        treasury: ContractAddress,
        positions_address: ContractAddress,
        extension_address: ContractAddress,
        order_config: BuybackOrderConfig,
    ) {
        // Initialize Ownable component
        self.ownable.initializer(owner);

        // Initialize Buyback component
        self
            .buyback
            .initializer(
                buyback_token, treasury, positions_address, extension_address, order_config,
            );
    }

    /// Owner-only implementation of IBuybackAdmin
    /// Ensures only the owner can call admin functions
    #[abi(embed_v0)]
    impl BuybackAdminImpl of IBuybackAdmin<ContractState> {
        /// Set the buyback order configuration (owner only)
        fn set_buyback_order_config(ref self: ContractState, config: BuybackOrderConfig) {
            self.ownable.assert_only_owner();
            self.buyback.set_buyback_order_config(config);
        }

        /// Set the treasury address (owner only)
        fn set_treasury(ref self: ContractState, treasury: ContractAddress) {
            self.ownable.assert_only_owner();
            self.buyback.set_treasury(treasury);
        }

        /// Emergency withdraw ERC20 tokens (owner only)
        fn emergency_withdraw_erc20(
            ref self: ContractState,
            token: ContractAddress,
            amount: u256,
            recipient: ContractAddress,
        ) {
            self.ownable.assert_only_owner();
            self.buyback.emergency_withdraw_erc20(token, amount, recipient);
        }
    }
}
