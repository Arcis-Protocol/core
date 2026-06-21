# Arcis Subgraph

Indexed event queries for the Arcis Protocol on The Graph.

## Deploy

```bash
graph init --from-contract 0xa8eF658E125C7f6D7aFa9B6b8035b66b32CBE98d \
  --network base-sepolia --abi ./abis/ArcisVault.json

graph deploy arcis-protocol/arcis-subgraph \
  --studio --deploy-key YOUR_DEPLOY_KEY
```

## Entities

- `Deposit` / `Withdrawal` — every vault deposit/withdrawal with agent, amount, shares
- `Harvest` — yield harvested with fee breakdown
- `Loan` — full loan lifecycle (created → repaid/liquidated)
- `VaultSnapshot` — vault state at pause/unpause events
- `ProtocolStats` — cumulative counters (deposits, harvests, yield, fees)
