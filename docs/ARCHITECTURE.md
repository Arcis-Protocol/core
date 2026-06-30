# Arcis Protocol — Architecture

## Contract Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    EXTERNAL ACTORS                        │
│  Agents (wallets)  ·  Human Investors  ·  Liquidators     │
└──────────────┬──────────────┬──────────────┬─────────────┘
               │              │              │
               ▼              ▼              ▼
┌──────────────────────────────────────────────────────────┐
│                     ATI ROUTER                            │
│  Single entry point for all agent interactions            │
│  Routes: deposit / withdraw / balance / borrow / repay    │
│  src/periphery/ATIRouter.sol                              │
└──────────┬──────────┬──────────┬──────────┬──────────────┘
           │          │          │          │
           ▼          ▼          ▼          ▼
┌────────────┐ ┌────────────┐ ┌──────────┐ ┌──────────────┐
│ ArcisVault │ │AgentCredit │ │ Revenue  │ │  Strategy    │
│            │ │            │ │  Bonds   │ │  Allocator   │
│ ERC-4626   │ │ ERC-8004   │ │          │ │              │
│ raUSDC     │ │ Identity   │ │ Bond NFT │ │ Rebalancer   │
│ shares     │ │ Lending    │ │ Escrow   │ │ Yield Router │
└─────┬──────┘ └─────┬──────┘ └────┬─────┘ └──────┬───────┘
      │              │             │               │
      ▼              ▼             ▼               ▼
┌──────────────────────────────────────────────────────────┐
│                   YIELD SOURCES                           │
│  Aave V3  ·  Morpho  ·  Ondo USDY  ·  Stable LP         │
└──────────────────────────────────────────────────────────┘
```

## Contract Inventory

### Core (src/core/)
| Contract | Purpose | Status |
|---|---|---|
| ArcisVault.sol | ERC-4626 vault, accepts USDC, mints raUSDC | Phase 1 |
| StrategyAllocator.sol | Routes capital across yield sources | Phase 1 |
| AgentCredit.sol | Identity-aware lending against raUSDC | Phase 2 |
| RevenueBondFactory.sol | Issues + manages agent revenue bonds | Phase 3 |
| RevenueEscrow.sol | Escrows agent revenue for bond servicing | Phase 3 |

### Interfaces (src/interfaces/)
| Interface | Purpose |
|---|---|
| IAgentTreasury.sol | The ATI standard — 3 functions |
| IStrategyAdapter.sol | Adapter interface for yield sources |
| IAgentCredit.sol | Credit module interface |
| IAgentIdentity.sol | ERC-8004 identity reader |
| IRevenueBond.sol | Bond issuance + purchase interface |

### Tokens (src/tokens/)
| Token | Purpose |
|---|---|
| RaUSDC.sol | Rebasing share token (ERC-20) |
| BondToken.sol | ERC-1155 bond position tokens |

### Periphery (src/periphery/)
| Contract | Purpose |
|---|---|
| ATIRouter.sol | Single-call entry point for agents |
| StrategyAave.sol | Aave V3 adapter |
| StrategyMorpho.sol | Morpho adapter |
| StrategyOndoUSDY.sol | Reserved — Ondo not on Base yet |

### Libraries (src/libraries/)
| Library | Purpose |
|---|---|
| MathLib.sol | Fixed-point math, share calculations |
| ErrorLib.sol | Custom error definitions |

## Deployment Order

1. RaUSDC token
2. ArcisVault (references RaUSDC, USDC)
3. Strategy adapters (Aave, Morpho, Ondo)
4. StrategyAllocator (references vault + adapters)
5. ATIRouter (references vault)
6. AgentCredit (Phase 2)
7. RevenueBondFactory + RevenueEscrow (Phase 3)

## Security Model

- Reentrancy guards on all state-changing functions
- Deposit cap enforced at vault level ($1M initial)
- Pausable via owner multisig
- Strategy allocation changes timelocked (24h)
- No flash loan exposure on exchange rate
- Share price manipulation resistant (ERC-4626 inflation attack mitigated with virtual shares)
