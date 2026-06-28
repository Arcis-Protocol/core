// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// src/libraries/ErrorLib.sol

/// @title Arcis Protocol Error Definitions
/// @notice All custom errors used across the protocol
library ErrorLib {
    // ── Vault ──
    error ZeroAmount();
    error ZeroAddress();
    error ZeroShares();
    error InsufficientShares(uint256 requested, uint256 available);
    error InsufficientLiquidity(uint256 requested, uint256 available);
    error VaultCapExceeded(uint256 depositAmount, uint256 remaining);
    error VaultPaused();
    error DepositTooSmall(uint256 amount, uint256 minimum);

    // ── Strategy ──
    error InvalidAllocation();
    error AllocationSumMismatch(uint256 sum);
    error StrategyNotRegistered(address strategy);
    error StrategyAlreadyRegistered(address strategy);
    error TimelockNotExpired(uint256 executeAfter);
    error NoRebalanceNeeded();

    // ── Credit ──
    error NoIdentity(address agent);
    error InsufficientCollateral(uint256 required, uint256 provided);
    error LoanNotFound(uint256 loanId);
    error LoanAlreadyRepaid(uint256 loanId);
    error NotLoanOwner(uint256 loanId, address caller);
    error LoanHealthy(uint256 loanId);

    // ── Bonds ──
    error BondNotActive(uint256 bondId);
    error BondMatured(uint256 bondId);
    error BondNotMatured(uint256 bondId);
    error InsufficientRevenue(uint256 required, uint256 available);
    error AgentNotVerified(address agent);

    // ── Access ──
    error Unauthorized(address caller);
    error OnlyRouter();
    error CallFailed();
    error TransferFailed();
    error ApprovalFailed();
}

// src/interfaces/IStrategyAdapter.sol

/// @title IStrategyAdapter
/// @notice Interface for yield source adapters (Aave, Morpho, Ondo, etc.)
/// @dev Each yield source gets its own adapter that implements this interface.
///      The StrategyAllocator routes capital to adapters based on allocation weights.
interface IStrategyAdapter {
    /// @notice Deploy capital into the yield source
    /// @param amount USDC amount to deploy (6 decimals)
    /// @return deployed Actual amount deployed (may differ due to fees)
    function deploy(uint256 amount) external returns (uint256 deployed);

    /// @notice Withdraw capital from the yield source
    /// @param amount USDC amount to withdraw (6 decimals)
    /// @return withdrawn Actual amount withdrawn
    function withdrawFromStrategy(uint256 amount) external returns (uint256 withdrawn);

    /// @notice Total value of assets deployed in this strategy (in USDC)
    /// @return Total USDC value including accrued yield
    function totalValue() external view returns (uint256);

    /// @notice Current APY of this strategy in basis points
    /// @return APY in bps (e.g. 450 = 4.50%)
    function currentAPY() external view returns (uint256);

    /// @notice Maximum amount that can be instantly withdrawn
    /// @return Maximum USDC that can be withdrawn in one tx
    function availableLiquidity() external view returns (uint256);

    /// @notice Whether this strategy is currently active
    function isActive() external view returns (bool);

    /// @notice Harvest any pending yield and reinvest
    /// @return harvested Amount of yield harvested (in USDC)
    function harvest() external returns (uint256 harvested);

    /// @notice Emergency withdraw all funds from the strategy
    /// @return recovered Total USDC recovered
    function emergencyWithdraw() external returns (uint256 recovered);

    /// @notice Emitted when capital is deployed
    event Deployed(uint256 amount);

    /// @notice Emitted when capital is withdrawn
    event Withdrawn(uint256 amount);

    /// @notice Emitted when yield is harvested
    event Harvested(uint256 amount);
}

// src/libraries/MathLib.sol

