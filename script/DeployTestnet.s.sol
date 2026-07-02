// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ArcisVault} from "../src/core/ArcisVault.sol";
import {AgentCredit} from "../src/core/AgentCredit.sol";
import {StrategyAllocator} from "../src/core/StrategyAllocator.sol";
import {ATIRouter} from "../src/periphery/ATIRouter.sol";
import {MockUSDC} from "../test/mocks/MockUSDC.sol";
import {MockStrategy} from "../test/mocks/MockStrategy.sol";
import {MockIdentityRegistry} from "../test/mocks/MockIdentityRegistry.sol";

/// @title DeployTestnet
/// @notice Full testnet deployment on Base Sepolia with mock tokens
/// @dev Deploys mock USDC, vault, credit, strategy, router, and identity registry.
///      Mints test USDC to deployer and seeds the lending pool.
///
///      Run:
///      export PRIVATE_KEY=<key>
///      forge script script/DeployTestnet.s.sol \
///        --rpc-url https://sepolia.base.org \
///        --broadcast \
///        --slow
contract DeployTestnet is Script {
    // ── Config ──
    uint256 constant DEPOSIT_CAP = 10_000_000e6;     // 10M USDC testnet cap
    uint256 constant FEE_BPS = 200;                    // 2% management fee
    uint256 constant RESERVE_RATIO_BPS = 1_000;        // 10% liquid reserve
    uint256 constant TIMELOCK = 300;                    // 5 min timelock (testnet)
    uint256 constant DRIFT_THRESHOLD = 500;            // 5% drift
    uint256 constant BASE_RATE_BPS = 1_000;            // 10% base interest rate
    uint256 constant MINT_AMOUNT = 1_000_000e6;        // 1M USDC to deployer
    uint256 constant POOL_SEED = 500_000e6;            // 500K USDC to lending pool

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("=== Arcis Protocol - Base Sepolia Deployment ===");
        console.log("Deployer:", deployer);
        console.log("");

        vm.startBroadcast(pk);

        // ── 1. Mock USDC ──
        MockUSDC usdc = new MockUSDC();
        console.log("[1/8] MockUSDC:", address(usdc));

        // ── 2. Mock Identity Registry ──
        MockIdentityRegistry identity = new MockIdentityRegistry();
        console.log("[2/8] MockIdentityRegistry:", address(identity));

        // ── 3. ArcisVault ──
        ArcisVault vault = new ArcisVault(
            address(usdc),
            DEPOSIT_CAP,
            FEE_BPS,
            deployer,       // fee recipient = deployer on testnet
            RESERVE_RATIO_BPS
        );
        console.log("[3/8] ArcisVault (raUSDC):", address(vault));

        // ── 4. MockStrategy ──
        MockStrategy strategy = new MockStrategy(address(usdc), address(vault));
        console.log("[4/8] MockStrategy:", address(strategy));

        // Queue strategy with vault (90% allocation) — execute after 24h timelock
        vault.queueStrategy(address(strategy), 9_000);
        console.log("     Strategy queued: 90% allocation (executeStrategy after 24h)");

        // ── 5. StrategyAllocator ──
        StrategyAllocator allocator = new StrategyAllocator(
            address(vault),
            TIMELOCK,
            DRIFT_THRESHOLD
        );
        console.log("[5/8] StrategyAllocator:", address(allocator));

        // ── 6. AgentCredit ──
        AgentCredit credit = new AgentCredit(
            address(vault),
            address(usdc),
            address(identity),
            BASE_RATE_BPS
        );
        console.log("[6/8] AgentCredit:", address(credit));

        // ── 7. ATIRouter ──
        ATIRouter router = new ATIRouter(
            address(vault),
            address(credit),
            address(usdc)
        );
        console.log("[7/8] ATIRouter:", address(router));

        // ── 8. Seed testnet state ──
        // Mint USDC to deployer
        usdc.mint(deployer, MINT_AMOUNT);
        console.log("[8/8] Minted 1M USDC to deployer");

        // Seed lending pool
        usdc.approve(address(credit), POOL_SEED);
        credit.fundPool(POOL_SEED);
        console.log("     Funded lending pool with 500K USDC");

        // Register deployer identity with high score
        identity.register(deployer, 85);
        console.log("     Registered deployer identity (score: 85, Tier 4)");

        vm.stopBroadcast();

        // ── Summary ──
        console.log("");
        console.log("========================================");
        console.log("  ARCIS PROTOCOL - TESTNET DEPLOYED");
        console.log("  Chain: Base Sepolia (84532)");
        console.log("========================================");
        console.log("");
        console.log("  MockUSDC:          ", address(usdc));
        console.log("  IdentityRegistry:  ", address(identity));
        console.log("  ArcisVault:        ", address(vault));
        console.log("  MockStrategy:      ", address(strategy));
        console.log("  StrategyAllocator: ", address(allocator));
        console.log("  AgentCredit:       ", address(credit));
        console.log("  ATIRouter:         ", address(router));
        console.log("");
        console.log("  Deployer USDC:     ", MINT_AMOUNT / 1e6, "USDC");
        console.log("  Lending Pool:      ", POOL_SEED / 1e6, "USDC");
        console.log("  Deposit Cap:       ", DEPOSIT_CAP / 1e6, "USDC");
        console.log("========================================");
    }
}
