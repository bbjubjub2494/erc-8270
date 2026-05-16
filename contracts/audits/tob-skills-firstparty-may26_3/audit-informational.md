# ERC-XXXX Informational Findings

## I-01: `tokenURI` Contains Placeholder Image Field
**`src/core/ERCXXXX.vy:116`**

`"image": "TODO"` is hardcoded in the on-chain JSON metadata. The token URI is otherwise fully on-chain. This is incomplete — marketplaces and wallets that render NFT images will display nothing or an error.

---

## I-02: `initial_owner` in CREATE2 Salt Allows Duplicate Validator Wrapping
**`src/core/ERCXXXX.vy:315`**

The CREATE2 salt includes `initial_owner`, meaning the same BLS12-381 key can be minted multiple times by different callers. Two NFTs can exist for one validator, each with a distinct withdrawal address. The beacon chain only honors the validator's actual withdrawal credential — so only one of them controls the real validator. The other token is effectively a phantom with a withdrawal address that will never receive protocol-level ETH. This is likely intentional (enables re-wrapping after transferring ownership) but is a significant semantic design choice worth documenting explicitly.

---

## I-03: No Burn Mechanism
**`src/core/ERCXXXX.vy`**

There is no way to destroy a token. After a validator fully exits and its balance is returned to the withdrawal address, the NFT persists permanently. `totalSupply()` monotonically increases. `tokenByIndex` and `tokenOfOwnerByIndex` will continue to return these dead tokens. Protocol users cannot signal that a validator has exited.

---

## I-04: Withdrawal Requests Excluded from State Fingerprint
**`src/core/ERCXXXX.vy:350–376`**

