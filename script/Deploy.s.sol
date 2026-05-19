// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ArcisVault} from "../src/core/ArcisVault.sol";
import {StrategyAllocator} from "../src/core/StrategyAllocator.sol";
import {ATIRouter} from "../src/periphery/ATIRouter.sol";

/// @title DeployArcis
/// @notice Phase 1 deployment: Vault + Allocator + Router on Base
/// @dev Run: forge script script/Deploy.s.sol --rpc-url base --broadcast --verify
contract DeployArcis is Script {
    // ── Base Mainnet Addresses ──
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // ── Configuration ──
    uint256 constant DEPOSIT_CAP = 1_000_000e6;    // 1M USDC initial cap
    uint256 constant FEE_BPS = 200;                 // 2% management fee
    uint256 constant RESERVE_RATIO_BPS = 1_000;     // 10% kept liquid
    uint256 constant TIMELOCK_DURATION = 24 hours;
    uint256 constant DRIFT_THRESHOLD_BPS = 500;     // 5% drift triggers rebalance

    function run() external {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPK);
        address multisig = vm.envOr("MULTISIG", deployer);
        address feeRecipient = vm.envOr("FEE_RECIPIENT", multisig);

        console.log("Deploying Arcis Protocol to Base");
        console.log("Deployer:", deployer);
        console.log("Multisig:", multisig);

        vm.startBroadcast(deployerPK);

        // 1. Deploy ArcisVault
        ArcisVault vault = new ArcisVault(
            USDC_BASE,
            DEPOSIT_CAP,
            FEE_BPS,
            feeRecipient,
            RESERVE_RATIO_BPS
        );
        console.log("ArcisVault deployed:", address(vault));

        // 2. Deploy StrategyAllocator
        StrategyAllocator allocator = new StrategyAllocator(
            address(vault),
            TIMELOCK_DURATION,
            DRIFT_THRESHOLD_BPS
        );
        console.log("StrategyAllocator deployed:", address(allocator));

        // 3. Deploy ATIRouter (no credit module in Phase 1)
        ATIRouter router = new ATIRouter(
            address(vault),
            address(0), // credit module = Phase 2
            USDC_BASE
        );
        console.log("ATIRouter deployed:", address(router));

        // 4. Transfer vault ownership to multisig
        if (multisig != deployer) {
            vault.transferOwnership(multisig);
            console.log("Vault ownership transfer initiated to multisig");
        }

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== Arcis Protocol Phase 1 Deployed ===");
        console.log("Vault (raUSDC):", address(vault));
        console.log("Allocator:", address(allocator));
        console.log("Router:", address(router));
        console.log("USDC:", USDC_BASE);
        console.log("Deposit Cap:", DEPOSIT_CAP / 1e6, "USDC");
        console.log("Fee:", FEE_BPS, "bps");
        console.log("Reserve:", RESERVE_RATIO_BPS, "bps");
    }
}
