//! Destination escrow contract for cross-chain atomic swaps
//! Handles withdrawal and cancellation logic on the destination chain

use crate::Immutables;

#[starknet::interface]
pub trait IEscrowDst<TContractState> {
    fn withdraw_public(ref self: TContractState, immutables: Immutables, secret: u256);
    fn cancel_private(ref self: TContractState, immutables: Immutables);
}

#[starknet::contract]
pub mod EscrowDst {
    use super::{IEscrowDst, Immutables};
    use crate::escrow_base::{IBaseEscrow};
    use crate::hashlock::{HashlockValidatorTrait, Errors as HashlockErrors};
    use crate::timelock::{TimelocksTrait, Stage};
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use openzeppelin::token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::security::reentrancyguard::ReentrancyGuardComponent;
    
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent);
    
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;
    
    #[storage]
    struct Storage {
        immutables: Immutables,
        deployed_at: u64,
        is_withdrawn: bool,
        is_cancelled: bool,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        reentrancy_guard: ReentrancyGuardComponent::Storage,
    }
    
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PublicWithdrawn: PublicWithdrawn,
        PrivateCancelled: PrivateCancelled,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
    }
    
    #[derive(Drop, starknet::Event)]
    struct PublicWithdrawn {
        #[key]
        token: ContractAddress,
        #[key]
        withdrawer: ContractAddress,
        amount: u256,
        secret: u256,
    }
    
    #[derive(Drop, starknet::Event)]
    struct PrivateCancelled {
        #[key]
        token: ContractAddress,
        #[key]
        canceller: ContractAddress,
        amount: u256,
    }
    
    pub mod Errors {
        pub const UNAUTHORIZED_CALLER: felt252 = 'Unauthorized caller';
        pub const INVALID_TIMELOCK_STAGE: felt252 = 'Invalid timelock stage';
    }
    
    #[constructor]
    fn constructor(ref self: ContractState, mut immutables: Immutables) {
        self.ownable.initializer(immutables.maker);
        
        // Set the deployed_at timestamp in timelocks
        let current_time = starknet::get_block_timestamp();
        immutables.timelocks = immutables.timelocks.set_deployed_at(current_time);
        
        self.immutables.write(immutables);
        self.deployed_at.write(current_time);
        
        // Token transfer will be handled by the factory after deployment
    }
    
    #[abi(embed_v0)]
    impl BaseEscrowImpl of IBaseEscrow<ContractState> {
        fn get_immutables(self: @ContractState) -> Immutables {
            self.immutables.read()
        }
        
        fn withdraw(ref self: ContractState, immutables: Immutables, secret: u256) {
            self.reentrancy_guard.start();
            
            // Private withdrawal: only taker during DstWithdrawal period
            self._validate_immutables(immutables);
            assert(get_caller_address() == immutables.taker, Errors::UNAUTHORIZED_CALLER);
            assert(!self.is_withdrawn.read(), 'Already withdrawn');
            assert(!self.is_cancelled.read(), 'Already cancelled');
            
            // Check timelock: after DstWithdrawal, before DstCancellation
            self._check_timelock_stage(Stage::DstWithdrawal);
            self._check_before_stage(Stage::DstCancellation);
            
            // Validate secret
            let hashlock_validator = HashlockValidatorTrait::new(immutables.hashlock);
            assert(hashlock_validator.validate(secret), HashlockErrors::INVALID_SECRET);
            
            self._perform_withdrawal(immutables, secret);
            
            self.reentrancy_guard.end();
        }
        
        fn cancel(ref self: ContractState, immutables: Immutables) {
            // This is for public cancellation after DstCancellation period
            self.reentrancy_guard.start();
            
            self._validate_immutables(immutables);
            assert(!self.is_withdrawn.read(), 'Already withdrawn');
            assert(!self.is_cancelled.read(), 'Already cancelled');
            
            // Check timelock: after DstCancellation
            self._check_timelock_stage(Stage::DstCancellation);
            
            self._perform_cancellation(immutables);
            
            self.reentrancy_guard.end();
        }
        
        fn rescue(ref self: ContractState, token: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            
            let immutables = self.immutables.read();
            let timelocks = immutables.timelocks;
            let rescue_time = timelocks.rescue_start(crate::escrow_base::RESCUE_DELAY);
            
            assert(starknet::get_block_timestamp() >= rescue_time, 'Too early for rescue');
            
            let erc20 = ERC20ABIDispatcher { contract_address: token };
            let success = erc20.transfer(get_caller_address(), amount);
            assert(success, 'Transfer failed');
        }
    }
    
    #[abi(embed_v0)]
    impl EscrowDstImpl of IEscrowDst<ContractState> {
        fn withdraw_public(ref self: ContractState, immutables: Immutables, secret: u256) {
            self.reentrancy_guard.start();
            
            // Public withdrawal: anyone during DstPublicWithdrawal period  
            self._validate_immutables(immutables);
            assert(!self.is_withdrawn.read(), 'Already withdrawn');
            assert(!self.is_cancelled.read(), 'Already cancelled');
            
            // Check timelock: after DstPublicWithdrawal, before DstCancellation
            self._check_timelock_stage(Stage::DstPublicWithdrawal);
            self._check_before_stage(Stage::DstCancellation);
            
            // Validate secret
            let hashlock_validator = HashlockValidatorTrait::new(immutables.hashlock);
            assert(hashlock_validator.validate(secret), HashlockErrors::INVALID_SECRET);
            
            self._perform_withdrawal(immutables, secret);
            
            self.emit(PublicWithdrawn {
                token: immutables.token,
                withdrawer: get_caller_address(),
                amount: immutables.amount,
                secret
            });
            
            self.reentrancy_guard.end();
        }
        
        fn cancel_private(ref self: ContractState, immutables: Immutables) {
            self.reentrancy_guard.start();
            
            // Private cancellation: only maker after DstCancellation period
            self._validate_immutables(immutables);
            assert(get_caller_address() == immutables.maker, Errors::UNAUTHORIZED_CALLER);
            assert(!self.is_withdrawn.read(), 'Already withdrawn');
            assert(!self.is_cancelled.read(), 'Already cancelled');
            
            // Check timelock: after DstCancellation  
            self._check_timelock_stage(Stage::DstCancellation);
            
            self._perform_cancellation(immutables);
            
            self.emit(PrivateCancelled {
                token: immutables.token,
                canceller: get_caller_address(),
                amount: immutables.amount
            });
            
            self.reentrancy_guard.end();
        }
    }
    
    #[generate_trait]
    impl EscrowDstInternalImpl of EscrowDstInternalTrait {
        fn _validate_immutables(self: @ContractState, immutables: Immutables) {
            let stored_immutables = self.immutables.read();
            
            assert(immutables.maker == stored_immutables.maker, 'Invalid immutables');
            assert(immutables.taker == stored_immutables.taker, 'Invalid immutables');
            assert(immutables.token == stored_immutables.token, 'Invalid immutables');
            assert(immutables.amount == stored_immutables.amount, 'Invalid immutables');
            assert(immutables.hashlock == stored_immutables.hashlock, 'Invalid immutables');
            assert(immutables.timelocks == stored_immutables.timelocks, 'Invalid immutables');
        }
        
        fn _perform_withdrawal(ref self: ContractState, immutables: Immutables, secret: u256) {
            self.is_withdrawn.write(true);
            
            let token = ERC20ABIDispatcher { contract_address: immutables.token };
            let success = token.transfer(immutables.taker, immutables.amount);
            assert(success, 'Transfer failed');
        }
        
        fn _perform_cancellation(ref self: ContractState, immutables: Immutables) {
            self.is_cancelled.write(true);
            
            let token = ERC20ABIDispatcher { contract_address: immutables.token };
            let success = token.transfer(immutables.maker, immutables.amount);
            assert(success, 'Transfer failed');
        }
        
        fn _check_timelock_stage(self: @ContractState, stage: Stage) {
            let immutables = self.immutables.read();
            let timelocks = immutables.timelocks;
            
            assert(timelocks.is_stage_active(stage), 'Too early');
        }
        
        fn _check_before_stage(self: @ContractState, stage: Stage) {
            let immutables = self.immutables.read();
            let timelocks = immutables.timelocks;
            
            assert(timelocks.is_before_stage(stage), 'Too late');
        }
    }
}