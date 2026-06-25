const hre = require("hardhat");
const fs = require("fs");

const USDC = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";

async function main() {
  const addresses = JSON.parse(fs.readFileSync("deployed-addresses.json"));

  console.log("");
  console.log("  Verifying contracts on Basescan...");
  console.log("");

  try {
    await hre.run("verify:verify", {
      address: addresses.vault,
      constructorArguments: [USDC, 1_000_000_000_000n, 200n, addresses.deployer, 1_000n],
    });
    console.log("  ArcisVault verified ✓");
  } catch (e) { console.log("  ArcisVault:", e.message.slice(0, 60)); }

  try {
    await hre.run("verify:verify", {
      address: addresses.allocator,
      constructorArguments: [addresses.vault, 86400n, 500n],
    });
    console.log("  StrategyAllocator verified ✓");
  } catch (e) { console.log("  StrategyAllocator:", e.message.slice(0, 60)); }

  try {
    await hre.run("verify:verify", {
      address: addresses.router,
      constructorArguments: [addresses.vault, "0x0000000000000000000000000000000000000000", USDC],
    });
    console.log("  ATIRouter verified ✓");
  } catch (e) { console.log("  ATIRouter:", e.message.slice(0, 60)); }

  if (addresses.strategy) {
    try {
      await hre.run("verify:verify", {
        address: addresses.strategy,
        constructorArguments: [addresses.vault, USDC, "0xA238Dd80C259a72e81d7e4664a9801593F98d1c5", "0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB"],
      });
      console.log("  StrategyAave verified ✓");
    } catch (e) { console.log("  StrategyAave:", e.message.slice(0, 60)); }
  }

  console.log("");
  console.log("  Done. Check basescan.org for verified status.");
  console.log("");
}

main().catch((error) => { console.error(error); process.exit(1); });
