# ERC-XXXX Audit Context

*Built via `/audit-context` skill — pure context-building phase, no vulnerability findings.*

---

## 1. System Overview

ERC-XXXX is an ERC-721 NFT standard for Ethereum staking validators. Each token wraps one beacon chain validator identified by its BLS12-381 public key. The NFT owner controls: EIP-7002 withdrawal requests, EIP-7251 consolidation requests, ETH balance pulls from the withdrawal receiver, and arbitrary EVM calls from the withdrawal receiver address. All operations are routed through a per-token `WithdrawalReceiver` proxy contract.

**Languages:** Vyper 0.4.3 (core), Solidity ^0.8 (interfaces, tests, periphery)  
**Tooling:** Foundry + Soldeer + Jujutsu (not Git)  
**Target chains:** Ethereum mainnet (`Deposits.sol`) and Gnosis Chain (`DepositsGno.sol`)

### Source Files

| File | Lines | Language | Purpose |
|---|---|---|---|
| `src/core/ERCXXXX.vy` | 449 | Vyper | Main ERC-721 contract |
| `src/core/WithdrawalReceiver.vy` | 43 | Vyper | Per-validator ETH proxy |
| `src/core/format_helpers.vy` | 169 | Vyper | Hex / ERC-55 display helpers |
| `src/periphery/DepositsBase.sol` | 66 | Solidity | Abstract deposit helper base |
| `src/periphery/Deposits.sol` | 58 | Solidity | Mainnet ETH deposit helper |
| `src/periphery/DepositsGno.sol` | 72 | Solidity | Gnosis Chain GNO deposit helper |
| `src/interfaces/` | — | Solidity / Vyper | Interface definitions |

---

## 2. Actors

| Actor | Role |
|---|---|
| Token owner (`ownerOf`) | Full control of their token's validator operations |
| Per-token approved (`token_data[id].approved`) | Same power as owner for one specific token |
| ApprovalForAll operator | Same power as owner across all their tokens |
| EIP-7002 system contract (`0x00000961...7002`) | Receives withdrawal requests + fee |
| EIP-7251 system contract (`0x0000BBdDc7...7251`) | Receives consolidation requests + fee |
| Beacon chain | Pushes ETH to withdrawal receiver (no EL code runs) |
| Deposit contract | Validates and records beacon chain deposits |
| Depositor (Deposits / DepositsGno caller) | No special role on ERCXXXX; open to anyone |

---

## 3. Storage Layout

Confirmed by `test_storage_layout`:

| Slots | Content |
|---|---|
| 0 | `next_id: uint256` |
| 1 | `tokens_by_owner` (HashMap base slot) |
| 2 | `approval_for_all` (HashMap base slot) |
| 3–247 | `_padding: bytes32[245]` (245 slots) |
| 248 = 0xF8 | `token_data[0]` — permanently unused sentinel |
| 256 = 0x100 | `token_data[1]` — first real NFT |

**Why the padding?** `1 + 1 + 1 + 245 = 248`. `token_data[1]` starts at slot `248 + 8 = 256 = 0x100`, a clean 256-byte boundary. The comment "this puts the unused 0th element at 0xf8 and the first NFT at 0x100" is exact.

### `TokenData` Struct (8 slots = 256 bytes per token)

| Slot offset | Field | Notes |
|---|---|---|
| +0 | `index_and_owner: uint256` | 96-bit owner-array index (bits 255:160) + 160-bit address (bits 159:0) |
| +1 | `approved: address` | Per-token approval; cleared on every transfer |
| +2 | `validator_key_hi: bytes32` | Upper 256 bits of BLS12-381 public key |
| +3 | `validator_key_lo: bytes16` | Lower 128 bits (left-aligned, 16 trailing zero bytes) |
| +4 | `withdrawal_address: address` | EIP-1167 proxy for this validator |
| +5 | `state_fingerprint: bytes32` | ERC-5646 hash chain |
| +6, +7 | `_padding: bytes32[2]` | Pads struct to 256-byte boundary |

---

## 4. Function Analysis — `ERCXXXX.vy`

### 4.1 `_pack` / `_unpack`

Pack a 96-bit owner-array index and a 160-bit address into one `uint256` to reduce SLOADs. Pure bijection.

```
packed = (index << 160) | address
```

**Invariants:**
- `_unpack(_pack(i, a)) == (i, a)` for all valid `(i, a)`
- `packed != 0` for any minted token (owner address is always non-zero)
- Bits 255:160 = index; bits 159:0 = address (no overlap)

