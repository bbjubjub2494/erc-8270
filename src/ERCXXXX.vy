# pragma version ~=0.4.3

from ethereum.ercs import IERC721

implements: IERC721

# we store all the data associated with a token in an array of structs
# to increase locality and reduce hashing
# preemptive optimisation for state warming update and hash gas cost increases.
struct TokenData:
    owner: address
    approved: address
    validator_key_hi: bytes32
    validator_key_lo: bytes16
    withdrawal_address: address
    _padding: bytes32[3]


next_id: public(uint256)
balances: HashMap[address, uint256]
approval_for_all: HashMap[address, HashMap[address, bool]]

# this puts the unused 0th element at 0xe8 and the first NFT at 0x100
_padding: bytes32[245]
token_data: TokenData[2**128]


@deploy
def __init__():
    self.next_id = 1


### ERC-165 ###

SUPPORTED_INTERFACES: constant(bytes4[2]) = [
    0x01ffc9a7,  # ERC-165
    0x80ac58cd,  # ERC-721
    # 0x780e9d63, # ERC-721 enumeration # TODO decide
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
    owner: address = self.token_data[token_id].owner
    assert owner != empty(address), "ERC-721: token does not exist"
    return owner


@internal
@view
def check_allowed(token_id: uint256) -> address:
    owner: address = self._owner(token_id)
    if msg.sender != owner and msg.sender != self.token_data[token_id].approved:
        assert self.approval_for_all[owner][
            msg.sender
        ], "ERC-721: not owner or approved"
    return owner


@external
@view
def totalSupply() -> uint256:
    return self.next_id


@external
@view
def balanceOf(owner: address) -> uint256:
    return self.balances[owner]


@external
@view
def ownerOf(token_id: uint256) -> address:
    return self._owner(token_id)


@external
@view
def getApproved(token_id: uint256) -> address:
    self._owner(token_id)
    return self.token_data[token_id].approved


@external
@view
def isApprovedForAll(owner: address, operator: address) -> bool:
    return self.approval_for_all[owner][operator]


@external
@payable
def approve(approved: address, token_id: uint256):
    self.check_allowed(token_id)
    self.token_data[token_id].approved = approved
    log IERC721.Approval(owner=msg.sender, approved=approved, token_id=token_id)


@external
def setApprovalForAll(operator: address, approved: bool):
    self.approval_for_all[msg.sender][operator] = approved


@internal
def _transfer(owner: address, receiver: address, token_id: uint256):
    assert owner == self.check_allowed(token_id), "ERC-721: wrong owner"
    assert receiver != empty(address), "ERC-721: transfer to zero"
    self.token_data[token_id].owner = receiver
    self.token_data[token_id].approved = empty(
        address
    )  # TODO: is this supposed receiver reset?
    self.balances[owner] -= 1
    self.balances[receiver] += 1
    log IERC721.Transfer(sender=owner, receiver=receiver, token_id=token_id)


# caller must ensure the token_id is fresh
@internal
def _mint(receiver: address, token_id: uint256):
    assert receiver != empty(address), "ERC-721: mint to zero"
    self.token_data[token_id].owner = receiver
    self.token_data[token_id].approved = empty(
        address
    )  # TODO: is this supposed receiver reset?
    self.balances[receiver] += 1
    log IERC721.Transfer(
        sender=empty(address), receiver=receiver, token_id=token_id
    )


@internal
def _call_erc721receiver(receiver: address, token_id: uint256):
    raise "TODO"


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
    self._call_erc721receiver(receiver, token_id)


## ERC-XXXX ##

@external
def mint(
    validator_key_hi: bytes32,
    validator_key_lo: bytes16,
    initial_owner: address = msg.sender,
) -> uint256:
    token_id: uint256 = self.next_id
    self.next_id = token_id + 1
    self._mint(initial_owner, token_id)
    self.token_data[token_id].owner = initial_owner
    self.token_data[token_id].validator_key_hi = validator_key_hi
    self.token_data[token_id].validator_key_lo = validator_key_lo
    # TODO: deploy withdrawal_address
    return token_id


@external
@view
def validatorKeyOf(token_id: uint256) -> (bytes32, bytes16):
    return (
        self.token_data[token_id].validator_key_hi,
        self.token_data[token_id].validator_key_lo,
    )
