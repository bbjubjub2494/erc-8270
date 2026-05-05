# pragma version ==0.4.3
# pragma evm-version prague

from src.interfaces import IWithdrawalReceiver

from ethereum.ercs import IERC721


interface ERC721Receiver:
    def onERC721Received(
        sender: address, owner: address, token_id: uint256, data: Bytes[1024]
    ) -> bytes4: nonpayable


implements: IERC721

# we cap the token id so that it fits with a 20-byte address in one storage slot.
# this is purely for ease of reasoning since we will never mint this many.
MAX_ID: constant(uint256) = 2**96

# we store all the data associated with a token in an array of structs
# to increase locality and reduce hashing
# preemptive optimisation for state warming update and hash gas cost increases.
struct TokenData:
    index_and_owner: uint256
    approved: address
    validator_key_hi: bytes32
    validator_key_lo: bytes16
    withdrawal_address: address
    state_fingerprint: bytes32
    _padding: bytes32[2]


next_id: public(uint256)
tokens_by_owner: HashMap[address, DynArray[uint256, MAX_ID]]
approval_for_all: HashMap[address, HashMap[address, bool]]

# this puts the unused 0th element at 0xe8 and the first NFT at 0x100
_padding: bytes32[245]
token_data: TokenData[MAX_ID]

WITHDRAWAL_RECEIVER_IMPL: immutable(address)


@internal
@view
def _pack(index_by_owner: uint96, owner: address) -> uint256:
    return convert(index_by_owner, uint256) << 160 | convert(owner, uint256)


@internal
@view
def _unpack(index_and_owner: uint256) -> (uint96, address):
    index_by_owner: uint96 = convert(index_and_owner >> 160, uint96)
    mask: uint256 = convert(max_value(uint160), uint256)
    owner: address = convert(index_and_owner & mask, address)
    return index_by_owner, owner


@deploy
def __init__(withdrawal_receiver_code: Bytes[49152]):
    WITHDRAWAL_RECEIVER_IMPL = raw_create(withdrawal_receiver_code)
    self.next_id = 1


### ERC-165 ###

SUPPORTED_INTERFACES: constant(bytes4[3]) = [
    0x01ffc9a7,  # ERC-165
    0x80ac58cd,  # ERC-721
    0x780e9d63,  # ERC-721 enumeration
    # TODO ERC-5646, ERC-XXXX
]


@external
@view
def supportsInterface(interface_id: bytes4) -> bool:
    return interface_id in SUPPORTED_INTERFACES


## ERC-721 ##

@internal
@view
def _owner(token_id: uint256) -> address:
    owner: address = self._unpack(self.token_data[token_id].index_and_owner)[1]
    assert owner != empty(address), "ERC-721: token does not exist"
    return owner


@internal
@view
def check_exists(token_id: uint256):
    assert self.token_data[token_id].index_and_owner != 0, "ERC-721: token does not exist"


@internal
@view
def check_allowed(token_id: uint256, owner: address) -> address:
    if msg.sender != owner and msg.sender != self.token_data[token_id].approved:
        assert self.approval_for_all[owner][msg.sender], "ERC-721: not owner or approved"
    return owner


@external
@view
def balanceOf(owner: address) -> uint256:
    return len(self.tokens_by_owner[owner])


@external
@view
def ownerOf(token_id: uint256) -> address:
    return self._owner(token_id)


@external
@view
def getApproved(token_id: uint256) -> address:
    self.check_exists(token_id)
    return self.token_data[token_id].approved


@external
@view
def isApprovedForAll(owner: address, operator: address) -> bool:
    return self.approval_for_all[owner][operator]


@external
@payable
def approve(approved: address, token_id: uint256):
    self.check_allowed(token_id, self._owner(token_id))
    self.token_data[token_id].approved = approved
    log IERC721.Approval(owner=msg.sender, approved=approved, token_id=token_id)


@external
def setApprovalForAll(operator: address, approved: bool):
    self.approval_for_all[msg.sender][operator] = approved


