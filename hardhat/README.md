# Arcis Deploy (Hardhat)

Deploy Arcis Protocol to Base mainnet. No Foundry required — just Node.js.

## Setup

```bash
cd hardhat
npm install
cp .env.example .env
# Edit .env with your private key and Basescan API key
```

## Deploy (in order)

```bash
npm run deploy          # 1. Vault + Allocator + Router
npm run strategy        # 2. Aave strategy (queues 24h timelock)
# ... wait 24 hours ...
npm run execute         # 3. Activate strategy
npm run seed            # 4. First $500 deposit
npm run verify          # 5. Verify on Basescan
npm run status          # Check everything
```

Addresses are saved to `deployed-addresses.json` after each step.
