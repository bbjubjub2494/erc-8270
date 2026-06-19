// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8;

import {Test} from "dependencies/forge-std-1.16.1/src/Test.sol";
import {IERC8270} from "src/interfaces/IERC8270.sol";
import {deployCore} from "scripts/Deploy.s.sol";

/// @notice Fuzz target for ERC8270 invariant tests.
/// All public handler_* functions are call targets; the fuzzer exercises arbitrary sequences.
contract ERC8270Handler is Test {
    IERC8270 public dut;

    address[] private _actors;
    uint256[] private _mintedIds;

    constructor(IERC8270 _dut) {
        dut = _dut;
        _actors.push(makeAddr("alpha"));
        _actors.push(makeAddr("beta"));
        _actors.push(makeAddr("gamma"));
    }

    function getActors() external view returns (address[] memory) {
        return _actors;
    }

    function getMintedIds() external view returns (uint256[] memory) {
        return _mintedIds;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return _actors[seed % _actors.length];
    }

    function _tokenId(uint256 seed) internal view returns (uint256) {
        if (_mintedIds.length == 0) return 0;
        return _mintedIds[seed % _mintedIds.length];
    }

    function handler_mint(uint256 actorSeed, bytes32 hi, bytes16 lo) external {
        address actor = _actor(actorSeed);
        vm.prank(actor);
        try dut.mint(hi, lo, actor) returns (uint256 id) {
            _mintedIds.push(id);
        } catch {}
    }

    function handler_transferFrom(uint256 callerSeed, uint256 tokenSeed, uint256 toSeed) external {
        uint256 id = _tokenId(tokenSeed);
        if (id == 0) return;
        address owner = dut.ownerOf(id);
        address to = _actor(toSeed);
        address caller = _actor(callerSeed);
        vm.prank(caller);
        try dut.transferFrom(owner, to, id) {} catch {}
    }

    function handler_approve(uint256 callerSeed, uint256 tokenSeed, uint256 approvedSeed) external {
        uint256 id = _tokenId(tokenSeed);
        if (id == 0) return;
        address caller = _actor(callerSeed);
        address approved = _actor(approvedSeed);
        vm.prank(caller);
        try dut.approve(approved, id) {} catch {}
    }

    function handler_setApprovalForAll(uint256 ownerSeed, uint256 operatorSeed, bool approved) external {
        address owner_ = _actor(ownerSeed);
        address operator = _actor(operatorSeed);
        if (owner_ == operator) return;
        vm.prank(owner_);
        dut.setApprovalForAll(operator, approved);
    }
}

contract ERC8270InvariantTest is Test {
    IERC8270 dut;
    ERC8270Handler handler;

    function setUp() external {
        dut = IERC8270(deployCore());
        handler = new ERC8270Handler(dut);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = ERC8270Handler.handler_mint.selector;
        selectors[1] = ERC8270Handler.handler_transferFrom.selector;
        selectors[2] = ERC8270Handler.handler_approve.selector;
        selectors[3] = ERC8270Handler.handler_setApprovalForAll.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// The sum of all actor balances must equal totalSupply.
    /// Tokens can only move between the three handler actors, so this is exact.
    function invariant_balance_sum_equals_total_supply() external view {
        address[] memory actors = handler.getActors();
        uint256 sum;
        for (uint256 i; i < actors.length; i++) {
            sum += dut.balanceOf(actors[i]);
        }
        assertEq(sum, dut.totalSupply());
    }

    /// Every minted token must be reachable via tokenOfOwnerByIndex.
    function invariant_owner_index_consistency() external view {
        uint256[] memory ids = handler.getMintedIds();
        for (uint256 i; i < ids.length; i++) {
            uint256 id = ids[i];
            address owner = dut.ownerOf(id);
            uint256 bal = dut.balanceOf(owner);
            bool found;
            for (uint256 j; j < bal; j++) {
                if (dut.tokenOfOwnerByIndex(owner, j) == id) {
                    found = true;
                    break;
                }
            }
            assertTrue(found);
        }
    }

    /// Since tokens are never burned, tokenByIndex(i) == i+1 for all i < totalSupply.
    function invariant_token_by_index_sequential() external view {
        uint256 total = dut.totalSupply();
        for (uint256 i; i < total; i++) {
            assertEq(dut.tokenByIndex(i), i + 1);
        }
    }

    /// State fingerprint is initialized on mint and never set back to zero.
    function invariant_fingerprint_nonzero() external view {
        uint256[] memory ids = handler.getMintedIds();
        for (uint256 i; i < ids.length; i++) {
            assertNotEq(dut.getStateFingerprint(ids[i]), bytes32(0));
        }
    }

    /// Withdrawal address is set on mint and must remain non-zero.
    function invariant_withdrawal_address_nonzero() external view {
        uint256[] memory ids = handler.getMintedIds();
        for (uint256 i; i < ids.length; i++) {
            assertNotEq(dut.withdrawalAddressOf(ids[i]), address(0));
        }
    }

    /// totalSupply must exactly equal the number of successful mints.
    function invariant_total_supply_matches_mint_count() external view {
        assertEq(dut.totalSupply(), handler.getMintedIds().length);
    }
}
