//! Source escrow contract for cross-chain atomic swaps
//! Handles multiple withdrawal and cancellation modes on the source chain

use crate::Immutables;

#[starknet::interface]
pub trait IEscrowSrc<TContractState> {
    fn withdraw_public(ref self: TContractState, immutables: Immutables, secret: u256);
    fn cancel_public(ref self: TContractState, immutables: Immutables);
    fn cancel_private(ref self: TContractState, immutables: Immutables);
}

#[starknet::contract]
pub mod EscrowSrc {
    use super::{IEscrowSrc, Immutables};
    use crate::escrow_base::{IBaseEscrow, RESCUE_DELAY};
    use crate::hashlock::{HashlockValidatorTrait, Errors as HashlockErrors};
    use crate::timelock::{TimelocksTrait, Stage};
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
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
        Deposited: Deposited,
        Withdrawn: Withdrawn,
        PublicWithdrawn: PublicWithdrawn,
        Cancelled: Cancelled,
        PublicCancelled: PublicCancelled,
        PrivateCancelled: PrivateCancelled,
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
    struct PublicWithdrawn {
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
    struct PublicCancelled {
        #[key]
        token: ContractAddress,
        #[key]
        canceller: ContractAddress,
        amount: u256,
    }
    
    #[derive(Drop, starknet::Event)]
    struct PrivateCancelled {
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
        pub const UNAUTHORIZED_CALLER: felt252 = 'Unauthorized caller';
        pub const ALREADY_WITHDRAWN: felt252 = 'Already withdrawn';
        pub const ALREADY_CANCELLED: felt252 = 'Already cancelled';
        pub const INVALID_IMMUTABLES: felt252 = 'Invalid immutables';
        pub const TRANSFER_FAILED: felt252 = 'Transfer failed';
    }
    
    #[constructor]
    fn constructor(ref self: ContractState, immutables: Immutables) {
        self.ownable.initializer(immutables.maker);
        self.immutables.write(immutables);
        self.deployed_at.write(get_block_timestamp());
        
        // Token transfer will be handled by the factory after deployment
        
        self.emit(Deposited {
            token: immutables.token,
            depositor: immutables.maker,
            amount: immutables.amount
        });
    }
    
    #[abi(embed_v0)]
    impl BaseEscrowImpl of IBaseEscrow<ContractState> {
        fn get_immutables(self: @ContractState) -> Immutables {
            self.immutables.read()
        }
        
        fn withdraw(ref self: ContractState, immutables: Immutables, secret: u256) {
            self.reentrancy_guard.start();
            
            // Private withdrawal: only maker during SrcWithdrawal period
            self._validate_immutables(immutables);
            assert(get_caller_address() == immutables.maker, Errors::UNAUTHORIZED_CALLER);
            assert(!self.is_withdrawn.read(), Errors::ALREADY_WITHDRAWN);
            assert(!self.is_cancelled.read(), Errors::ALREADY_CANCELLED);
            
            // Check timelock: after SrcWithdrawal, before SrcCancellation
            self._check_timelock_stage(Stage::SrcWithdrawal);
            self._check_before_stage(Stage::SrcCancellation);
            
            // Validate secret
            let hashlock_validator = HashlockValidatorTrait::new(immutables.hashlock);
            assert(hashlock_validator.validate(secret), HashlockErrors::INVALID_SECRET);
            
            self._perform_withdrawal(immutables, secret);
            
            self.reentrancy_guard.end();
        }
        
        fn cancel(ref self: ContractState, immutables: Immutables) {
            // This is for private cancellation: only maker after SrcCancellation
            self.reentrancy_guard.start();
            
            self._validate_immutables(immutables);
            assert(get_caller_address() == immutables.maker, Errors::UNAUTHORIZED_CALLER);
            assert(!self.is_withdrawn.read(), Errors::ALREADY_WITHDRAWN);
            assert(!self.is_cancelled.read(), Errors::ALREADY_CANCELLED);
            
            // Check timelock: after SrcCancellation
            self._check_timelock_stage(Stage::SrcCancellation);
            
            self._perform_cancellation(immutables);
            
            self.reentrancy_guard.end();
        }
        
