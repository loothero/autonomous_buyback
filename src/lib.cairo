/// Autonomous Buyback Library
///
/// A Cairo library providing reusable components for executing autonomous
/// token buybacks and distributions via Ekubo's TWAMM (Time-Weighted Average Market Maker).
///
/// # Features
/// - Permissionless buyback execution
/// - Autonomous token distribution with multiple concurrent orders
/// - Support for any ERC20 token
/// - Multiple concurrent DCA orders per token
/// - Configurable order duration and fee parameters
/// - Treasury/recipient destination for acquired tokens
///
/// # Usage
/// ```cairo
/// // For buyback functionality
/// use autonomous_buyback::buyback::BuybackComponent;
/// component!(path: BuybackComponent, storage: buyback, event: BuybackEvent);
///
/// // For stream token distribution
/// use autonomous_buyback::stream::StreamComponent;
/// component!(path: StreamComponent, storage: stream, event: StreamEvent);
/// ```
pub mod buyback;
pub mod constants;
pub mod factory;
pub mod presets;
pub mod stream;

// Re-exports for convenience - Buyback
pub use buyback::{
    BuybackComponent, BuybackOrderConfig, IBuyback, IBuybackAdmin, IBuybackAdminDispatcher,
    IBuybackAdminDispatcherTrait, IBuybackDispatcher, IBuybackDispatcherTrait,
};

// Re-exports for convenience - Constants
pub use constants::Errors;

// Re-exports for convenience - Factory
pub use factory::StreamTokenFactory;

// Re-exports for convenience - Stream
pub use stream::{
    CreateTokenParams, DistributionOrder, IStreamToken, IStreamTokenDispatcher,
    IStreamTokenDispatcherTrait, IStreamTokenFactory, IStreamTokenFactoryDispatcher,
    IStreamTokenFactoryDispatcherTrait, LiquidityConfig, StoredDistributionOrder, StreamComponent,
};
