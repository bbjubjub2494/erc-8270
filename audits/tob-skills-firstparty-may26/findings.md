# ERC-XXXX Audit Findings

## F-01 — `_transfer` does not update the index of the moved token (swap-and-pop bug)

**Severity:** High  
**Location:** `src/ERCXXXX.vy:156–162`

### Description

`_transfer` removes a token from the owner's array using a swap-and-pop pattern: it overwrites
the hole left by the transferred token with the last element of the array, then pops the tail.
It updates `token_data[token_id].index_and_owner` for the token being transferred, but it does
**not** update the index stored for the token that was moved from the last position.

```vyper
self.tokens_by_owner[owner][index] = (
    self.tokens_by_owner[owner][len(self.tokens_by_owner[owner]) - 1]
)
self.tokens_by_owner[owner].pop()
# ← token previously at len-1 is now at `index`, but its token_data entry still says len-1
index = convert(len(self.tokens_by_owner[receiver]), uint96)
self.tokens_by_owner[receiver].append(token_id)
self.token_data[token_id].index_and_owner = self._pack(index, receiver)  # only the transferred token is updated
```

### Impact

Any time a non-last token is transferred, the moved token's stored index becomes stale. The next
attempt to transfer (or perform any operation that reads that index from storage and accesses the
array) fails with an out-of-bounds revert, permanently freezing that token.

**Example:** owner has `[id1, id2]`. Transferring `id1` moves `id2` to position 0, but
`token_data[id2].index_and_owner` still encodes index 1. A subsequent `transferFrom(owner, …, id2)`
reads stale index 1, tries `tokens_by_owner[owner][1]` on a length-1 array, and reverts.

### Proof of Concept

```solidity
function test_stale_index_after_transfer() external {
    uint256 id1 = dut.mint(key1hi, key1lo, user1); // user1 = [id1]
    uint256 id2 = dut.mint(key2hi, key2lo, user1); // user1 = [id1, id2]

    vm.prank(user1);
    dut.transferFrom(user1, user2, id1); // id2 moves to index 0; its stored index is still 1

    vm.prank(user1);
    vm.expectRevert(); // index out-of-bounds
    dut.transferFrom(user1, user2, id2);
}
```

### Recommendation

Before popping, capture the ID of the element being moved and update its stored index:

```vyper
last_index: uint96 = convert(len(self.tokens_by_owner[owner]) - 1, uint96)
last_token_id: uint256 = self.tokens_by_owner[owner][last_index]
self.tokens_by_owner[owner][index] = last_token_id
self.tokens_by_owner[owner].pop()
if last_token_id != token_id:
    self.token_data[last_token_id].index_and_owner = self._pack(index, owner)
```

The guard `last_token_id != token_id` handles the degenerate case where the transferred token is
already the last element (index == last_index), in which case no movement occurs and no index
update is needed.

---

## F-02 — `requestPartialWithdrawal` silently becomes a full exit for amounts below 1 Gwei

**Severity:** High  
**Location:** `src/ERCXXXX.vy:295–297`

### Description

The withdrawal amount is converted from wei to Gwei using integer division before being packed
into the 8-byte EIP-7002 request field:

```vyper
convert(convert(amount // 1_000_000_000, uint64), bytes8)
```

EIP-7002 interprets a zero value in this field as a **full validator exit**, not a partial
withdrawal. Any call with `0 < amount < 1_000_000_000` (i.e., less than 1 Gwei) rounds down to
zero, so the system contract records a full exit request instead of a partial one.

The existing guard `assert amount != 0` does not prevent this: it only rejects exact zero.

### Impact

A caller who passes any sub-Gwei `amount` (e.g., `amount = 1`) expecting a partial withdrawal
will instead trigger an irreversible full validator exit on the beacon chain.

### Recommendation

Add an explicit minimum-amount check before the conversion:

```vyper
assert amount >= 1_000_000_000, "ERC-XXXX: amount below 1 Gwei"
```

Or equivalently, assert that the converted value is non-zero:

```vyper
gwei_amount: uint64 = convert(amount // 1_000_000_000, uint64)
assert gwei_amount != 0, "ERC-XXXX: amount below 1 Gwei"
```

---