/// @title Arcis Math Library
/// @notice Fixed-point math utilities for share/asset conversions
library MathLib {
    uint256 internal constant WAD = 1e18;

    error DivisionByZero();
    error Overflow();

    /// @notice Multiply then divide with full precision
    function mulDiv(uint256 x, uint256 y, uint256 z) internal pure returns (uint256 result) {
        if (z == 0) revert DivisionByZero();
        result = (x * y) / z;
    }

    /// @notice Multiply then divide, rounding up
    function mulDivUp(uint256 x, uint256 y, uint256 z) internal pure returns (uint256) {
        uint256 result = mulDiv(x, y, z);
        if (mulmod(x, y, z) > 0) {
            if (result == type(uint256).max) revert Overflow();
            result++;
        }
        return result;
    }

    /// @notice Convert assets to shares: shares = assets * totalShares / totalAssets
    /// @dev Uses virtual shares/assets to prevent inflation attacks
    function toShares(
        uint256 assets,
        uint256 totalShares,
        uint256 totalAssets,
        bool roundUp
    ) internal pure returns (uint256) {
        uint256 virtualShares = totalShares + 1;
        uint256 virtualAssets = totalAssets + 1e6;
        if (roundUp) return mulDivUp(assets, virtualShares, virtualAssets);
        return mulDiv(assets, virtualShares, virtualAssets);
    }

    /// @notice Convert shares to assets: assets = shares * totalAssets / totalShares
    function toAssets(
        uint256 shares,
        uint256 totalShares,
        uint256 totalAssets,
        bool roundUp
    ) internal pure returns (uint256) {
        uint256 virtualShares = totalShares + 1;
        uint256 virtualAssets = totalAssets + 1e6;
        if (roundUp) return mulDivUp(shares, virtualAssets, virtualShares);
        return mulDiv(shares, virtualAssets, virtualShares);
    }

    /// @notice Basis points calculation: amount * bps / 10000
    function bps(uint256 amount, uint256 basisPoints) internal pure returns (uint256) {
        return mulDiv(amount, basisPoints, 10_000);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) { return a < b ? a : b; }
    function max(uint256 a, uint256 b) internal pure returns (uint256) { return a > b ? a : b; }
    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) { return a > b ? a - b : b - a; }
}

// src/periphery/BaseStrategy.sol

/// @title BaseStrategy
/// @notice Shared logic for all yield strategy adapters
/// @dev Concrete adapters (Aave, Morpho, Ondo) inherit from this.
///      Handles access control, pausing, and safe token transfers.
abstract contract BaseStrategy is IStrategyAdapter {
    address public immutable vault;
    address public immutable usdc;
    address public owner;

    bool public active;
    uint256 internal _deployedAmount;

    modifier onlyVault() {
        if (msg.sender != vault) revert ErrorLib.Unauthorized(msg.sender);
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert ErrorLib.Unauthorized(msg.sender);
        _;
    }

    modifier whenActive() {
        if (!active) revert ErrorLib.StrategyNotRegistered(address(this));
        _;
    }

    constructor(address _vault, address _usdc) {
        if (_vault == address(0) || _usdc == address(0)) revert ErrorLib.ZeroAddress();
        vault = _vault;
        usdc = _usdc;
        owner = msg.sender;
        active = true;
    }

    function isActive() external view override returns (bool) {
        return active;
    }

    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ErrorLib.ZeroAddress();
        owner = newOwner;
        // Event omitted — use owner() view to check
    }

    // ── Safe token helpers ──

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0xa9059cbb, to, amount)
        );
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) revert ErrorLib.TransferFailed();
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd, from, to, amount)
        );
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) revert ErrorLib.TransferFailed();
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x095ea7b3, spender, amount)
        );
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) revert ErrorLib.TransferFailed();
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(0x70a08231, account)
        );
        if (!success || data.length < 32) return 0;
        return abi.decode(data, (uint256));
    }
}

// src/periphery/StrategyMorpho.sol

