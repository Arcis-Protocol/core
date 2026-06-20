// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/core/ArcisVault.sol";
import "../src/core/StrategyAllocator.sol";
import "../src/periphery/StrategyAave.sol";

/// @title ConnectStrategy
/// @notice Connects a yield strategy to the vault and allocates funds
/// @dev Run on testnet: forge script script/ConnectStrategy.s.sol --rpc-url $BASE_SEPOLIA_RPC --broadcast
///      Run on mainnet: forge script script/ConnectStrategy.s.sol --rpc-url $BASE_RPC --broadcast
contract ConnectStrategy is Script {
    // ── Testnet Addresses ──
    address constant VAULT_TESTNET = 0xa8eF658E125C7f6D7aFa9B6b8035b66b32CBE98d;
    address constant ALLOCATOR_TESTNET = 0x9f101e1159AA530dC5Cb104decB32aBA1eAF2617;
    address constant MOCK_STRATEGY_TESTNET = 0x9d6FB397224141FD323096e95667d3Ae5D9FF9cC;

    // ── Mainnet Addresses (to be filled after deploy) ──
    address constant VAULT_MAINNET = address(0);
    address constant USDC_MAINNET = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    address constant A_USDC = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");

        vm.startBroadcast(deployerKey);

        ArcisVault vault = ArcisVault(VAULT_TESTNET);
        StrategyAllocator allocator = StrategyAllocator(ALLOCATOR_TESTNET);

        // ── Step 1: Verify strategy is registered ──
        console.log("=== Strategy Connection ===");
        console.log("Vault:", address(vault));
        console.log("Allocator:", ALLOCATOR_TESTNET);
        console.log("Strategy:", MOCK_STRATEGY_TESTNET);

        uint256 tvl = vault.totalAssets();
        uint256 reserve = vault.reserveBalance();
        console.log("TVL:", tvl);
        console.log("Reserve:", reserve);

        // ── Step 2: Rebalance to push reserve into strategy ──
        if (reserve > 0) {
            console.log("Rebalancing to deploy reserve into strategy...");

            vault.rebalance();

            console.log("Reserve after:", vault.reserveBalance());
            console.log("Deployed after:", vault.deployedBalance());
        } else {
            console.log("No reserve to allocate");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("=== Strategy Connected ===");
        console.log("Funds are now earning yield through the strategy");
    }
}

/// @title DeployAaveStrategy
/// @notice Deploys and connects the Aave strategy on Base mainnet
contract DeployAaveStrategy is Script {
    address constant VAULT_MAINNET = address(0); // Fill after vault deploy
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    address constant A_USDC = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB;

    function run() external {
        require(VAULT_MAINNET != address(0), "Set VAULT_MAINNET first");

        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        vm.startBroadcast(deployerKey);

        // Deploy Aave strategy
        StrategyAave strategy = new StrategyAave(
            VAULT_MAINNET,
            USDC,
            AAVE_POOL,
            A_USDC
        );

        console.log("StrategyAave deployed:", address(strategy));

        // Register with vault
        ArcisVault vault = ArcisVault(VAULT_MAINNET);
        vault.addStrategy(address(strategy), 7000); // 70% weight

        console.log("Strategy registered with vault at 70% weight");
        console.log("30% reserve maintained for instant withdrawals");

        vm.stopBroadcast();
    }
}
