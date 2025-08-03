//! Base escrow contract with common functionality
//! Implements core atomic swap logic with timelock and hashlock validation

use starknet::ContractAddress;
use crate::Immutables;

pub const RESCUE_DELAY: u64 = 365 * 24 * 60 * 60; // 1 year in seconds

#[starknet::interface]
pub trait IBaseEscrow<TContractState> {
    fn get_immutables(self: @TContractState) -> Immutables;
    fn withdraw(ref self: TContractState, immutables: Immutables, secret: u256);
    fn cancel(ref self: TContractState, immutables: Immutables);
    fn rescue(ref self: TContractState, token: ContractAddress, amount: u256);
}

#[starknet::contract]
pub mod BaseEscrow {
    use super::{IBaseEscrow, Immutables, RESCUE_DELAY};
    use crate::hashlock::{HashlockValidatorTrait, Errors as HashlockErrors};
    use crate::timelock::{TimelocksTrait, Stage, Errors as TimelockErrors};
    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_block_timestamp, get_contract_address};
    use starknet::storage::*;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::security::reentrancyguard::ReentrancyGuardComponent;
    
    component!(path: openzeppelin::access::ownable::OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: openzeppelin::security::reentrancyguard::ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent);
    
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
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
        Deposited: Deposited,
        Withdrawn: Withdrawn,
        Cancelled: Cancelled,
        Rescued: Rescued,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
    }
    
    #[derive(Drop, starknet::Event)]
    struct Deposited {
        #[key]
        token: ContractAddress,
        #[key]
        depositor: ContractAddress,
        amount: u256,
    }
    
    #[derive(Drop, starknet::Event)]
    struct Withdrawn {
        #[key]
        token: ContractAddress,
        #[key]
        withdrawer: ContractAddress,
        amount: u256,
        secret: u256,
    }
    
    #[derive(Drop, starknet::Event)]
    struct Cancelled {
        #[key]
        token: ContractAddress,
        #[key]
        canceller: ContractAddress,
        amount: u256,
    }
    
    #[derive(Drop, starknet::Event)]
    struct Rescued {
        #[key]
        token: ContractAddress,
        amount: u256,
    }
    
    pub mod Errors {
        pub const INVALID_IMMUTABLES: felt252 = 'Invalid immutables';
        pub const ALREADY_WITHDRAWN: felt252 = 'Already withdrawn';
        pub const ALREADY_CANCELLED: felt252 = 'Already cancelled';
        pub const INSUFFICIENT_BALANCE: felt252 = 'Insufficient balance';
        pub const TRANSFER_FAILED: felt252 = 'Transfer failed';
        pub const UNAUTHORIZED: felt252 = 'Unauthorized';
    }
    
    #[constructor]
    fn constructor(ref self: ContractState, immutables: Immutables) {
        self.ownable.initializer(immutables.maker);
        self.immutables.write(immutables);
        self.deployed_at.write(get_block_timestamp());
        
        // Transfer tokens to escrow contract
        let erc20_dispatcher = IERC20Dispatcher { contract_address: immutables.token };
        let success = erc20_dispatcher.transfer_from(
            immutables.maker,
            get_contract_address(),
            immutables.amount
        );
        assert(success, Errors::TRANSFER_FAILED);
        
        self.emit(Deposited {
            token: immutables.token,
            depositor: immutables.maker,
            amount: immutables.amount
        });
    }
    
    #[abi(embed_v0)]
    pub impl BaseEscrowImpl of IBaseEscrow<ContractState> {
        fn get_immutables(self: @ContractState) -> Immutables {
            self.immutables.read()
        }
        
        fn withdraw(ref self: ContractState, immutables: Immutables, secret: u256) {
            self.reentrancy_guard.start();
            
            self._validate_immutables(immutables);
            assert(!self.is_withdrawn.read(), Errors::ALREADY_WITHDRAWN);
            assert(!self.is_cancelled.read(), Errors::ALREADY_CANCELLED);
            
            // Validate secret against hashlock
            let hashlock_validator = HashlockValidatorTrait::new(immutables.hashlock);
            assert(hashlock_validator.validate(secret), HashlockErrors::INVALID_SECRET);
            
            self._perform_withdrawal(immutables, secret);
            
            self.reentrancy_guard.end();
        }
        
        fn cancel(ref self: ContractState, immutables: Immutables) {
            self.reentrancy_guard.start();
            
            self._validate_immutables(immutables);
            assert(!self.is_withdrawn.read(), Errors::ALREADY_WITHDRAWN);
            assert(!self.is_cancelled.read(), Errors::ALREADY_CANCELLED);
            
            self._perform_cancellation(immutables);
            
            self.reentrancy_guard.end();
        }
        
        fn rescue(ref self: ContractState, token: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            
            let immutables = self.immutables.read();
            let timelocks = immutables.timelocks;
            let rescue_time = timelocks.rescue_start(RESCUE_DELAY);
            
            assert(get_block_timestamp() >= rescue_time, TimelockErrors::TOO_EARLY);
            
            let erc20_dispatcher = IERC20Dispatcher { contract_address: token };
            let success = erc20_dispatcher.transfer(get_caller_address(), amount);
            assert(success, Errors::TRANSFER_FAILED);
            
            self.emit(Rescued { token, amount });
        }
    }
    
    #[generate_trait]
    impl BaseEscrowInternalImpl of BaseEscrowInternalTrait {
        fn _validate_immutables(self: @ContractState, immutables: Immutables) {
            let stored_immutables = self.immutables.read();
            
            assert(immutables.maker == stored_immutables.maker, Errors::INVALID_IMMUTABLES);
            assert(immutables.taker == stored_immutables.taker, Errors::INVALID_IMMUTABLES);
            assert(immutables.token == stored_immutables.token, Errors::INVALID_IMMUTABLES);
            assert(immutables.amount == stored_immutables.amount, Errors::INVALID_IMMUTABLES);
            assert(immutables.hashlock == stored_immutables.hashlock, Errors::INVALID_IMMUTABLES);
            assert(immutables.timelocks == stored_immutables.timelocks, Errors::INVALID_IMMUTABLES);
        }
        
        fn _perform_withdrawal(ref self: ContractState, immutables: Immutables, secret: u256) {
            self.is_withdrawn.write(true);
            
            let erc20_dispatcher = IERC20Dispatcher { contract_address: immutables.token };
            let success = erc20_dispatcher.transfer(immutables.taker, immutables.amount);
            assert(success, Errors::TRANSFER_FAILED);
            
            self.emit(Withdrawn {
                token: immutables.token,
                withdrawer: immutables.taker,
                amount: immutables.amount,
                secret
            });
        }
        
        fn _perform_cancellation(ref self: ContractState, immutables: Immutables) {
            self.is_cancelled.write(true);
            
            let erc20_dispatcher = IERC20Dispatcher { contract_address: immutables.token };
            let success = erc20_dispatcher.transfer(immutables.maker, immutables.amount);
            assert(success, Errors::TRANSFER_FAILED);
            
            self.emit(Cancelled {
                token: immutables.token,
                canceller: immutables.maker,
                amount: immutables.amount
            });
        }
        
        fn _check_timelock_stage(self: @ContractState, stage: Stage) {
            let immutables = self.immutables.read();
            let timelocks = immutables.timelocks;
            
            assert(timelocks.is_stage_active(stage), TimelockErrors::TOO_EARLY);
        }
        
        fn _check_before_stage(self: @ContractState, stage: Stage) {
            let immutables = self.immutables.read();
            let timelocks = immutables.timelocks;
            
            assert(timelocks.is_before_stage(stage), TimelockErrors::TOO_LATE);
        }
    }
}