**Used by:** `_mint`, `_transfer`, `_owner`. The non-zero property is the foundation of all existence checks.

---

### 4.2 `__init__`

Deploys the `WithdrawalReceiver` implementation via `raw_create` (non-deterministic CREATE, not CREATE2). Stores the resulting address in the immutable `WITHDRAWAL_RECEIVER_IMPL`. Sets `next_id = 1` so the first minted token receives ID 1 and ID 0 is permanently unused.

The implementation's `__init__` runs with `msg.sender = address(ERCXXXX)`, binding `CONTROLLER = address(ERCXXXX)` into the implementation's bytecode as an immutable. All future EIP-1167 minimal proxy clones share this bytecode and therefore share the same `CONTROLLER`.

**Invariants:**
- `WITHDRAWAL_RECEIVER_IMPL != address(0)` post-deploy
- All per-token proxies have `CONTROLLER == address(ERCXXXX)`
- `next_id = 1`; first mint produces `token_id = 1`

---

### 4.3 Existence Checks

Five overlapping mechanisms, all equivalent for valid data:

| Method | Check field | SLOAD position | Used in |
|---|---|---|---|
| `check_exists` | `index_and_owner != 0` | Slot +0 (cheapest) | `tokenURI`, `getApproved` |
| `_owner` | `_unpack(...)[1] != address(0)` | Slot +0 | All state-mutating functions |
| `validatorKeyOf` | `validator_key_hi != 0` | Slot +2 | External view |
| `withdrawalAddressOf` | `withdrawal_address != address(0)` | Slot +4 | External view |
| `getStateFingerprint` | `state_fingerprint != bytes32(0)` | Slot +5 | ERC-5646 |

Each fuses the existence check with the primary field read, saving one SLOAD versus using `check_exists` then reading separately. `validator_key_hi != 0` is valid because compressed BLS12-381 points always have their high bit set; `mint` explicitly asserts this.

---

### 4.4 Authorization Model

Two authorization levels, used in different contexts:

| Function | Authorized parties |
|---|---|
| `check_operator` (used only by `approve`) | Owner or `approval_for_all` operator — **excludes** per-token `approved` |
| `check_allowed` (all other mutations) | Owner, per-token `approved`, or `approval_for_all` operator |

`check_allowed` is a strict superset of `check_operator`. A per-token approved address can transfer tokens and perform all validator operations but **cannot** call `approve` to sub-delegate that permission (confirmed by `test_approve_by_approvee`). The `token_id` parameter of `check_operator` is unused in the function body — intentional API symmetry with `check_allowed`.

---

### 4.5 `_transfer`

Core ownership move implementing swap-and-pop for O(1) removal.

**Block 1 — Re-read and verify:**
```vyper
index, owner = self._unpack(self.token_data[token_id].index_and_owner)
assert owner == expected_owner, "ERC-721: wrong owner"
self.check_allowed(token_id, owner)
assert receiver != empty(address), "ERC-721: transfer to zero"
```
Storage is the ground truth; the caller-supplied `owner` parameter is validated against the stored value.

**Block 2 — Remove from old owner (swap-and-pop):**
```vyper
last_id = tokens_by_owner[owner][len(...) - 1]
tokens_by_owner[owner][index] = last_id
tokens_by_owner[owner].pop()
token_data[last_id].index_and_owner = _pack(index, owner)   # CRITICAL: update last_id's stored index
```
The last element is moved into the vacated slot; `token_data[last_id].index_and_owner` is updated to reflect its new position.

**Edge case: `token_id == last_id`** (token is the last element): The write to `token_data[last_id]` is immediately superseded by Block 3. Net effect is correct.

**Block 3 — Add to new owner:**
```vyper
index = convert(len(tokens_by_owner[receiver]), uint96)   # before append
tokens_by_owner[receiver].append(token_id)
token_data[token_id].index_and_owner = _pack(index, receiver)
token_data[token_id].approved = empty(address)             # clear stale approval
```

**Self-transfer (`owner == receiver`):** Block 2 pops (length decreases by 1); Block 3 appends at new end (length restored). Works correctly, confirmed by `test_stale_index_after_transfer`.

**State fingerprint:** NOT updated on transfer. Transfers are invisible to ERC-5646.

