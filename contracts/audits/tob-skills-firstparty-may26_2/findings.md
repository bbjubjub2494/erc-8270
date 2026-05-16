# ERC-XXXX Audit Findings

**Date:** 2026-05-15  
**Codebase:** `src/core/ERCXXXX.vy`, `src/core/WithdrawalReceiver.vy`, `src/periphery/Deposits.sol`, `src/periphery/DepositsGno.sol`  
**Compiler:** Vyper 0.4.3 (EVM: Prague), Solidity ^0.8.34

---

## Summary

| ID  | Severity     | Title                                                              |
|-----|--------------|--------------------------------------------------------------------|
| M-1 | Medium       | Approved address can re-delegate approval via `approve`            |
| L-1 | Low          | ETH sent to non-forwarding payable functions is permanently locked |
| L-2 | Low          | Zero-balance `pullNativeBalance` advances fingerprint without ETH movement |
| L-3 | Low          | `pullNativeBalance(id, address(0))` burns validator ETH            |
| L-4 | Low          | Sub-Gwei ETH silently lost to deposit contract in `Deposits.topup` |
| I-1 | Informational| `GNO_TOKEN.transferFrom` return value unchecked                    |
| I-2 | Informational| Any `create_minimal_proxy_to` failure misreported as "already minted" |
| I-3 | Informational| `setApprovalForAll(msg.sender, …)` not restricted                  |

---

## M-1 — Approved Address Can Re-Delegate Approval (ERC-721 Spec Violation)

**Severity:** Medium  
**Location:** `src/core/ERCXXXX.vy:152–154` (`check_allowed`), `src/core/ERCXXXX.vy:184–188` (`approve`)

### Description

`check_allowed` grants permission to three caller types: the token owner, the per-token approved address, and a `setApprovalForAll` operator. This single function is reused by every guarded operation.

```vyper
@internal
@view
def check_allowed(token_id: uint256, owner: address):
    if msg.sender != owner and msg.sender != self.token_data[token_id].approved:
        assert self.approval_for_all[owner][msg.sender], "ERC-721: not owner or approved"
```

For most operations (transfers, withdrawal requests, `pullNativeBalance`, `arbitraryCall`) allowing the approved address is a reasonable design choice for ERC-XXXX. For `approve` specifically it is not. ERC-721 states:

> *"Throws unless `msg.sender` is the current NFT owner, or an authorized operator of the current owner."*

An "authorized operator" means a `setApprovalForAll` grantee. The per-token approved address is not in that category, so permitting it to call `approve` violates the spec.

Because `check_allowed` is used uniformly, the currently-approved address can call `approve(newAddress, tokenId)` and hand off the approval to any third party the original owner never sanctioned.

### Attack Scenario

1. Alice (owner) approves `MarketplaceContract` — a well-audited contract that only transfers tokens when a signed order exists — for token 1.
2. `MarketplaceContract` is compromised, or a malicious actor gains control of it.
3. `MarketplaceContract` calls `approve(Mallory, 1)`. Alice has no say; an `Approval(owner=Alice, approved=Mallory, tokenId=1)` event is emitted.
4. Mallory can now call `requestFullWithdrawal(1)` — triggering a beacon-chain exit of Alice's validator — or `arbitraryCall(1, …)` to make arbitrary EVM calls from the withdrawal address, all without Alice's consent.

Note: `MarketplaceContract` loses its own approval in the handoff, but the chosen replacement is arbitrary.

### Recommendation

In `approve`, do not use `check_allowed`. Check only `owner` or `setApprovalForAll` operator explicitly:

```vyper
@external
@payable
def approve(approved: address, token_id: uint256):
    owner: address = self._owner(token_id)
    assert msg.sender == owner or self.approval_for_all[owner][msg.sender], \
        "ERC-721: not owner or operator"
    self.token_data[token_id].approved = approved
    log IERC721.Approval(owner=owner, approved=approved, token_id=token_id)
```

---

## L-1 — ETH Sent to Non-Forwarding Payable Functions Is Permanently Locked

**Severity:** Low  
**Location:** `src/core/ERCXXXX.vy:183` (`approve`), `:230` (`transferFrom`), `:236` (`safeTransferFrom`)

### Description

