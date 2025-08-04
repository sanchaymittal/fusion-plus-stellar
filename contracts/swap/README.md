# Atomic Swap Contract

A Soroban smart contract for trustless cross-chain atomic swaps on the Stellar network.

## Overview

This contract implements the Hashed Timelock Contract (HTLC) pattern, enabling secure token swaps between parties without requiring trust. The contract uses both hashlock and timelock mechanisms to ensure atomicity - either both parties successfully complete the swap, or neither does.

## Features

- **Hashlock Security**: Swaps are protected by cryptographic hash functions
- **Timelock Protection**: Built-in expiration mechanism prevents funds from being locked forever
- **Escrow Management**: Secure holding of funds during the swap process
- **Event Emission**: Comprehensive event logging for swap lifecycle tracking

## Contract Structure

```
swap/
├── src/
│   ├── lib.rs          # Main contract implementation
│   ├── types.rs        # Data structures and types
│   ├── events.rs       # Event definitions
│   ├── escrow.rs       # Escrow management utilities
│   ├── hashlock.rs     # Hashlock validation logic
│   ├── timelock.rs     # Timelock validation logic
│   └── test.rs         # Comprehensive test suite
└── Cargo.toml          # Contract dependencies
```

## Key Functions

### `create_escrow`
Creates a new atomic swap escrow with specified parameters:
- `maker`: Address initiating the swap
- `taker`: Address receiving the swap
- `token`: Token contract address
- `amount`: Amount to be swapped
- `hashlock`: Hash of the secret preimage
- `timelock_start`: When the swap becomes active
- `timelock_end`: When the swap expires

### `withdraw`
Allows the taker to withdraw funds by providing the correct preimage.

### `cancel`
Allows the maker to cancel and reclaim funds after timelock expiration.

## Usage Example

```rust
// Create a new atomic swap
let secret = "my_secret_phrase";
let hashlock = sha256(secret);

let escrow_id = swap_contract.create_escrow(
    &env,
    maker_address,
    taker_address,
    token_address,
    1000, // amount
    hashlock,
    current_time,
    current_time + 3600, // 1 hour expiration
);

// Taker withdraws with preimage
swap_contract.withdraw(&env, escrow_id, secret);
```

## Security Considerations

1. **Preimage Security**: Keep the preimage secret until ready to withdraw
2. **Timelock Duration**: Set appropriate timelock duration for cross-chain coordination
3. **Hash Function**: Uses SHA-256 for cryptographic security
4. **Authorization**: Only designated parties can interact with their escrows

## Testing

Run the comprehensive test suite:

```bash
cargo test
```

Tests cover:
- Basic swap functionality
- Edge cases and error conditions
- Event emission verification
- Security scenarios