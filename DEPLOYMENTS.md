# Arcis Protocol — Deployments

## Base Mainnet (Chain ID: 8453)

| Contract | Address | Role |
|---|---|---|
| ArcisVault (raUSDC) | [`0x00325d9da832b38179ed2f0dabd4062d93e325a7`](https://basescan.org/address/0x00325d9da832b38179ed2f0dabd4062d93e325a7) | ERC-4626 yield vault |
| AgentCredit | [`0xdf31800e620f728297340d66acf5a306f07ce7a1`](https://basescan.org/address/0xdf31800e620f728297340d66acf5a306f07ce7a1) | Identity-aware lending |
| RevenueBondFactory | [`0xeb65d8bb08e0ea4a6bb9162d53d1b444f99681ba`](https://basescan.org/address/0xeb65d8bb08e0ea4a6bb9162d53d1b444f99681ba) | Bond issuance |
| IdentityRegistry | [`0xaa4da295dd368c0f10128654af76e3f002e20e71`](https://basescan.org/address/0xaa4da295dd368c0f10128654af76e3f002e20e71) | Agent reputation |
| ATIRouter | [`0xd0c64f997ca9aa427f8834578bd7f0313f868e83`](https://basescan.org/address/0xd0c64f997ca9aa427f8834578bd7f0313f868e83) | Single entry point |
| StrategyAave | [`0x43626D6162Ccb12328B989BB228DaD2941F2F12a`](https://basescan.org/address/0x43626D6162Ccb12328B989BB228DaD2941F2F12a) | Aave V3 USDC yield |
| StrategyAllocator | [`0x7Fd5d7b49694858FCf143E0039e83cDB0196DD7A`](https://basescan.org/address/0x7Fd5d7b49694858FCf143E0039e83cDB0196DD7A) | Timelocked weight mgmt |

**Owner:** `0x0FA8aa44683D68C760B3743fC872692c24344642` (hardware wallet)
**USDC:** `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`

### Yield Strategy

| Strategy | Protocol | Allocation | APY |
|---|---|---|---|
| Aave V3 USDC | Aave | 70% | ~3.2% |
| Reserve | — | 30% | 0% |

### Verified Operations (Mainnet)

- Seed deposit: $100 USDC from `0xbae3fd2d46520ee76d53bf09abf42eb7b9ec6944`
- Strategy queued and executed (24h timelock honored)
- raUSDC shares issued to depositor
- Balance query returns correct USDC value
- DeFiLlama TVL tracking active

### DeFiLlama

Listed: [defillama.com/protocol/arcis-protocol](https://defillama.com/protocol/arcis-protocol)
