# Fusion Plus Stellar

A collection of smart contracts built on the Stellar blockchain using Soroban, including cross-chain atomic swap functionality.

## Overview

This project implements essential DeFi primitives on Stellar's Soroban smart contract platform:

- **Atomic Swap Contract**: Enable trustless cross-chain token swaps with hashlock and timelock mechanisms
- **Token Contract**: Standard token implementation following Stellar's token interface

## Project Structure

```
fusion-plus-stellar/
├── contracts/
│   ├── swap/            # Cross-chain atomic swap contract
│   └── token/           # Token contract implementation
├── Cargo.toml           # Workspace configuration
└── README.md            # This file
```

## Contracts

### Atomic Swap Contract

Located in `contracts/swap/`, this contract enables trustless cross-chain atomic swaps using:

- **Hashlock**: Cryptographic hash-based locking mechanism
- **Timelock**: Time-based expiration for swap security
- **Escrow Management**: Secure fund holding during swap execution

Key features:
- Create escrow with maker/taker addresses, token, amount, and lock parameters
- Withdraw funds by providing the correct preimage
- Cancel escrow after timelock expiration
- Event emission for tracking swap lifecycle

### Token Contract

A standard token implementation in `contracts/token/` that provides:
- Token minting and burning
- Transfer functionality
- Balance queries
- Allowance management


## Prerequisites

- [Rust](https://www.rust-lang.org/tools/install) (latest stable version)
- [Stellar CLI](https://developers.stellar.org/docs/tools/stellar-cli)
- [Soroban CLI](https://soroban.stellar.org/docs/getting-started/setup)

## Setup

1. Clone the repository:
```bash
git clone https://github.com/yourusername/fusion-plus-stellar.git
cd fusion-plus-stellar
```

2. Install dependencies:
```bash
cargo build
```

3. Run tests:
```bash
cargo test
```

## Building Contracts

To build all contracts:
```bash
stellar contract build
```

To build a specific contract:
```bash
cd contracts/swap
stellar contract build
```

## Testing

Each contract includes comprehensive test suites. Run tests with:

```bash
# Test all contracts
cargo test

# Test specific contract
cd contracts/swap
cargo test
```

## Deployment

Deploy contracts to Stellar's testnet:

```bash
# Deploy swap contract
stellar contract deploy \
  --wasm target/wasm32-unknown-unknown/release/swap.wasm \
  --source YOUR_SECRET_KEY \
  --network testnet
```

## Usage Example

### Creating an Atomic Swap

```rust
// Initialize escrow for atomic swap
let escrow_id = contract.create_escrow(
    &env,
    maker_address,
    taker_address,
    token_address,
    amount,
    hashlock,
    timelock_start,
    timelock_end,
);

// Taker withdraws by providing preimage
contract.withdraw(&env, escrow_id, preimage);
```

## Security Considerations

- Always verify hashlock and timelock parameters before creating swaps
- Ensure sufficient timelock duration for cross-chain coordination
- Test thoroughly on testnet before mainnet deployment

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Resources

- [Stellar Documentation](https://developers.stellar.org/)
- [Soroban Documentation](https://soroban.stellar.org/docs)
- [Stellar Laboratory](https://laboratory.stellar.org/)