# ERC-XXXX Audit Findings

## F-01 — `_transfer` does not update the index of the moved token (swap-and-pop bug)

Valid finding, fixed

---

## F-02 — `requestPartialWithdrawal` silently becomes a full exit for amounts below 1 Gwei

Valid finding, fixed

---

## F-03 — `approve` emits `Approval` event with `msg.sender` instead of the actual token owner

ERC-721 per se is ambigous, but fixed for now

---

## F-04 — Fingerprint updates on silent call failures produce false state transitions

Invalid finding: raw_call reverts by default unless explicitly overriden.
Beacon chain requests could fail on the beacon chain and this is not detectable; in this case, the state fingerprint is unnecessarily updated, but this is better than an undetectable state change.
No change besides addition of a PoC.

---

## F-05 — `requestSwitchToCompounding` does not update the state fingerprint

Intended. Changing to compounding is not as severe since the stake is still in the validator unlike a normal consolidation. That said it wouldn't hurt to change this for consistency either.

---

## F-06 — ERC-165 does not advertise ERC-5646 or ERC-XXXX interfaces

Valid finding, fixed in the meantime. ERC-XXXX will not have an interface ID since it's a singleton contract.

---

## F-07 — ETH sent to `approve`, `transferFrom`, or `safeTransferFrom` is permanently locked

Intended. This is required for ERC-721 compliance even though it is an antipattern.

---

## F-08 — Reentrancy in `pullNativeBalance` and `arbitraryCall` allows fingerprint manipulation

Valid finding, fixed.

---

## Informational

### I-01 — `check_allowed` return value is dead code

Valid finding, fixed.

### I-02 — Incorrect storage-layout comment

Valid finding, fixed.

### I-03 — Multiple redundant existence sentinels

Intended for gas optimisation. Valid remark.
