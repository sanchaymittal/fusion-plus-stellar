use soroban_sdk::{contracttype, Address, String};

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EscrowCreated {
    pub escrow_id: String,
    pub maker: Address,
    pub taker: Address,
    pub token: Address,
    pub amount: i128,
}

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EscrowWithdrawn {
    pub escrow_id: String,
    pub taker: Address,
    pub amount: i128,
    pub secret: String,
}

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EscrowCancelled {
    pub escrow_id: String,
    pub maker: Address,
    pub amount: i128,
}