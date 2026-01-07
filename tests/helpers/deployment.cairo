use autonomous_buyback::GlobalBuybackConfig;
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;
use crate::fixtures::constants::{OWNER, TREASURY, defaults};
use crate::mocks::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};

/// Deploy a mock ERC20 token
pub fn deploy_mock_erc20(name: ByteArray, symbol: ByteArray) -> ContractAddress {
    let contract = declare("MockERC20").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];

    // Serialize name and symbol
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);

    let (address, _) = contract.deploy(@calldata).unwrap();
    address
}

/// Deploy the AutonomousBuyback preset contract
pub fn deploy_autonomous_buyback(
    owner: ContractAddress,
    global_config: GlobalBuybackConfig,
    positions_address: ContractAddress,
    extension_address: ContractAddress,
) -> ContractAddress {
    let contract = declare("AutonomousBuyback").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];

    // Serialize constructor arguments
    owner.serialize(ref calldata);
    global_config.serialize(ref calldata);
    positions_address.serialize(ref calldata);
    extension_address.serialize(ref calldata);

    let (address, _) = contract.deploy(@calldata).unwrap();
    address
}

/// Deploy a mock ERC20 and mint tokens to a recipient
pub fn deploy_and_mint_token(
    name: ByteArray, symbol: ByteArray, recipient: ContractAddress, amount: u256,
) -> ContractAddress {
    let token_address = deploy_mock_erc20(name, symbol);
    let token = IMockERC20Dispatcher { contract_address: token_address };
    token.mint(recipient, amount);
    token_address
}

/// Helper struct for test setup
#[derive(Drop)]
pub struct TestSetup {
    pub buyback_contract: ContractAddress,
    pub buyback_token: ContractAddress,
    pub sell_token: ContractAddress,
}

/// Deploy a complete test setup with buyback contract and tokens
/// Uses mock addresses for Ekubo contracts (for unit testing)
pub fn deploy_test_setup_mock() -> TestSetup {
    // Deploy mock tokens
    let buyback_token = deploy_mock_erc20("Buyback Token", "BUY");
    let sell_token = deploy_mock_erc20("Sell Token", "SELL");

    // Mock Ekubo addresses (not real contracts - for unit testing only)
    let mock_positions: ContractAddress = 'POSITIONS'.try_into().unwrap();
    let mock_extension: ContractAddress = 'EXTENSION'.try_into().unwrap();

    // Deploy buyback contract with global config
    let global_config = defaults::global_config_with(buyback_token, TREASURY());
    let buyback_contract = deploy_autonomous_buyback(
        OWNER(), global_config, mock_positions, mock_extension,
    );

    TestSetup { buyback_contract, buyback_token, sell_token }
}
