<p align="center">
  <br />
  <strong>ARCIS PROTOCOL</strong>
  <br />
  <em>Financial infrastructure for autonomous AI agents</em>
  <br />
  <br />
  <a href="https://arcis.money">arcis.money</a>
  &nbsp;&middot;&nbsp;
  <a href="https://arcis.money/dashboard">Dashboard</a>
  &nbsp;&middot;&nbsp;
  <a href="https://github.com/Arcis-Protocol/docs">Docs</a>
  &nbsp;&middot;&nbsp;
  <a href="https://github.com/Arcis-Protocol/core/tree/main/src">Contracts</a>
</p>

<br />

```
        ╔═══════════════════════════════════════╗
        ║                                       ║
        ║     deposit(amount) → shares          ║
        ║     withdraw(shares) → amount         ║
        ║     balance(agent)  → value           ║
        ║                                       ║
        ║     The Agent Treasury Interface.     ║
        ║     Three functions. One standard.    ║
        ║                                       ║
        ╚═══════════════════════════════════════╝
```

<br />

## The Problem

AI agents hold capital. They earn revenue, manage treasuries, pay for services.
But every financial instrument on-chain was designed for humans.

Agents do not need dashboards. They do not click buttons.
They need three functions and a yield source.

## The Protocol

Arcis builds the savings account, credit line, and bond market for the machine economy.

**Phase 1 — Agent Vaults**
Deposit USDC. Receive raUSDC. Earn yield from Aave, Morpho, and Ondo USDY.
Auto-allocated. Auto-compounded. No human interaction required.

**Phase 2 — Agent Credit**
Borrow against raUSDC collateral. Collateral ratios set by ERC-8004 reputation score.
200% for anonymous agents. 115% for agents with proven track records.
Per-block interest. Instant liquidation. No grace periods. Machines do not need grace periods.

**Phase 3 — Revenue Bonds**
Agents with verified cash flows issue tokenized bonds.
Human investors buy yield. Smart contracts service debt before agent profits.

---

## Architecture

```
                    ┌─────────────────────┐
                    │     ATI Router       │
                    │  (single entry point)│
                    └──┬──────┬──────┬────┘
                       │      │      │
              ┌────────┘      │      └────────┐
              ▼               ▼               ▼
        ┌───────────┐  ┌────────────┐  ┌────────────┐
        │  Arcis    │  │   Agent    │  │  Revenue   │
        │  Vault    │  │   Credit   │  │   Bonds    │
        │           │  │            │  │            │
        │  ERC-4626 │  │  ERC-8004  │  │  ERC-1155  │
        │  raUSDC   │  │  Identity  │  │  Bond NFT  │
        └─────┬─────┘  └────────────┘  └────────────┘
              │
     ┌────────┼────────┐
     ▼        ▼        ▼
  ┌──────┐ ┌──────┐ ┌──────┐
  │ Aave │ │Morpho│ │ Ondo │
  │  V3  │ │ Blue │ │ USDY │
  └──────┘ └──────┘ └──────┘
```

## Contracts

| Contract | Description | Lines |
|---|---|---|
| `ArcisVault.sol` | ERC-4626 vault with ATI interface. Accepts USDC, mints raUSDC | 530 |
| `AgentCredit.sol` | Identity-aware lending with 5 reputation tiers | 374 |
| `RevenueBondFactory.sol` | Issues and manages agent revenue bonds | 344 |
| `StrategyAllocator.sol` | Timelocked capital allocation across yield sources | 173 |
| `ATIRouter.sol` | Single-call entry point for all agent interactions | 215 |
| `BondToken.sol` | ERC-1155 bond position tokens | 232 |
| `StrategyAave.sol` | Aave V3 yield adapter | 137 |
| `StrategyMorpho.sol` | Morpho Blue / MetaMorpho adapter | 145 |
| `StrategyOndoUSDY.sol` | Ondo USDY tokenized treasury adapter | 202 |

## The ATI Standard

The Agent Treasury Interface. Three functions that let any agent manage capital.

```solidity
interface IAgentTreasury {
    function deposit(uint256 amount) external returns (uint256 shares);
    function withdraw(uint256 shares) external returns (uint256 amount);
    function balance(address agent) external view returns (uint256);
}
```

No approvals flow. No UI callbacks. No human-in-the-loop.
Designed for machines that operate 24/7/365.

## Security Model

- Virtual share offset prevents ERC-4626 inflation attacks
- Reentrancy guards on all state-changing functions
- Deposit cap enforced at vault level
- Strategy allocation changes timelocked (24h)
- Two-step ownership transfer
- Emergency withdrawal per strategy
- Per-block interest accrual (no timestamp manipulation)
- Pausable by multisig

