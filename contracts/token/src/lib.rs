#![no_std]

use soroban_sdk::{
    contract, contractimpl, contracttype, contractmeta,
    Address, Env, String, Symbol,
};

contractmeta!(
    key = "Description",
    val = "Simple token contract for testing swaps"
);

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum DataKey {
    Balance(Address),
    TotalSupply,
    Name,
    Symbol,
    Decimals,
    Admin,
}

#[contract]
pub struct Token;

#[contractimpl]
impl Token {
    pub fn initialize(
        env: Env,
        admin: Address,
        name: String,
        symbol: String,
        decimals: u32,
    ) {
        if env.storage().persistent().has(&DataKey::Admin) {
            panic!("Already initialized");
        }
        
        env.storage().persistent().set(&DataKey::Admin, &admin);
        env.storage().persistent().set(&DataKey::Name, &name);
        env.storage().persistent().set(&DataKey::Symbol, &symbol);
        env.storage().persistent().set(&DataKey::Decimals, &decimals);
        env.storage().persistent().set(&DataKey::TotalSupply, &0i128);
    }
    
    pub fn mint(env: Env, to: Address, amount: i128) {
        let admin: Address = env.storage().persistent().get(&DataKey::Admin).unwrap();
        admin.require_auth();
        
        let balance = Self::balance(env.clone(), to.clone());
        let new_balance = balance + amount;
        env.storage().persistent().set(&DataKey::Balance(to.clone()), &new_balance);
        
        let total_supply: i128 = env.storage().persistent().get(&DataKey::TotalSupply).unwrap_or(0);
        env.storage().persistent().set(&DataKey::TotalSupply, &(total_supply + amount));
        
        env.events().publish(
            (Symbol::new(&env, "mint"),),
            (to, amount)
        );
    }
    
    pub fn transfer(env: Env, from: Address, to: Address, amount: i128) {
        from.require_auth();
        
        let from_balance = Self::balance(env.clone(), from.clone());
        if from_balance < amount {
            panic!("Insufficient balance");
        }
        
        let to_balance = Self::balance(env.clone(), to.clone());
        
        env.storage().persistent().set(&DataKey::Balance(from.clone()), &(from_balance - amount));
        env.storage().persistent().set(&DataKey::Balance(to.clone()), &(to_balance + amount));
        
        env.events().publish(
            (Symbol::new(&env, "transfer"),),
            (from, to, amount)
        );
    }
    
    pub fn balance(env: Env, account: Address) -> i128 {
        env.storage().persistent().get(&DataKey::Balance(account)).unwrap_or(0)
    }
    
    pub fn total_supply(env: Env) -> i128 {
        env.storage().persistent().get(&DataKey::TotalSupply).unwrap_or(0)
    }
    
    pub fn name(env: Env) -> String {
        env.storage().persistent().get(&DataKey::Name).unwrap()
    }
    
    pub fn symbol(env: Env) -> String {
        env.storage().persistent().get(&DataKey::Symbol).unwrap()
    }
    
    pub fn decimals(env: Env) -> u32 {
        env.storage().persistent().get(&DataKey::Decimals).unwrap()
    }
}