`requestPartialWithdrawal` and `requestFullWithdrawal` do not update `state_fingerprint`. A buyer using ERC-5646 for pre-purchase state checks cannot detect a pending full exit (which would drain the validator's balance) from the fingerprint alone. The design decision is documented by test (`test_state_fingerprint`), but the ERC-5646 guarantees are meaningfully weakened for DeFi integrations that rely on fingerprint stability.

---

## I-05: Production Contract Imports Test Mock
**`src/periphery/DepositsGno.sol:12`**

```solidity
import {SBCDepositContractMock} from "test/mock/SBCDepositContractMock.sol";
```

The symbol `SBCDepositContractMock` is never referenced in the contract body. This is a dead import of test code into a production contract. It does not affect deployed bytecode (Solidity imports don't pull in bytecode unless instantiated), but it should be removed before deployment.

---

## I-06: Zero-Balance `pullNativeBalance` Executes Destination Code
**`src/core/WithdrawalReceiver.vy`**

`_pull_native_balance` calls `raw_call(destination, b"", value=self.balance)`. When `self.balance == 0`, this performs a zero-value CALL to `destination`, which still executes the destination's code (including fallback). This is observable as a side effect — callers who observe no ETH transferred may still cause side effects at the destination. Not a vulnerability given CEI is respected in the caller, but a behavioral subtlety.

---

## I-07: Excess `msg.value` Stranded in WithdrawalReceiver After Beacon Chain Requests
**`src/core/WithdrawalReceiver.vy`** — `beacon_chain_request`

The fee paid to EIP-7002/7251 system contracts is the exact value returned by the system contract's fee query. Any `msg.value` sent beyond that fee accumulates in the `WithdrawalReceiver` balance and can only be recovered via a subsequent `pullNativeBalance` call. This is the intended design (balance acts as a buffer), but callers who overpay must take a separate action to reclaim funds.

---

## I-08: `topup` Callable Before Validator Activation
**`src/periphery/Deposits.sol`, `src/periphery/DepositsGno.sol`**

`topup` can be called for a validator that has never been deposited or has already fully exited. For unactivated validators, this sends ETH/GNO to the deposit contract with zero withdrawal credentials (`new bytes(32)` = all zeros), which would set BLS-type (0x00) withdrawal credentials on the beacon chain for a new validator created with this call. For exited validators, the deposit is silently wasted. No validation is performed that the validator is active or that the withdrawal credential matches the NFT's actual withdrawal address.

---

## I-09: `requestConsolidation` with Zero Target Key Advances Fingerprint Permanently
**`src/core/ERCXXXX.vy:407`**

`requestConsolidation` does not validate that `target_key_hi != 0`. A call with `target_key_hi = 0, target_key_lo = 0` updates the state fingerprint and queues an invalid consolidation request (the beacon chain will silently ignore it). The fingerprint is irreversibly advanced, which could affect ERC-5646 integrations expecting fingerprint changes to correspond to meaningful state transitions.

---

## I-10: No Events on Fingerprint State Changes
**`src/core/ERCXXXX.vy`**

State fingerprint updates (`pullNativeBalance`, `requestConsolidation`, `arbitraryCall`, `requestSwitchToCompounding`) emit no dedicated events. Off-chain indexers must reconstruct fingerprint state by replaying all transaction inputs or rely on `getStateFingerprint` calls. ERC-5646 does not require events, but they are conventional and aid indexing.

---

## I-11: `arbitraryCall` Can Target System Contracts Directly
**`src/core/ERCXXXX.vy:437`**

Nothing prevents `arbitraryCall` from targeting `WITHDRAWAL_REQUESTS` or `CONSOLIDATION_REQUESTS` with hand-crafted payloads. This bypasses the standardized key-formatting in `requestPartialWithdrawal`/`requestFullWithdrawal`/`requestConsolidation`, allowing malformed requests (wrong key encoding, wrong amount encoding). The beacon chain will likely ignore malformed entries, but fingerprint is still advanced and fee ETH is consumed.

---

## I-12: `safeTransferFrom` Data Parameter Capped at 1024 Bytes
**`src/core/ERCXXXX.vy:251`**

The `data` parameter in `safeTransferFrom` is bounded to `Bytes[1024]`. ERC-721 does not specify a maximum, and some integrations (e.g., NFT marketplaces passing structured settlement data) may require larger payloads. This is a Vyper compile-time constraint and cannot be changed without redeployment.

---

## I-13: `WithdrawalReceiver` Rejects Direct ETH Sends
**`src/core/WithdrawalReceiver.vy`**

No `@payable` `__default__` function is defined. Any attempt to send ETH directly to the `WithdrawalReceiver` via a regular transfer (e.g., `address.transfer(v)` from Solidity, or a wallet send) will revert. Beacon chain withdrawals work correctly because the protocol credits the balance directly at the EVM level without executing code — no fallback needed for that path. However, any external contract attempting to pay the receiver directly will fail.

---

## I-14: `tokenByIndex` Breaks Silently if Burn Were Added
**`src/core/ERCXXXX.vy:273`**

```vyper
def tokenByIndex(index: uint256) -> uint256:
    assert index < self.next_id - 1, "ERC-721: invalid index"
    return index + 1
```

This is correct only because IDs are assigned sequentially with no gaps and no burns. It is a mathematical shortcut that encodes the no-burn invariant directly. Any future addition of burn functionality would silently break this function without a compile error.

---

## I-15: `_padding: bytes32[2]` in `TokenData` — Intentional but Fragile
**`src/core/ERCXXXX.vy:34`**

The two padding slots align `TokenData` to exactly 8 EVM storage slots (256 bytes), enabling clean array addressing. The comment notes this as a "preemptive optimisation for state warming update and hash gas cost increases." Adding new fields to `TokenData` without removing padding would silently overflow the struct to 9 slots, breaking the alignment assumption.

---

## I-16: `check_operator` Receives Unused `token_id` Parameter
**`src/core/ERCXXXX.vy:159`**

`check_operator(token_id, owner)` accepts `token_id` but never reads it — it only checks `approval_for_all`. This is intentional API symmetry with `check_allowed`. A future version adding per-token operator exceptions would need to use this parameter.

---

## I-17: `format_helpers.vy` Functions Marked `@view` Rather Than Conceptually Pure
**`src/core/format_helpers.vy`**

All helper functions are purely computational with no state reads, but Vyper requires `@view` (not `@pure`) for functions called via `self.` from other modules. This is a Vyper language constraint, not a bug, but static analysis tools or auditors unfamiliar with Vyper may flag these as unnecessarily reading state.

---

## I-18: ERC-55 Checksum Uses Sequential `if` Instead of `elif`
**`src/core/format_helpers.vy`** — `erc55_process_nibble`

The nibble-to-character conversion uses a chain of `if` statements rather than `if/elif`. Since conditions are mutually exclusive by construction (a nibble is exactly one value), this is correct but uses redundant comparisons. `elif` would be more idiomatic.

---

## I-19: `getStateFingerprint` Uses Non-Standard Existence Check
**`src/core/ERCXXXX.vy:290`**

```vyper
assert state_fingerprint != empty(bytes32), "ERC-721: token does not exist"
```

Token existence is inferred from `state_fingerprint != 0` rather than the canonical `index_and_owner != 0` used elsewhere. This works because every minted token immediately receives `keccak256(keccak256("Minted()"))` as its fingerprint. However, the invariant that `state_fingerprint` is never explicitly zeroed is not enforced structurally — it relies on the current code never writing `empty(bytes32)` to that field.