@internal
def _transfer(expected_owner: address, receiver: address, token_id: uint256):
    index: uint96 = 0
    owner: address = empty(address)
    index, owner = self._unpack(self.token_data[token_id].index_and_owner)
    assert owner == expected_owner, "ERC-721: wrong owner"
    self.check_allowed(token_id, owner)
    assert receiver != empty(address), "ERC-721: transfer to zero"
    self.tokens_by_owner[owner][index] = (
        self.tokens_by_owner[owner][len(self.tokens_by_owner[owner]) - 1]
    )
    self.tokens_by_owner[owner].pop()
    index = convert(len(self.tokens_by_owner[receiver]), uint96)
    self.tokens_by_owner[receiver].append(token_id)
    self.token_data[token_id].index_and_owner = self._pack(index, receiver)
    self.token_data[token_id].approved = empty(address)
    log IERC721.Transfer(sender=owner, receiver=receiver, token_id=token_id)


# caller must ensure the token_id is fresh
@internal
def _mint(receiver: address, token_id: uint256):
    assert receiver != empty(address), "ERC-721: mint to zero"
    index: uint96 = convert(len(self.tokens_by_owner[receiver]), uint96)
    self.tokens_by_owner[receiver].append(token_id)
    self.token_data[token_id].index_and_owner = self._pack(index, receiver)
    self.token_data[token_id].approved = empty(address)
    log IERC721.Transfer(sender=empty(address), receiver=receiver, token_id=token_id)


@external
@payable
def transferFrom(owner: address, receiver: address, token_id: uint256):
    self._transfer(owner, receiver, token_id)


@external
@payable
def safeTransferFrom(
    owner: address,
    receiver: address,
    token_id: uint256,
    data: Bytes[1024] = b"",
):
    self._transfer(owner, receiver, token_id)

    if receiver.is_contract:
        assert (
            extcall ERC721Receiver(receiver).onERC721Received(msg.sender, owner, token_id, data)
            == 0x150b7a02
        ), "ERC-721: receiver rejected transfer"


## ERC-721 Enumerable ##

@external
@view
def totalSupply() -> uint256:
    return self.next_id - 1


@external
@view
def tokenByIndex(index: uint256) -> uint256:
    assert index < self.next_id - 1, "ERC-721: invalid index"
    return index + 1


@external
@view
def tokenOfOwnerByIndex(owner: address, index: uint256) -> uint256:
    assert index < len(self.tokens_by_owner[owner]), "ERC-721: invalid index"
    return self.tokens_by_owner[owner][index]


## ERC-5646 ##

@external
@view
def getStateFingerprint(token_id: uint256) -> bytes32:
    state_fingerprint: bytes32 = self.token_data[token_id].state_fingerprint
    assert state_fingerprint != empty(bytes32), "ERC-721: token does not exist"
    return state_fingerprint


## ERC-XXXX ##

@internal
@view
def withdrawal_receiver(token_id: uint256) -> IWithdrawalReceiver:
    return IWithdrawalReceiver(self.token_data[token_id].withdrawal_address)


@external
def mint(
    validator_key_hi: bytes32,
    validator_key_lo: bytes16,
    initial_owner: address = msg.sender,
) -> uint256:
    # compressed BLS12 points start with flags, hence structurally cannot be zero
    # we use this to save an sload in validatorKeyOf()
    assert validator_key_hi != empty(bytes32), "ERC-XXXX: invalid validator key"
    withdrawal_address: address = create_minimal_proxy_to(
        WITHDRAWAL_RECEIVER_IMPL,
        revert_on_failure=False,
        salt=keccak256(abi_encode(validator_key_hi, validator_key_lo, initial_owner)),
    )
    assert withdrawal_address != empty(address), "ERC-XXXX: already minted"

    token_id: uint256 = self.next_id
    self.next_id = token_id + 1
    self._mint(initial_owner, token_id)
    self.token_data[token_id].validator_key_hi = validator_key_hi
    self.token_data[token_id].validator_key_lo = validator_key_lo
    self.token_data[token_id].withdrawal_address = withdrawal_address
    self.token_data[token_id].state_fingerprint = keccak256(
        abi_encode(
            keccak256("Minted(bytes32 validatorKeyHi,bytes16 validatorKeyLo,address initialOwner)"),
            validator_key_hi,
            validator_key_lo,
            initial_owner,
        )
    )
    return token_id


