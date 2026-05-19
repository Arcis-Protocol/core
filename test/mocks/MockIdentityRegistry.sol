// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockIdentityRegistry
/// @notice Simulated ERC-8004 identity registry for testing
contract MockIdentityRegistry {
    mapping(address => uint256) public scores;
    mapping(address => bool) public registered;
    mapping(address => uint256) public txCounts;
    mapping(address => uint256) public registrationBlock;

    function register(address agent, uint256 score) external {
        scores[agent] = score;
        registered[agent] = true;
        registrationBlock[agent] = block.number;
    }

    function setScore(address agent, uint256 score) external {
        scores[agent] = score;
    }

    function getScore(address agent) external view returns (uint256) {
        return scores[agent];
    }

    function hasIdentity(address agent) external view returns (bool) {
        return registered[agent];
    }

    function transactionCount(address agent) external view returns (uint256) {
        return txCounts[agent];
    }

    function identityAge(address agent) external view returns (uint256) {
        if (!registered[agent]) return 0;
        return block.number - registrationBlock[agent];
    }

    function incrementTxCount(address agent) external {
        txCounts[agent]++;
    }
}
