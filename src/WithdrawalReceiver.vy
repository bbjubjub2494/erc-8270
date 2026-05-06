# pragma version ==0.4.3
# pragma evm-version prague

from src.interfaces import IWithdrawalReceiver

implements: IWithdrawalReceiver

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
def beacon_chain_request(target: address, data: Bytes[96]):
    assert msg.sender == CONTROLLER
    fee: uint256 = self._query_fee(target)
    raw_call(target, data, value=fee)


@external
@payable
def _pull_native_balance(destination: address):
    raw_call(destination, b"", value=self.balance)


@external
@payable
def _arbitrary_call(target: address, data: Bytes[65536] = b""):
    raw_call(target, data, value=msg.value)
