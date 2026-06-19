# Arcis Protocol — Security Report

## Static Analysis: Slither v0.11.5

Date: 2026-06-19
Contracts analyzed: 17 production contracts
Detectors run: 101

### Summary

| Severity | Count | Status |
|---|---|---|
| High | 0 | — |
| Medium (Reentrancy) | 15 | Mitigated by `nonReentrant` on all public functions |
| Low (Missing zero-checks) | 9 | Accepted for testnet, fix before mainnet |
| Informational | 108 | Reviewed, mostly expected patterns |

### Reentrancy Findings

Slither flagged 15 reentrancy patterns where state variables are written after external calls. All flagged functions are protected by the `nonReentrant` modifier, which prevents re-entry. These are false positives in the context of the reentrancy guard.

Affected functions: `deposit`, `withdraw`, `borrow`, `repay`, `liquidate`, `harvest`, `purchase`, `redeem`, `serviceDebt`, `rebalance`, `emergencyWithdrawStrategy`

Status: **Mitigated.** All external-calling functions use `nonReentrant`.

### Missing Zero-Address Checks

The following constructor parameters accept `address(0)` without reverting:

- `AgentCredit._identityRegistry` — Intentional: `address(0)` disables identity checks
- `ATIRouter._credit` — Intentional: `address(0)` means credit module not deployed yet
- `StrategyAave._aavePool`, `._aToken` — Should add check before mainnet
- `StrategyMorpho._morphoVault` — Should add check before mainnet
- `StrategyOndoUSDY._usdy`, `._ondoRouter` — Should add check before mainnet

### Gas Optimizations Identified

- Array length not cached in strategy loops — minor, 3-5 strategies max
- Some state variables could be `immutable` — partially fixed
- `paused` in AgentCredit/RevenueBondFactory never toggled — could remove or add toggle functions

### Recommendations Before Mainnet

1. Add zero-address checks to strategy adapter constructors
2. Add `pause()`/`unpause()` to AgentCredit and RevenueBondFactory
3. Consider adding a withdrawal delay for large redemptions (whale protection)
4. Professional audit by Trail of Bits, OpenZeppelin, or Spearbit
5. Formal verification of share price calculation (MathLib.toShares/toAssets)
6. Fuzz testing with Echidna for invariant properties
