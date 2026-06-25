const hre = require("hardhat");
const fs = require("fs");

async function main() {
  const addresses = JSON.parse(fs.readFileSync("deployed-addresses.json"));

  const vault = await hre.ethers.getContractAt("ArcisVault", addresses.vault);

  const tvl = await vault.totalAssets();
  const supply = await vault.totalSupply();
  const rate = await vault.exchangeRate();
  const cap = await vault.depositCap();
  const reserve = await vault.reserveBalance();
  const deployed = await vault.deployedBalance();
  const paused = await vault.paused();
  const strategies = await vault.strategyCount();

  console.log("");
  console.log("  ARCIS VAULT STATUS");
  console.log("  ──────────────────");
  console.log("");
  console.log("  Vault:       ", addresses.vault);
  console.log("  Status:      ", paused ? "PAUSED" : "ACTIVE");
  console.log("  TVL:          $" + (Number(tvl) / 1e6).toLocaleString());
  console.log("  Supply:       " + (Number(supply) / 1e6).toLocaleString() + " raUSDC");
  console.log("  Rate:         " + (Number(rate) / 1e18).toFixed(6));
  console.log("  Cap:          $" + (Number(cap) / 1e6).toLocaleString());
  console.log("  Reserve:      $" + (Number(reserve) / 1e6).toLocaleString());
  console.log("  Deployed:     $" + (Number(deployed) / 1e6).toLocaleString());
  console.log("  Strategies:  ", strategies.toString());
  console.log("");
}

main().catch((error) => { console.error(error); process.exit(1); });
