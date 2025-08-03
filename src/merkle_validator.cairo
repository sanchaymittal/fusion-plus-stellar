//! Merkle tree validation for partial fills
//! Allows atomic swaps to be split across multiple transactions

// Global imports for common types and traits
use core::felt252;
use core::integer::u256;


// Define MerkleLeaf struct globally as it's used by multiple components
#[derive(Drop, Serde, Copy, starknet::Store)]
pub struct MerkleLeaf {
    pub leaf_hash: felt252,
    pub amount: u256,
}

// Interface for Merkle proof verification functions
#[starknet::interface]
pub trait IMerkleVerifier<TContractState> {
    fn verify_single_proof(self: @TContractState, proof: Span<felt252>, root: felt252, leaf: felt252) -> bool;
    fn verify_single_proof_poseidon(self: @TContractState, proof: Span<felt252>, root: felt252, leaf: felt252) -> bool;
    fn verify_multi_proof(
        self: @TContractState,
        proof: Span<felt252>,
        proof_flags: Span<bool>,
        root: felt252,
        leaves: Span<felt252>
    ) -> bool;
    fn verify_multi_proof_poseidon(
        self: @TContractState,
        proof: Span<felt252>,
        proof_flags: Span<bool>,
        root: felt252,
        leaves: Span<felt252>
    ) -> bool;
}

#[starknet::contract]
pub mod MerkleVerifier {
    // Imports specific to this contract module
    use core::felt252;
    use openzeppelin_merkle_tree::merkle_proof;
    use openzeppelin_merkle_tree::hashes::{PedersenCHasher, PoseidonCHasher};

    #[storage]
    struct Storage {} // Merkle verifier is stateless

    #[abi(embed_v0)]
    pub impl MerkleVerifierImpl of super::IMerkleVerifier<ContractState> {
        /// Verifies a single Merkle proof using Pedersen hash.
        fn verify_single_proof(self: @ContractState, proof: Span<felt252>, root: felt252, leaf: felt252) -> bool {
            merkle_proof::verify::<PedersenCHasher>(proof, root, leaf)
        }

        /// Verifies a single Merkle proof using Poseidon hash (more efficient).
        fn verify_single_proof_poseidon(self: @ContractState, proof: Span<felt252>, root: felt252, leaf: felt252) -> bool {
            merkle_proof::verify::<PoseidonCHasher>(proof, root, leaf)
        }

        /// Verifies a multi Merkle proof using Pedersen hash.
        fn verify_multi_proof(
            self: @ContractState,
            proof: Span<felt252>,
            proof_flags: Span<bool>,
            root: felt252,
            leaves: Span<felt252>
        ) -> bool {
            merkle_proof::verify_multi_proof::<PedersenCHasher>(proof, proof_flags, root, leaves)
        }

        /// Verifies a multi Merkle proof using Poseidon hash (more efficient).
        fn verify_multi_proof_poseidon(
            self: @ContractState,
            proof: Span<felt252>,
            proof_flags: Span<bool>,
            root: felt252,
            leaves: Span<felt252>
        ) -> bool {
            merkle_proof::verify_multi_proof::<PoseidonCHasher>(proof, proof_flags, root, leaves)
        }
    }
}

// Interface for Merkle storage invalidator
#[starknet::interface]
pub trait IMerkleStorageInvalidator<TContractState> {
    fn get_last_validated(self: @TContractState, key: felt252) -> MerkleLeaf;
    fn invalidate_merkle_leaf(ref self: TContractState, key: felt252, leaf: MerkleLeaf);
    fn is_leaf_valid(self: @TContractState, key: felt252, leaf: MerkleLeaf) -> bool;
}

#[starknet::contract]
pub mod MerkleStorageInvalidator {
    // Imports specific to this contract module
    use super::{IMerkleStorageInvalidator, MerkleLeaf};
        use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };

    #[storage]
    struct Storage {
        validated_leaves: Map<felt252, MerkleLeaf>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MerkleLeafInvalidated: MerkleLeafInvalidated,
    }

    #[derive(Drop, starknet::Event)]
    struct MerkleLeafInvalidated {
        #[key]
        key: felt252,
        leaf: MerkleLeaf,
    }

    #[abi(embed_v0)]
    pub impl MerkleStorageInvalidatorImpl of IMerkleStorageInvalidator<ContractState> {
        fn get_last_validated(self: @ContractState, key: felt252) -> MerkleLeaf {
            // Returns a default MerkleLeaf (all zeros) if the key is not found
            self.validated_leaves.entry(key).read()
        }

        fn invalidate_merkle_leaf(ref self: ContractState, key: felt252, leaf: MerkleLeaf) {
            self.validated_leaves.entry(key).write(leaf);
            self.emit(MerkleLeafInvalidated { key, leaf });
        }

        fn is_leaf_valid(self: @ContractState, key: felt252, leaf: MerkleLeaf) -> bool {
            let last_validated = self.get_last_validated(key);
            // A leaf is valid if it has a higher amount than the last validated leaf
            leaf.amount > last_validated.amount
        }
    }
}

// Error definitions
pub mod Errors {
    use core::felt252;
    pub const INVALID_MERKLE_PROOF: felt252 = 'Invalid merkle proof';
    pub const MERKLE_LEAF_ALREADY_USED: felt252 = 'Merkle leaf already used';
    pub const INVALID_MULTI_PROOF: felt252 = 'Invalid multi proof';
    pub const INVALID_PROOF_FLAGS: felt252 = 'Invalid proof flags length';
    pub const EMPTY_PROOF: felt252 = 'Proof cannot be empty';
}