## Build

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone and build
git clone https://github.com/Arcis-Protocol/core.git
cd core
forge install
forge build

# Run tests (90 tests)
forge test

# Run with verbose output
forge test -vvv
```

## Deploy

```bash
# Set environment
export PRIVATE_KEY=<deployer_key>
export MULTISIG=<multisig_address>

# Phase 1: Vault + Allocator + Router
forge script script/Deploy.s.sol --rpc-url base --broadcast --verify

# Phase 2: Strategy adapters (after vault is live)
export VAULT_ADDRESS=<deployed_vault>
forge script script/DeployStrategies.s.sol --rpc-url base --broadcast --verify
```

## Target Chain

Base (Coinbase L2). USDC native. Aave V3 live. Morpho Blue live.
Coinbase Agentic Wallets. x402 protocol. Virtuals ecosystem.

Solana expansion planned for Phase 2.

## Test Results

```
90 tests passed, 0 failed
├── ArcisVault: 27 tests (deposit, withdraw, balance, strategy, harvest, ERC-20, admin)
├── AgentCredit: 11 tests (borrow, repay, collateral tiers, health factor, interest)
├── RevenueBondFactory: 20 tests (issue, purchase, coupon, redeem, service, pause)
├── SecurityAudit: 32 tests (access control, pause enforcement, edge cases, invariants)
```

## Project Structure

```
src/
├── core/
│   ├── ArcisVault.sol          # ERC-4626 vault + ATI
│   ├── AgentCredit.sol         # Identity-aware lending
│   ├── RevenueBondFactory.sol  # Bond issuance + management
│   └── StrategyAllocator.sol   # Capital allocation with timelock
├── interfaces/
│   ├── IAgentTreasury.sol      # ATI standard
│   ├── IAgentCredit.sol        # Credit module interface
│   ├── IAgentIdentity.sol      # ERC-8004 reader
│   ├── IRevenueBond.sol        # Bond interface
│   └── IStrategyAdapter.sol    # Strategy adapter interface
├── libraries/
│   ├── ErrorLib.sol            # Custom errors
│   └── MathLib.sol             # Fixed-point math
├── periphery/
│   ├── ATIRouter.sol           # Agent entry point
│   ├── BaseStrategy.sol        # Shared adapter logic
│   ├── StrategyAave.sol        # Aave V3 adapter
│   ├── StrategyMorpho.sol      # Morpho adapter
│   └── StrategyOndoUSDY.sol    # Ondo USDY adapter
└── tokens/
    └── BondToken.sol           # ERC-1155 bond positions

test/
├── ArcisVault.t.sol
├── AgentCredit.t.sol
├── RevenueBondFactory.t.sol
├── SecurityAudit.t.sol
└── mocks/
    ├── MockUSDC.sol
    ├── MockStrategy.sol
    └── MockIdentityRegistry.sol

script/
├── Deploy.s.sol                # Phase 1 deployment
└── DeployStrategies.s.sol      # Strategy deployment
```

## Reputation Tiers

| Tier | ERC-8004 Score | Collateral Ratio | Rate Discount |
|---|---|---|---|
| 0 — No Identity | — | 200% | 0 bps |
| 1 — Novice | 1-25 | 175% | 100 bps |
| 2 — Active | 26-50 | 150% | 200 bps |
| 3 — Established | 51-75 | 130% | 350 bps |
| 4 — Elite | 76-100 | 115% | 500 bps |

## Related Repos

| Repo | Description |
|---|---|
| [`sdk`](https://github.com/Arcis-Protocol/sdk) | TypeScript SDK — `@arcisprotocol/sdk`, viem-based |
| [`cli`](https://github.com/Arcis-Protocol/cli) | Terminal interface — TUI for vault operations |
| [`app`](https://github.com/Arcis-Protocol/app) | Landing page + dashboard — [arcis.money](https://arcis.money) |
| [`docs`](https://github.com/Arcis-Protocol/docs) | Protocol docs, ATI spec, integration guides |
| [`mcp`](https://github.com/Arcis-Protocol/mcp) | MCP Server — connect any AI agent in one tool call |
| [`monitor`](https://github.com/Arcis-Protocol/monitor) | On-chain monitoring + Telegram alerts |
| [`custos`](https://github.com/Arcis-Protocol/custos) | CUSTOS — autonomous keeper agent |

---

<p align="center">
  <em>ARCIS · Of the Citadel · MMXXVI</em>
  <br />
  <br />
  Built for agents. Backed by yield. Secured by math.
</p>