## F-03 — `approve` emits `Approval` event with `msg.sender` instead of the actual token owner

**Severity:** Medium  
**Location:** `src/ERCXXXX.vy:139`

### Description

`approve` allows the token owner, the per-token approved address, **or** a for-all operator to
call it. When an operator (not the actual owner) calls `approve`, the emitted event is:

```vyper
log IERC721.Approval(owner=msg.sender, approved=approved, token_id=token_id)
```

`msg.sender` is the operator, so the `owner` field in the event contains the operator's address
rather than the actual token owner's address.

### Impact

ERC-721 requires the `Approval` event's first indexed parameter to be the actual token owner.
Indexers, marketplace contracts, and off-chain watchers that track approvals by owner will receive
incorrect data and may fail to associate the approval with the correct owner.

### Recommendation

Compute the actual owner first and use it in the event:

```vyper
def approve(approved: address, token_id: uint256):
    owner: address = self._owner(token_id)
    self.check_allowed(token_id, owner)
    self.token_data[token_id].approved = approved
    log IERC721.Approval(owner=owner, approved=approved, token_id=token_id)
```

---

## F-04 — Fingerprint updates on silent call failures produce false state transitions

**Severity:** Medium  
**Location:** `src/WithdrawalReceiver.vy:28,35,42`; `src/ERCXXXX.vy:331–340,363–368,376–383`

### Description

Three `raw_call` invocations in `WithdrawalReceiver` lack `revert_on_failure=True`:

```vyper
raw_call(target, data, value=fee)          # beacon_chain_request
raw_call(destination, b"", value=self.balance)  # _pull_native_balance
raw_call(target, data, value=msg.value)    # _arbitrary_call
```

If any of these calls fail (e.g., the destination reverts, the system contract rejects the
request due to insufficient fee, or the EIP-7002/7251 contract is unavailable), the failure is
silently discarded. Execution continues normally in ERCXXXX, and the state fingerprint is updated
as though the action had succeeded.

The fingerprint is therefore updated even when:
- `pullNativeBalance` fails to send ETH (e.g., non-payable destination contract);
- `arbitraryCall` target reverts;
- `requestConsolidation` fails to submit the beacon chain request.

### Impact

ERC-5646 fingerprint changes are meant to signal that the token's meaningful state changed.
Consumers observing a `NativeBalancePulled` or `ArbitraryCall` fingerprint transition cannot
distinguish a successful action from a silently-failed one. A contract that checks the fingerprint
to confirm an action completed before proceeding will be misled.

### Recommendation

Use `revert_on_failure=True` on each call, or check the boolean return value and revert on
failure:

```vyper
# Option A — propagate revert
raw_call(destination, b"", value=self.balance, revert_on_failure=True)

# Option B — explicit check
success: bool = raw_call(destination, b"", value=self.balance)
assert success, "transfer failed"
```

For `beacon_chain_request` the same applies; additionally consider reverting in ERCXXXX if
the fee query returns zero (which indicates the static call to the system contract failed).

---

## F-05 — `requestSwitchToCompounding` does not update the state fingerprint

**Severity:** Low  
**Location:** `src/ERCXXXX.vy:344–356`

### Description

`requestConsolidation` updates the state fingerprint to record that a consolidation was requested.
`requestSwitchToCompounding` calls the same EIP-7251 system contract (with the source key as both
source and target), but **does not** update the fingerprint.

Switching to compounding permanently changes the validator's exit-credential type from 0x01 to
0x02, which is an irreversible state change of the same severity as a consolidation. The asymmetry
means that ERC-5646 consumers cannot detect this transition by watching the fingerprint.

### Recommendation

Add an equivalent fingerprint update to `requestSwitchToCompounding`:

```vyper
self.token_data[token_id].state_fingerprint = keccak256(
    abi_encode(
        keccak256("SwitchToCompoundingRequested(bytes32 previousFingerprint)"),
        self.token_data[token_id].state_fingerprint,
    )
)
```

---

## F-06 — ERC-165 does not advertise ERC-5646 or ERC-XXXX interfaces

**Severity:** Low  
**Location:** `src/ERCXXXX.vy:71–76`

### Description

`SUPPORTED_INTERFACES` contains only three entries, with ERC-5646 and ERC-XXXX marked TODO:

```vyper
SUPPORTED_INTERFACES: constant(bytes4[3]) = [
    0x01ffc9a7,  # ERC-165
    0x80ac58cd,  # ERC-721
    0x780e9d63,  # ERC-721 enumeration
    # TODO ERC-5646, ERC-XXXX
]
```

`supportsInterface` returns `false` for both ERC-5646 and ERC-XXXX, so any contract or tool that
checks capabilities via ERC-165 before interacting will conclude this contract does not support
them.

### Recommendation

Extend the constant to include both interface IDs once finalized:

```vyper
SUPPORTED_INTERFACES: constant(bytes4[5]) = [
    0x01ffc9a7,  # ERC-165
    0x80ac58cd,  # ERC-721
    0x780e9d63,  # ERC-721 enumeration
    0x00000000,  # TODO: ERC-5646 interface ID
    0x00000000,  # TODO: ERC-XXXX interface ID
]
```

---

## F-07 — ETH sent to `approve`, `transferFrom`, or `safeTransferFrom` is permanently locked

**Severity:** Low  
**Location:** `src/ERCXXXX.vy:135,179,185`

### Description

`approve`, `transferFrom`, and `safeTransferFrom` are marked `@payable` but never consume or
forward `msg.value`. There is no receive/fallback function and no withdrawal path for ETH held
by ERCXXXX. Any ETH accidentally sent to these functions is permanently locked in the contract.

### Recommendation

Remove the `@payable` decorator from functions that do not require ETH. ERC-721 does not require
these functions to be payable:

```vyper
@external
def approve(approved: address, token_id: uint256):
    ...

@external
def transferFrom(owner: address, receiver: address, token_id: uint256):
    ...
```

---

## F-08 — Reentrancy in `pullNativeBalance` and `arbitraryCall` allows fingerprint manipulation

**Severity:** Low  
**Location:** `src/ERCXXXX.vy:360–368,372–383`

### Description

Both `pullNativeBalance` and `arbitraryCall` perform external calls before updating the
fingerprint (a Checks-Effects-Interactions violation). Neither function uses `@nonreentrant`.

During the external call, a malicious contract can reenter ERCXXXX. If it triggers another
fingerprint-updating action (e.g., a second `pullNativeBalance` or `arbitraryCall`), that
action's fingerprint update runs first. When the outer call's fingerprint update then runs, it
reads the already-mutated fingerprint as "previous", producing a chain different from what a
non-reentrant execution would produce.

**Concrete path:** `arbitraryCall(id, target, data)` → WR → `target` reenters
`pullNativeBalance(id, …)` → fingerprint updates to `NativeBalancePulled(F1)` → reentry returns
→ outer `arbitraryCall` updates fingerprint to `ArbitraryCall(NativeBalancePulled(F1), …)`
instead of the expected `ArbitraryCall(F1, …)`.

### Recommendation

Apply `@nonreentrant` to `pullNativeBalance` and `arbitraryCall`, and move all fingerprint
updates to before any external calls (or use a reentrancy guard):

```vyper
@external
@nonreentrant
def pullNativeBalance(token_id: uint256, destination: address = msg.sender):
    self.check_allowed(token_id, self._owner(token_id))
    # Update fingerprint before external call
    self.token_data[token_id].state_fingerprint = keccak256(...)
    extcall self.withdrawal_receiver(token_id)._pull_native_balance(destination)
```

---

## Informational

### I-01 — `check_allowed` return value is dead code

`check_allowed` always returns its `owner` argument, but no caller uses the return value. The
return type can be removed to reduce confusion.

### I-02 — Incorrect storage-layout comment

The comment on `_padding` says "this puts the unused 0th element at 0xe8". The actual slot of
`token_data[0]` is 0xF8 (248 decimal), not 0xe8. `token_data[1]` is at 0x100 as stated and
confirmed by the storage-layout test.

### I-03 — Multiple redundant existence sentinels

Token existence is checked via four independent fields (`index_and_owner`, `state_fingerprint`,
`validator_key_hi`, `withdrawal_address`), all set atomically in `mint`. They agree in practice
but create maintenance surface: any future code that writes these fields independently could
introduce inconsistency. Consider designating a single canonical sentinel.