**Invariants:**
- `tokens_by_owner[owner]` no longer contains `token_id` after Block 2
- `token_data[last_id].index_and_owner` correctly reflects `last_id`'s new position
- `token_data[token_id].approved == address(0)` after every transfer
- `balanceOf(owner)` decreases by 1; `balanceOf(receiver)` increases by 1

---

### 4.6 `_mint`

Generic ERC-721 minting primitive. Sets `index_and_owner` and `approved`; emits `Transfer(address(0), receiver, token_id)`. Does **not** set `validator_key_hi/lo`, `withdrawal_address`, or `state_fingerprint` — `mint` writes those immediately after.

The Transfer event is emitted at the end of `_mint`. The reentrancy guard (`pragma nonreentrancy on`) prevents any external observer from calling back between the Transfer event and the subsequent field writes in `mint`.

**Precondition:** `token_id` must be fresh (guaranteed by `mint` using monotone `next_id`).

---

### 4.7 `mint`

The sole token creation entry point.

**Step 1 — Validate key:**
```vyper
assert validator_key_hi != empty(bytes32), "ERC-XXXX: invalid validator key"
```
Dual purpose: structural validity of BLS12-381 key (high bit always set), and enables `validatorKeyOf` to use zero as the non-existence sentinel.

**Step 2 — Deploy per-token proxy via CREATE2:**
```vyper
withdrawal_address = create_minimal_proxy_to(
    WITHDRAWAL_RECEIVER_IMPL,
    revert_on_failure=False,
    salt=keccak256(abi_encode(validator_key_hi, validator_key_lo, initial_owner)),
)
assert withdrawal_address != empty(address), "ERC-XXXX: already minted"
```
Salt encodes `(key_hi, key_lo, initial_owner)` hashed to 32 bytes. A collision (same triple already minted) causes `create_minimal_proxy_to` to return `address(0)`.

**Key design implication:** `initial_owner` is part of the salt, so the same validator key can be minted with a different initial owner to produce a different withdrawal address. The withdrawal address is NOT a function of the validator key alone.

**Step 3 — Assign ID and mint:**
```vyper
token_id = self.next_id
self.next_id = token_id + 1
self._mint(initial_owner, token_id)
```

**Step 4 — Initialize remaining `TokenData` fields:**
```vyper
self.token_data[token_id].validator_key_hi = validator_key_hi
self.token_data[token_id].validator_key_lo = validator_key_lo
self.token_data[token_id].withdrawal_address = withdrawal_address
self.token_data[token_id].state_fingerprint = keccak256(keccak256("Minted()"))
```

**Invariants:**
- All 6 meaningful `TokenData` fields are initialized in one atomic transaction
- `validator_key_hi/lo`, `withdrawal_address` are write-once (no setters exist)
- `state_fingerprint == keccak256(keccak256("Minted()"))` at mint — non-zero by collision resistance
- The deployed proxy's `CONTROLLER == address(ERCXXXX)`

---

### 4.8 State Fingerprint Chain (ERC-5646)

Starting value: `fp₀ = keccak256(keccak256("Minted()"))`.

Each update follows the EIP-712 struct-hash pattern:

| Operation | Update formula |
|---|---|
| `pullNativeBalance` | `fp = keccak256(abi_encode(keccak256("NativeBalancePulled(bytes32 previousFingerprint)"), prev_fp))` |
| `requestConsolidation` / `requestSwitchToCompounding` | `fp = keccak256(abi_encode(keccak256("ConsolidationRequested(...)"), prev_fp, target_key_hi, target_key_lo))` |
| `arbitraryCall` | `fp = keccak256(abi_encode(keccak256("ArbitraryCall(...)"), prev_fp, target, keccak256(data)))` |
| `requestPartialWithdrawal` | **No update** |
| `requestFullWithdrawal` | **No update** |
| `transferFrom` / `safeTransferFrom` | **No update** |

Rationale for no-update on withdrawal requests: withdrawal requests are beacon-layer actions with non-deterministic outcomes from the EL perspective. Consolidation and arbitrary calls are considered semantically significant EL state changes.

All fingerprint-updating functions follow CEI: fingerprint is written to storage **before** the external call. If the external call reverts, the transaction rolls back including the fingerprint update.

---

### 4.9 EIP-7002 / EIP-7251 Request Flow