Three functions are decorated `@payable` but make no use of `msg.value`. ERCXXXX has no `__default__` receiver and no ETH recovery path — `pullNativeBalance` exclusively drains per-token withdrawal receiver proxies, not the main contract balance.

Any ETH forwarded to `approve`, `transferFrom`, or `safeTransferFrom` is permanently locked in ERCXXXX.

```vyper
@external
@payable
def approve(approved: address, token_id: uint256): ...   # msg.value unused

@external
@payable
def transferFrom(owner: address, receiver: address, token_id: uint256): ...  # msg.value unused

@external
@payable
def safeTransferFrom(...): ...  # msg.value unused
```

### Scenario

A smart contract that bundles an ERC-20 approval with an ERC-721 transfer in a single multicall, or one that unconditionally attaches value to every call, silently loses any ETH sent with these three functions.

### Recommendation

Remove `@payable` from `approve`, `transferFrom`, and `safeTransferFrom`. The ERC-721 standard permits non-payable implementations; the `@payable` decorator here serves no functional purpose.

---

## L-2 — Zero-Balance `pullNativeBalance` Advances the State Fingerprint Without ETH Movement

**Severity:** Low  
**Location:** `src/core/ERCXXXX.vy:411–420`

### Description

`pullNativeBalance` updates the ERC-5646 state fingerprint unconditionally before calling `_pull_native_balance`, which sends `self.balance` ETH to the destination. When the proxy holds no ETH the fingerprint still advances:

```vyper
@external
def pullNativeBalance(token_id: uint256, destination: address = msg.sender):
    self.check_allowed(token_id, self._owner(token_id))
    self.token_data[token_id].state_fingerprint = keccak256(   # ← always updated
        abi_encode(
            keccak256("NativeBalancePulled(bytes32 previousFingerprint)"),
            self.token_data[token_id].state_fingerprint,
        )
    )
    extcall self.withdrawal_receiver(token_id)._pull_native_balance(destination)
    # WithdrawalReceiver: raw_call(destination, b"", value=self.balance)
    # If self.balance == 0, this is a no-op.
```

No guard prevents this call on an empty proxy. Any authorized caller (owner, approved address, or operator) can invoke it repeatedly, each time changing the fingerprint.

### Impact

Smart contracts using `getStateFingerprint` as a mutation guard — for example, a lending protocol that records the fingerprint at collateral deposit time and reverts if it has changed at liquidation time — can have the guard tripped without any actual value-relevant state change occurring. An authorized caller (or an attacker who has acquired approval) can "poison" the fingerprint to block such integrations, or to fabricate an apparent state-change history.

### Recommendation

Either gate on a non-zero balance before executing:

```vyper
assert extcall self.withdrawal_receiver(token_id).balance() > 0, \
    "ERC-XXXX: no balance to pull"
```

Or document explicitly that the fingerprint advancing does not guarantee ETH was moved, and that zero-balance pulls are valid, intentional state transitions under ERC-5646.

---

## L-3 — `pullNativeBalance` Has No Zero-Address Guard on `destination`

**Severity:** Low  
**Location:** `src/core/ERCXXXX.vy:411`, `src/core/WithdrawalReceiver.vy:35`

### Description

```vyper
# ERCXXXX.vy
@external
def pullNativeBalance(token_id: uint256, destination: address = msg.sender):
    self.check_allowed(token_id, self._owner(token_id))
    ...
    extcall self.withdrawal_receiver(token_id)._pull_native_balance(destination)

# WithdrawalReceiver.vy
@external
def _pull_native_balance(destination: address):
    assert msg.sender == CONTROLLER
    raw_call(destination, b"", value=self.balance)   # destination unchecked
```

If `destination = address(0)` is passed explicitly, the entire ETH balance of the withdrawal receiver is transferred to the zero address and becomes permanently inaccessible. The default parameter `= msg.sender` mitigates this for the common case, but the explicit-zero path is reachable by any authorized caller.

### Recommendation

Add a zero-address guard in either function:

```vyper
# Option A — in ERCXXXX.vy
assert destination != empty(address), "ERC-XXXX: destination is zero address"

# Option B — in WithdrawalReceiver.vy
assert destination != empty(address), "ERC-XXXX: destination is zero address"
```

