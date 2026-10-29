PLEA test coverage
==================

The existing metadata, constructor, event, ERC-20 and factory tests are retained.
`PLEAProperties.t.sol` adds 11 deterministic edge/sequence tests and nine fuzz
properties. `PLEAInvariant.t.sol` extends the existing four-actor ledger model
with rejected operations, positive delegated spending, round trips, full-balance
transfers and a final spendability check after each sequence.

The supplied Pashov fizz discovery guides and Trail of Bits property-testing
guide informed the following five review passes. These are grounded properties
of this token; vault pricing, rounding and yield properties do not apply.

| Review pass | Property and source basis | Checks |
| --- | --- | --- |
| Conservation | The constructor mints exactly `10^27` base units to its immediate deployer (`src/PLEA.sol:10–15`); transfers redistribute this fixed supply. | Existing constructor/factory tests; balances equal the independent ledger and sum to the required supply after every handler call. |
| State transitions | Approvals replace a single owner/spender grant; finite spending consumes it, unlimited spending preserves it (`ERC20.sol:118–119,284–314`). Reverted calls must roll back all changes. | Replacement/idempotence, cumulative spending, revocation, refill and two-spender tests; all 16 actor allowance pairs checked in invariants. |
| Round trips | Exact base-unit transfers have no fee or conversion (`ERC20.sol:188–214`). Sending an amount out and back restores the ledger; splitting transfers preserves balances and total allowance consumption. | Repeated round-trip and partition fuzz tests, plus a stateful round-trip action that also checks its intermediate state. |
| Adversarial inputs | A balance or allowance cannot be exceeded; invalid receivers/spenders must be rejected (`ERC20.sol:171–176,193–195,284–312`). | Stateful failures and stateless fuzz tests verify exact custom errors and unchanged accounting; pinned cases cover one unit, the full supply, self transfers, `uint256.max - 1` and unlimited approvals. |
| Token-specific rules | Metadata remains PLEA/PLEA/18; no holder can be frozen by ordinary operations; self transfers preserve balances and still require sufficient balance/allowance. | Metadata invariant, aliasing tests and `afterInvariant`, which moves every remaining actor balance to one holder and verifies the entire supply and unchanged allowances. |

`ERC20.sol` above refers to
`lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol`. The properties use
the public API of the actual `PLEA` contract; no storage edits, inherited token
variants or token-balance cheatcodes supply the test balances.

The model starts from the specified supply, not a copy of observed balances.
Only the 14 selected handler actions are fuzz targets. Valid and invalid calls
are deliberately mixed; expected failures leave the model unchanged after any
preparatory approval. Unexpected handler reverts fail the run. The positive
spending and full-balance actions select a funded actor from the closed set, so
they cannot silently become zero-value calls when a selected holder is empty.
Successful self/zero transfers remain reachable through the other actions.

The new stateless properties run 1,000 cases each. Stateful invariants run 256
sequences of 96 calls, with assertions checked after every action. These settings
live in inline Foundry annotations in the test files. Inputs use `bound` and
actor selection, without discarded fuzz cases in the additions.

Run from the repository root:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xd4baa130dc8db549b7f5efd6a6e83178db3d58f0732d71555820a12f230955f2 forge test
```

For local checks confined to the disposable test area, prefix either command
with `FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache`.
There are no additional dependencies or network requirements.

The protected launch inputs were reviewed. The factory test covers token-side
distribution and pool-direction transfers only. This repository does not contain
the external launch factory/Uniswap infrastructure needed to execute the
protected integration suite, and these tests do not substitute for it.
