// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// src/interfaces/IAgentIdentity.sol

/// @title IAgentIdentity
/// @notice ERC-8004 compliant identity registry for AI agents
/// @dev Read-only interface. The registry itself is a separate deployment
///      that tracks agent reputation scores (0-100) based on on-chain history.
///      Arcis contracts use this to determine collateral ratios and bond eligibility.
interface IAgentIdentity {
    /// @notice Get the reputation score of an agent
    /// @param agent Address of the agent wallet
    /// @return score Reputation score from 0 to 100
    function getScore(address agent) external view returns (uint256 score);

    /// @notice Check if an agent has a registered identity
    /// @param agent Address of the agent wallet
    /// @return Whether the agent has any identity record
    function hasIdentity(address agent) external view returns (bool);

    /// @notice Get the total transaction count for an agent
    /// @param agent Address of the agent wallet
    /// @return count Number of on-chain transactions tracked
    function transactionCount(address agent) external view returns (uint256 count);

    /// @notice Get the age of the agent identity (blocks since registration)
    /// @param agent Address of the agent wallet
    /// @return age Number of blocks since identity was created
    function identityAge(address agent) external view returns (uint256 age);

    /// @notice Emitted when a new identity is registered
    event IdentityRegistered(address indexed agent, uint256 initialScore);

    /// @notice Emitted when a score is updated
    event ScoreUpdated(address indexed agent, uint256 oldScore, uint256 newScore);
}

// src/core/IdentityRegistry.sol

/// @title IdentityRegistry
/// @notice Owner-managed agent reputation registry (Phase 1)
/// @dev Phase 2 will add automated scoring based on on-chain history
contract IdentityRegistry is IAgentIdentity {
    address public owner;
    
    mapping(address => uint256) private _scores;
    mapping(address => bool) private _registered;
    mapping(address => uint256) private _txCounts;
    mapping(address => uint256) private _registeredBlock;

    error NotOwner();
    error AlreadyRegistered();
    error NotRegistered();
    error InvalidScore();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Register a new agent with an initial score
    function registerAgent(address agent, uint256 initialScore) external onlyOwner {
        if (_registered[agent]) revert AlreadyRegistered();
        if (initialScore > 100) revert InvalidScore();
        
        _registered[agent] = true;
        _scores[agent] = initialScore;
        _registeredBlock[agent] = block.number;
        
        emit IdentityRegistered(agent, initialScore);
    }

    /// @notice Update an agent's reputation score
    function setScore(address agent, uint256 newScore) external onlyOwner {
        if (!_registered[agent]) revert NotRegistered();
        if (newScore > 100) revert InvalidScore();
        
        uint256 oldScore = _scores[agent];
        _scores[agent] = newScore;
        
        emit ScoreUpdated(agent, oldScore, newScore);
    }

    /// @notice Increment transaction count (callable by owner or authorized contracts)
    function incrementTxCount(address agent) external onlyOwner {
        if (!_registered[agent]) revert NotRegistered();
        _txCounts[agent]++;
    }

    // ── IAgentIdentity Implementation ──

    function getScore(address agent) external view override returns (uint256) {
        return _scores[agent];
    }

    function hasIdentity(address agent) external view override returns (bool) {
        return _registered[agent];
    }

    function transactionCount(address agent) external view override returns (uint256) {
        return _txCounts[agent];
    }

    function identityAge(address agent) external view override returns (uint256) {
        if (!_registered[agent]) return 0;
        return block.number - _registeredBlock[agent];
    }

    /// @notice Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}

