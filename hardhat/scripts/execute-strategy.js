const hre = require("hardhat");
const fs = require("fs");

async function main() {
  const addresses = JSON.parse(fs.readFileSync("deployed-addresses.json"));
  const vault = await hre.ethers.getContractAt("ArcisVault", addresses.vault);

  console.log("");
  console.log("  Executing queued strategy...");

  const pending = await vault.pendingStrategy();
  if (pending.strategy === "0x0000000000000000000000000000000000000000") {
    console.log("  No strategy queued. Run 'npm run strategy' first.");
    return;
  }

  const now = Math.floor(Date.now() / 1000);
  if (now < Number(pending.executeAfter)) {
    const wait = Number(pending.executeAfter) - now;
    const hours = Math.floor(wait / 3600);
    const mins = Math.floor((wait % 3600) / 60);
    console.log(`  Timelock not expired. Wait ${hours}h ${mins}m.`);
    console.log("  Execute after:", new Date(Number(pending.executeAfter) * 1000).toLocaleString());
    return;
  }

  const tx = await vault.executeStrategy();
  await tx.wait();

  const count = await vault.strategyCount();
  console.log("  Strategy activated.");
  console.log("  Active strategies:", count.toString());
  console.log("");
  console.log("  Next: npm run seed");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
