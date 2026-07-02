// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ArcisVaultFactory} from "../src/core/ArcisVaultFactory.sol";
import {ArcisAgentVault} from "../src/core/ArcisAgentVault.sol";

/// @title DeployVaultFactory — Base mainnet
/// @notice Deploys the ArcisVaultFactory and the first agent-token vault ($CUSTOS,
///         reserve-only). Run with the protocol owner key so factory + vault
///         ownership land on the owner wallet.
///
/// Usage:
///   forge script script/DeployVaultFactory.s.sol \
///     --rpc-url $BASE_RPC_URL --broadcast --verify -i 1
///
/// $CUSTOS vault parameters:
///   - reserve-only (reserveRatioBps = 10000): zero strategy risk; utility is
///     custody + future AgentCredit collateral
///   - feeBps = 0: no yield, no fee
///   - minDeposit = 1 CUSTOS; cap = 100M CUSTOS (10% of supply)
contract DeployVaultFactory is Script {
    address constant CUSTOS = 0xD7C479F720b0bC2FF1088A16D1c06C3e11C62882;
    address constant TREASURY = 0x0FA8aa44683D68C760B3743fC872692c24344642; // owner wallet

    function run() external {
        vm.startBroadcast();

        // 1. Factory (deployer becomes owner)
        ArcisVaultFactory factory = new ArcisVaultFactory();
        console.log("ArcisVaultFactory:", address(factory));

        // 2. First agent-token vault: $CUSTOS, reserve-only
        address custosVault = factory.createVault(
            CUSTOS,
            "Arcis CUSTOS",
            "raCUSTOS",
            1e18,          // min deposit: 1 CUSTOS
            100_000_000e18, // cap: 100M CUSTOS
            0,             // no fee (reserve-only, no yield)
            TREASURY,
            10_000         // 100% reserve — no strategies
        );
        console.log("CUSTOS Vault (raCUSTOS):", custosVault);
        console.log("Vault owner:", ArcisAgentVault(custosVault).owner());

        vm.stopBroadcast();
    }
}
