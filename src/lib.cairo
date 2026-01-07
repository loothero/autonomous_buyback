/// Autonomous Buyback Library v2
///
/// A Cairo library providing a reusable component for executing autonomous
/// token buybacks via Ekubo's TWAMM (Time-Weighted Average Market Maker).
///
/// # Features
/// - Permissionless buyback execution
/// - Per-token configuration with global defaults
/// - Delayed start support for scheduled orders
/// - Minimum amount threshold for spam prevention
/// - Multiple concurrent DCA orders per token
/// - Append-only design: no emergency functions
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
    BuybackComponent, BuybackParams, GlobalBuybackConfig, IBuyback, IBuybackAdmin,
    IBuybackAdminDispatcher, IBuybackAdminDispatcherTrait, IBuybackDispatcher,
    IBuybackDispatcherTrait, OrderInfo, TokenBuybackConfig,
};
pub use constants::Errors;
