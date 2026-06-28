# Arcis Protocol — Core Contracts

Smart contracts powering financial infrastructure for autonomous AI agents. Live on Base mainnet.

## Contracts (7 deployed)

### Core

| Contract | Address | Description |
|---|---|---|
| ArcisVault | [`0x0032...25a7`](https://basescan.org/address/0x00325d9da832b38179ed2f0dabd4062d93e325a7) | ERC-4626 yield vault. USDC → raUSDC. Multi-strategy. |
| AgentCredit | [`0xdf31...e7a1`](https://basescan.org/address/0xdf31800e620f728297340d66acf5a306f07ce7a1) | Identity-aware credit. ERC-8004 tiers. Utilization rate oracle. |
| RevenueBondFactory | [`0xeb65...81ba`](https://basescan.org/address/0xeb65d8bb08e0ea4a6bb9162d53d1b444f99681ba) | Bond issuance, purchase, coupon, maturity. |
| IdentityRegistry | [`0xaa4d...0e71`](https://basescan.org/address/0xaa4da295dd368c0f10128654af76e3f002e20e71) | Agent reputation scores (0-100). Phase 1: owner-managed. |
| StrategyAllocator | [`0x7Fd5...D7A`](https://basescan.org/address/0x7Fd5d7b49694858FCf143E0039e83cDB0196DD7A) | Timelocked strategy weight management. |

### Periphery

| Contract | Address | Description |
|---|---|---|
| ATIRouter | [`0xeC3b...728F`](https://basescan.org/address/0xd0c64f997ca9aa427f8834578bd7f0313f868e83) | Single entry point: deposit, borrow, depositAndBorrow. |
| StrategyAave | [`0x4362...F12a`](https://basescan.org/address/0x43626D6162Ccb12328B989BB228DaD2941F2F12a) | Aave V3 USDC lending strategy. |

## Security

Emergency withdrawal (works when paused) · 24h strategy timelock · 0.1% early withdrawal fee · Per-agent deposit caps · Utilization-based rate oracle · ERC-4626 compatible · Zero `require()` · 116 tests

## ATI Standard

```
deposit(uint256 amount)  → uint256 shares
withdraw(uint256 shares) → uint256 amount
balance(address agent)   → uint256 value
```

## Related

[`sdk`](https://github.com/Arcis-Protocol/sdk) · [`mcp`](https://github.com/Arcis-Protocol/mcp) · [`custos`](https://github.com/Arcis-Protocol/custos) · [`app`](https://github.com/Arcis-Protocol/app) · [`docs`](https://github.com/Arcis-Protocol/docs)

---

*ARCIS · 7 contracts · Base Mainnet · MMXXVI*
