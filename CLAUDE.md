# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
forge build                  # Compile all contracts
forge test                   # Run full test suite
forge test --match-test <name>  # Run a single test
forge fmt                    # Format Solidity files
just fmt                     # Format Vyper + Solidity
just check                   # Full check: fmt + test + gas snapshot
just check-fmt               # Format check only
just check-snapshot          # Gas snapshot check only
forge snapshot               # Update gas snapshot baselines
```

## Architecture

This project implements an ERC-721 NFT standard for managing Ethereum staking validators. Each token represents a validator, identified by its BLS12-381 public key.

**Languages**: Vyper 0.4.3 (EVM: Prague) for contracts, Solidity ^0.8 for interfaces and tests. **Tooling**: Foundry + Soldeer (dependencies), Just (task runner). The repo uses Jujutsu (`.jj/`) rather than Git.

### Core contracts

**`src/ERCXXXX.vy`** — Main ERC-721 implementation. Implements ERC-721, ERC-721 Enumerable, ERC-5646 (state fingerprinting), and the custom ERC-XXXX standard. Key design choices:
- BLS12 public keys are split into a 256-bit `hi` and 128-bit `lo` component to fit in `TokenData` structs.
- Owner/index are packed into a single `uint256` in storage (address in lower 160 bits, index in upper 96 bits) — see `pack_owner` / `unpack_owner`.
- There is 0xf8 bytes of padding before the first `TokenData` entry to align storage at a clean boundary.
- Each token gets a deterministic withdrawal receiver deployed via `create_minimal_proxy_to()` using CREATE2, with salt `keccak256(key_hi, key_lo, initial_owner)`.

**`src/WithdrawalReceiver.vy`** — Minimal proxy contract per validator. Receives ETH from withdrawals; exposes EIP-7002 partial/full withdrawal requests and EIP-7251 consolidation/compounding switch requests to the withdrawal address. Also forwards arbitrary calls from the withdrawal address.

**`src/interfaces/`** — Solidity interfaces (`IERCXXXX.sol`, `IERC5646.sol`) and a Vyper interface stub (`IWithdrawalReceiver.vyi`).

### State fingerprinting (ERC-5646)

Token state is hashed with EIP-712-style encoding. The fingerprint changes on: mint, native balance pull, consolidation request, and arbitrary call. This allows smart contracts to detect unexpected state mutations.

### EIP-7002 / EIP-7251 integration

Hardcoded system contract addresses used by `WithdrawalReceiver.vy`:
- EIP-7002 (withdrawal requests): `0x00000961Ef480Eb55e80D19ad83579A64c007002`
- EIP-7251 (consolidation): `0x0000BBdDc7CE488642fb579F8B00f3a590007251`
