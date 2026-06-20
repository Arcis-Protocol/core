// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/core/RevenueBondFactory.sol";

/// @title DeployBonds
/// @notice Deploys RevenueBondFactory to Base Sepolia
/// @dev forge script script/DeployBonds.s.sol --rpc-url $BASE_SEPOLIA_RPC --broadcast --verify
contract DeployBonds is Script {
    address constant USDC_TESTNET = 0x29440A12f15fe6bDf5F624f4eeEB298CCb782f05;
    address constant IDENTITY_REGISTRY = 0x79E79629DB86CFb8feF9594621882b065EBC80A7;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        RevenueBondFactory bonds = new RevenueBondFactory(
            USDC_TESTNET,
            IDENTITY_REGISTRY,
            deployer,          // feeRecipient = deployer for now
            50,                // 0.5% origination fee
            50,                // minIssuerScore = 50
            7_776_000          // maxDuration = ~6 months at 2s blocks
        );

        console.log("RevenueBondFactory:", address(bonds));
        console.log("USDC:", USDC_TESTNET);
        console.log("Identity:", IDENTITY_REGISTRY);
        console.log("Origination Fee: 0.5%");
        console.log("Min Issuer Score: 50");
        console.log("Max Duration: 7,776,000 blocks (~6 months)");

        vm.stopBroadcast();
    }
}