```
User --[msg.value]--> ERCXXXX.requestPartialWithdrawal(id, amount)
  check_allowed + _owner [SLOAD]
  assert amount != 0
  extcall WithdrawalReceiver.beacon_chain_request(WITHDRAWAL_REQUESTS, pubkey||amount, value=msg.value)
    assert msg.sender == CONTROLLER
    fee = _query_fee(WITHDRAWAL_REQUESTS)   ← static raw_call with empty calldata
    raw_call(WITHDRAWAL_REQUESTS, pubkey||amount, value=fee)
    // ETH: self.balance -= fee; excess remains in WithdrawalReceiver
```

**Payload formats:**
- EIP-7002 partial: `key_hi(32) || key_lo(16) || amount_big_endian(8)` = 56 bytes
- EIP-7002 full: `key_hi(32) || key_lo(16) || zeros(8)` = 56 bytes (zero amount = full exit per EIP-7002 spec)
- EIP-7251: `src_key_hi(32) || src_key_lo(16) || tgt_key_hi(32) || tgt_key_lo(16)` = 96 bytes

**ETH accounting in `WithdrawalReceiver`:**  
`self.balance` = accumulated beacon chain withdrawals + any excess `msg.value` from prior calls. Fee is paid from `self.balance`, not just from the current call's `msg.value`. Excess `msg.value - fee` stays in the receiver and is recoverable via `pullNativeBalance`.

---

## 5. Function Analysis — `WithdrawalReceiver.vy`

### 5.1 Deployment Model

- Implementation deployed **once** by `raw_create` inside ERCXXXX's `__init__`
- Per-token proxies are EIP-1167 minimal clones deployed via CREATE2
- Proxies do **not** re-run `__init__`; `CONTROLLER` immutable is embedded in the implementation's bytecode
- All proxies share `CONTROLLER = address(ERCXXXX)`
- `pragma nonreentrancy off` — no reentrancy guard; relies entirely on ERCXXXX's global lock

### 5.2 `_query_fee`

```vyper
out: Bytes[32] = raw_call(target, b"", max_outsize=32, is_static_call=True)
return extract32(out, 0, output_type=uint256)
```

Empty calldata signals a fee query per EIP-7002/7251 protocol. The `is_static_call=True` prevents state modification. If `target` returns fewer than 32 bytes, `extract32` zero-pads → fee = 0. Fee cannot change between query and submission since both occur in the same transaction.

### 5.3 `beacon_chain_request`

```vyper
assert msg.sender == CONTROLLER
fee = self._query_fee(target)
raw_call(target, data, value=fee)
```

Pays exactly `fee` from `self.balance`. Any `msg.value` in excess of `fee` remains in the contract permanently (until `_pull_native_balance`).

### 5.4 `_pull_native_balance`

```vyper
assert msg.sender == CONTROLLER
raw_call(destination, b"", value=self.balance)
```

Transfers the entire ETH balance in one call. No partial-pull mechanism. If `self.balance == 0`, issues a zero-value call (see Section 7, U-2).

### 5.5 `_arbitrary_call`

```vyper
assert msg.sender == CONTROLLER
raw_call(target, data, value=msg.value)
```

Forwards only `msg.value` — **not** `self.balance`. Pre-existing balance is untouched. This is the primary behavioral difference from `_pull_native_balance`.

### 5.6 ETH Sources and Exits

**ETH enters `WithdrawalReceiver` via:**
1. Beacon chain partial/full withdrawal pushes (no code runs; balance increases passively)
2. `msg.value` forwarded from ERCXXXX's `requestPartialWithdrawal`, `requestFullWithdrawal`, `requestConsolidation`, `requestSwitchToCompounding`, `arbitraryCall`

**ETH exits `WithdrawalReceiver` via:**
1. `beacon_chain_request` — pays exactly `fee` to the EIP-7002/7251 system contract
2. `_pull_native_balance` — sweeps entire balance to `destination`
3. `_arbitrary_call` — sends `msg.value` only to `target`

---

## 6. Function Analysis — Periphery

### 6.1 `DepositsBase._makeWithdrawalCredential`

```solidity
return bytes32(bytes1(uint8(compounding ? 2 : 1))) | bytes32(uint256(uint160(withdrawalAddress)));
```

Byte layout of the resulting `bytes32`:

| Bytes | Content |
|---|---|
| 0 | `0x01` (standard) or `0x02` (compounding) |
| 1–11 | `0x00` (zero padding, required by spec) |
| 12–31 | `withdrawalAddress` (20 bytes) |

### 6.2 `DepositsBase._prepareTopup` — SSZ Merkle Tree

