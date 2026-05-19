// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ArcisVault} from "../src/core/ArcisVault.sol";
import {StrategyAave} from "../src/periphery/StrategyAave.sol";
import {StrategyMorpho} from "../src/periphery/StrategyMorpho.sol";
import {StrategyOndoUSDY} from "../src/periphery/StrategyOndoUSDY.sol";

/// @title DeployStrategies
/// @notice Deploy yield strategy adapters and register them with the vault
/// @dev Run after Phase 1 deploy. Requires vault address in env.
///      forge script script/DeployStrategies.s.sol --rpc-url base --broadcast --verify
contract DeployStrategies is Script {
    // ── Base Mainnet Addresses ──
    // NOTE: Verify these addresses before mainnet deployment
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // Aave V3 Base (verify at https://docs.aave.com/developers/deployed-contracts/v3-mainnet)
    address constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    address constant AAVE_AUSDC = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB;

    // Morpho Blue MetaMorpho USDC vault on Base (verify at morpho.org)
    address constant MORPHO_VAULT = address(0); // TODO: set before deploy

    // Ondo USDY on Base (verify at ondo.finance)
    address constant ONDO_USDY = address(0);    // TODO: set before deploy
    address constant ONDO_ROUTER = address(0);  // TODO: set before deploy

    function run() external {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");

        ArcisVault vault = ArcisVault(vaultAddr);

        console.log("Deploying strategies for vault:", vaultAddr);

        vm.startBroadcast(deployerPK);

        // 1. Deploy Aave strategy
        StrategyAave aaveStrategy = new StrategyAave(
            vaultAddr,
            USDC_BASE,
            AAVE_POOL,
            AAVE_AUSDC
        );
        console.log("StrategyAave deployed:", address(aaveStrategy));

        // 2. Register Aave strategy with vault (45% allocation)
        vault.addStrategy(address(aaveStrategy), 4_500);
        console.log("Aave strategy registered: 45% allocation");

        // 3. Deploy Morpho strategy (if address set)
        if (MORPHO_VAULT != address(0)) {
            StrategyMorpho morphoStrategy = new StrategyMorpho(
                vaultAddr,
                USDC_BASE,
                MORPHO_VAULT
            );
            console.log("StrategyMorpho deployed:", address(morphoStrategy));

            vault.addStrategy(address(morphoStrategy), 3_000);
            console.log("Morpho strategy registered: 30% allocation");
        }

        // 4. Deploy Ondo strategy (if addresses set)
        if (ONDO_USDY != address(0) && ONDO_ROUTER != address(0)) {
            StrategyOndoUSDY ondoStrategy = new StrategyOndoUSDY(
                vaultAddr,
                USDC_BASE,
                ONDO_USDY,
                ONDO_ROUTER
            );
            console.log("StrategyOndoUSDY deployed:", address(ondoStrategy));

            vault.addStrategy(address(ondoStrategy), 1_500);
            console.log("Ondo strategy registered: 15% allocation");
        }

        vm.stopBroadcast();

        console.log("\n=== Strategies Deployed ===");
        console.log("Total strategies:", vault.strategyCount());
    }
}
