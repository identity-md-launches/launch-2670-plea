// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PLEA} from "../src/PLEA.sol";

/// @dev Test fixture only: represents the immediate deployer and its outgoing transfers.
contract TokenFactoryHarness {
    function deploy(bytes32 salt) external returns (PLEA) {
        return new PLEA{salt: salt}();
    }

    function move(PLEA token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

contract PLEAFactoryTest is Test {
    uint256 private constant SUPPLY = 1e27;
    TokenFactoryHarness private factory;

    function setUp() public {
        factory = new TokenFactoryHarness();
    }

    function test_create2MintsToFactoryRatherThanFactoryCaller() public {
        address caller = makeAddr("launch caller");
        bytes32 salt = keccak256("PLEA launch test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(PLEA).creationCode))
                    )
                )
            )
        );

        vm.prank(caller, caller);
        PLEA token = factory.deploy(salt);
        assertEq(address(token), predicted);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(caller), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_launchDistributionClaimsAndPoolTransfersArriveWhole() public {
        PLEA token = factory.deploy(keccak256("distribution test"));
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool manager transfer role");
        address remainder = makeAddr("remainder recipient");
        address claimant = makeAddr("claimant");
        address trader = makeAddr("trader");

        assertTrue(factory.move(token, distributor, SUPPLY / 10));
        assertTrue(factory.move(token, pool, SUPPLY * 8 / 10));
        assertTrue(factory.move(token, remainder, SUPPLY / 10));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), SUPPLY / 10);
        assertEq(token.balanceOf(pool), SUPPLY * 8 / 10);
        assertEq(token.balanceOf(remainder), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, SUPPLY / 10));
        assertEq(token.balanceOf(claimant), SUPPLY / 10);
        assertEq(token.balanceOf(distributor), 0);

        // Token-side settlement checks only; this fixture is not a Uniswap pool implementation.
        vm.prank(pool);
        assertTrue(token.transfer(trader, 1e18));
        assertEq(token.balanceOf(trader), 1e18);
        assertEq(token.balanceOf(pool), SUPPLY * 8 / 10 - 1e18);
        vm.prank(trader);
        assertTrue(token.transfer(pool, 1e18));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(pool), SUPPLY * 8 / 10);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_secondDeploymentHasIndependentSupply() public {
        PLEA first = factory.deploy(keccak256("first"));
        PLEA second = factory.deploy(keccak256("second"));
        assertNotEq(address(first), address(second));
        assertTrue(factory.move(first, address(this), SUPPLY));
        assertEq(first.balanceOf(address(factory)), 0);
        assertEq(second.balanceOf(address(factory)), SUPPLY);
        assertEq(first.totalSupply(), SUPPLY);
        assertEq(second.totalSupply(), SUPPLY);
    }

    function test_sameCreate2SaltCannotMintAgainAtSameAddress() public {
        bytes32 salt = keccak256("one deployment");
        PLEA token = factory.deploy(salt);
        vm.expectRevert();
        factory.deploy(salt);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_runtimeFitsDeploymentLimitAndHasNoForbiddenOpcodes() public {
        PLEA token = factory.deploy(keccak256("runtime check"));
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        bool reachable = true;
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5b) reachable = true;
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xf4, "DELEGATECALL");
                assertTrue(op != 0xf2, "CALLCODE");
                assertTrue(op != 0xff, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xf3 || op == 0xfd || op == 0xfe || op == 0xff) {
                reachable = false;
            }
        }
    }
}