---

## L-4 — Sub-Gwei ETH Is Silently Lost to the Deposit Contract in `Deposits.topup`

**Severity:** Low  
**Location:** `src/periphery/Deposits.sol:44–46`

### Description

```solidity
function topup(uint256 id) external payable {
    uint256 amount = msg.value;
    (
        bytes memory validatorKey,
        bytes memory withdrawalCredential,
        bytes memory signature,
        bytes32 depositDataRoot
    ) = _prepareTopup(id, amount / 1 gwei);   // ← integer division truncates
    DEPOSIT_CONTRACT.deposit{value: msg.value}(validatorKey, withdrawalCredential, signature, depositDataRoot);
}
```

`amount / 1 gwei` truncates any sub-Gwei Wei from the deposit data root computation. The ETH deposit contract receives `msg.value` in full but credits only `floor(msg.value / 1e9) × 1e9` Wei as validator stake. The remainder — up to `10^9 − 1` Wei ≈ 1 Gwei — is absorbed into the deposit contract's total balance with no accounting entry and no refund mechanism.

### Recommendation

Enforce that `msg.value` is a whole-Gwei amount:

```solidity
require(msg.value % 1 gwei == 0, "Deposits: value not a multiple of 1 gwei");
```

---

## I-1 — `GNO_TOKEN.transferFrom` Return Value Not Checked

**Severity:** Informational  
**Location:** `src/periphery/DepositsGno.sol:69`

### Description

```solidity
function _deposit(uint256 amount, bytes memory depositData) private {
    GNO_TOKEN.transferFrom(msg.sender, address(this), amount);   // bool return ignored
    GNO_TOKEN.transferAndCall(DEPOSIT_CONTRACT, amount, depositData);
}
```

The boolean return value of `transferFrom` is discarded. For GNO (which reverts on insufficient balance or allowance) this is safe in practice. For any IERC20-compliant token that returns `false` without reverting, the silent failure would cause the subsequent `transferAndCall` to attempt to transfer `amount` from `DepositsGno`'s own (likely zero) balance.

### Recommendation

Use a checked transfer pattern:

```solidity
require(GNO_TOKEN.transferFrom(msg.sender, address(this), amount), "DepositsGno: transferFrom failed");
```

Or use OpenZeppelin `SafeERC20.safeTransferFrom`.

---

## I-2 — Any `create_minimal_proxy_to` Failure Is Reported as "Already Minted"

**Severity:** Informational  
**Location:** `src/core/ERCXXXX.vy:301–306`

### Description

```vyper
withdrawal_address: address = create_minimal_proxy_to(
    WITHDRAWAL_RECEIVER_IMPL,
    revert_on_failure=False,
    salt=keccak256(abi_encode(validator_key_hi, validator_key_lo, initial_owner)),
)
assert withdrawal_address != empty(address), "ERC-XXXX: already minted"
```

`revert_on_failure=False` causes any CREATE2 failure to return `address(0)`. The anticipated failure mode is a salt collision (same key + same initial owner = duplicate mint). However, any other deployment failure — such as gas exhaustion during proxy code write — would produce the same `"ERC-XXXX: already minted"` error, misdirecting debugging.

### Recommendation

Document that `"ERC-XXXX: already minted"` encompasses all `create_minimal_proxy_to` failures, not solely salt collisions.

---

## I-3 — `setApprovalForAll(msg.sender, …)` Not Restricted

**Severity:** Informational  
**Location:** `src/core/ERCXXXX.vy:192–194`

### Description

```vyper
@external
def setApprovalForAll(operator: address, approved: bool):
    self.approval_for_all[msg.sender][operator] = approved
    log IERC721.ApprovalForAll(owner=msg.sender, operator=operator, approved=approved)
```

ERC-721 specifies: *"Throws if `_operator` is the `msg.sender`."* No such guard exists. Setting `approval_for_all[msg.sender][msg.sender] = true` is functionally a no-op (the owner already has full rights over their own tokens) but emits an `ApprovalForAll` event that could confuse off-chain indexers or monitoring tools.

### Recommendation

Add a self-approval guard if strict ERC-721 conformance is required:

```vyper
assert operator != msg.sender, "ERC-721: approve to caller"
```