        fn rescue(ref self: ContractState, token: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            
            let immutables = self.immutables.read();
            let timelocks = immutables.timelocks;
            let rescue_time = timelocks.rescue_start(RESCUE_DELAY);
            
            assert(get_block_timestamp() >= rescue_time, 'Too early for rescue');
            
            let erc20 = ERC20ABIDispatcher { contract_address: token };
            let success = erc20.transfer(get_caller_address(), amount);
            assert(success, Errors::TRANSFER_FAILED);
            
            self.emit(Rescued { token, amount });
        }
    }
    
    #[abi(embed_v0)]
    impl EscrowSrcImpl of IEscrowSrc<ContractState> {
        fn withdraw_public(ref self: ContractState, immutables: Immutables, secret: u256) {
            self.reentrancy_guard.start();
            
            // Public withdrawal: anyone during SrcPublicWithdrawal period
            self._validate_immutables(immutables);
            assert(!self.is_withdrawn.read(), Errors::ALREADY_WITHDRAWN);
            assert(!self.is_cancelled.read(), Errors::ALREADY_CANCELLED);
            
            // Check timelock: after SrcPublicWithdrawal, before SrcCancellation
            self._check_timelock_stage(Stage::SrcPublicWithdrawal);
            self._check_before_stage(Stage::SrcCancellation);
            
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
        
        fn cancel_public(ref self: ContractState, immutables: Immutables) {
            self.reentrancy_guard.start();
            
            // Public cancellation: anyone after SrcPublicCancellation period
            self._validate_immutables(immutables);
            assert(!self.is_withdrawn.read(), Errors::ALREADY_WITHDRAWN);
            assert(!self.is_cancelled.read(), Errors::ALREADY_CANCELLED);
            
            // Check timelock: after SrcPublicCancellation
            self._check_timelock_stage(Stage::SrcPublicCancellation);
            
            self._perform_cancellation(immutables);
            
            self.emit(PublicCancelled {
                token: immutables.token,
                canceller: get_caller_address(),
                amount: immutables.amount
            });
            
            self.reentrancy_guard.end();
        }
        
        fn cancel_private(ref self: ContractState, immutables: Immutables) {
            self.reentrancy_guard.start();
            
            // Private cancellation: only maker after SrcCancellation period
            self._validate_immutables(immutables);
            assert(get_caller_address() == immutables.maker, Errors::UNAUTHORIZED_CALLER);
            assert(!self.is_withdrawn.read(), Errors::ALREADY_WITHDRAWN);
            assert(!self.is_cancelled.read(), Errors::ALREADY_CANCELLED);
            
            // Check timelock: after SrcCancellation
            self._check_timelock_stage(Stage::SrcCancellation);
            
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
    impl EscrowSrcInternalImpl of EscrowSrcInternalTrait {
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
            
            let token = ERC20ABIDispatcher { contract_address: immutables.token };
            let success = token.transfer(immutables.taker, immutables.amount);
            assert(success, Errors::TRANSFER_FAILED);
            
            self.emit(Withdrawn {
                token: immutables.token,
                withdrawer: get_caller_address(),
                amount: immutables.amount,
                secret
            });
        }
        
        fn _perform_cancellation(ref self: ContractState, immutables: Immutables) {
            self.is_cancelled.write(true);
            
            let token = ERC20ABIDispatcher { contract_address: immutables.token };
            let success = token.transfer(immutables.maker, immutables.amount);
            assert(success, Errors::TRANSFER_FAILED);
            
            self.emit(Cancelled {
                token: immutables.token,
                canceller: get_caller_address(),
                amount: immutables.amount
            });
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