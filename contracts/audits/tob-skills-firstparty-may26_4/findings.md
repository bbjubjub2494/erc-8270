# Findings — ERC-8270 Canonical Validator Wrapper

---

## F-01 — HIGH: Partial withdrawal amount uses big-endian encoding; EIP-7002 requires little-endian

**Files**: `src/core/ERC8270.vy:403`, `src/core/WithdrawalReceiver.vy:55`

### Description

When a user calls `requestPartialWithdrawal(token_id, amount)`, the `amount` (a `uint64` in gwei) is encoded as a big-endian `bytes8` before being forwarded to the EIP-7002 system contract:

```vyper
# ERC8270.vy:402-405
extcall self.withdrawal_receiver(token_id)._request_withdrawal(
    convert(amount, bytes8),   # Vyper: uint64 → bytes8 = big-endian
    value=msg.value,
)
```

```vyper
# WithdrawalReceiver.vy:54-56
raw_call(
    WITHDRAWAL_REQUESTS, concat(self.validator_key_hi, self.validator_key_lo, amount), value=fee
)
```

The EIP-7002 system contract (`0x00000961Ef…7002`) decodes the amount as a **little-endian uint64** (SSZ encoding, the consensus layer's universal integer format). For example, requesting `1 gwei` sends `0x0000000000000001` (big-endian), which the system contract interprets as `0x0100000000000000` little-endian = `72,057,594,037,927,936 gwei` — orders of magnitude larger than any validator balance. The partial withdrawal request would either be processed as an effective full exit or silently fail at the consensus layer.

**Full withdrawal requests are unaffected.** `requestFullWithdrawal` sends `empty(bytes8) = 0x0000000000000000`, which is identical in both byte orders.

### Why the tests do not catch this

Both test files pass `bytes8(uint64(amount))` in `vm.expectCall`, which is also big-endian (Solidity pads integers to the left when casting to fixed bytes). The tests confirm that the code's output matches itself, not that it matches the EIP-7002 specification:

```solidity
// ERC8270.t.sol:415, WithdrawalReceiver.t.sol:55
vm.expectCall(WITHDRAWAL_REQUESTS, fee,
    bytes.concat(validatorKey1Hi, validatorKey1Lo, bytes8(amount)));
```

### Contrast with `DepositsBase.sol`

`DepositsBase.sol:23-34` implements `_toBytes8LittleEndian` specifically for the ETH2 deposit contract — showing the author understood little-endian is required by the consensus layer — but that knowledge was not applied to EIP-7002.

### Fix

Replace `convert(amount, bytes8)` with a little-endian encoding, mirroring the `_toBytes8LittleEndian` pattern from `DepositsBase.sol`.

> **Note**: Verify against the live Prague-fork EIP-7002 system contract, since tests use mocks.

---

## F-02 — MEDIUM: `requestSwitchToCompounding` missing fingerprint update (refactor regression)

**Files**: `src/core/ERC8270.vy:454-463`, `src/core/ERC8270.vy:315-322`

### Description

The `getStateFingerprint` NatSpec (line 316) explicitly states that the fingerprint changes when `requestSwitchToCompounding()` is called:

```
@notice ERC-5646 state fingerprint. It changes when `requestConsolidation()`,
`requestSwitchToCompounding()`, `pullNativeBalance()`, and `arbitraryCall()` are used on the token.
```

But the implementation contains no fingerprint update:

```vyper
# ERC8270.vy:454-463
@external
@payable
def requestSwitchToCompounding(token_id: uint256):
    self.check_allowed(token_id, self._owner(token_id))
    extcall self.withdrawal_receiver(token_id)._request_switch_to_compounding(value=msg.value)
    # no fingerprint update, no event
```

Every other fingerprint-sensitive operation has a corresponding inline type string (lines 363, 437, 479, 503). There is no `SwitchToCompoundingRequested(...)` type string anywhere in the codebase.

### Root cause

Prior to commit `3f2a325` ("refactor and document"), `requestSwitchToCompounding` called an internal helper that **did** update the fingerprint using the `ConsolidationRequested` type with the validator's own key as the target. The refactoring introduced a dedicated `_request_switch_to_compounding()` method on `WithdrawalReceiver` but did not carry over the fingerprint update. The NatSpec was written describing the intended (pre-refactor) behavior, while the test was incorrectly updated to assert "no change" (test line 382).

### Security impact

1. **ERC-5646 bypass**: An approved address (not the owner) can call `requestSwitchToCompounding(token_id)` to irreversibly switch the validator to compounding mode — changing how staking rewards accumulate — without changing the fingerprint. A DeFi protocol using `getStateFingerprint` as a "state guard" between recording a position and settling it would not detect this change.

2. **Asymmetry with `requestConsolidation`**: Calling `requestConsolidation(id, own_key_hi, own_key_lo)` produces the **identical EIP-7251 system contract call** (same 96-byte payload: source == target pubkey) as `requestSwitchToCompounding`, but `requestConsolidation` does update the fingerprint. An approved address can selectively choose the path that bypasses the fingerprint guard.

3. **No event**: `requestConsolidation` emits `ConsolidationRequest`. `requestSwitchToCompounding` emits nothing. Off-chain monitors relying on ERC-8270 events are blind to this operation.

4. **Irreversibility**: Switching from Type 1 (BLS-to-execution) to Type 2 (compounding execution) credentials is permanent on the consensus layer.

### Fix

Add a fingerprint update, e.g.:

```vyper
self.token_data[token_id].state_fingerprint = keccak256(
    abi_encode(
        keccak256("SwitchToCompoundingRequested(bytes32 previousFingerprint)"),
        self.token_data[token_id].state_fingerprint,
    )
)
```

Also add a corresponding event (e.g., `SwitchToCompoundingRequest(token_id: indexed(uint256))`), and update the test to assert the fingerprint changes.

---

## F-03 — LOW: No interface validation for `withdrawal_receiver_code` constructor parameter

**File**: `src/core/ERC8270.vy:83-90`

### Description

The `__init__` constructor accepts raw bytecode for the `WithdrawalReceiver` implementation and deploys it directly:

```vyper
@deploy
def __init__(image_url: String[128], withdrawal_receiver_code: Bytes[49152]):
    WITHDRAWAL_RECEIVER_IMPL = raw_create(withdrawal_receiver_code)
```

`raw_create` uses `revert_on_failure=True` by default (verified in Vyper 0.4.3 source). If the supplied bytecode's constructor reverts, `ERC8270`'s constructor reverts too — `WITHDRAWAL_RECEIVER_IMPL` cannot be silently set to `address(0)`.

However, if the supplied bytecode is **valid but incorrect** (a different contract whose constructor does not revert), `raw_create` succeeds and `WITHDRAWAL_RECEIVER_IMPL` is set to that wrong implementation. All proxies deployed via `create_minimal_proxy_to` will point to it. The `extcall IWithdrawalReceiver(withdrawal_address)._set_validator_key(...)` call in `mint` would silently succeed (a call to a contract that doesn't implement the function returns success in EVM), leaving validator keys unset at zero — with no revert or error at mint time.

There is no on-chain mechanism to verify that `withdrawal_receiver_code` is specifically the `WithdrawalReceiver` implementation, or that `CONTROLLER` was set correctly.

### Fix

At minimum, call `validator_key()` on the freshly deployed implementation as a smoke test, or check that the returned `CONTROLLER` matches `self`.

---

## F-04 — INFORMATIONAL: `image_url` storage slot comment is incorrect

**File**: `src/core/ERC8270.vy:59`

```vyper
image_url: String[128]  # 4 slots
```

A `String[128]` in Vyper storage occupies **5 slots**: 1 for the length field plus 4 for 128 bytes of data. The storage layout confirms this: `_padding` starts at slot 7 (not slot 6), and `token_data` begins at slot 252 (0xfc), which is consistent with 5 slots for `image_url`. The test at line 58 independently verifies the layout via `vm.load`.

---

## F-05 — INFORMATIONAL: `tokenByIndex` silently relies on a no-burn invariant

**File**: `src/core/ERC8270.vy:298-300`

```vyper
def tokenByIndex(index: uint256) -> uint256:
    assert index < self.next_id - 1, "ERC-721: invalid index"
    return index + 1
```

This O(1) implementation assumes token IDs are sequential and gapless. There is currently no `_burn` function, so the assumption holds. However, if a burn mechanism were ever added without updating this function, `tokenByIndex` would silently return non-existent token IDs without reverting. The invariant is not asserted or documented.

---

## Summary

| ID | Severity | Location | Title |
|----|----------|----------|-------|
| F-01 | HIGH | `ERC8270.vy:403`, `WithdrawalReceiver.vy:55` | Partial withdrawal amount encoded big-endian; EIP-7002 requires little-endian |
| F-02 | MEDIUM | `ERC8270.vy:454-463` | `requestSwitchToCompounding` missing fingerprint update (refactor regression) |
| F-03 | LOW | `ERC8270.vy:88` | No interface validation for `withdrawal_receiver_code` constructor argument |
| F-04 | INFO | `ERC8270.vy:59` | `image_url` comment says `# 4 slots`; correct value is 5 |
| F-05 | INFO | `ERC8270.vy:298-300` | `tokenByIndex` silently relies on no-burn invariant |