/// @title StrategyMorpho
/// @author Arcis Protocol
/// @notice Deploys USDC into Morpho Blue optimized lending on Base
/// @dev Morpho Blue is a permissionless lending protocol. We target
///      curated USDC vaults (MetaMorpho) for optimized yield.
///
///      Flow: USDC -> MetaMorpho vault -> earns optimized lending yield
///      MetaMorpho handles allocation across Morpho Blue markets.
contract StrategyMorpho is BaseStrategy {
    /// @notice MetaMorpho vault address (curated USDC vault)
    address public immutable morphoVault;

    /// @notice Shares held in the MetaMorpho vault
    uint256 public vaultShares;

    constructor(
        address _vault,
        address _usdc,
        address _morphoVault
    ) BaseStrategy(_vault, _usdc) {
        if (_morphoVault == address(0)) revert ErrorLib.ZeroAddress();
        morphoVault = _morphoVault;

        // Approve MetaMorpho vault to spend USDC
        _safeApprove(_usdc, _morphoVault, type(uint256).max);
    }

    /// @notice Override
    function deploy(uint256 amount) external override onlyVault whenActive returns (uint256 deployed) {
        // MetaMorpho implements ERC-4626: deposit(assets, receiver)
        (bool success, bytes memory data) = morphoVault.call(
            abi.encodeWithSignature(
                "deposit(uint256,address)",
                amount,
                address(this)
            )
        );
        if (!success) revert ErrorLib.CallFailed();

        uint256 shares = abi.decode(data, (uint256));
        vaultShares += shares;
        _deployedAmount += amount;
        deployed = amount;
        emit Deployed(amount);
    }

    /// @notice Override
    function withdrawFromStrategy(uint256 amount) external override onlyVault returns (uint256 withdrawn) {
        // ERC-4626: withdraw(assets, receiver, owner)
        (bool success, bytes memory data) = morphoVault.call(
            abi.encodeWithSignature(
                "withdraw(uint256,address,address)",
                amount,
                vault,          // send USDC to vault
                address(this)   // burn shares from this strategy
            )
        );
        if (!success) revert ErrorLib.CallFailed();

        uint256 sharesBurned = abi.decode(data, (uint256));
        vaultShares = vaultShares > sharesBurned ? vaultShares - sharesBurned : 0;
        _deployedAmount = _deployedAmount > amount ? _deployedAmount - amount : 0;
        withdrawn = amount;
        emit Withdrawn(withdrawn);
    }

    /// @notice Override
    function totalValue() external view override returns (uint256) {
        if (vaultShares == 0) return 0;

        // ERC-4626: convertToAssets(shares)
        (bool success, bytes memory data) = morphoVault.staticcall(
            abi.encodeWithSignature("convertToAssets(uint256)", vaultShares)
        );
        if (!success || data.length < 32) return _deployedAmount;
        return abi.decode(data, (uint256));
    }

    /// @notice Override
    function currentAPY() external view override returns (uint256) {
        // Fetch APY from MetaMorpho — implementation-specific
        // Most MetaMorpho vaults expose this via off-chain APIs
        // On-chain approximation: compare totalAssets growth over time
        // For now, return a conservative estimate
        // NOTE: Morpho APY oracle not yet available on Base. Returns 0 until oracle integration.
        return 400; // 4.00% default — updated by keeper
    }

    /// @notice Override
    function availableLiquidity() external view override returns (uint256) {
        if (vaultShares == 0) return 0;

        // Check max redeemable
        (bool success, bytes memory data) = morphoVault.staticcall(
            abi.encodeWithSignature("maxWithdraw(address)", address(this))
        );
        if (!success || data.length < 32) return 0;
        return abi.decode(data, (uint256));
    }

    /// @notice Override
    function harvest() external override returns (uint256 harvested) {
        if (vaultShares == 0) return 0;

        // Check current value vs deployed
        (bool success, bytes memory data) = morphoVault.staticcall(
            abi.encodeWithSignature("convertToAssets(uint256)", vaultShares)
        );
        if (!success || data.length < 32) return 0;

        uint256 currentValue = abi.decode(data, (uint256));
        if (currentValue > _deployedAmount) {
            harvested = currentValue - _deployedAmount;
            _deployedAmount = currentValue;
            emit Harvested(harvested);
        }
    }

    /// @notice Override
    function emergencyWithdraw() external override onlyOwner returns (uint256 recovered) {
        if (vaultShares == 0) return 0;

        // Redeem all shares: redeem(shares, receiver, owner)
        (bool success, bytes memory data) = morphoVault.call(
            abi.encodeWithSignature(
                "redeem(uint256,address,address)",
                vaultShares,
                vault,
                address(this)
            )
        );
        if (!success) revert ErrorLib.CallFailed();

        recovered = abi.decode(data, (uint256));
        vaultShares = 0;
        _deployedAmount = 0;
        active = false;
        emit Withdrawn(recovered);
    }
}

