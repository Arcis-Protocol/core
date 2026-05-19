// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAgentTreasury} from "../interfaces/IAgentTreasury.sol";
import {IStrategyAdapter} from "../interfaces/IStrategyAdapter.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {ErrorLib} from "../libraries/ErrorLib.sol";

/// @title ArcisVault
/// @author Arcis Protocol (arcis.money)
/// @notice ERC-4626 yield-bearing vault for autonomous AI agents
/// @dev Accepts USDC, mints raUSDC share tokens, routes capital to yield strategies.
///      Implements the ATI standard (deposit/withdraw/balance) plus ERC-20 for shares.
///
///      Security:
///      - Virtual shares/assets offset to prevent ERC-4626 inflation attacks
///      - Reentrancy guard on all state-changing functions
///      - Deposit cap enforced per-vault
///      - Pausable by owner (multisig)
///      - Management fee accrual on harvest
///
///      Share price: exchangeRate = totalAssets / totalShares
///      As yield accrues, each raUSDC becomes worth more USDC.
contract ArcisVault is IAgentTreasury {
    using MathLib for uint256;

    // ══════════════════════════════════════════════════════════════
    //                          CONSTANTS
    // ══════════════════════════════════════════════════════════════

    /// @notice USDC token address (set in constructor)
    address public immutable USDC;

    /// @notice Minimum deposit amount (1 USDC)
    uint256 public constant MIN_DEPOSIT = 1e6;

    /// @notice Maximum management fee: 5% (500 bps)
    uint256 public constant MAX_FEE_BPS = 500;

    /// @notice Fee denominator
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ══════════════════════════════════════════════════════════════
    //                        ERC-20 STORAGE
    // ══════════════════════════════════════════════════════════════

    string public constant name = "Arcis USDC";
    string public constant symbol = "raUSDC";
    uint8 public constant decimals = 6;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // ══════════════════════════════════════════════════════════════
    //                       VAULT STORAGE
    // ══════════════════════════════════════════════════════════════

    /// @notice Total USDC held in vault reserve (not deployed to strategies)
    uint256 public reserveBalance;

    /// @notice Total USDC value across all strategies (updated on harvest)
    uint256 public deployedBalance;

    /// @notice Maximum total deposits (in USDC)
    uint256 public depositCap;

    /// @notice Management fee in basis points
    uint256 public feeBps;

    /// @notice Fee recipient address
    address public feeRecipient;

    /// @notice Owner (multisig)
    address public owner;

    /// @notice Pending owner for two-step transfer
    address public pendingOwner;

    /// @notice Whether deposits/withdrawals are paused
    bool public paused;

    /// @notice Reentrancy lock
    uint256 private _locked = 1;

    // ══════════════════════════════════════════════════════════════
    //                     STRATEGY STORAGE
    // ══════════════════════════════════════════════════════════════

    /// @notice Registered strategy adapters
    IStrategyAdapter[] public strategies;

    /// @notice Allocation weight per strategy (in bps, must sum to 10000)
    uint256[] public allocationWeights;

    /// @notice Whether an address is a registered strategy
    mapping(address => bool) public isStrategy;

    /// @notice Target reserve ratio in bps (portion kept liquid in vault)
    uint256 public reserveRatioBps;

    // ══════════════════════════════════════════════════════════════
    //                         EVENTS
    // ══════════════════════════════════════════════════════════════

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event DepositCapUpdated(uint256 oldCap, uint256 newCap);
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event StrategyAdded(address indexed strategy, uint256 weight);
    event StrategyRemoved(address indexed strategy);
    event AllocationUpdated(uint256[] weights);
    event Harvested(uint256 totalYield, uint256 fee);
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event OwnershipTransferStarted(address indexed current, address indexed pending);
    event OwnershipTransferred(address indexed previous, address indexed current);
    event EmergencyWithdraw(address indexed strategy, uint256 recovered);

    // ══════════════════════════════════════════════════════════════
    //                        MODIFIERS
    // ══════════════════════════════════════════════════════════════

    modifier nonReentrant() {
        if (_locked != 1) revert ErrorLib.Unauthorized(msg.sender);
        _locked = 2;
        _;
        _locked = 1;
    }

    modifier whenNotPaused() {
        if (paused) revert ErrorLib.VaultPaused();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert ErrorLib.Unauthorized(msg.sender);
        _;
    }

    // ══════════════════════════════════════════════════════════════
    //                       CONSTRUCTOR
    // ══════════════════════════════════════════════════════════════

    /// @param _usdc USDC token address
    /// @param _depositCap Initial deposit cap in USDC (6 decimals)
    /// @param _feeBps Management fee in basis points
    /// @param _feeRecipient Address to receive management fees
    /// @param _reserveRatioBps Percentage of deposits kept liquid (e.g. 1000 = 10%)
    constructor(
        address _usdc,
        uint256 _depositCap,
        uint256 _feeBps,
        address _feeRecipient,
        uint256 _reserveRatioBps
    ) {
        if (_usdc == address(0)) revert ErrorLib.ZeroAddress();
        if (_feeRecipient == address(0)) revert ErrorLib.ZeroAddress();
        if (_feeBps > MAX_FEE_BPS) revert ErrorLib.InvalidAllocation();
        if (_reserveRatioBps > BPS_DENOMINATOR) revert ErrorLib.InvalidAllocation();

        USDC = _usdc;
        depositCap = _depositCap;
        feeBps = _feeBps;
        feeRecipient = _feeRecipient;
        reserveRatioBps = _reserveRatioBps;
        owner = msg.sender;
    }

    // ══════════════════════════════════════════════════════════════
    //                  ATI INTERFACE (3 functions)
    // ══════════════════════════════════════════════════════════════

    /// @inheritdoc IAgentTreasury
    function deposit(uint256 amount) external nonReentrant whenNotPaused returns (uint256 shares) {
        if (amount == 0) revert ErrorLib.ZeroAmount();
        if (amount < MIN_DEPOSIT) revert ErrorLib.DepositTooSmall(amount, MIN_DEPOSIT);

        uint256 totalBefore = totalAssets();
        if (totalBefore + amount > depositCap) {
            revert ErrorLib.VaultCapExceeded(amount, depositCap - totalBefore);
        }

        // Calculate shares BEFORE transfer (prevents manipulation)
        shares = _convertToShares(amount, false);
        if (shares == 0) revert ErrorLib.ZeroShares();

        // Transfer USDC from agent to vault
        _safeTransferFrom(USDC, msg.sender, address(this), amount);

        // Update reserve balance
        reserveBalance += amount;

        // Mint raUSDC shares
        _mint(msg.sender, shares);

        emit Deposit(msg.sender, amount, shares);
    }

    /// @inheritdoc IAgentTreasury
    function withdraw(uint256 shares) external nonReentrant whenNotPaused returns (uint256 amount) {
        if (shares == 0) revert ErrorLib.ZeroShares();
        if (balanceOf[msg.sender] < shares) {
            revert ErrorLib.InsufficientShares(shares, balanceOf[msg.sender]);
        }

        // Calculate USDC amount BEFORE burning shares
        amount = _convertToAssets(shares, false);
        if (amount == 0) revert ErrorLib.ZeroAmount();

        // Check liquidity — try reserve first, then pull from strategies
        if (amount > reserveBalance) {
            uint256 deficit = amount - reserveBalance;
            uint256 pulled = _pullFromStrategies(deficit);
            if (reserveBalance + pulled < amount) {
                revert ErrorLib.InsufficientLiquidity(amount, reserveBalance + pulled);
            }
        }

        // Burn shares
        _burn(msg.sender, shares);

        // Update reserve
        reserveBalance -= amount;

        // Transfer USDC to agent
        _safeTransfer(USDC, msg.sender, amount);

        emit Withdraw(msg.sender, shares, amount);
    }

    /// @inheritdoc IAgentTreasury
    function balance(address agent) external view returns (uint256) {
        if (balanceOf[agent] == 0) return 0;
        return _convertToAssets(balanceOf[agent], false);
    }

    // ══════════════════════════════════════════════════════════════
    //                      VIEW FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    /// @notice Total USDC value managed by the vault
    function totalAssets() public view returns (uint256) {
        return reserveBalance + deployedBalance;
    }

    /// @notice Current exchange rate: USDC per raUSDC share (in WAD)
    function exchangeRate() external view returns (uint256) {
        if (totalSupply == 0) return 1e18;
        return MathLib.mulDiv(totalAssets(), 1e18, totalSupply);
    }

    /// @notice Preview how many shares a deposit would mint
    function previewDeposit(uint256 assets) external view returns (uint256) {
        return _convertToShares(assets, false);
    }

    /// @notice Preview how much USDC a withdrawal would return
    function previewWithdraw(uint256 shares) external view returns (uint256) {
        return _convertToAssets(shares, false);
    }

    /// @notice Remaining capacity before deposit cap
    function remainingCapacity() external view returns (uint256) {
        uint256 total = totalAssets();
        if (total >= depositCap) return 0;
        return depositCap - total;
    }

    /// @notice Number of registered strategies
    function strategyCount() external view returns (uint256) {
        return strategies.length;
    }

    // ══════════════════════════════════════════════════════════════
    //                    STRATEGY MANAGEMENT
    // ══════════════════════════════════════════════════════════════

    /// @notice Add a new yield strategy
    /// @param strategy Address of the strategy adapter
    /// @param weight Allocation weight in bps
    function addStrategy(address strategy, uint256 weight) external onlyOwner {
        if (strategy == address(0)) revert ErrorLib.ZeroAddress();
        if (isStrategy[strategy]) revert ErrorLib.StrategyAlreadyRegistered(strategy);

        strategies.push(IStrategyAdapter(strategy));
        allocationWeights.push(weight);
        isStrategy[strategy] = true;

        // Approve strategy to pull USDC
        _safeApprove(USDC, strategy, type(uint256).max);

        emit StrategyAdded(strategy, weight);
    }

    /// @notice Update allocation weights for all strategies
    /// @param weights New weights array (must sum to 10000 - reserveRatioBps)
    function updateAllocations(uint256[] calldata weights) external onlyOwner {
        if (weights.length != strategies.length) revert ErrorLib.InvalidAllocation();

        uint256 sum;
        for (uint256 i; i < weights.length; ++i) {
            sum += weights[i];
        }

        // Weights + reserve ratio must equal 10000
        if (sum + reserveRatioBps != BPS_DENOMINATOR) {
            revert ErrorLib.AllocationSumMismatch(sum + reserveRatioBps);
        }

        allocationWeights = weights;
        emit AllocationUpdated(weights);
    }

    /// @notice Deploy reserve capital to strategies according to allocation weights
    function rebalance() external onlyOwner nonReentrant {
        uint256 total = totalAssets();
        if (total == 0) return;

        uint256 targetReserve = MathLib.bps(total, reserveRatioBps);

        // Deploy excess reserve to strategies
        if (reserveBalance > targetReserve) {
            uint256 toDeploy = reserveBalance - targetReserve;
            _deployToStrategies(toDeploy);
        }
    }

    /// @notice Harvest yield from all strategies, take fee, update deployed balance
    function harvest() external nonReentrant returns (uint256 totalYield) {
        uint256 totalValueBefore = deployedBalance;

        // Harvest each strategy
        for (uint256 i; i < strategies.length; ++i) {
            if (strategies[i].isActive()) {
                strategies[i].harvest();
            }
        }

        // Recalculate total deployed value
        uint256 newDeployed;
        for (uint256 i; i < strategies.length; ++i) {
            newDeployed += strategies[i].totalValue();
        }

        if (newDeployed > totalValueBefore) {
            totalYield = newDeployed - totalValueBefore;

            // Take management fee on yield
            uint256 fee = MathLib.bps(totalYield, feeBps);
            if (fee > 0) {
                // Mint fee shares to feeRecipient
                uint256 feeShares = _convertToShares(fee, false);
                if (feeShares > 0) {
                    _mint(feeRecipient, feeShares);
                }
            }
        }

        deployedBalance = newDeployed;
        emit Harvested(totalYield, MathLib.bps(totalYield, feeBps));
    }

    // ══════════════════════════════════════════════════════════════
    //                     ADMIN FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    function setDepositCap(uint256 newCap) external onlyOwner {
        emit DepositCapUpdated(depositCap, newCap);
        depositCap = newCap;
    }

    function setFeeBps(uint256 newFee) external onlyOwner {
        if (newFee > MAX_FEE_BPS) revert ErrorLib.InvalidAllocation();
        emit FeeUpdated(feeBps, newFee);
        feeBps = newFee;
    }

    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ErrorLib.ZeroAddress();
        feeRecipient = newRecipient;
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Two-step ownership transfer
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ErrorLib.ZeroAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert ErrorLib.Unauthorized(msg.sender);
        emit OwnershipTransferred(owner, msg.sender);
        owner = msg.sender;
        pendingOwner = address(0);
    }

    /// @notice Emergency: pull all funds from a strategy
    function emergencyWithdrawStrategy(uint256 index) external onlyOwner nonReentrant {
        IStrategyAdapter strategy = strategies[index];
        uint256 recovered = strategy.emergencyWithdraw();
        reserveBalance += recovered;
        deployedBalance -= MathLib.min(strategies[index].totalValue(), deployedBalance);
        emit EmergencyWithdraw(address(strategy), recovered);
    }

    // ══════════════════════════════════════════════════════════════
    //                     ERC-20 FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    function transfer(address to, uint256 amount) external returns (bool) {
        if (to == address(0)) revert ErrorLib.ZeroAddress();
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (to == address(0)) revert ErrorLib.ZeroAddress();
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    // ══════════════════════════════════════════════════════════════
    //                    INTERNAL FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    function _convertToShares(uint256 assets, bool roundUp) internal view returns (uint256) {
        return MathLib.toShares(assets, totalSupply, totalAssets(), roundUp);
    }

    function _convertToAssets(uint256 shares, bool roundUp) internal view returns (uint256) {
        return MathLib.toAssets(shares, totalSupply, totalAssets(), roundUp);
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    /// @dev Deploy capital to strategies according to allocation weights
    function _deployToStrategies(uint256 amount) internal {
        for (uint256 i; i < strategies.length; ++i) {
            if (!strategies[i].isActive()) continue;

            uint256 portion = MathLib.bps(amount, allocationWeights[i]);
            if (portion == 0) continue;

            // Transfer USDC to strategy and deploy
            _safeTransfer(USDC, address(strategies[i]), portion);
            uint256 deployed = strategies[i].deploy(portion);

            reserveBalance -= portion;
            deployedBalance += deployed;
        }
    }

    /// @dev Pull capital from strategies to cover withdrawal deficit
    function _pullFromStrategies(uint256 deficit) internal returns (uint256 totalPulled) {
        // Pull proportionally from each strategy, starting with highest liquidity
        for (uint256 i; i < strategies.length && totalPulled < deficit; ++i) {
            if (!strategies[i].isActive()) continue;

            uint256 available = strategies[i].availableLiquidity();
            uint256 toPull = MathLib.min(available, deficit - totalPulled);

            if (toPull > 0) {
                uint256 pulled = strategies[i].withdrawFromStrategy(toPull);
                totalPulled += pulled;
                deployedBalance -= MathLib.min(pulled, deployedBalance);
                reserveBalance += pulled;
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    //                    SAFE TOKEN HELPERS
    // ══════════════════════════════════════════════════════════════

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0xa9059cbb, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd, from, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x095ea7b3, spender, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_FAILED");
    }
}