Constructs the `DepositData` hash-tree-root for a top-up deposit using null credentials and null signature.

```
depositDataRoot = sha256(
    sha256(pubkeyRoot || bytes32(0)),              // leaf0=pubkey_hash, leaf1=zero_credentials
    sha256(bytes32(amountLE8) || signatureRoot)    // leaf2=amount_chunk,  leaf3=null_sig_hash
)
```

- `pubkeyRoot = sha256(validatorKey_48bytes || bytes16(0))` — SSZ ByteVector[48] padded to 64 bytes
- `signatureRoot = 0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71` — hardcoded SHA-256 of a 96-byte all-zero BLS signature
- `withdrawalCredential = bytes32(0)` — zero tells the beacon chain to use the validator's existing credentials (valid for topups)
- `signature = bytes96(0)` — null BLS signature (valid for topups per post-Capella spec)

The hardcoded `signatureRoot` derivation:
```
sha256(zeros_64) = f5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b
signatureRoot = sha256(f5a5...4b || f5a5...4b) = 0xdb56...5d71  ✓
```

### 6.3 `DepositsBase._toBytes8LittleEndian`

Assembly converts `uint64 v` (stored in the low 8 bytes of a 256-bit EVM word) to an 8-byte little-endian `bytes8`. Byte 0x1f of `v` (least significant byte) is placed at the most significant position of `bytes8`. Verification: for `v=1`, output = `0x0100000000000000` (correct LE representation of 1).

### 6.4 `Deposits.protected` — Front-Run Protection

```solidity
require(DEPOSIT_CONTRACT.get_deposit_root() == expectedDepositRoot, DepositRootMismatch());
```

Commits to a specific state of the deposit Merkle accumulator. If an attacker inserts a deposit (e.g., with fraudulent withdrawal credentials) between the caller's broadcast and confirmation, `get_deposit_root()` changes and this call reverts. The honest caller retries with the new root.

### 6.5 `DepositsGno._deposit(uint256, bytes)` — Double Transfer Pattern

```solidity
require(GNO_TOKEN.transferFrom(msg.sender, address(this), amount));
require(GNO_TOKEN.transferAndCall(DEPOSIT_CONTRACT, amount, depositData));
```

Step 1 pulls tokens from caller to `DepositsGno`. Step 2 sends from `DepositsGno` to `DEPOSIT_CONTRACT`, triggering `onTokenTransfer`. If step 2 reverts, the entire transaction reverts including step 1 — no stuck tokens. Net: caller's GNO moves `msg.sender → DEPOSIT_CONTRACT`.

### 6.6 `DepositsGno` Amount Scaling

GNO token has **18 decimals**. The formula `32 * amount / 1e9` in `topup` converts GNO base units to beacon chain gwei-equivalents. The deposit contract applies `stake_amount = 32 * stake_amount` then `deposit_amount = stake_amount / 1e9`, producing the same value. Internally consistent.

`onTokenTransfer` data format (208 bytes for single deposit):
```
data[0:32]    = withdrawal_credentials
data[32:80]   = pubkey (48 bytes)
data[80:176]  = signature (96 bytes)
data[176:208] = deposit_data_root (32 bytes)
```
`208 % 176 == 32` — passes the contract's length check.

---

## 7. Uncertainty Investigations

### U-1 — `raw_call` revert propagation ✅ Resolved

**Confirmed propagates.** `test_inner_revert` (`WithdrawalReceiver.t.sol:45`) proves both `_arbitrary_call` and `_pull_native_balance` propagate reverts from the target. Vyper 0.4.3's `raw_call` without `revert_on_failure=False` uses the default `revert_on_failure=True`.

### U-2 — Zero-balance `_pull_native_balance` ⚠️ Edge case confirmed

`raw_call(destination, b"", value=0)` with a zero balance is a valid EVM call that still invokes the destination's `receive`/fallback if it is a contract. If that function reverts, `pullNativeBalance` reverts even though there is no ETH to transfer.

Consequence: if `destination` is a contract that rejects zero-value ETH calls, `pullNativeBalance` unexpectedly fails when the receiver holds no balance. Since `destination` defaults to `msg.sender`, a multisig or proxy contract with such a guard could be affected. There is no partial-state risk (CEI means fingerprint rollback if reverted), but the unexpected revert is a usability concern.

### U-3 — GNO token decimals ✅ Resolved

