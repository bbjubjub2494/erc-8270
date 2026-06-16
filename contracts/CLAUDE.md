# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
forge build                  # Compile all contracts
forge test                   # Run full test suite
forge test --match-test <name>  # Run a single test
forge fmt                    # Format Solidity files
just fmt                     # Format Vyper + Solidity (mamushi + forge fmt)
just check                   # Full check: fmt + test + gas snapshot
just check-fmt               # Format check only
just check-snapshot          # Gas snapshot check only
forge snapshot               # Update gas snapshot baselines
node generate.mjs            # Generate dist/index.js (ABIs + deployed addresses)
just verify                  # Sourcify verification for Gnosis/Chiado/Ethereum mainnet
```

## Architecture

This project implements ERC-8270, an ERC-721 NFT standard for managing Ethereum staking validators. Each token represents a validator identified by its BLS12-381 public key and controls a dedicated withdrawal address.

**Languages**: Vyper 0.4.3 (EVM: Prague) for core contracts, Solidity ^0.8 for interfaces, periphery, and tests. **Tooling**: Foundry + Soldeer (dependencies), Just (task runner). The repo uses Jujutsu (`.jj/`) rather than Git.

### Core contracts (Vyper — in the `ercs` dependency)

The Vyper source files live in `dependencies/ercs-unversioned/assets/erc-8270/`, not in `src/`. They are vendored from a custom branch of the [ercs](https://github.com/bbjubjub2494/ercs) repository.

**`ERC8270.vy`** — Main ERC-721 implementation. Implements ERC-721, ERC-721 Enumerable, ERC-5646 (state fingerprinting), and ERC-8270. Key design choices:
- BLS12 public keys are split into a 256-bit `hi` and 128-bit `lo` component to fit in `TokenData` structs.
- Owner and per-owner index are packed into a single `uint256` in storage (address in lower 160 bits, index in upper 96 bits) — see `_pack` / `_unpack`.
- A `bytes32[244]` padding array puts `token_data[0]` at slot 0xFC and the first real token (`id=1`) at slot 0x100, creating a clean alignment boundary.
- Each token gets a deterministic `WithdrawalReceiver` deployed via `create_minimal_proxy_to()` using CREATE2, with salt `keccak256(key_hi, key_lo, initial_owner)`.

**`WithdrawalReceiver.vy`** — Minimal proxy per validator. Receives ETH from withdrawals; forwards EIP-7002 partial/full withdrawal requests and EIP-7251 consolidation/compounding requests to the system contracts. Also forwards arbitrary calls from the controller (ERC8270).

**`format_helpers.vy`** and **`IWithdrawalReceiver.vyi`** — Utility module and Vyper interface.

System contract addresses hardcoded in `WithdrawalReceiver.vy`:
- EIP-7002 (withdrawal requests): `0x00000961Ef480Eb55e80D19ad83579A64c007002`
- EIP-7251 (consolidation): `0x0000BBdDc7CE488642fb579F8B00f3a590007251`

### Interfaces and periphery (Solidity — in `src/`)

**`src/interfaces/`** — Solidity interfaces consumed by tests and periphery:
- `IERC8270.sol`, `IERC5646.sol` — the ERC-8270 and ERC-5646 interfaces
- `IDepositContract.sol`, `ISBCDepositContract.sol`, `IERC677.sol` — beacon deposit contract interfaces for ETH mainnet and Gnosis Chain

**`src/periphery/`** — Deposit helper contracts (not part of the ERC-8270 core):
- `DepositsBase.sol` — abstract base with shared deposit data root calculation and little-endian conversion helpers
- `Deposits.sol` — ETH mainnet deposit helper; wraps the EIP-2612 `DepositContract` (`deposit()` payable)
- `DepositsGno.sol` — Gnosis Chain variant; uses GNO ERC-677 token via `transferAndCall` into the SBC deposit contract

Both helpers expose `protected(...)` (checks deposit root to prevent frontrunning) and `frontrunnable(...)` variants, plus `topup(id)` for top-ups using a zero-signature deposit.

### Deployment

`scripts/Deploy.s.sol` deploys via FFI: it calls `uv run dependencies/ercs-unversioned/assets/erc-8270/prepare.py` to get the Vyper-compiled initcode as JSON, then deploys through the CREATE2 factory at `0x4e59b44847b379578588920cA78FbF26c0B4956C`. The ERC-8270 contract has a vanity address ending in `08270`. Supported chains: Hoodi testnet (`560048`), Gnosis Chain, Gnosis Chiado.

### State fingerprinting (ERC-5646)

Token state is hashed with EIP-712-style encoding. The fingerprint changes on: mint, `pullNativeBalance`, consolidation request, and `arbitraryCall`. Withdrawal requests (`requestFullWithdrawal`, `requestPartialWithdrawal`, `requestSwitchToCompounding`) do **not** change the fingerprint. This lets smart contracts detect unexpected state mutations before acting.

### JS distribution

`generate.mjs` reads compiled ABIs from `out/` and deployed addresses from `broadcast/Deploy.s.sol/<chainId>/run-latest.json`, then writes `dist/index.js` exporting `IERC8270ABI`, `DepositsABI`, `DepositsGnoABI`, and a `deployments` mapping by chain ID.
