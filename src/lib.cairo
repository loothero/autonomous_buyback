/// Autonomous Buyback Library
///
/// A Cairo library providing a reusable component for executing autonomous
/// token buybacks via Ekubo's TWAMM (Time-Weighted Average Market Maker).
///
/// # Features
/// - Permissionless buyback execution
/// - Support for any ERC20 token
/// - Multiple concurrent DCA orders per token
/// - Configurable order duration and fee parameters
/// - Treasury destination for acquired tokens
///
/// # Usage
/// ```cairo
/// use autonomous_buyback::buyback::BuybackComponent;
///
/// component!(path: BuybackComponent, storage: buyback, event: BuybackEvent);
/// ```
pub mod buyback;
pub mod constants;
pub mod presets;

// Re-exports for convenience
pub use buyback::{
    BuybackComponent, BuybackOrderConfig, IBuyback, IBuybackAdmin, IBuybackAdminDispatcher,
    IBuybackAdminDispatcherTrait, IBuybackDispatcher, IBuybackDispatcherTrait,
};
pub use constants::Errors;
