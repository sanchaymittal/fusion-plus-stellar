#[cfg(test)]
mod test {
    use crate::{SwapContract, EscrowState, Immutables, DataKey};
    use soroban_sdk::{testutils::{Address as _, Ledger as _}, Address, Env, String};

    #[test]
    fn test_basic_functionality() {
        let env = Env::default();
        let contract_id = env.register(SwapContract, ());
        
        let maker = Address::generate(&env);
        let taker = Address::generate(&env);
        let token = Address::generate(&env);

        // Mock auth for the maker
        env.mock_all_auths();

        // Test basic storage operations
        let immutables = Immutables {
            maker: maker.clone(),
            taker: taker.clone(),
            token: token.clone(),
            amount: 1000i128,
            hashlock: String::from_str(&env, "secret123"),
            timelock_start: 1000u64,
            timelock_end: 2000u64,
        };

        // Store test data using contract context
        env.as_contract(&contract_id, || {
            env.storage().persistent().set(&DataKey::Escrow(String::from_str(&env, "test_id")), &immutables);
            env.storage().persistent().set(&DataKey::EscrowState(String::from_str(&env, "test_id")), &EscrowState::Active);
            
            // Retrieve and verify
            let stored_immutables: Option<Immutables> = env.storage().persistent().get(&DataKey::Escrow(String::from_str(&env, "test_id")));
            assert!(stored_immutables.is_some());
            
            let data = stored_immutables.unwrap();
            assert_eq!(data.maker, maker);
            assert_eq!(data.taker, taker);
            assert_eq!(data.amount, 1000i128);
        });
    }
}