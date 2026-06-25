const hre = require("hardhat");
const fs = require("fs");

const DEPOSIT_AMOUNT = 500_000_000n; // $500 USDC

async function main() {
  const addresses = JSON.parse(fs.readFileSync("deployed-addresses.json"));
  const [deployer] = await hre.ethers.getSigners();

  const usdc = await hre.ethers.getContractAt("IERC20", addresses.usdc);
  const vault = await hre.ethers.getContractAt("ArcisVault", addresses.vault);

  console.log("");
  console.log("  Seeding first deposit: $500 USDC");
  console.log("  From:", deployer.address);

  // Check USDC balance
  const balance = await usdc.balanceOf(deployer.address);
  console.log("  USDC balance:", (Number(balance) / 1e6).toFixed(2));

  if (balance < DEPOSIT_AMOUNT) {
    console.log("  Insufficient USDC. Need $500.");
    return;
  }

  // Approve
  console.log("  [1/2] Approving USDC...");
  const approveTx = await usdc.approve(addresses.vault, DEPOSIT_AMOUNT);
  await approveTx.wait();

  // Deposit
  console.log("  [2/2] Depositing...");
  const depositTx = await vault.deposit(DEPOSIT_AMOUNT);
  await depositTx.wait();

  // Verify
  const tvl = await vault.totalAssets();
  const shares = await vault.balanceOf(deployer.address);
  const rate = await vault.exchangeRate();

  console.log("");
  console.log("  ═══════════════════════════════════════");
  console.log("  FIRST DEPOSIT CONFIRMED");
  console.log("  ═══════════════════════════════════════");
  console.log("");
  console.log("  TVL:          $" + (Number(tvl) / 1e6).toFixed(2));
  console.log("  Your shares:  " + (Number(shares) / 1e6).toFixed(2) + " raUSDC");
  console.log("  Rate:         " + (Number(rate) / 1e18).toFixed(6));
  console.log("");
  console.log("  The vault is live. Arcis is on mainnet.");
  console.log("");
}

main().catch((error) => { console.error(error); process.exit(1); });
