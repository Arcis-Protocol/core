# Arcis Protocol — Deployment Registry

## Base Sepolia Testnet (Chain ID: 84532)

Deployed: 2026-05-19
Verified: All 7 contracts verified on Blockscout

| Contract | Address | Verified |
|---|---|---|
| MockUSDC | [`0x29440A12f15fe6bDf5F624f4eeEB298CCb782f05`](https://base-sepolia.blockscout.com/address/0x29440A12f15fe6bDf5F624f4eeEB298CCb782f05) | ✓ |
| MockIdentityRegistry | [`0x79E79629DB86CFb8feF9594621882b065EBC80A7`](https://base-sepolia.blockscout.com/address/0x79E79629DB86CFb8feF9594621882b065EBC80A7) | ✓ |
| ArcisVault (raUSDC) | [`0xa8eF658E125C7f6D7aFa9B6b8035b66b32CBE98d`](https://base-sepolia.blockscout.com/address/0xa8eF658E125C7f6D7aFa9B6b8035b66b32CBE98d) | ✓ |
| MockStrategy | [`0x9d6FB397224141FD323096e95667d3Ae5D9FF9cC`](https://base-sepolia.blockscout.com/address/0x9d6FB397224141FD323096e95667d3Ae5D9FF9cC) | ✓ |
| StrategyAllocator | [`0x9f101e1159AA530dC5Cb104decB32aBA1eAF2617`](https://base-sepolia.blockscout.com/address/0x9f101e1159AA530dC5Cb104decB32aBA1eAF2617) | ✓ |
| AgentCredit | [`0x019540E33a0292a9DDE36bD9Ef11774d5A1Ce6FC`](https://base-sepolia.blockscout.com/address/0x019540E33a0292a9DDE36bD9Ef11774d5A1Ce6FC) | ✓ |
| ATIRouter | [`0x0281e7D37683c585325004F84e0b94170c78d5B4`](https://base-sepolia.blockscout.com/address/0x0281e7D37683c585325004F84e0b94170c78d5B4) | ✓ |

Deployer: `0xB390c9a4fB16389B6edd468f18AB2597bdf857db`
Total gas cost: ~0.00048 ETH

### Testnet E2E Verified Operations
- Deposit 10,000 USDC → 10,000 raUSDC shares
- Withdraw 5,000 shares → 5,000 USDC returned
- Borrow 1,000 USDC with 5,000 raUSDC collateral (Tier 4, 115%)
- Interest accrued over 13 blocks
- Repay loan with interest → collateral returned
- Lending pool restored

---

## Base Mainnet (Chain ID: 8453) — Pending

### External Protocol Addresses (Verified)

| Protocol | Contract | Address |
|---|---|---|
| Circle | USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| Aave V3 | Pool (L2Pool) | `0xA238Dd80C259a72e81d7e4664a9801593F98d1c5` |
| Aave V3 | aBasUSDC | `0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB` |
| Morpho | Blue Chip USDC Vault | `0x8A034f069D59d62a4643ad42E49b846d036468D7` |
| Ondo | USDY | Not on Base yet — Phase 2 |

### Pre-Deployment Checklist
- [ ] Create Safe multisig on Base for contract ownership
- [ ] Fund deployer wallet with ~0.05 ETH on Base mainnet
- [ ] Professional audit or peer review completed
- [ ] Update `script/DeployStrategies.s.sol` with Morpho vault address
- [ ] Deploy Phase 1: Vault + Allocator + Router
- [ ] Deploy Phase 2: Aave + Morpho strategy adapters
- [ ] Verify all contracts on BaseScan
- [ ] Transfer ownership to multisig
- [ ] Set initial deposit cap ($100K suggested for launch)
- [ ] Update SDK with mainnet addresses
- [ ] Update landing page with mainnet contract links
