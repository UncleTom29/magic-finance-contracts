// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./MagicInterfaces.sol";

/**
 * @title LendingPool
 * @dev Overcollateralized lending protocol for borrowing stablecoins against lstBTC
 */
contract LendingPool is Ownable, ReentrancyGuard, Pausable {
    using Math for uint256;

    struct LoanPosition {
        uint256 collateralAmount;    // Amount of lstBTC collateral
        uint256 borrowedAmount;      // Amount of stablecoin borrowed
        uint256 interestRate;        // Interest rate at time of borrowing (in basis points)
        uint256 lastInterestAccrual; // Last time interest was accrued
        uint256 accruedInterest;     // Total accrued interest
        address borrower;            // Borrower address
        address asset;               // Borrowed asset address
        bool isActive;               // Whether the loan is active
        uint256 liquidationThreshold; // LTV threshold for liquidation
    }

    struct AssetConfig {
        bool isSupported;            // Whether asset is supported for borrowing
        uint256 baseInterestRate;    // Base interest rate (basis points)
        uint256 utilizationRate;     // Current utilization rate
        uint256 totalBorrowed;       // Total amount borrowed
        uint256 totalDeposited;      // Total amount deposited
        uint256 liquidationBonus;    // Liquidation bonus percentage
        uint256 maxLTV;              // Maximum loan-to-value ratio
    }

    struct UserData {
        uint256 totalCollateral;     // Total lstBTC collateral value
        uint256 totalBorrowed;       // Total borrowed amount across all assets
        uint256 healthFactor;        // Current health factor
        uint256[] activeLoanIds;     // Array of active loan IDs
    }

    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant SECONDS_IN_YEAR = 365 days;
    uint256 public constant LIQUIDATION_THRESHOLD = 8500; // 85% LTV
    uint256 public constant MAX_LTV = 8000; // 80% max LTV for new loans
    uint256 public constant MIN_HEALTH_FACTOR = 1.1e18; // 1.1 minimum health factor

    // State variables
    IERC20 public immutable lstBTC;
    IPriceOracle public priceOracle;
    
    // Supported stablecoins
    mapping(address => AssetConfig) public assetConfigs;
    address[] public supportedAssets;
    
    // Loan tracking
    mapping(uint256 => LoanPosition) public loans;
    mapping(address => UserData) public userData;
    mapping(address => uint256[]) public userLoans;
    uint256 public nextLoanId = 1;
    
    // Protocol parameters
    uint256 public protocolFeeRate = 100; // 1% protocol fee
    address public feeRecipient;
    address public liquidationBot;
    
    // Events
    event Deposited(address indexed asset, address indexed user, uint256 amount);
    event Borrowed(address indexed user, address indexed asset, uint256 amount, uint256 loanId);
    event Repaid(address indexed user, uint256 loanId, uint256 amount);
    event CollateralAdded(address indexed user, uint256 loanId, uint256 amount);
    event CollateralRemoved(address indexed user, uint256 loanId, uint256 amount);
    event Liquidated(address indexed borrower, uint256 loanId, address indexed liquidator, uint256 collateralSeized);
    event AssetConfigured(address indexed asset, uint256 baseRate, uint256 maxLTV);

    constructor(
        address _lstBTC,
        address _priceOracle,
        address _feeRecipient,
        address _liquidationBot,
        address _owner
    ) Ownable(_owner) {
        lstBTC = IERC20(_lstBTC);
        priceOracle = IPriceOracle(_priceOracle);
        feeRecipient = _feeRecipient;
        liquidationBot = _liquidationBot;
    }

    /**
     * @dev Configure a supported borrowable asset
     */
    function configureAsset(
        address asset,
        uint256 baseInterestRate,
        uint256 maxLTV,
        uint256 liquidationBonus
    ) external onlyOwner {
        require(asset != address(0), "Invalid asset address");
        require(maxLTV <= MAX_LTV, "LTV too high");
        require(baseInterestRate > 0, "Invalid interest rate");
        
        if (!assetConfigs[asset].isSupported) {
            supportedAssets.push(asset);
        }
        
        assetConfigs[asset] = AssetConfig({
            isSupported: true,
            baseInterestRate: baseInterestRate,
            utilizationRate: 0,
            totalBorrowed: 0,
            totalDeposited: 0,
            liquidationBonus: liquidationBonus,
            maxLTV: maxLTV
        });
        
        emit AssetConfigured(asset, baseInterestRate, maxLTV);
    }

    /**
     * @dev Deposit stablecoins to earn yield
     */
    function deposit(address asset, uint256 amount) external nonReentrant whenNotPaused {
        require(assetConfigs[asset].isSupported, "Asset not supported");
        require(amount > 0, "Invalid amount");
        
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        assetConfigs[asset].totalDeposited += amount;
        
        emit Deposited(asset, msg.sender, amount);
    }

    /**
     * @dev Borrow stablecoins against lstBTC collateral
     */
    function borrow(
        address asset,
        uint256 amount,
        uint256 collateralAmount
    ) external nonReentrant whenNotPaused {
        require(assetConfigs[asset].isSupported, "Asset not supported");
        require(amount > 0 && collateralAmount > 0, "Invalid amounts");
        
        // Transfer collateral from user
        lstBTC.transferFrom(msg.sender, address(this), collateralAmount);
        
        // Calculate LTV and validate
        uint256 collateralValue = _getCollateralValue(collateralAmount);
        uint256 ltv = (amount * BASIS_POINTS) / collateralValue;
        require(ltv <= assetConfigs[asset].maxLTV, "LTV too high");
        
        // Calculate interest rate based on utilization
        uint256 interestRate = _calculateInterestRate(asset);
        
        // Create loan position
        uint256 loanId = nextLoanId++;
        loans[loanId] = LoanPosition({
            collateralAmount: collateralAmount,
            borrowedAmount: amount,
            interestRate: interestRate,
            lastInterestAccrual: block.timestamp,
            accruedInterest: 0,
            borrower: msg.sender,
            asset: asset,
            isActive: true,
            liquidationThreshold: LIQUIDATION_THRESHOLD
        });
        
        // Update user data
        userLoans[msg.sender].push(loanId);
        userData[msg.sender].activeLoanIds.push(loanId);
        _updateUserData(msg.sender);
        
        // Update asset metrics
        assetConfigs[asset].totalBorrowed += amount;
        _updateUtilizationRate(asset);
        
        // Transfer borrowed amount to user
        IERC20(asset).transfer(msg.sender, amount);
        
        emit Borrowed(msg.sender, asset, amount, loanId);
    }

    /**
     * @dev Repay a loan
     */
    function repay(uint256 loanId, uint256 amount) external nonReentrant whenNotPaused {
        LoanPosition storage loan = loans[loanId];
        require(loan.isActive, "Loan not active");
        require(loan.borrower == msg.sender, "Not loan owner");
        
        // Accrue interest
        _accrueInterest(loanId);
        
        uint256 totalDebt = loan.borrowedAmount + loan.accruedInterest;
        require(amount <= totalDebt, "Amount exceeds debt");
        
        // Transfer repayment from user
        IERC20(loan.asset).transferFrom(msg.sender, address(this), amount);
        
        if (amount >= totalDebt) {
            // Full repayment - return all collateral
            uint256 collateralToReturn = loan.collateralAmount;
            loan.isActive = false;
            loan.borrowedAmount = 0;
            loan.accruedInterest = 0;
            loan.collateralAmount = 0;
            
            // Return collateral to borrower
            lstBTC.transfer(msg.sender, collateralToReturn);
            
            // Update asset metrics
            assetConfigs[loan.asset].totalBorrowed -= loan.borrowedAmount;
        } else {
            // Partial repayment
            if (amount >= loan.accruedInterest) {
                // Pay interest first, then principal
                uint256 principalPayment = amount - loan.accruedInterest;
                loan.accruedInterest = 0;
                loan.borrowedAmount -= principalPayment;
                assetConfigs[loan.asset].totalBorrowed -= principalPayment;
            } else {
                // Only paying interest
                loan.accruedInterest -= amount;
            }
        }
        
        _updateUtilizationRate(loan.asset);
        _updateUserData(msg.sender);
        
        emit Repaid(msg.sender, loanId, amount);
    }

    /**
     * @dev Add collateral to an existing loan
     */
    function addCollateral(uint256 loanId, uint256 amount) external nonReentrant whenNotPaused {
        LoanPosition storage loan = loans[loanId];
        require(loan.isActive, "Loan not active");
        require(loan.borrower == msg.sender, "Not loan owner");
        require(amount > 0, "Invalid amount");
        
        lstBTC.transferFrom(msg.sender, address(this), amount);
        loan.collateralAmount += amount;
        
        _updateUserData(msg.sender);
        
        emit CollateralAdded(msg.sender, loanId, amount);
    }

    /**
     * @dev Remove collateral from a loan (if health factor allows)
     */
    function removeCollateral(uint256 loanId, uint256 amount) external nonReentrant whenNotPaused {
        LoanPosition storage loan = loans[loanId];
        require(loan.isActive, "Loan not active");
        require(loan.borrower == msg.sender, "Not loan owner");
        require(amount > 0 && amount <= loan.collateralAmount, "Invalid amount");
        
        // Check if removal would make position unhealthy
        uint256 newCollateralAmount = loan.collateralAmount - amount;
        uint256 newCollateralValue = _getCollateralValue(newCollateralAmount);
        uint256 totalDebt = loan.borrowedAmount + loan.accruedInterest;
        
        require(
            (totalDebt * BASIS_POINTS) / newCollateralValue <= assetConfigs[loan.asset].maxLTV,
            "Would exceed max LTV"
        );
        
        loan.collateralAmount = newCollateralAmount;
        lstBTC.transfer(msg.sender, amount);
        
        _updateUserData(msg.sender);
        
        emit CollateralRemoved(msg.sender, loanId, amount);
    }

    /**
     * @dev Liquidate an unhealthy position
     */
    function liquidate(uint256 loanId, uint256 debtToCover) external nonReentrant whenNotPaused {
        LoanPosition storage loan = loans[loanId];
        require(loan.isActive, "Loan not active");
        
        // Accrue interest
        _accrueInterest(loanId);
        
        // Check if position is liquidatable
        require(_isLiquidatable(loanId), "Position healthy");
        
        uint256 totalDebt = loan.borrowedAmount + loan.accruedInterest;
        require(debtToCover <= totalDebt, "Debt to cover exceeds total debt");
        
        // Calculate collateral to seize
        uint256 collateralValue = _getCollateralValue(loan.collateralAmount);
        uint256 collateralToSeize = (debtToCover * collateralValue) / totalDebt;
        
        // Add liquidation bonus
        uint256 liquidationBonus = (collateralToSeize * assetConfigs[loan.asset].liquidationBonus) / BASIS_POINTS;
        collateralToSeize += liquidationBonus;
        
        // Ensure we don't seize more than available
        collateralToSeize = Math.min(collateralToSeize, loan.collateralAmount);
        
        // Transfer debt payment from liquidator
        IERC20(loan.asset).transferFrom(msg.sender, address(this), debtToCover);
        
        // Transfer collateral to liquidator
        lstBTC.transfer(msg.sender, collateralToSeize);
        
        // Update loan position
        if (debtToCover >= totalDebt) {
            // Full liquidation
            loan.isActive = false;
            loan.borrowedAmount = 0;
            loan.accruedInterest = 0;
            
            // Return remaining collateral to borrower
            uint256 remainingCollateral = loan.collateralAmount - collateralToSeize;
            if (remainingCollateral > 0) {
                lstBTC.transfer(loan.borrower, remainingCollateral);
            }
            loan.collateralAmount = 0;
        } else {
            // Partial liquidation
            loan.borrowedAmount = totalDebt - debtToCover;
            loan.accruedInterest = 0;
            loan.collateralAmount -= collateralToSeize;
        }
        
        // Update asset metrics
        assetConfigs[loan.asset].totalBorrowed -= debtToCover;
        _updateUtilizationRate(loan.asset);
        _updateUserData(loan.borrower);
        
        emit Liquidated(loan.borrower, loanId, msg.sender, collateralToSeize);
    }

    /**
     * @dev Calculate current interest rate for an asset based on utilization
     */
    function _calculateInterestRate(address asset) internal view returns (uint256) {
        AssetConfig memory config = assetConfigs[asset];
        
        if (config.totalDeposited == 0) {
            return config.baseInterestRate;
        }
        
        uint256 utilizationRate = (config.totalBorrowed * BASIS_POINTS) / config.totalDeposited;
        
        // Linear interest rate model: base rate + (utilization * multiplier)
        uint256 utilizationMultiplier = 200; // 2% additional per 100% utilization
        uint256 variableRate = (utilizationRate * utilizationMultiplier) / BASIS_POINTS;
        
        return config.baseInterestRate + variableRate;
    }

    /**
     * @dev Accrue interest for a loan
     */
    function _accrueInterest(uint256 loanId) internal {
        LoanPosition storage loan = loans[loanId];
        
        if (!loan.isActive || loan.borrowedAmount == 0) return;
        
        uint256 timeElapsed = block.timestamp - loan.lastInterestAccrual;
        if (timeElapsed > 0) {
            uint256 interestAccrued = (loan.borrowedAmount * loan.interestRate * timeElapsed) / 
                                    (BASIS_POINTS * SECONDS_IN_YEAR);
            loan.accruedInterest += interestAccrued;
            loan.lastInterestAccrual = block.timestamp;
        }
    }

    /**
     * @dev Get collateral value in USD
     */
    function _getCollateralValue(uint256 collateralAmount) internal view returns (uint256) {
        uint256 btcPrice = priceOracle.getPrice("BTC");
        return (collateralAmount * btcPrice) / 1e18;
    }

    /**
     * @dev Check if a position is liquidatable
     */
    function _isLiquidatable(uint256 loanId) internal view returns (bool) {
        LoanPosition memory loan = loans[loanId];
        
        if (!loan.isActive) return false;
        
        uint256 collateralValue = _getCollateralValue(loan.collateralAmount);
        uint256 totalDebt = loan.borrowedAmount + loan.accruedInterest;
        
        if (collateralValue == 0) return true;
        
        uint256 currentLTV = (totalDebt * BASIS_POINTS) / collateralValue;
        return currentLTV >= loan.liquidationThreshold;
    }

    /**
     * @dev Update utilization rate for an asset
     */
    function _updateUtilizationRate(address asset) internal {
        AssetConfig storage config = assetConfigs[asset];
        
        if (config.totalDeposited > 0) {
            config.utilizationRate = (config.totalBorrowed * BASIS_POINTS) / config.totalDeposited;
        } else {
            config.utilizationRate = 0;
        }
    }

    /**
     * @dev Update user data and health factor
     */
    function _updateUserData(address user) internal {
        UserData storage data = userData[user];
        
        uint256 totalCollateralValue = 0;
        uint256 totalBorrowedValue = 0;
        
        // Calculate totals across all user loans
        for (uint256 i = 0; i < userLoans[user].length; i++) {
            uint256 loanId = userLoans[user][i];
            LoanPosition memory loan = loans[loanId];
            
            if (loan.isActive) {
                totalCollateralValue += _getCollateralValue(loan.collateralAmount);
                totalBorrowedValue += loan.borrowedAmount + loan.accruedInterest;
            }
        }
        
        data.totalCollateral = totalCollateralValue;
        data.totalBorrowed = totalBorrowedValue;
        
        // Calculate health factor
        if (totalBorrowedValue > 0) {
            data.healthFactor = (totalCollateralValue * LIQUIDATION_THRESHOLD) / (totalBorrowedValue * BASIS_POINTS);
        } else {
            data.healthFactor = type(uint256).max;
        }
    }

    // View functions
    function getLoanDetails(uint256 loanId) external view returns (LoanPosition memory) {
        return loans[loanId];
    }

    function getUserLoans(address user) external view returns (uint256[] memory) {
        return userLoans[user];
    }

    function calculateHealthFactor(address user) external view returns (uint256) {
        return userData[user].healthFactor;
    }

    function isLiquidatable(uint256 loanId) external view returns (bool) {
        return _isLiquidatable(loanId);
    }

    function getCurrentInterestRate(address asset) external view returns (uint256) {
        return _calculateInterestRate(asset);
    }

    function getSupportedAssets() external view returns (address[] memory) {
        return supportedAssets;
    }

    // Admin functions
    function setPriceOracle(address _priceOracle) external onlyOwner {
        priceOracle = IPriceOracle(_priceOracle);
    }

    function setProtocolFeeRate(uint256 _feeRate) external onlyOwner {
        require(_feeRate <= 1000, "Fee rate too high"); // Max 10%
        protocolFeeRate = _feeRate;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }

    function setLiquidationBot(address _liquidationBot) external onlyOwner {
        liquidationBot = _liquidationBot;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Emergency function
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }
}