// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PLEA} from "src/PLEA.sol";

/// @dev Complements the basic ERC-20 tests with sequence, aliasing and boundary properties.
/// forge-config: default.fuzz.runs = 1000
contract PLEAPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    PLEA private token;
    address private alice;
    address private bob;
    address private spender;
    address private otherSpender;
    address[5] private actors;

    function setUp() public {
        token = new PLEA();
        alice = makeAddr("property holder");
        bob = makeAddr("property recipient");
        spender = makeAddr("property spender");
        otherSpender = makeAddr("property other spender");
        actors = [address(this), alice, bob, spender, otherSpender];
    }

    function test_oneBaseUnitCanRoundTrip() public {
        bytes32 beforeState = _fingerprint();
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        assertEq(_fingerprint(), beforeState);
    }

    function test_fullSupplyCanMoveByDelegationAndReturn() public {
        token.approve(spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);

        vm.prank(alice);
        token.approve(otherSpender, SUPPLY);
        vm.prank(otherSpender);
        assertTrue(token.transferFrom(alice, address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(alice, otherSpender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_directSelfTransferStillRequiresSufficientBalance() public {
        token.transfer(alice, 7);
        bytes32 beforeState = _fingerprint();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 7, 8));
        vm.prank(alice);
        token.transfer(alice, 8);
        assertEq(_fingerprint(), beforeState);
    }

    function test_delegatedSelfTransferStillRequiresSufficientBalance() public {
        token.transfer(alice, 7);
        vm.prank(alice);
        token.approve(spender, 8);
        bytes32 beforeState = _fingerprint();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 7, 8));
        vm.prank(spender);
        token.transferFrom(alice, alice, 8);
        assertEq(_fingerprint(), beforeState);
    }

    function test_maximumFiniteAllowanceIsSpent() public {
        uint256 finite = type(uint256).max - 1;
        token.approve(spender, finite);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), finite - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), finite - SUPPLY);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_unlimitedApprovalCanBeRevokedAndReplacedWithFiniteApproval() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        token.approve(spender, 0);
        bytes32 revokedState = _fingerprint();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(_fingerprint(), revokedState);

        token.approve(spender, 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 2));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 3);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
    }

    function test_refillingAnEmptiedHolderDoesNotRenewSpentAllowance() public {
        token.transfer(alice, 5);
        vm.prank(alice);
        token.approve(spender, 8);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 5));
        assertEq(token.allowance(alice, spender), 3);

        bytes32 emptyState = _fingerprint();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(_fingerprint(), emptyState);

        token.transfer(alice, 4);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 3));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 8);
        assertEq(token.allowance(alice, spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
    }

    function test_twoSpendersCannotSpendTheSameBalanceTwice() public {
        token.transfer(alice, 10);
        vm.startPrank(alice);
        token.approve(spender, 10);
        token.approve(otherSpender, 10);
        vm.stopPrank();
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 10));

        bytes32 spentState = _fingerprint();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 10));
        vm.prank(otherSpender);
        token.transferFrom(alice, otherSpender, 10);
        assertEq(_fingerprint(), spentState);

        // The failed spender retains its grant and can use it once the holder is funded again.
        vm.prank(bob);
        token.transfer(alice, 10);
        vm.prank(otherSpender);
        assertTrue(token.transferFrom(alice, otherSpender, 10));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(alice, otherSpender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(otherSpender), 10);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferToZeroWithUnlimitedAllowanceReverts() public {
        token.approve(spender, type(uint256).max);
        bytes32 beforeState = _fingerprint();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(_fingerprint(), beforeState);
    }

    function test_zeroOwnerCannotBeUsedAsAMintSource() public {
        bytes32 beforeState = _fingerprint();
        // Both amounts must be rejected; the property does not depend on which validation runs first.
        vm.prank(spender);
        (bool zeroSucceeded,) = address(token).call(abi.encodeCall(token.transferFrom, (address(0), alice, 0)));
        assertFalse(zeroSucceeded);
        vm.prank(spender);
        (bool oneSucceeded,) = address(token).call(abi.encodeCall(token.transferFrom, (address(0), alice, 1)));
        assertFalse(oneSucceeded);
        assertEq(_fingerprint(), beforeState);
    }

    function test_ownerCanSpendItsSelfApprovalAndMustConsumeIt() public {
        token.approve(address(this), SUPPLY);
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), address(this)), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
    }

    function testFuzz_repeatedRoundTripsHaveNoFeesOrProfit(uint256 amount, uint256 repetitions) public {
        amount = bound(amount, 1, SUPPLY);
        repetitions = bound(repetitions, 1, 16);
        token.approve(spender, type(uint256).max);
        vm.prank(alice);
        token.approve(otherSpender, 1);
        bytes32 beforeState = _fingerprint();
        for (uint256 i; i < repetitions; ++i) {
            assertTrue(token.transfer(alice, amount));
            assertEq(token.balanceOf(alice), amount);
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
            vm.prank(alice);
            assertTrue(token.transfer(address(this), amount));
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
        }
        assertEq(_fingerprint(), beforeState);
    }

    function testFuzz_splittingTransfersMatchesOneTransfer(uint256 prefund, uint256 amount, uint256 first) public {
        prefund = bound(prefund, 0, SUPPLY);
        amount = bound(amount, 0, SUPPLY - prefund);
        first = bound(first, 0, amount);
        PLEA combined = new PLEA();
        token.transfer(alice, prefund);
        combined.transfer(alice, prefund);
        assertTrue(token.transfer(alice, first));
        assertTrue(token.transfer(alice, amount - first));
        assertTrue(combined.transfer(alice, amount));
        assertEq(token.balanceOf(alice), combined.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), combined.balanceOf(address(this)));
        assertEq(token.balanceOf(alice), prefund + amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - prefund - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splittingDelegatedTransfersConsumesTheSameAllowance(
        uint256 approved,
        uint256 amount,
        uint256 first
    ) public {
        uint256 limit = approved < SUPPLY ? approved : SUPPLY;
        amount = bound(amount, 0, limit);
        first = bound(first, 0, amount);
        PLEA combined = new PLEA();
        token.approve(spender, approved);
        combined.approve(spender, approved);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertTrue(token.transferFrom(address(this), alice, amount - first));
        assertTrue(combined.transferFrom(address(this), alice, amount));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), combined.allowance(address(this), spender));
        assertEq(token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.balanceOf(alice), combined.balanceOf(alice));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalReplacementIsIdempotentAndIsolated(uint256 first, uint256 replacement) public {
        token.approve(otherSpender, first);
        vm.prank(alice);
        token.approve(spender, first);
        token.approve(spender, first);
        token.approve(spender, replacement);
        bytes32 once = _fingerprint();
        assertTrue(token.approve(spender, replacement));
        assertEq(_fingerprint(), once);
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.allowance(address(this), otherSpender), first);
        assertEq(token.allowance(alice, spender), first);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_cumulativeSpendingCannotExceedFiniteGrant(uint256 grant, uint256 first) public {
        grant = bound(grant, 1, SUPPLY - 1);
        first = bound(first, 0, grant);
        token.approve(spender, grant);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertTrue(token.transferFrom(address(this), bob, grant - first));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), grant);
        assertEq(token.balanceOf(address(this)), SUPPLY - grant);
        bytes32 beforeState = _fingerprint();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(_fingerprint(), beforeState);
    }

    function testFuzz_delegatedSelfTransferOnlyChangesAllowance(uint256 balance, uint256 amount, uint256 approved)
        public
    {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, 0, approved < balance ? approved : balance);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, amount));
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(alice, spender), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedDelegatedOverspendRestoresApproval(uint256 balance, uint256 amount, bool unlimited) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max);
        uint256 approved = unlimited ? type(uint256).max : amount;
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, approved);
        bytes32 beforeState = _fingerprint();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(_fingerprint(), beforeState);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, balance));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), balance);
        assertEq(token.allowance(alice, spender), approved == type(uint256).max ? approved : approved - balance);
    }

    function testFuzz_rejectedZeroRecipientDoesNotConsumeApproval(uint256 amount, bool unlimited) public {
        amount = bound(amount, 0, SUPPLY);
        uint256 approved = unlimited ? type(uint256).max : amount;
        token.approve(spender, approved);
        bytes32 beforeState = _fingerprint();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(_fingerprint(), beforeState);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, amount));
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), spender), unlimited ? type(uint256).max : 0);
    }

    function testFuzz_approvalForAnotherOwnerOrSpenderCannotBeBorrowed(uint256 grant, uint256 amount) public {
        grant = bound(grant, 1, type(uint256).max);
        amount = bound(amount, 1, SUPPLY / 2);
        token.transfer(alice, SUPPLY / 2);
        token.approve(spender, grant);
        vm.prank(alice);
        token.approve(otherSpender, grant);
        bytes32 beforeState = _fingerprint();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(_fingerprint(), beforeState);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, otherSpender, 0, amount)
        );
        vm.prank(otherSpender);
        token.transferFrom(address(this), bob, amount);
        assertEq(_fingerprint(), beforeState);
    }

    /// @dev Observe the entire reachable ledger, including unrelated allowances, without reading slots.
    function _fingerprint() private view returns (bytes32) {
        uint256[5] memory balances;
        uint256[25] memory allowances;
        for (uint256 i; i < actors.length; ++i) {
            balances[i] = token.balanceOf(actors[i]);
            for (uint256 j; j < actors.length; ++j) {
                allowances[i * actors.length + j] = token.allowance(actors[i], actors[j]);
            }
        }
        return keccak256(
            abi.encode(
                token.totalSupply(), token.balanceOf(address(0)), token.balanceOf(address(token)), balances, allowances
            )
        );
    }
}