**GNO mock has 18 decimals** (`GnosisToken.sol:26`). The system context description of "9 decimals" was misleading. The formula `32 * amount / 1e9` is correct with 18 decimals: `32 * 1e18 / 1e9 = 32e9` gwei-equivalent per GNO, which matches the deposit contract's internal computation (`32 * stake_amount / 1e9`). Verified against `_computeDepositDataRoot` in `SBCDepositContractMock.sol:237`.

### U-4 — Deposit amount alignment ✅ Resolved

Both deposit contracts enforce alignment before computing the data root:

- **Mainnet** (`DepositContractMock:69`): `require(msg.value % 1 gwei == 0, "...not multiple of gwei")`
- **Gnosis** (`SBCDepositContractMock:152`): `require(32 * stake_amount % 1 gwei == 0, ...)`

Sub-gwei amounts revert with a clear message. Confirmed by `test_topup_extra_value` in both test suites. There is no silent absorption scenario.

### U-5 — `check_operator` unused `token_id` parameter ✅ Resolved (by design)

The `token_id` parameter is unused inside `check_operator` and exists purely for API symmetry with `check_allowed`, which shares the same `(token_id, owner)` signature and does use `token_id` to read the per-token `approved` address. Call sites are uniform across the codebase.

### U-6 — `nonreentrancy on` scope ✅ Confirmed

`pragma nonreentrancy on` with `pragma evm-version prague` uses EIP-1153 transient storage (`TSTORE`/`TLOAD`) for a **single global lock** covering all external state-modifying functions. View functions are not guarded. Consequence: any callback (ERC-721 receiver, ETH destination, arbitrary call target) cannot re-enter any state-mutating ERCXXXX function.

### U-7 — ERC-55 nibble alignment ✅ Resolved

The implementation correctly maps hex character `i` to bits `(255−4i):(252−4i)` of `keccak256(lowercase_hex_address)`. `erc55_process_nibble(checksum >> shift, char)` uses `checksum % 16 > 7` to test the extracted nibble ≥ 8. Empirically verified: `test_token_uri_reverts_nonexistent` asserts `tokenURI`'s withdrawal address field equals `vm.toString(withdrawalAddressOf(id1))`, where Foundry's `vm.toString` produces canonical ERC-55 output.

### U-8 — CREATE2 producing `address(0)` ✅ Non-issue

Probability = 1/2^160 ≈ 6×10^−49. The conflation between a genuine hash-to-zero result and a CREATE2 deployment failure is harmless in practice. The "already minted" error message is accurate for all real-world scenarios.

### U-9 — `_padding[245]` slot count ✅ Resolved

Calculation: `1 (next_id) + 1 (tokens_by_owner) + 1 (approval_for_all) + 245 (_padding) = 248`. `token_data[0]` at slot 248 = 0xF8; `token_data[1]` at slot 256 = 0x100. Confirmed by `test_storage_layout`: `vm.load(address(dut), bytes32(uint256(256))) == bytes32(uint256(uint160(user1)))`.

---

## 8. Global Invariants

| ID | Invariant |
|---|---|
| G-1 | `CONTROLLER` in every `WithdrawalReceiver` proxy == `address(ERCXXXX)` |
| G-2 | Token ID 0 is permanently unminted; valid IDs are `{1, …, next_id−1}` with no gaps |
| G-3 | `tokens_by_owner[owner][token_data[t].index] == t` for all minted `t` (ownership/index bi-consistency) |
| G-4 | `token_data[t].approved == address(0)` immediately after every transfer |
| G-5 | `validator_key_hi`, `validator_key_lo`, `withdrawal_address` are write-once (set in `mint`, no setters) |
| G-6 | `state_fingerprint` advances monotonically; never resets to a prior value |
| G-7 | ETH exits `WithdrawalReceiver` only via: `beacon_chain_request` (exact fee), `_pull_native_balance` (entire balance), `_arbitrary_call` (msg.value only) |
| G-8 | Fingerprint NOT updated on `requestPartialWithdrawal`, `requestFullWithdrawal`, or transfers |
| G-9 | All external state-modifying ERCXXXX functions are reentrancy-guarded by a single global lock |
| G-10 | Fee paid to EIP-7002/7251 == fee queried in the same transaction (no block boundary between query and submit) |
| G-11 | `DepositsGno` token transfers are atomic — no partial state if either step fails |
| G-12 | `balanceOf(owner) == len(tokens_by_owner[owner])` for all addresses |
| G-13 | For topup deposits, withdrawal credentials in `depositDataRoot` are always zero bytes |
| G-14 | For initial/full deposits, withdrawal credentials reference the exact `WithdrawalReceiver` for that token ID |

