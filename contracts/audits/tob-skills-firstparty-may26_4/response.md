# Response

## F-01 — HIGH: Partial withdrawal amount uses big-endian encoding; EIP-7002 requires little-endian

Invalid finding. Confusingly, EIP-7002 takes its amount input as big endian and converts internally.

> 1. Add withdrawal request - requires a 56 byte input, the validator’s public key concatenated with a big-endian uint64 amount value.

https://eips.ethereum.org/EIPS/eip-7002#withdrawal-request-contract

---

## F-02 — MEDIUM: `requestSwitchToCompounding` missing fingerprint update (refactor regression)

This is correct, but intentional. The natspec should have been changed. Allowing changes to compounding allows switching to

---

## F-03 — LOW: No interface validation for `withdrawal_receiver_code` constructor parameter

Invalid finding. The deployment process is responsible to pass the correct bytecode.

> However, if the supplied bytecode is **valid but incorrect** (a different contract whose constructor does not revert), `raw_create` succeeds and `WITHDRAWAL_RECEIVER_IMPL` is set to that wrong implementation. All proxies deployed via `create_minimal_proxy_to` will point to it. The `extcall IWithdrawalReceiver(withdrawal_address)._set_validator_key(...)` call in `mint` would silently succeed (a call to a contract that doesn't implement the function returns success in EVM), leaving validator keys unset at zero — with no revert or error at mint time.

A call to a non-existent function does not return success.

---

## F-04 — INFORMATIONAL: `image_url` storage slot comment is incorrect

Comment fixed.

---

## F-05 — INFORMATIONAL: `tokenByIndex` silently relies on a no-burn invariant

Valid finding. We don't intend to introduce a burn function since there is no real use for it
