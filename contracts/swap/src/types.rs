use soroban_sdk::{contracttype, Address, String};

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Immutables {
    pub maker: Address,
    pub taker: Address,
    pub token: Address,
    pub amount: i128,
    pub hashlock: String,
    pub timelock_start: u64,
    pub timelock_end: u64,
}

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum EscrowState {
    Active,
    Withdrawn,
    Cancelled,
}

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum DataKey {
    Escrow(String),
    EscrowState(String),
}

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Order {
    pub salt: String,
    pub maker: Address,
    pub receiver: Address,
    pub maker_asset: Address,
    pub taker_asset: Address,
    pub making_amount: i128,
    pub taking_amount: i128,
}