---

## 9. Assumptions

| ID | Assumption |
|---|---|
| A-1 | The `withdrawal_receiver_code` passed to `__init__` is the compiled `WithdrawalReceiver.vy` bytecode. Incorrect bytecode would set wrong `CONTROLLER`, breaking all beacon chain request calls. |
| A-2 | BLS12-381 compressed points always have their most significant bit set, making `validator_key_hi != bytes32(0)` a valid existence proxy. |
| A-3 | EIP-7002/7251 system contracts: static call with empty input returns a `uint256` fee; subsequent call with `value=fee` and the appropriate payload processes the request. |
| A-4 | CREATE2 never legitimately produces `address(0)` (probability 1/2^160). |
| A-5 | Vyper 0.4.3's `DynArray.append` reverts when length would exceed `MAX_ID = 2^96`. Bounds per-owner token count. |
| A-6 | `abi_encode` in Vyper encodes `bytes16` as left-aligned with 16 zero bytes of right-padding in the 32-byte ABI word. Critical for fingerprint computation consistency. |
| A-7 | GNO token on Gnosis Chain has 18 decimals. The `32 * amount / 1e9` scaling in `DepositsGno` depends on this. |

---

## 10. Test Coverage Notes

| Test | What it validates |
|---|---|
| `test_storage_layout` | `token_data[1]` at slot 0x100; `token_data[2]` at slot 0x108 |
| `test_stale_index_after_transfer` | `_transfer` correctly updates `last_id`'s index; self-consistency of swap-and-pop |
| `test_approve_by_approvee` | Per-token approved address cannot call `approve` to sub-delegate |
| `test_approve_by_operator` | Emitted `Approval.owner` is the actual owner, not `msg.sender` |
| `test_inner_revert` | `_arbitrary_call` and `_pull_native_balance` propagate reverts from targets |
| `test_state_fingerprint` | Withdrawal requests do NOT change fingerprint; consolidation, pull, arbitraryCall do |
| `test_mint_already_minted` | CREATE2 collision → "already minted" |
| `test_request_full_withdrawal_fee_from_receiver` | Fee sourced from receiver's pre-existing balance, not just `msg.value` |
| `test_topup_extra_value` (both) | Sub-gwei amounts revert with "not multiple of gwei" |
| `test_token_uri_reverts_nonexistent` | ERC-55 implementation matches `vm.toString` output |

---

## 11. Key End-to-End Workflows

### Validator Onboarding (Mainnet)
1. Caller invokes `ERCXXXX.mint(key_hi, key_lo, owner)` → CREATE2 deploys `WithdrawalReceiver`
2. Caller invokes `Deposits.protected(id, compounding, sig, dataRoot, expectedDepositRoot){value: 32 ether}` → constructs withdrawal credential pointing to `WithdrawalReceiver`, forwards deposit to ETH2 deposit contract
3. Beacon chain activates validator; ETH withdrawals are pushed to `WithdrawalReceiver` balance

### Claiming Withdrawal ETH
1. Token owner calls `ERCXXXX.pullNativeBalance(id, destination)`
2. ERCXXXX: authorization check → fingerprint update → `extcall WithdrawalReceiver._pull_native_balance(destination)`
3. `WithdrawalReceiver`: `assert msg.sender == CONTROLLER` → `raw_call(destination, b"", value=self.balance)`

### Validator Exit
1. Owner calls `ERCXXXX.requestFullWithdrawal(id){value: fee}` (or 0 if receiver holds balance)
2. ERCXXXX: authorization → `extcall WithdrawalReceiver.beacon_chain_request(WITHDRAWAL_REQUESTS, pubkey||zeros8, value=msg.value)`
3. `WithdrawalReceiver`: queries fee via static call → calls `WITHDRAWAL_REQUESTS` with `value=fee`

### Trust Boundary
```
Untrusted caller
  → ERCXXXX (check_allowed gate + global reentrancy guard)
    → WithdrawalReceiver (assert CONTROLLER gate)
      → EIP-7002/7251 system contracts  (protocol)
      → arbitrary target                (user-controlled, guarded by ERCXXXX's lock)
      → ETH destination                 (user-controlled, guarded by ERCXXXX's lock)
```
