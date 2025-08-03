//! Pre and Post interaction interfaces for order processing
//! Allows custom logic before and after fund transfers

use starknet::ContractAddress;
use crate::{Order};

#[derive(Drop, Serde)]
pub struct InteractionContext {
    pub order: Order,
    pub order_hash: u256,
    pub taker: ContractAddress,
    pub making_amount: u256,
    pub taking_amount: u256,
    pub remaining_making_amount: u256,
    pub extra_data: Array<u256>,
}

// Pre-interaction interface - called before fund transfers
#[starknet::interface]
pub trait IPreInteraction<TContractState> {
    fn pre_interaction(
        ref self: TContractState,
        context: InteractionContext
    );
}

// Post-interaction interface - called after fund transfers  
#[starknet::interface]
pub trait IPostInteraction<TContractState> {
    fn post_interaction(
        ref self: TContractState, 
        context: InteractionContext
    );
}

// Taker interaction interface - called between maker->taker and taker->maker transfers
#[starknet::interface]
pub trait ITakerInteraction<TContractState> {
    fn taker_interaction(
        ref self: TContractState,
        context: InteractionContext
    );
}

// Base extension contract that implements all interaction interfaces
#[starknet::contract]
pub mod BaseExtension {
    use super::InteractionContext;
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::storage::*; // Full path for storage imports

    #[storage]
    struct Storage {
        limit_order_protocol: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PreInteractionExecuted: PreInteractionExecuted,
        PostInteractionExecuted: PostInteractionExecuted,
        TakerInteractionExecuted: TakerInteractionExecuted, // Added for ITakerInteraction
    }

    #[derive(Drop, starknet::Event)]
    struct PreInteractionExecuted {
        #[key]
        order_hash: u256,
        taker: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct PostInteractionExecuted {
        #[key]
        order_hash: u256,
        taker: ContractAddress,
    }

    #[derive(Drop, starknet::Event)] // Added for ITakerInteraction
    struct TakerInteractionExecuted {
        #[key]
        order_hash: u256,
        taker: ContractAddress,
    }

    pub mod Errors {
        pub const UNAUTHORIZED: felt252 = 'Unauthorized caller';
    }

    #[constructor]
    fn constructor(ref self: ContractState, limit_order_protocol: ContractAddress) {
        self.limit_order_protocol.write(limit_order_protocol);
    }


    #[abi(embed_v0)]
    impl PreInteractionImpl of super::IPreInteraction<ContractState> {
        fn pre_interaction(
            ref self: ContractState,
            context: InteractionContext
        ) {
            self.only_limit_order_protocol();
            // Override in derived contracts for custom pre-interaction logic
            self._handle_pre_interaction(context);
        }
    }

    #[abi(embed_v0)]
    impl PostInteractionImpl of super::IPostInteraction<ContractState> {
        fn post_interaction(
            ref self: ContractState,
            context: InteractionContext
        ) {
            self.only_limit_order_protocol();
            // Override in derived contracts for custom post-interaction logic
            self._handle_post_interaction(context);
        }
    }

    #[abi(embed_v0)] // Added for ITakerInteraction
    impl TakerInteractionImpl of super::ITakerInteraction<ContractState> {
        fn taker_interaction(
            ref self: ContractState,
            context: InteractionContext
        ) {
            self.only_limit_order_protocol();
            // Override in derived contracts for custom taker-interaction logic
            self._handle_taker_interaction(context);
        }
    }

    #[generate_trait]
    impl BaseExtensionInternalImpl of BaseExtensionInternalTrait {
        fn only_limit_order_protocol(self: @ContractState) {
            let caller = get_caller_address();
            let protocol = self.limit_order_protocol.read();
            assert(caller == protocol, Errors::UNAUTHORIZED);
        }

        fn _handle_pre_interaction(
            ref self: ContractState,
            context: InteractionContext
        ) {
            // Default implementation - emit event
            self.emit(PreInteractionExecuted {
                order_hash: context.order_hash,
                taker: context.taker
            });
        }

        fn _handle_post_interaction(
            ref self: ContractState,
            context: InteractionContext
        ) {
            // Default implementation - emit event
            self.emit(PostInteractionExecuted {
                order_hash: context.order_hash,
                taker: context.taker
            });
        }

        fn _handle_taker_interaction( // Added for ITakerInteraction
            ref self: ContractState,
            context: InteractionContext
        ) {
            // Default implementation - emit event
            self.emit(TakerInteractionExecuted {
                order_hash: context.order_hash,
                taker: context.taker
            });
        }
    }
}

// Interaction utilities
pub mod InteractionUtils {
    use super::InteractionContext;
    use crate::Order;
    use starknet::ContractAddress;

    pub fn create_context(
        order: Order,
        order_hash: u256,
        taker: ContractAddress,
        making_amount: u256,
        taking_amount: u256,
        remaining_making_amount: u256,
        extra_data: Array<u256>
    ) -> InteractionContext {
        InteractionContext {
            order,
            order_hash,
            taker,
            making_amount,
            taking_amount,
            remaining_making_amount,
            extra_data
        }
    }
}