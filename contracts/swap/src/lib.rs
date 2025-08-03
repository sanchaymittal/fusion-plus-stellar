#![no_std]

use soroban_sdk::{
    contract, contractimpl, contractmeta,
    token, Address, Env, String, Symbol, Vec, Bytes,
};

pub mod types;
pub mod events;
pub mod timelock;
pub mod hashlock;
pub mod escrow;

#[cfg(test)]
mod test;

pub use types::*;
pub use events::*;
pub use escrow::*;

contractmeta!(
    key = "Description",
    val = "Cross-chain atomic swap contract"
);

#[contract]
pub struct SwapContract;

#[contractimpl]
impl SwapContract {
    /// Initialize a new escrow for atomic swap
    pub fn create_escrow(
        env: Env,
        maker: Address,
        taker: Address,
        token: Address,
        amount: i128,
        hashlock: String,
        timelock_start: u64,
        timelock_end: u64,
    ) -> String {
        maker.require_auth();
        
        let escrow_id = generate_escrow_id(&env, &maker, &taker, &token, amount);
        
        let immutables = Immutables {
            maker: maker.clone(),
            taker: taker.clone(),
            token: token.clone(),
            amount,
            hashlock: hashlock.clone(),
            timelock_start,
            timelock_end,
        };
        
        // Store escrow data
        env.storage().persistent().set(&DataKey::Escrow(escrow_id.clone()), &immutables);
        env.storage().persistent().set(&DataKey::EscrowState(escrow_id.clone()), &EscrowState::Active);
        
        // Transfer tokens to contract
        let token_client = token::Client::new(&env, &token);
        token_client.transfer(&maker, &env.current_contract_address(), &amount);
        
        // Emit event
        env.events().publish(
            (Symbol::new(&env, "escrow_created"),),
            (escrow_id.clone(), maker, taker, token, amount)
        );
        
        escrow_id
    }
    
    /// Withdraw from escrow using secret
    pub fn withdraw(env: Env, escrow_id: String, secret: String) -> bool {
        let immutables: Immutables = env.storage().persistent()
            .get(&DataKey::Escrow(escrow_id.clone()))
            .unwrap();
        
        let state: EscrowState = env.storage().persistent()
            .get(&DataKey::EscrowState(escrow_id.clone()))
            .unwrap();
        
        // Verify escrow is active
        if state != EscrowState::Active {
            panic!("Escrow not active");
        }
        
        // Verify timelock
        let current_time = env.ledger().timestamp();
        if current_time < immutables.timelock_start || current_time > immutables.timelock_end {
            panic!("Outside timelock window");
        }
        
        // Verify hashlock
        if !verify_hashlock(&env, &immutables.hashlock, &secret) {
            panic!("Invalid secret");
        }
        
        // Transfer tokens to taker
        let token_client = token::Client::new(&env, &immutables.token);
        token_client.transfer(&env.current_contract_address(), &immutables.taker, &immutables.amount);
        
        // Update state
        env.storage().persistent().set(&DataKey::EscrowState(escrow_id.clone()), &EscrowState::Withdrawn);
        
        // Emit event
        env.events().publish(
            (Symbol::new(&env, "escrow_withdrawn"),),
            (escrow_id, immutables.taker, immutables.amount, secret)
        );
        
        true
    }
    
    /// Cancel escrow and return funds to maker
    pub fn cancel(env: Env, escrow_id: String) -> bool {
        let immutables: Immutables = env.storage().persistent()
            .get(&DataKey::Escrow(escrow_id.clone()))
            .unwrap();
        
        let state: EscrowState = env.storage().persistent()
            .get(&DataKey::EscrowState(escrow_id.clone()))
            .unwrap();
        
        // Verify escrow is active
        if state != EscrowState::Active {
            panic!("Escrow not active");
        }
        
        // Verify timelock has expired
        let current_time = env.ledger().timestamp();
        if current_time <= immutables.timelock_end {
            panic!("Timelock not expired");
        }
        
        // Only maker can cancel
        immutables.maker.require_auth();
        
        // Transfer tokens back to maker
        let token_client = token::Client::new(&env, &immutables.token);
        token_client.transfer(&env.current_contract_address(), &immutables.maker, &immutables.amount);
        
        // Update state
        env.storage().persistent().set(&DataKey::EscrowState(escrow_id.clone()), &EscrowState::Cancelled);
        
        // Emit event
        env.events().publish(
            (Symbol::new(&env, "escrow_cancelled"),),
            (escrow_id, immutables.maker, immutables.amount)
        );
        
        true
    }
    
    /// Get escrow details
    pub fn get_escrow(env: Env, escrow_id: String) -> Option<Immutables> {
        env.storage().persistent().get(&DataKey::Escrow(escrow_id))
    }
    
    /// Get escrow state
    pub fn get_escrow_state(env: Env, escrow_id: String) -> Option<EscrowState> {
        env.storage().persistent().get(&DataKey::EscrowState(escrow_id))
    }
}

fn generate_escrow_id(env: &Env, _maker: &Address, _taker: &Address, _token: &Address, _amount: i128) -> String {
    // Simple ID generation using timestamp
    String::from_str(env, "escrow_")
}

fn verify_hashlock(_env: &Env, hashlock: &String, secret: &String) -> bool {
    // Simple comparison for now - in production you'd want proper hashing
    secret == hashlock
}