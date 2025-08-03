use soroban_sdk::{contracttype, Env};

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Timelock {
    pub start: u64,
    pub end: u64,
}

impl Timelock {
    pub fn new(start: u64, end: u64) -> Self {
        Self { start, end }
    }
    
    pub fn is_active(&self, env: &Env) -> bool {
        let current_time = env.ledger().timestamp();
        current_time >= self.start && current_time <= self.end
    }
    
    pub fn is_expired(&self, env: &Env) -> bool {
        let current_time = env.ledger().timestamp();
        current_time > self.end
    }
    
    pub fn is_before_start(&self, env: &Env) -> bool {
        let current_time = env.ledger().timestamp();
        current_time < self.start
    }
}