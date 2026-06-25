# Arcis Protocol — Core Contracts

Smart contracts powering financial infrastructure for autonomous AI agents. Deployed on Base.

## Contracts

### Core

| Contract | Description |
|---|---|
| `ArcisVault` | ERC-4626 yield-bearing vault. USDC → raUSDC shares. Multi-strategy allocation. |
| `AgentCredit` | Identity-aware credit lines. ERC-8004 reputation tiers. Utilization-based rate oracle. |
| `RevenueBondFactory` | Revenue bond issuance, purchase, coupon distribution, maturity redemption. |
| `StrategyAllocator` | Timelocked strategy weight management with drift detection. |

### Periphery

| Contract | Description |
|---|---|
| `ATIRouter` | Single entry point: deposit, borrow, depositAndBorrow in one call. |
| `BaseStrategy` | Abstract strategy adapter with vault-only access control. |
| `StrategyAave` | Aave V3 USDC lending strategy. |
| `StrategyMorpho` | Morpho optimized lending strategy. |
| `StrategyOndoUSDY` | Ondo USDY tokenized treasury yield strategy. |

### Libraries

| Library | Description |
|---|---|
| `MathLib` | Fixed-point math, share/asset conversions, virtual offset inflation protection. |
| `ErrorLib` | All custom errors — zero `require()` across the protocol. |

### Tokens

| Token | Description |
|---|---|
| `BondToken` | ERC-20 bond receipt tokens minted per bond issuance. |

## Security Features

| Feature | Description |
|---|---|
| Emergency withdrawal | `emergencyWithdraw()` works even when vault is paused (reserve-only) |
| Strategy timelock | 24-hour delay on strategy additions (queue → execute → cancel) |
| Withdrawal fee ramp | 0.1% fee on withdrawals within 24h of deposit (flash loan protection) |
| Per-agent deposit caps | `perAgentCap` enforced alongside global `depositCap` |
| Rate oracle | Utilization-based interest curve (base + slope1 below optimal + slope2 jump) |
| ERC-4626 compatibility | Full view functions: convertToShares/Assets, maxWithdraw/Redeem, preview* |
| Inflation protection | Virtual shares/assets offset prevents first-depositor attacks |
| Reentrancy guards | `nonReentrant` on all state-changing functions |
| Custom errors | Zero `require()` — all custom errors for gas efficiency |
| Pausable | Owner can pause deposits/withdrawals; emergency withdraw still works |
| Two-step ownership | `transferOwnership` + `acceptOwnership` pattern |

## Tests

116/116 passing across 6 test suites:

| Suite | Tests | Coverage |
|---|---|---|
| ArcisVault | 27 | Deposit, withdraw, shares, strategies, fees, pause, ownership |
| AgentCredit | 11 | Borrow, repay, tiers, interest, collateral, liquidation |
| RevenueBondFactory | 20 | Issue, purchase, service debt, coupon, redeem, default |
| SecurityAudit | 32 | Access control, reentrancy, inflation, invariants, edge cases |
| ATIRouter | 15 | Deposit, borrow, depositAndBorrow, position queries |
| StrategyAllocator | 11 | Queue, execute, cancel, drift, timelock, ownership |

## Subgraph

The `subgraph/` directory contains a ready-to-deploy subgraph for The Graph:

- `schema.graphql` — Deposit, Withdrawal, Harvest, Loan, VaultSnapshot, ProtocolStats
- `src/vault.ts` — Vault event handlers
- `src/credit.ts` — Credit event handlers

## Deployed (Base Mainnet)

| Contract | Address |
|---|---|
| ArcisVault (raUSDC) | [`0x00325d9da832b38179ed2f0dabd4062d93e325a7`](https://basescan.org/address/0x00325d9da832b38179ed2f0dabd4062d93e325a7) |
| ATIRouter | [`0xeC3b7Daa942C03651D55A4A01797498fA6dB728F`](https://basescan.org/address/0xeC3b7Daa942C03651D55A4A01797498fA6dB728F) |
| StrategyAave | [`0x43626D6162Ccb12328B989BB228DaD2941F2F12a`](https://basescan.org/address/0x43626D6162Ccb12328B989BB228DaD2941F2F12a) |
| StrategyAllocator | [`0x7Fd5d7b49694858FCf143E0039e83cDB0196DD7A`](https://basescan.org/address/0x7Fd5d7b49694858FCf143E0039e83cDB0196DD7A) |

## Related Repos

| Repo | Description |
|---|---|
| [`sdk`](https://github.com/Arcis-Protocol/sdk) | `@arcisprotocol/sdk` — TypeScript SDK |
| [`mcp`](https://github.com/Arcis-Protocol/mcp) | `@arcisprotocol/mcp` — MCP server for AI agents |
| [`custos`](https://github.com/Arcis-Protocol/custos) | CUSTOS — autonomous keeper agent |
| [`app`](https://github.com/Arcis-Protocol/app) | arcis.money — landing + dashboard |
| [`docs`](https://github.com/Arcis-Protocol/docs) | ATI v1.1, integration guide, SDK examples |

---

*ARCIS · Solidity 0.8.24 · Foundry · Base · MMXXVI*
