# ERC-XXXX Audit Findings


## M-1 — Approved Address Can Re-Delegate Approval (ERC-721 Spec Violation)

code corrected

---

## L-1 — ETH Sent to Non-Forwarding Payable Functions Is Permanently Locked

code corrected. The interface forces us to use `@payable`, so added an equivalent assert.

---

## L-2 — Zero-Balance `pullNativeBalance` Advances the State Fingerprint Without ETH Movement

this is intended.

---

## L-3 — `pullNativeBalance` Has No Zero-Address Guard on `destination`

valid but debatable: There are many other burn addresses where ether could be sent to. There is nothing special about the zero address. added for completeness.

---

## L-4 — Sub-Gwei ETH Is Silently Lost to the Deposit Contract in `Deposits.topup`

rejected. both the Ethereum and GnosisChain deposit contracts reject deposits if the value transfered is not a multiple of 1 gwei.

---

## I-1 — `GNO_TOKEN.transferFrom` Return Value Not Checked

valid. We assume that GNO reverts, but added for completeness

---

## I-2 — Any `create_minimal_proxy_to` Failure Is Reported as "Already Minted"

valid, but not an issue: `eth_estimateGas` can handle this, and there are many other existing contracts that have similar behavior.

---

## I-3 — `setApprovalForAll(msg.sender, …)` Not Restricted

code corrected.
