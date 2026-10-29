// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PLEA} from "../src/PLEA.sol";

/// @dev A closed set of holders lets the invariant account for every unit of supply.
contract PLEAHandler is Test {
    PLEA public immutable token;
    address[4] private actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(PLEA token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = 1e27;
    }

    function transfer(uint256 senderSeed, uint256 recipientSeed, uint256 amount) external {
        address sender = _actor(senderSeed);
        address recipient = _actor(recipientSeed);
        amount = bound(amount, 0, expectedBalance[sender]);
        _transfer(sender, recipient, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function approveMaximum(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(_actor(ownerSeed), _actor(spenderSeed), type(uint256).max);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 recipientSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address recipient = _actor(recipientSeed);
        uint256 approved = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner] < approved ? expectedBalance[owner] : approved;
        amount = bound(amount, 0, available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[recipient] += amount;
        if (approved != type(uint256).max) expectedAllowance[owner][spender] = approved - amount;
    }

    function revokeAndAttemptSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 recipientSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        _approve(owner, spender, 0);
        address recipient = _actor(recipientSeed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, recipient, 1);
    }

    /// @dev Always moves a positive amount, even if the seeded holder has been emptied.
    function transferFullBalance(uint256 senderSeed, uint256 recipientSeed) external {
        address sender = _fundedActor(senderSeed);
        address recipient = _differentActor(recipientSeed, sender);
        uint256 amount = expectedBalance[sender];
        _transfer(sender, recipient, amount);
        assertEq(token.balanceOf(sender), 0, "full transfer left dust");
    }

    /// @dev Makes successful, positive delegated spends reachable without a lucky prior approval.
    function approveAndSpend(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 recipientSeed,
        uint256 amount,
        bool unlimited
    ) external {
        address owner = _fundedActor(ownerSeed);
        address spender = _actor(spenderSeed);
        address recipient = _actor(recipientSeed);
        amount = bound(amount, 1, expectedBalance[owner]);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[recipient] += amount;
        if (!unlimited) expectedAllowance[owner][spender] = 0;
    }

    function transferAboveBalance(uint256 senderSeed, uint256 recipientSeed, uint256 excess) external {
        address sender = _actor(senderSeed);
        address recipient = _actor(recipientSeed);
        uint256 balance = expectedBalance[sender];
        uint256 amount = balance + bound(excess, 1, type(uint256).max - balance);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, sender, balance, amount));
        vm.prank(sender);
        token.transfer(recipient, amount);
        // No ghost update: the ledger invariants must still hold after a rejected call.
    }

    function transferToZero(uint256 senderSeed, uint256 amount) external {
        address sender = _actor(senderSeed);
        amount = bound(amount, 0, expectedBalance[sender]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(sender);
        token.transfer(address(0), amount);
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function transferFromAboveAllowance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 recipientSeed,
        uint256 approvalSeed,
        uint256 amountSeed
    ) external {
        address owner = _fundedActor(ownerSeed);
        address spender = _actor(spenderSeed);
        address recipient = _actor(recipientSeed);
        uint256 approved = bound(approvalSeed, 0, expectedBalance[owner] - 1);
        uint256 amount = bound(amountSeed, approved + 1, expectedBalance[owner]);
        _approve(owner, spender, approved);
        // Balance is sufficient, so only the authorization check can reject this call.
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, recipient, amount);
    }

    function transferFromAboveBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 recipientSeed,
        uint256 excess,
        bool unlimited
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address recipient = _actor(recipientSeed);
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + bound(excess, 1, type(uint256).max - balance);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, recipient, amount);
        // The sufficient allowance above must survive the failed transfer in full.
    }

    function transferFromToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        amount = bound(amount, 0, expectedBalance[owner]);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
    }

    function roundTrip(uint256 senderSeed, uint256 recipientSeed, uint256 amount) external {
        address sender = _fundedActor(senderSeed);
        address recipient = _differentActor(recipientSeed, sender);
        amount = bound(amount, 1, expectedBalance[sender]);
        uint256 senderBefore = expectedBalance[sender];
        uint256 recipientBefore = expectedBalance[recipient];
        _transfer(sender, recipient, amount);
        // Check the outbound leg too: offsetting errors must not hide behind the round trip.
        assertEq(token.balanceOf(sender), senderBefore - amount);
        assertEq(token.balanceOf(recipient), recipientBefore + amount);
        _transfer(recipient, sender, amount);
        assertEq(token.balanceOf(sender), senderBefore);
        assertEq(token.balanceOf(recipient), recipientBefore);
    }

    function _transfer(address sender, address recipient, uint256 amount) private {
        vm.prank(sender);
        assertTrue(token.transfer(recipient, amount));
        expectedBalance[sender] -= amount;
        expectedBalance[recipient] += amount;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }

    function _differentActor(uint256 seed, address excluded) private view returns (address) {
        uint256 index = seed % actors.length;
        if (actors[index] == excluded) index = (index + 1) % actors.length;
        return actors[index];
    }

    function _fundedActor(uint256 seed) private view returns (address) {
        uint256 start = seed % actors.length;
        for (uint256 i; i < actors.length; ++i) {
            address candidate = actors[(start + i) % actors.length];
            if (expectedBalance[candidate] > 0) return candidate;
        }
        // A closed set owning a positive fixed supply must always contain a funded actor.
        revert("model lost the entire supply");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract PLEAInvariantTest is Test {
    PLEA private token;
    PLEAHandler private handler;
    address[4] private actors;

    function setUp() public {
        token = new PLEA();
        actors = [makeAddr("holder one"), makeAddr("holder two"), makeAddr("holder three"), makeAddr("holder four")];
        token.transfer(actors[0], 1e27);
        handler = new PLEAHandler(token, actors);

        bytes4[] memory selectors = new bytes4[](14);
        selectors[0] = PLEAHandler.transfer.selector;
        selectors[1] = PLEAHandler.approve.selector;
        selectors[2] = PLEAHandler.approveMaximum.selector;
        selectors[3] = PLEAHandler.transferFrom.selector;
        selectors[4] = PLEAHandler.revokeAndAttemptSpend.selector;
        selectors[5] = PLEAHandler.transferFullBalance.selector;
        selectors[6] = PLEAHandler.approveAndSpend.selector;
        selectors[7] = PLEAHandler.transferAboveBalance.selector;
        selectors[8] = PLEAHandler.transferToZero.selector;
        selectors[9] = PLEAHandler.approveZeroSpender.selector;
        selectors[10] = PLEAHandler.transferFromAboveAllowance.selector;
        selectors[11] = PLEAHandler.transferFromAboveBalance.selector;
        selectors[12] = PLEAHandler.transferFromToZero.selector;
        selectors[13] = PLEAHandler.roundTrip.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyAndBalancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertEq(balance, handler.expectedBalance(actors[i]));
            sum += balance;
        }
        assertEq(sum, 1e27);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_allowancesMatchModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }

    function invariant_metadataIsImmutable() public view {
        assertEq(token.name(), "PLEA");
        assertEq(token.symbol(), "PLEA");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), 1e27);
    }

    /// @dev After each random sequence every holder must still be able to move its entire balance.
    function afterInvariant() public {
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transfer(i, 0, handler.expectedBalance(actors[i]));
            assertEq(token.balanceOf(actors[i]), 0, "holder could not empty its balance");
        }
        assertEq(token.balanceOf(actors[0]), 1e27, "full supply cannot be recovered by its holders");
        // The collecting holder must be able to spend too, including at the full-supply boundary.
        handler.transfer(0, 1, 1e27);
        assertEq(token.balanceOf(actors[0]), 0);
        assertEq(token.balanceOf(actors[1]), 1e27);
        handler.transfer(1, 0, 1e27);
        assertEq(token.balanceOf(actors[1]), 0);
        invariant_supplyAndBalancesMatchModel();
        invariant_allowancesMatchModel();
        invariant_metadataIsImmutable();
    }
}
