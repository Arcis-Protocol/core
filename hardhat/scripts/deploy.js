const hre = require("hardhat");

// ── Base Mainnet ──
const USDC = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";

// ── Configuration ──
const DEPOSIT_CAP = 1_000_000n * 1_000_000n; // $1M USDC
const FEE_BPS = 200n;                         // 2%
const RESERVE_RATIO = 1_000n;                  // 10%
const TIMELOCK = 86400n;                       // 24 hours
const DRIFT_BPS = 500n;                        // 5%

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("");
  console.log("  ┌──────────────────────────────────────┐");
  console.log("  │                                      │");
  console.log("  │  ARCIS                               │");
  console.log("  │  Mainnet Deployment                  │");
  console.log("  │                                      │");
  console.log("  └──────────────────────────────────────┘");
  console.log("");
  console.log("  Deployer:", deployer.address);
  console.log("  Network: ", hre.network.name);
  console.log("  USDC:    ", USDC);
  console.log("");

  // ── 1. Deploy ArcisVault ──
  console.log("  [1/3] Deploying ArcisVault...");
  const Vault = await hre.ethers.getContractFactory("ArcisVault");
  const vault = await Vault.deploy(USDC, DEPOSIT_CAP, FEE_BPS, deployer.address, RESERVE_RATIO);
  await vault.waitForDeployment();
  const vaultAddr = await vault.getAddress();
  console.log("        ArcisVault:", vaultAddr);

  // ── 2. Deploy StrategyAllocator ──
  console.log("  [2/3] Deploying StrategyAllocator...");
  const Allocator = await hre.ethers.getContractFactory("StrategyAllocator");
  const allocator = await Allocator.deploy(vaultAddr, TIMELOCK, DRIFT_BPS);
  await allocator.waitForDeployment();
  const allocatorAddr = await allocator.getAddress();
  console.log("        StrategyAllocator:", allocatorAddr);

  // ── 3. Deploy ATIRouter ──
  console.log("  [3/3] Deploying ATIRouter...");
  const Router = await hre.ethers.getContractFactory("ATIRouter");
  const router = await Router.deploy(
    vaultAddr,
    "0x0000000000000000000000000000000000000000", // Credit = Phase 2
    USDC
  );
  await router.waitForDeployment();
  const routerAddr = await router.getAddress();
  console.log("        ATIRouter:", routerAddr);

  // ── Summary ──
  console.log("");
  console.log("  ═══════════════════════════════════════");
  console.log("  DEPLOYMENT COMPLETE");
  console.log("  ═══════════════════════════════════════");
  console.log("");
  console.log("  ArcisVault (raUSDC):", vaultAddr);
  console.log("  StrategyAllocator:  ", allocatorAddr);
  console.log("  ATIRouter:          ", routerAddr);
  console.log("  USDC:               ", USDC);
  console.log("  Owner:              ", deployer.address);
  console.log("  Deposit Cap:         $1,000,000");
  console.log("  Fee:                 2%");
  console.log("  Reserve:             10%");
  console.log("");
  console.log("  Save these addresses. Next steps:");
  console.log("  1. npm run strategy   — deploy Aave strategy + queue");
  console.log("  2. Wait 24 hours      — strategy timelock");
  console.log("  3. npm run execute    — activate strategy");
  console.log("  4. npm run seed       — first deposit");
  console.log("  5. npm run verify     — verify on Basescan");
  console.log("");

  // Save addresses to file
  const fs = require("fs");
  const addresses = {
    network: hre.network.name,
    chainId: hre.network.config.chainId,
    deployer: deployer.address,
    vault: vaultAddr,
    allocator: allocatorAddr,
    router: routerAddr,
    usdc: USDC,
    deployedAt: new Date().toISOString(),
  };
  fs.writeFileSync("deployed-addresses.json", JSON.stringify(addresses, null, 2));
  console.log("  Addresses saved to deployed-addresses.json");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