@external
@view
def validatorKeyOf(token_id: uint256) -> (bytes32, bytes16):
    validator_key_hi: bytes32 = self.token_data[token_id].validator_key_hi
    assert validator_key_hi != empty(bytes32), "ERC-721: token does not exist"
    return (
        validator_key_hi,
        self.token_data[token_id].validator_key_lo,
    )


@external
@view
def withdrawalAddressOf(token_id: uint256) -> address:
    withdrawal_address: address = self.token_data[token_id].withdrawal_address
    assert withdrawal_address != empty(address), "ERC-721: token does not exist"
    return withdrawal_address


@external
@payable
def requestPartialWithdrawal(token_id: uint256, amount: uint256):
    self.check_allowed(token_id, self._owner(token_id))
    assert amount != 0, "ERC-XXXX: zero partial withdrawal amount"
    extcall self.withdrawal_receiver(token_id)._request_withdrawal(
        self.token_data[token_id].validator_key_hi,
        self.token_data[token_id].validator_key_lo,
        convert(amount // 1_000_000_000, uint64),
        value=msg.value,
    )


@external
@payable
def requestFullWithdrawal(token_id: uint256):
    self.check_allowed(token_id, self._owner(token_id))
    extcall self.withdrawal_receiver(token_id)._request_withdrawal(
        self.token_data[token_id].validator_key_hi,
        self.token_data[token_id].validator_key_lo,
        0,
        value=msg.value,
    )


@external
@payable
def requestConsolidation(token_id: uint256, target_key_hi: bytes32, target_key_lo: bytes16):
    self.check_allowed(token_id, self._owner(token_id))
    extcall self.withdrawal_receiver(token_id)._request_consolidation(
        self.token_data[token_id].validator_key_hi,
        self.token_data[token_id].validator_key_lo,
        target_key_hi,
        target_key_lo,
        value=msg.value,
    )
    self.token_data[token_id].state_fingerprint = keccak256(
        abi_encode(
            keccak256(
                "ConsolidationRequested(bytes32 previousFingerprint,bytes32 targetKeyHi,bytes16 targetKeyLo)"
            ),
            self.token_data[token_id].state_fingerprint,
            target_key_hi,
            target_key_lo,
        )
    )


@external
@payable
def requestSwitchToCompounding(token_id: uint256):
    self.check_allowed(token_id, self._owner(token_id))
    extcall self.withdrawal_receiver(token_id)._request_consolidation(
        self.token_data[token_id].validator_key_hi,
        self.token_data[token_id].validator_key_lo,
        self.token_data[token_id].validator_key_hi,
        self.token_data[token_id].validator_key_lo,
        value=msg.value,
    )


@external
def pullNativeBalance(token_id: uint256, destination: address = msg.sender):
    self.check_allowed(token_id, self._owner(token_id))
    extcall self.withdrawal_receiver(token_id)._pull_native_balance(destination)
    self.token_data[token_id].state_fingerprint = keccak256(
        abi_encode(
            keccak256("NativeBalancePulled(bytes32 previousFingerprint)"),
            self.token_data[token_id].state_fingerprint,
        )
    )


@external
@payable
def arbitraryCall(token_id: uint256, target: address, data: Bytes[65536] = b""):
    self.check_allowed(token_id, self._owner(token_id))
    extcall self.withdrawal_receiver(token_id)._arbitrary_call(target, data, value=msg.value)
    self.token_data[token_id].state_fingerprint = keccak256(
        abi_encode(
            keccak256("ArbitraryCall(bytes32 previousFingerprint,address target,bytes data)"),
            self.token_data[token_id].state_fingerprint,
            target,
            keccak256(data),
        )
    )
