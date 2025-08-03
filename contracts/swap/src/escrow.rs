use soroban_sdk::{Env, String};
use crate::types::{Immutables, EscrowState, DataKey};

pub struct EscrowManager;

impl EscrowManager {
    pub fn create(
        env: &Env,
        immutables: &Immutables,
    ) -> String {
        let escrow_id = Self::generate_id(env, immutables);
        
        // Store escrow data
        env.storage().persistent().set(&DataKey::Escrow(escrow_id.clone()), immutables);
        env.storage().persistent().set(&DataKey::EscrowState(escrow_id.clone()), &EscrowState::Active);
        
        escrow_id
    }
    
    pub fn get(env: &Env, escrow_id: &String) -> Option<Immutables> {
        env.storage().persistent().get(&DataKey::Escrow(escrow_id.clone()))
    }
    
    pub fn get_state(env: &Env, escrow_id: &String) -> Option<EscrowState> {
        env.storage().persistent().get(&DataKey::EscrowState(escrow_id.clone()))
    }
    
    pub fn set_state(env: &Env, escrow_id: &String, state: &EscrowState) {
        env.storage().persistent().set(&DataKey::EscrowState(escrow_id.clone()), state);
    }
    
    fn generate_id(env: &Env, _immutables: &Immutables) -> String {
        // Simple ID generation using timestamp
        String::from_str(env, "escrow_id")
    }
}