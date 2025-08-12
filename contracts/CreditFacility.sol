// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./MagicInterfaces.sol";

/**
 * @title CreditFacility
 * @dev Bitcoin-backed credit card and spending management system
 */
contract CreditFacility is Ownable, ReentrancyGuard, Pausable {
    struct CreditCard {
        uint256 cardId;
        address holder;
        uint256 creditLimit;
        uint256 currentBalance;
        uint256 availableCredit;
        uint256 collateralAmount;
        uint256 lastPaymentDate;
        uint256 gracePeriod;
        bool isActive;
        bool isBlocked;
        PaymentSource primarySource;
        SpendingLimits limits;
    }

    struct SpendingLimits {
        uint256 dailyLimit;
        uint256 monthlyLimit;
        uint256 perTransactionLimit;
        uint256 dailySpent;
        uint256 monthlySpent;
        uint256 lastDayReset;
        uint256 lastMonthReset;
    }

    struct Transaction {
        uint256 transactionId;
        uint256 cardId;
        address merchant;
        uint256 amount;
        uint256 timestamp;
        TransactionType txType;
        PaymentSource source;
        string category;
        bool isReversed;
    }

    struct PaymentConfig {
        bool autoPayEnabled;
        uint256 autoPayAmount; // 0 = minimum, 1 = full balance
        uint256 gracePeriod;
        uint256 interestRate; // Only applies after grace period
    }

    enum PaymentSource {
        BTC_YIELD,      // Use BTC staking yield first
        CREDIT_LINE,    // Use credit line
        MANUAL_PAYMENT  // Manual payment required
    }

    enum TransactionType {
        PURCHASE,
        PAYMENT,
        INTEREST_CHARGE,
        FEE,
        REFUND
    }

    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant SECONDS_IN_DAY = 86400;
    uint256 public constant SECONDS_IN_MONTH = 30 days;
    uint256 public constant MIN_CREDIT_LIMIT = 100e6; // $100 minimum
    uint256 public constant MAX_CREDIT_LIMIT = 1000000e6; // $1M maximum
    uint256 public constant DEFAULT_GRACE_PERIOD = 30 days;

    // State variables
    IERC20 public immutable lstBTC;
    IPriceOracle public priceOracle;
    IMagicVault public magicVault;
    
    // Card management
    mapping(uint256 => CreditCard) public creditCards;
    mapping(address => uint256[]) public userCards;
    mapping(address => PaymentConfig) public paymentConfigs;
    uint256 public nextCardId = 1;
    
    // Transaction tracking
    mapping(uint256 => Transaction) public transactions;
    mapping(uint256 => uint256[]) public cardTransactions;
    uint256 public nextTransactionId = 1;
    
    // Payment processing
    mapping(address => uint256) public yieldBalances; // Available yield for spending
    address public paymentProcessor;
    address public feeRecipient;
    
    // Protocol parameters
    uint256 public protocolFeeRate = 50; // 0.5% transaction fee
    uint256 public interestRate = 1800; // 18% APR after grace period
    uint256 public liquidationThreshold = 8500; // 85% LTV for liquidation
    
    // Events
    event CardIssued(address indexed holder, uint256 cardId, uint256 creditLimit);
    event CardBlocked(uint256 cardId, bool blocked);
    event TransactionProcessed(uint256 cardId, uint256 transactionId, uint256 amount, PaymentSource source);
    event PaymentMade(uint256 cardId, uint256 amount, PaymentSource source);
    event CollateralAdded(uint256 cardId, uint256 amount);
    event CollateralRemoved(uint256 cardId, uint256 amount);
    event CreditLimitAdjusted(uint256 cardId, uint256 newLimit);
    event YieldDeposited(address indexed user, uint256 amount);

    modifier validCard(uint256 cardId) {
        require(cardId > 0 && cardId < nextCardId, "Invalid card ID");
        require(creditCards[cardId].isActive, "Card not active");
        _;
    }

    modifier cardOwner(uint256 cardId) {
        require(creditCards[cardId].holder == msg.sender, "Not card owner");
        _;
    }

    constructor(
        address _lstBTC,
        address _priceOracle,
        address _magicVault,
        address _paymentProcessor,
        address _feeRecipient,
        address _owner
    ) Ownable(_owner) {
        lstBTC = IERC20(_lstBTC);
        priceOracle = IPriceOracle(_priceOracle);
        magicVault = IMagicVault(_magicVault);
        paymentProcessor = _paymentProcessor;
        feeRecipient = _feeRecipient;
    }

    /**
     * @dev Issue a new credit card backed by lstBTC collateral
     */
    function issueCard(
        uint256 collateralAmount,
        uint256 requestedCreditLimit
    ) external nonReentrant whenNotPaused {
        require(collateralAmount > 0, "Invalid collateral amount");
        require(requestedCreditLimit >= MIN_CREDIT_LIMIT, "Credit limit too low");
        require(requestedCreditLimit <= MAX_CREDIT_LIMIT, "Credit limit too high");
        
        // Transfer collateral
        lstBTC.transferFrom(msg.sender, address(this), collateralAmount);
        
        // Calculate maximum allowable credit limit based on collateral
        uint256 collateralValue = _getCollateralValue(collateralAmount);
        uint256 maxCreditLimit = (collateralValue * 8000) / BASIS_POINTS; // 80% LTV
        
        require(requestedCreditLimit <= maxCreditLimit, "Insufficient collateral");
        
        uint256 cardId = nextCardId++;
        
        // Create credit card
        creditCards[cardId] = CreditCard({
            cardId: cardId,
            holder: msg.sender,
            creditLimit: requestedCreditLimit,
            currentBalance: 0,
            availableCredit: requestedCreditLimit,
            collateralAmount: collateralAmount,
            lastPaymentDate: block.timestamp,
            gracePeriod: DEFAULT_GRACE_PERIOD,
            isActive: true,
            isBlocked: false,
            primarySource: PaymentSource.BTC_YIELD,
            limits: SpendingLimits({
                dailyLimit: requestedCreditLimit / 10, // 10% of credit limit per day
                monthlyLimit: requestedCreditLimit,
                perTransactionLimit: requestedCreditLimit / 20, // 5% per transaction
                dailySpent: 0,
                monthlySpent: 0,
                lastDayReset: block.timestamp,
                lastMonthReset: block.timestamp
            })
        });
        
        userCards[msg.sender].push(cardId);
        
        // Set default payment configuration
        paymentConfigs[msg.sender] = PaymentConfig({
            autoPayEnabled: true,
            autoPayAmount: 1, // Full balance
            gracePeriod: DEFAULT_GRACE_PERIOD,
            interestRate: interestRate
        });
        
        emit CardIssued(msg.sender, cardId, requestedCreditLimit);
    }

    /**
     * @dev Process a purchase transaction
     */
    function processPurchase(
        uint256 cardId,
        uint256 amount,
        address merchant,
        string memory category
    ) external validCard(cardId) nonReentrant whenNotPaused {
        require(msg.sender == paymentProcessor, "Only payment processor");
        
        CreditCard storage card = creditCards[cardId];
        require(!card.isBlocked, "Card is blocked");
        
        // Check spending limits
        _updateSpendingLimits(cardId);
        _checkSpendingLimits(cardId, amount);
        
        // Determine payment source and process payment
        PaymentSource source = _determinePaymentSource(cardId, amount);
        bool success = _processPayment(cardId, amount, source);
        
        require(success, "Payment failed");
        
        // Record transaction
        uint256 transactionId = nextTransactionId++;
        transactions[transactionId] = Transaction({
            transactionId: transactionId,
            cardId: cardId,
            merchant: merchant,
            amount: amount,
            timestamp: block.timestamp,
            txType: TransactionType.PURCHASE,
            source: source,
            category: category,
            isReversed: false
        });
        
        cardTransactions[cardId].push(transactionId);
        
        // Update spending limits
        card.limits.dailySpent += amount;
        card.limits.monthlySpent += amount;
        
        emit TransactionProcessed(cardId, transactionId, amount, source);
    }

    /**
     * @dev Make a manual payment towards card balance
     */
    function makePayment(
        uint256 cardId,
        uint256 amount,
        address paymentToken
    ) external validCard(cardId) cardOwner(cardId) nonReentrant whenNotPaused {
        require(amount > 0, "Invalid amount");
        
        CreditCard storage card = creditCards[cardId];
        require(card.currentBalance > 0, "No balance to pay");
        
        // Transfer payment from user
        IERC20(paymentToken).transferFrom(msg.sender, address(this), amount);
        
        // Apply payment to balance
        uint256 paymentAmount = amount > card.currentBalance ? card.currentBalance : amount;
        card.currentBalance -= paymentAmount;
        card.availableCredit += paymentAmount;
        card.lastPaymentDate = block.timestamp;
        
        // Record payment transaction
        uint256 transactionId = nextTransactionId++;
        transactions[transactionId] = Transaction({
            transactionId: transactionId,
            cardId: cardId,
            merchant: msg.sender,
            amount: paymentAmount,
            timestamp: block.timestamp,
            txType: TransactionType.PAYMENT,
            source: PaymentSource.MANUAL_PAYMENT,
            category: "Payment",
            isReversed: false
        });
        
        cardTransactions[cardId].push(transactionId);
        
        emit PaymentMade(cardId, paymentAmount, PaymentSource.MANUAL_PAYMENT);
    }

    /**
     * @dev Deposit BTC yield for spending
     */
    function depositYield(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Invalid amount");
        
        // User should have claimed yield from MagicVault first
        // This function accepts USDT/USDC that represents converted BTC yield
        IERC20(address(0x1234)).transferFrom(msg.sender, address(this), amount); // Placeholder for stablecoin
        
        yieldBalances[msg.sender] += amount;
        
        emit YieldDeposited(msg.sender, amount);
    }

    /**
     * @dev Add collateral to increase credit limit
     */
    function addCollateral(uint256 cardId, uint256 amount) 
        external validCard(cardId) cardOwner(cardId) nonReentrant whenNotPaused 
    {
        require(amount > 0, "Invalid amount");
        
        lstBTC.transferFrom(msg.sender, address(this), amount);
        
        CreditCard storage card = creditCards[cardId];
        card.collateralAmount += amount;
        
        // Recalculate and update credit limit
        uint256 newCollateralValue = _getCollateralValue(card.collateralAmount);
        uint256 newMaxCreditLimit = (newCollateralValue * 8000) / BASIS_POINTS;
        
        if (newMaxCreditLimit > card.creditLimit) {
            uint256 additionalCredit = newMaxCreditLimit - card.creditLimit;
            card.creditLimit = newMaxCreditLimit;
            card.availableCredit += additionalCredit;
            
            emit CreditLimitAdjusted(cardId, newMaxCreditLimit);
        }
        
        emit CollateralAdded(cardId, amount);
    }

    /**
     * @dev Remove collateral (if health factor allows)
     */
    function removeCollateral(uint256 cardId, uint256 amount) 
        external validCard(cardId) cardOwner(cardId) nonReentrant whenNotPaused 
    {
        require(amount > 0, "Invalid amount");
        
        CreditCard storage card = creditCards[cardId];
        require(amount <= card.collateralAmount, "Insufficient collateral");
        
        // Check if removal would make position unhealthy
        uint256 newCollateralAmount = card.collateralAmount - amount;
        uint256 newCollateralValue = _getCollateralValue(newCollateralAmount);
        
        if (card.currentBalance > 0) {
            uint256 currentLTV = (card.currentBalance * BASIS_POINTS) / newCollateralValue;
            require(currentLTV <= 8000, "Would exceed safe LTV"); // Keep 80% max LTV
        }
        
        card.collateralAmount = newCollateralAmount;
        lstBTC.transfer(msg.sender, amount);
        
        emit CollateralRemoved(cardId, amount);
    }

    /**
     * @dev Block/unblock a credit card
     */
    function setCardBlocked(uint256 cardId, bool blocked) 
        external validCard(cardId) cardOwner(cardId) 
    {
        creditCards[cardId].isBlocked = blocked;
        emit CardBlocked(cardId, blocked);
    }

    /**
     * @dev Update spending limits for a card
     */
    function updateSpendingLimits(
        uint256 cardId,
        uint256 dailyLimit,
        uint256 monthlyLimit,
        uint256 perTransactionLimit
    ) external validCard(cardId) cardOwner(cardId) {
        CreditCard storage card = creditCards[cardId];
        
        require(dailyLimit <= card.creditLimit, "Daily limit too high");
        require(monthlyLimit <= card.creditLimit, "Monthly limit too high");
        require(perTransactionLimit <= card.creditLimit, "Transaction limit too high");
        
        card.limits.dailyLimit = dailyLimit;
        card.limits.monthlyLimit = monthlyLimit;
        card.limits.perTransactionLimit = perTransactionLimit;
    }

    /**
     * @dev Configure payment preferences
     */
    function configurePayments(
        bool autoPayEnabled,
        uint256 autoPayAmount,
        PaymentSource primarySource
    ) external {
        paymentConfigs[msg.sender] = PaymentConfig({
            autoPayEnabled: autoPayEnabled,
            autoPayAmount: autoPayAmount,
            gracePeriod: DEFAULT_GRACE_PERIOD,
            interestRate: interestRate
        });
        
        // Update primary source for all user cards
        uint256[] memory userCardIds = userCards[msg.sender];
        for (uint256 i = 0; i < userCardIds.length; i++) {
            creditCards[userCardIds[i]].primarySource = primarySource;
        }
    }

    // Internal functions
    function _determinePaymentSource(uint256 cardId, uint256 amount) internal view returns (PaymentSource) {
        CreditCard memory card = creditCards[cardId];
        
        if (card.primarySource == PaymentSource.BTC_YIELD) {
            if (yieldBalances[card.holder] >= amount) {
                return PaymentSource.BTC_YIELD;
            }
        }
        
        if (card.availableCredit >= amount) {
            return PaymentSource.CREDIT_LINE;
        }
        
        return PaymentSource.MANUAL_PAYMENT;
    }

    function _processPayment(uint256 cardId, uint256 amount, PaymentSource source) internal returns (bool) {
        CreditCard storage card = creditCards[cardId];
        
        if (source == PaymentSource.BTC_YIELD) {
            if (yieldBalances[card.holder] >= amount) {
                yieldBalances[card.holder] -= amount;
                return true;
            }
            return false;
        } else if (source == PaymentSource.CREDIT_LINE) {
            if (card.availableCredit >= amount) {
                card.currentBalance += amount;
                card.availableCredit -= amount;
                return true;
            }
            return false;
        }
        
        return false;
    }

    function _getCollateralValue(uint256 collateralAmount) internal view returns (uint256) {
        uint256 btcPrice = priceOracle.getPrice("BTC");
        return (collateralAmount * btcPrice) / 1e18;
    }

    function _checkSpendingLimits(uint256 cardId, uint256 amount) internal view {
        CreditCard memory card = creditCards[cardId];
        
        require(amount <= card.limits.perTransactionLimit, "Exceeds per-transaction limit");
        require(card.limits.dailySpent + amount <= card.limits.dailyLimit, "Exceeds daily limit");
        require(card.limits.monthlySpent + amount <= card.limits.monthlyLimit, "Exceeds monthly limit");
    }

    function _updateSpendingLimits(uint256 cardId) internal {
        CreditCard storage card = creditCards[cardId];
        
        // Reset daily spending if a day has passed
        if (block.timestamp >= card.limits.lastDayReset + SECONDS_IN_DAY) {
            card.limits.dailySpent = 0;
            card.limits.lastDayReset = block.timestamp;
        }
        
        // Reset monthly spending if a month has passed
        if (block.timestamp >= card.limits.lastMonthReset + SECONDS_IN_MONTH) {
            card.limits.monthlySpent = 0;
            card.limits.lastMonthReset = block.timestamp;
        }
    }

    // View functions
    function getCardDetails(uint256 cardId) external view returns (CreditCard memory) {
        return creditCards[cardId];
    }

    function getUserCards(address user) external view returns (uint256[] memory) {
        return userCards[user];
    }

    function getCardTransactions(uint256 cardId) external view returns (uint256[] memory) {
        return cardTransactions[cardId];
    }

    function getYieldBalance(address user) external view returns (uint256) {
        return yieldBalances[user];
    }

    function calculateHealthFactor(uint256 cardId) external view returns (uint256) {
        CreditCard memory card = creditCards[cardId];
        
        if (card.currentBalance == 0) {
            return type(uint256).max;
        }
        
        uint256 collateralValue = _getCollateralValue(card.collateralAmount);
        return (collateralValue * liquidationThreshold) / (card.currentBalance * BASIS_POINTS);
    }

    // Admin functions
    function setPriceOracle(address _priceOracle) external onlyOwner {
        priceOracle = IPriceOracle(_priceOracle);
    }

    function setPaymentProcessor(address _paymentProcessor) external onlyOwner {
        paymentProcessor = _paymentProcessor;
    }

    function setProtocolFeeRate(uint256 _feeRate) external onlyOwner {
        require(_feeRate <= 500, "Fee rate too high"); // Max 5%
        protocolFeeRate = _feeRate;
    }

    function setInterestRate(uint256 _interestRate) external onlyOwner {
        require(_interestRate <= 3600, "Interest rate too high"); // Max 36% APR
        interestRate = _interestRate;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Emergency functions
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }
}