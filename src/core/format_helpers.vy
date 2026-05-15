# pragma version ==0.4.3
# pragma evm-version prague

@pure
def to_hex_digit(nibble: uint256) -> String[1]:
    alphabet: String[16] = "0123456789abcdef"
    return slice(alphabet, nibble, 1)


@view
def to_hex(byte: uint256) -> String[2]:
    byte = byte % 256
    return concat(self.to_hex_digit(byte // 16), self.to_hex_digit(byte % 16))


@view
def bytes32_to_hex(data: bytes32) -> String[64]:
    v: uint256 = convert(data, uint256)
    return concat(
        self.to_hex(v >> 248),
        self.to_hex(v >> 240),
        self.to_hex(v >> 232),
        self.to_hex(v >> 224),
        self.to_hex(v >> 216),
        self.to_hex(v >> 208),
        self.to_hex(v >> 200),
        self.to_hex(v >> 192),
        self.to_hex(v >> 184),
        self.to_hex(v >> 176),
        self.to_hex(v >> 168),
        self.to_hex(v >> 160),
        self.to_hex(v >> 152),
        self.to_hex(v >> 144),
        self.to_hex(v >> 136),
        self.to_hex(v >> 128),
        self.to_hex(v >> 120),
        self.to_hex(v >> 112),
        self.to_hex(v >> 104),
        self.to_hex(v >> 96),
        self.to_hex(v >> 88),
        self.to_hex(v >> 80),
        self.to_hex(v >> 72),
        self.to_hex(v >> 64),
        self.to_hex(v >> 56),
        self.to_hex(v >> 48),
        self.to_hex(v >> 40),
        self.to_hex(v >> 32),
        self.to_hex(v >> 24),
        self.to_hex(v >> 16),
        self.to_hex(v >> 8),
        self.to_hex(v),
    )


@view
def bytes16_to_hex(data: bytes16) -> String[32]:
    v: uint256 = convert(data, uint256)
    return concat(
        self.to_hex(v >> 120),
        self.to_hex(v >> 112),
        self.to_hex(v >> 104),
        self.to_hex(v >> 96),
        self.to_hex(v >> 88),
        self.to_hex(v >> 80),
        self.to_hex(v >> 72),
        self.to_hex(v >> 64),
        self.to_hex(v >> 56),
        self.to_hex(v >> 48),
        self.to_hex(v >> 40),
        self.to_hex(v >> 32),
        self.to_hex(v >> 24),
        self.to_hex(v >> 16),
        self.to_hex(v >> 8),
        self.to_hex(v),
    )


@view
def address_to_hex(data: address) -> String[40]:
    v: uint256 = convert(data, uint256)
    return concat(
        self.to_hex(v >> 152),
        self.to_hex(v >> 144),
        self.to_hex(v >> 136),
        self.to_hex(v >> 128),
        self.to_hex(v >> 120),
        self.to_hex(v >> 112),
        self.to_hex(v >> 104),
        self.to_hex(v >> 96),
        self.to_hex(v >> 88),
        self.to_hex(v >> 80),
        self.to_hex(v >> 72),
        self.to_hex(v >> 64),
        self.to_hex(v >> 56),
        self.to_hex(v >> 48),
        self.to_hex(v >> 40),
        self.to_hex(v >> 32),
        self.to_hex(v >> 24),
        self.to_hex(v >> 16),
        self.to_hex(v >> 8),
        self.to_hex(v),
    )
