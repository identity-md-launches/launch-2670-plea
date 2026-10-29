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
        vm.prank(sender);
        assertTrue(token.transfer(recipient, amount));
        expectedBalance[sender] -= amount;
        expectedBalance[recipient] += amount;
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

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }
}

contract PLEAInvariantTest is Test {
    PLEA private token;
    PLEAHandler private handler;
    address[4] private actors;

    function setUp() public {
        token = new PLEA();
        actors = [makeAddr("holder one"), makeAddr("holder two"), makeAddr("holder three"), makeAddr("holder four")];
        token.transfer(actors[0], 1e27);
        handler = new PLEAHandler(token, actors);

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = PLEAHandler.transfer.selector;
        selectors[1] = PLEAHandler.approve.selector;
        selectors[2] = PLEAHandler.approveMaximum.selector;
        selectors[3] = PLEAHandler.transferFrom.selector;
        selectors[4] = PLEAHandler.revokeAndAttemptSpend.selector;
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
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }
}
