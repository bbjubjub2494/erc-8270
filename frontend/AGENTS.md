# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a web frontend for ERC-8270 - a system that represents Ethereum/Gnosis validator stakes as NFTs. Users can mint NFTs for validators, deposit stake, view validator status, and claim withdrawals.

## Development Commands

```bash
# Install dependencies
npm install

# Start development server (with hot reload)
npm run dev

# Build for production
npm run build

# Preview production build
npm run preview
```

## Architecture

### Technology Stack
- **Build Tool**: Vite 7.x (ESM-based, no bundler config needed)
- **Framework**: Vanilla JS with ES modules (no React despite dependencies)
- **Ethereum Interaction**: ethers.js v6 for ABI encoding, hex utilities, and contract interaction
- **Wallet**: EIP-1193 provider (window.ethereum)

### File Structure
- `index.html` / `main.js` - Token viewer page (view validator balances, claim withdrawals)
- `mint.html` / `mint.js` - Mint new NFT for a validator pubkey
- `deposit.html` / `deposit.js` - Deposit stake to a validator (parses deposit data JSON)
- `config.js` - Network configurations and contract ABI
- `styles.css` - Global styles

### Network Configuration
Supports two networks configured in `config.js`:
- **Chiado** (Chain ID 10200): GNO token, ERC20 deposits require approval
- **Hoodi** (Chain ID 560048): Native ETH, payable deposits

### ethers.js v6 Usage
Import patterns used throughout:
```javascript
import { ethers } from 'ethers';

const iface = new ethers.Interface(CONTRACT_ABI);
const calldata = iface.encodeFunctionData('functionName', [args]);
const [result] = iface.decodeFunctionResult('functionName', hexResult);

// For hex/bytes conversions:
const bytes = ethers.getBytes(hexValue);
const hex = ethers.hexlify(bytes);
```

### Contract Interactions
The contract (configured per-network) supports:
- `mint(validatorKey, destination)` - Create NFT for validator
- `deposit(id, compounding, signature, depositDataRoot, [amount])` - Stake to validator
- `pullExecutionLayerBalance(id, destination)` - Claim withdrawals
- View functions: `executionLayerBalanceOf`, `nativeBalanceOf`, `validatorKeyOf`, `withdrawalAddressOf`

### Beacon Chain Integration
The app fetches validator status from beacon chain APIs:
- Chiado: `https://chiado.beaconrpc.bbjubjub.fr`
- Hoodi: `https://hoodi.beaconrpc.bbjubjub.fr`

### EIP-5792 Support
`deposit.js` supports wallet batching (EIP-5792 `wallet_sendCalls`) for single-signature approve+deposit on ERC20 networks, with fallback to two-step approval flow.
