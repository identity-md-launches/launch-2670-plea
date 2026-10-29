# PLEA

PLEA is an immutable ERC-20 token. Its constructor mints the entire supply to the
immediate deployer, and there is no way to mint again or change the token's rules.

| Property | Value |
| --- | --- |
| Solidity contract | `src/PLEA.sol:PLEA` |
| Token name | `PLEA` |
| Token symbol | `PLEA` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor transaction value | `0` ETH |
| Initial recipient | Constructor `msg.sender` |
| Owner / admin / initialization | None |

## Behavior and assumptions

The brief specifies a custom token's metadata and supply without additional
transfer rules. PLEA therefore uses the unmodified ERC-20 behavior from
[OpenZeppelin Contracts v5.0.2](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2/contracts/token/ERC20).
There are no taxes, transfer fees, burns, rebases, restrictions on trading,
blacklists, pause controls, owner privileges, permit signatures, or upgrades.
`INITIAL_SUPPLY` is the named constant for the constructor's single mint.

Transfers move exactly the requested amount and emit `Transfer`. Zero-amount
transfers between nonzero addresses are valid, including for accounts without a
balance. Self-transfers preserve the balance. Transfers to the zero address
revert; insufficient balances and allowances revert with ERC-6093 custom errors.
All failed operations roll back balances and allowances together.

`approve` replaces the caller's allowance for a spender and emits `Approval`.
`transferFrom` requires an allowance even when the spender is also the holder,
and reduces finite allowances. The maximum `uint256` allowance is treated as
unlimited and is not reduced. A zero-amount `transferFrom` between nonzero
addresses can succeed with zero allowance. This OpenZeppelin version does not
emit `Approval` when an allowance is spent; integrations should query `allowance`.

The contract makes no external calls or recipient callbacks. It does not accept
ordinary ETH payments and has no asset recovery method. Tokens sent to its own
address, or to another contract unable to return them, may be permanently locked.

## Build and check

Run from the repository root with Foundry and Solidity **0.8.26** available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xd4baa130dc8db549b7f5efd6a6e83178db3d58f0732d71555820a12f230955f2 forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, optimizer runs of 200,
and `bytecode_hash = "none"`. FFI is disabled and no filesystem permissions are
granted. Fuzz tests run 512 cases per property. Each invariant runs 128 sequences
of up to 64 operations and fails on unexpected handler reverts. Tests use no RPC,
fork, keys, environment reads, wall-clock delays, or filesystem cheatcodes.

Dependencies are ordinary files under `lib/`, including their licenses; no
package installation, submodule initialization, or network access is required
once Foundry and the pinned compiler are present. `DEPENDENCIES.json` records
upstream tags, archive URLs, and SHA-256 hashes for every vendored file:

- OpenZeppelin Contracts **v5.0.2**: the five Solidity files needed for ERC-20,
  including its interfaces and context, with the MIT license.
- forge-std **v1.9.6**: test support sources, with MIT and Apache-2.0 licenses.

## Deployment

Deploy the creation bytecode for **PLEA**, with no appended constructor
arguments and no ETH. `out/PLEA.sol/PLEA.json` contains the ABI and bytecode after
building. For inspection without sending a transaction:

```sh
forge inspect src/PLEA.sol:PLEA abi
forge inspect src/PLEA.sol:PLEA bytecode
```

The intended launch chain is Ethereum mainnet (chain ID 1). The constructor has
no chain-specific addresses or external dependencies. It requires no owner,
oracle, router, configuration setter, or initialization transaction.

When a factory deploys the token using CREATE or CREATE2, **the factory receives
all `10^27` base units**, not the account calling the factory and not `tx.origin`.
A direct deployment instead credits the deploying account. Any deployment
wrapper must be able to distribute the tokens it receives; otherwise they stay
in that wrapper. The token gives its deployer no continuing privileges over
holders' balances.

The IdentityMD launch factory is responsible for the launch's distribution: 10%
of supply to its MerkleDistributor, 80% for pool seeding, and the remaining 10% to
`0x863e974406764c8526b102c28a1e53906e032954`. The native-ETH pool and its 1.25% pool
fee are external launch infrastructure, not a token transfer tax. The launch's
10 ETH initial market cap, liquidity placement, and distribution are not
implemented by this token. There are no application contracts to deploy.
The separate launch process supplies `launch.json`, attestation, and transactions.
This project does not broadcast transactions.

## After launch

No owner action or token configuration is required. The launch operator must
verify the deployed bytecode, metadata, 18 decimals, and initial mint of `10^27`
base units to the factory, then verify distribution and pool setup against the
launch manifest. Source verification and publication of the actual token address
belong to that operator.

Holders control their tokens and spending approvals. Use only trusted spenders
and approve the amounts needed. When changing a live nonzero allowance, first
set it to zero and wait for confirmation before granting the replacement; an
already-authorized spender may consume the old allowance before revocation.
Unlimited allowances remain usable until revoked. There is no administrator who
can reverse transfers, recover lost assets, freeze accounts, or repair the code.

## Validation scope

- `test/PLEA.t.sol` checks metadata, the sole constructor mint event, exact
  transfers, self/zero transfers, finite and unlimited approvals, revocation,
  allowance isolation, invalid recipients, balance/allowance failures and atomic
  rollback. It probes absent administrative entrypoints from the deployer and an
  outsider and fuzzes success and failure paths over arbitrary amounts.
- `test/PLEAFactory.t.sol` checks CREATE2 prediction, minting to the factory rather
  than its caller, independent deployments, duplicate salt failure, exact
  distribution/claim/pool-direction token transfers, runtime size, and absence of
  the forbidden runtime opcodes used by the launch checks. The pool roles here
  exercise token transfers, not a live Uniswap liquidity manager or price model.
- `test/PLEAInvariant.t.sol` checks an independent balance and allowance model
  after randomized transfers, approvals, unlimited approvals, delegated spending,
  and attempted spending after revocation. Every unit of the fixed supply is
  accounted for across the closed set of holders.

The supplied protected launch tests were read as acceptance inputs. They require
the separate launch infrastructure, resolved manifest bytecode, and runtime
configuration; those are not included here. Local tests do not claim to run that
external harness. Independent launch verification and adversarial review remain
release responsibilities. Slither and Mythril were not run; passing Foundry tests
is not a security audit.

Local verification completed with Solidity 0.8.26: `forge build`, the seeded
`forge test` command above (39 passing tests as counted by Foundry, including
both invariant properties over 8,192 handler calls), and `forge fmt --check`.
The deployed runtime is 1,752 bytes and has no library link references. Vendored
dependency hashes were checked against `DEPENDENCIES.json`.
