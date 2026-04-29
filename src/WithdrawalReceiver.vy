# pragma version ~=0.4.3

from src.interfaces import IWithdrawalReceiver

implements: IWithdrawalReceiver

WITHDRAWAL_REQUESTS: constant(
    address
) = 0x00000961Ef480Eb55e80D19ad83579A64c007002
CONSOLIDATION_REQUESTS: constant(
    address
) = 0x0000BBdDc7CE488642fb579F8B00f3a590007251

CONTROLLER: public(immutable(address))


@deploy
def __init__():
    CONTROLLER = msg.sender


@internal
@view
def _query_fee(target: address) -> uint256:
    out: Bytes[32] = raw_call(target, b"", max_outsize=32, is_static_call=True)
    return extract32(out, 0, output_type=uint256)


@external
@payable
def _request_withdrawal(
    validatorKeyHi: bytes32, validatorKeyLo: bytes16, amount: uint64
):
    assert msg.sender == CONTROLLER
    fee: uint256 = self._query_fee(WITHDRAWAL_REQUESTS)
    raw_call(
        WITHDRAWAL_REQUESTS,
        concat(validatorKeyHi, validatorKeyLo, convert(amount, bytes8)),
        value=fee,
    )


@external
@payable
def _request_consolidation(
    sourceKeyHi: bytes32,
    sourceKeyLo: bytes16,
    targetKeyHi: bytes32,
    targetKeyLo: bytes16,
):
    assert msg.sender == CONTROLLER
    fee: uint256 = self._query_fee(CONSOLIDATION_REQUESTS)
    raw_call(
        CONSOLIDATION_REQUESTS,
        concat(
            sourceKeyHi,
            sourceKeyLo,
            targetKeyHi,
            targetKeyLo,
        ),
        value=fee,
    )


@external
@payable
def _pull_native_balance(destination: address):
    raw_call(destination, b"", value=self.balance)


@external
@payable
def _arbitrary_call(target: address, data: Bytes[65536] = b""):
    raw_call(target, data, value=msg.value)
