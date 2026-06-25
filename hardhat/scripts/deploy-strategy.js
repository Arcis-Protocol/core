const hre = require("hardhat");
const fs = require("fs");

const USDC = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";
const AAVE_POOL = "0xA238Dd80C259a72e81d7e4664a9801593F98d1c5";
const AAVE_AUSDC = "0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB";

async function main() {
  const addresses = JSON.parse(fs.readFileSync("deployed-addresses.json"));
  const [deployer] = await hre.ethers.getSigners();

  console.log("");
  console.log("  Deploying Aave strategy...");
  console.log("  Vault:", addresses.vault);
  console.log("");

  // Deploy StrategyAave
  const Strategy = await hre.ethers.getContractFactory("StrategyAave");
  const strategy = await Strategy.deploy(addresses.vault, USDC, AAVE_POOL, AAVE_AUSDC);
  await strategy.waitForDeployment();
  const stratAddr = await strategy.getAddress();
  console.log("  StrategyAave deployed:", stratAddr);

  // Queue strategy with vault (24h timelock starts)
  const vault = await hre.ethers.getContractAt("ArcisVault", addresses.vault);
  const tx = await vault.queueStrategy(stratAddr, 7000); // 70% allocation
  await tx.wait();
  console.log("  Strategy queued with 70% allocation");

  // Read when it can be executed
  const pending = await vault.pendingStrategy();
  const executeAfter = new Date(Number(pending.executeAfter) * 1000);
  console.log("");
  console.log("  ═══════════════════════════════════════");
  console.log("  STRATEGY QUEUED — 24h TIMELOCK ACTIVE");
  console.log("  ═══════════════════════════════════════");
  console.log("");
  console.log("  Strategy:", stratAddr);
  console.log("  Weight:   70%");
  console.log("  Execute after:", executeAfter.toISOString());
  console.log("");
  console.log("  Run 'npm run execute' after:", executeAfter.toLocaleString());
  console.log("");

  // Save strategy address
  addresses.strategy = stratAddr;
  addresses.strategyQueuedAt = new Date().toISOString();
  addresses.strategyExecuteAfter = executeAfter.toISOString();
  fs.writeFileSync("deployed-addresses.json", JSON.stringify(addresses, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
