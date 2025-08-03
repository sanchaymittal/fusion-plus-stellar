use soroban_sdk::{Env, String};

pub struct HashlockValidator {
    expected_hash: String,
}

impl HashlockValidator {
    pub fn new(expected_hash: String) -> Self {
        Self { expected_hash }
    }
    
    pub fn validate(&self, _env: &Env, secret: &String) -> bool {
        // Simple comparison for now - in production you'd want proper hashing
        secret == &self.expected_hash
    }
}

pub fn create_hashlock(_env: &Env, secret: &String) -> String {
    // Simple return secret for now - in production you'd want proper hashing
    secret.clone()
}