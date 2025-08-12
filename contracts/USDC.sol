// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./MagicInterfaces.sol";
/**
 * @title USDCToken
 * @dev USDC token implementation with price oracle integration for Magic Finance
 */
contract USDCToken is ERC20, ERC20Burnable, ERC20Pausable, Ownable, ReentrancyGuard {
    
    // Price Oracle integration
    IPriceOracle public priceOracle;
    string public constant PRICE_FEED_ID = "USDC";
    
    // Token configuration
    uint8 private _decimals = 6; // USDC uses 6 decimals
    uint256 public constant MAX_SUPPLY = 100_000_000_000 * 10**6; // 100 billion USDC
    
    // Minting controls
    mapping(address => bool) public minters;
    mapping(address => bool) public burners;
    uint256 public totalMinted;
    uint256 public totalBurned;
    
    // Lending and savings functionality
    mapping(address => uint256) public savingsDeposits;
    mapping(address => uint256) public lastSavingsUpdate;
    mapping(address => bool) public authorizedSavingsVaults;
    
    // Credit facility integration
    struct CreditLine {
        uint256 creditLimit;
        uint256 usedCredit;
        uint256 collateralAmount;
        uint256 interestRate; // Annual rate in basis points
        uint256 lastAccrualTime;
        uint256 accruedInterest;
        bool isActive;
    }
    
    mapping(address => CreditLine) public creditLines;
    mapping(address => bool) public authorizedCreditFacilities;
    uint256 public totalCreditIssued;
    uint256 public totalCollateralLocked;
    
    // Yield settings
    uint256 public savingsRate = 300; // 3% annual savings rate
    uint256 public creditInterestRate = 800; // 8% annual credit interest
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant SECONDS_PER_YEAR = 365 days;
    
    // Fee structure
    uint256 public transferFee = 0; // No transfer fee for stablecoin
    uint256 public creditFee = 200; // 2% fee on credit interest
    address public feeRecipient;
    mapping(address => bool) public feeExempt;
    
    // Compliance features
    mapping(address => bool) public blacklisted;
    mapping(address => uint256) public dailyTransferLimits;
    mapping(address => uint256) public dailyTransferAmounts;
    mapping(address => uint256) public lastTransferReset;
    uint256 public defaultDailyLimit = 10000 * 10**6; // $10,000 default limit
    
    // Events
    event PriceOracleUpdated(address indexed newOracle);
    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
    event BurnerAdded(address indexed burner);
    event BurnerRemoved(address indexed burner);
    event SavingsDeposited(address indexed user, uint256 amount);
    event SavingsWithdrawn(address indexed user, uint256 amount);
    event SavingsInterestAccrued(address indexed user, uint256 interest);
    event CreditLineIssued(address indexed user, uint256 creditLimit, uint256 collateral);
    event CreditUsed(address indexed user, uint256 amount);
    event CreditRepaid(address indexed user, uint256 amount);
    event AddressBlacklisted(address indexed account);
    event AddressUnblacklisted(address indexed account);
    event DailyLimitExceeded(address indexed account, uint256 attempted, uint256 limit);
    
    modifier onlyMinter() {
        require(minters[msg.sender] || msg.sender == owner(), "Not authorized to mint");
        _;
    }
    
    modifier onlyBurner() {
        require(burners[msg.sender] || msg.sender == owner(), "Not authorized to burn");
        _;
    }
    
    modifier onlyAuthorizedVault() {
        require(authorizedSavingsVaults[msg.sender], "Not authorized vault");
        _;
    }
    
    modifier onlyAuthorizedCreditFacility() {
        require(authorizedCreditFacilities[msg.sender], "Not authorized credit facility");
        _;
    }
    
    modifier notBlacklisted(address account) {
        require(!blacklisted[account], "Address is blacklisted");
        _;
    }
    
    modifier checkTransferLimit(address from, uint256 amount) {
        if (!feeExempt[from] && dailyTransferLimits[from] > 0) {
            _checkDailyTransferLimit(from, amount);
        }
        _;
    }
    
    constructor(
        address _priceOracle,
        address _feeRecipient,
        address _owner
    ) ERC20("USD Coin", "USDC") Ownable(_owner) {
        priceOracle = IPriceOracle(_priceOracle);
        feeRecipient = _feeRecipient;
        
        // Owner is fee exempt
        feeExempt[_owner] = true;
        feeExempt[address(this)] = true;
        
        emit PriceOracleUpdated(_priceOracle);
    }
    
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    /**
     * @dev Get current USDC price from oracle (should be ~$1.00)
     */
    function getCurrentPrice() external view returns (uint256) {
        return priceOracle.getPrice(PRICE_FEED_ID);
    }
    
    /**
     * @dev Get detailed price data from oracle
     */
    function getPriceData() external view returns (
        uint256 price,
        uint256 timestamp,
        uint256 confidence,
        bool isStale
    ) {
        return priceOracle.getPriceData(PRICE_FEED_ID);
    }
    
    /**
     * @dev Check if USDC is trading within peg range (0.99 - 1.01 USD)
     */
    function isWithinPeg() external view returns (bool) {
        uint256 price = priceOracle.getPrice(PRICE_FEED_ID);
        // Price should be between $0.99 and $1.01 (considering 18 decimal precision)
        return price >= 0.99e18 && price <= 1.01e18;
    }
    
    /**
     * @dev Mint new tokens (only by authorized minters)
     */
    function mint(address to, uint256 amount) external onlyMinter notBlacklisted(to) {
        require(totalMinted + amount <= MAX_SUPPLY, "Exceeds max supply");
        
        _mint(to, amount);
        totalMinted += amount;
    }
    
    /**
     * @dev Burn tokens (only by authorized burners)
     */
    function burn(uint256 amount) public override onlyBurner {
        super.burn(amount);
        totalBurned += amount;
    }
    
    /**
     * @dev Burn tokens from account (only by authorized burners)
     */
    function burnFrom(address account, uint256 amount) public override onlyBurner notBlacklisted(account) {
        super.burnFrom(account, amount);
        totalBurned += amount;
    }
    
    /**
     * @dev Deposit tokens to savings for yield generation
     */
    function depositToSavings(uint256 amount) external nonReentrant notBlacklisted(msg.sender) {
        require(amount > 0, "Invalid amount");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        // Accrue any existing interest first
        _accrueSavingsInterest(msg.sender);
        
        // Transfer tokens to this contract
        _transfer(msg.sender, address(this), amount);
        
        // Update savings deposit
        savingsDeposits[msg.sender] += amount;
        lastSavingsUpdate[msg.sender] = block.timestamp;
        
        emit SavingsDeposited(msg.sender, amount);
    }
    
    /**
     * @dev Withdraw tokens from savings
     */
    function withdrawFromSavings(uint256 amount) external nonReentrant notBlacklisted(msg.sender) {
        require(amount > 0, "Invalid amount");
        
        // Accrue interest first
        _accrueSavingsInterest(msg.sender);
        
        require(savingsDeposits[msg.sender] >= amount, "Insufficient savings balance");
        
        // Update savings deposit
        savingsDeposits[msg.sender] -= amount;
        
        // Transfer tokens back to user
        _transfer(address(this), msg.sender, amount);
        
        emit SavingsWithdrawn(msg.sender, amount);
    }
    
    /**
     * @dev Accrue savings interest
     */
    function _accrueSavingsInterest(address user) internal {
        if (savingsDeposits[user] == 0) return;
        
        uint256 timeElapsed = block.timestamp - lastSavingsUpdate[user];
        if (timeElapsed == 0) return;
        
        uint256 annualInterest = (savingsDeposits[user] * savingsRate) / BASIS_POINTS;
        uint256 interest = (annualInterest * timeElapsed) / SECONDS_PER_YEAR;
        
        if (interest > 0) {
            savingsDeposits[user] += interest;
            lastSavingsUpdate[user] = block.timestamp;
            
            // Mint interest tokens
            if (totalMinted + interest <= MAX_SUPPLY) {
                _mint(address(this), interest);
                totalMinted += interest;
            }
            
            emit SavingsInterestAccrued(user, interest);
        }
    }
    
    /**
     * @dev Calculate current accrued savings interest (view function)
     */
    function calculateSavingsInterest(address user) external view returns (uint256) {
        if (savingsDeposits[user] == 0) return 0;
        
        uint256 timeElapsed = block.timestamp - lastSavingsUpdate[user];
        uint256 annualInterest = (savingsDeposits[user] * savingsRate) / BASIS_POINTS;
        uint256 interest = (annualInterest * timeElapsed) / SECONDS_PER_YEAR;
        
        return interest;
    }
    
    /**
     * @dev Issue credit line to user (only by authorized credit facilities)
     */
    function issueCreditLine(
        address user,
        uint256 creditLimit,
        uint256 collateralAmount,
        uint256 interestRate
    ) external onlyAuthorizedCreditFacility notBlacklisted(user) {
        require(creditLimit > 0, "Invalid credit limit");
        require(collateralAmount > 0, "Invalid collateral amount");
        require(!creditLines[user].isActive, "Credit line already exists");
        
        creditLines[user] = CreditLine({
            creditLimit: creditLimit,
            usedCredit: 0,
            collateralAmount: collateralAmount,
            interestRate: interestRate,
            lastAccrualTime: block.timestamp,
            accruedInterest: 0,
            isActive: true
        });
        
        totalCreditIssued += creditLimit;
        totalCollateralLocked += collateralAmount;
        
        emit CreditLineIssued(user, creditLimit, collateralAmount);
    }
    
    /**
     * @dev Use credit line (only by authorized credit facilities)
     */
    function useCredit(address user, uint256 amount) external onlyAuthorizedCreditFacility {
        require(creditLines[user].isActive, "No active credit line");
        
        CreditLine storage credit = creditLines[user];
        
        // Accrue interest first
        _accrueCreditInterest(user);
        
        require(credit.usedCredit + amount <= credit.creditLimit, "Exceeds credit limit");
        
        credit.usedCredit += amount;
        
        // Mint tokens to user
        _mint(user, amount);
        totalMinted += amount;
        
        emit CreditUsed(user, amount);
    }
    
    /**
     * @dev Repay credit (burns tokens)
     */
    function repayCredit(uint256 amount) external nonReentrant notBlacklisted(msg.sender) {
        require(creditLines[msg.sender].isActive, "No active credit line");
        require(amount > 0, "Invalid amount");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        CreditLine storage credit = creditLines[msg.sender];
        
        // Accrue interest first
        _accrueCreditInterest(msg.sender);
        
        uint256 totalDebt = credit.usedCredit + credit.accruedInterest;
        require(amount <= totalDebt, "Amount exceeds debt");
        
        // Burn tokens
        _burn(msg.sender, amount);
        totalBurned += amount;
        
        // Apply payment to interest first, then principal
        if (amount <= credit.accruedInterest) {
            credit.accruedInterest -= amount;
        } else {
            uint256 principalPayment = amount - credit.accruedInterest;
            credit.accruedInterest = 0;
            credit.usedCredit -= principalPayment;
        }
        
        emit CreditRepaid(msg.sender, amount);
    }
    
    /**
     * @dev Accrue credit interest
     */
    function _accrueCreditInterest(address user) internal {
        CreditLine storage credit = creditLines[user];
        
        if (!credit.isActive || credit.usedCredit == 0) return;
        
        uint256 timeElapsed = block.timestamp - credit.lastAccrualTime;
        if (timeElapsed == 0) return;
        
        uint256 annualInterest = (credit.usedCredit * credit.interestRate) / BASIS_POINTS;
        uint256 interest = (annualInterest * timeElapsed) / SECONDS_PER_YEAR;
        
        if (interest > 0) {
            credit.accruedInterest += interest;
            credit.lastAccrualTime = block.timestamp;
            
            // Protocol earns fee on credit interest
            uint256 fee = (interest * creditFee) / BASIS_POINTS;
            if (fee > 0 && totalMinted + fee <= MAX_SUPPLY) {
                _mint(feeRecipient, fee);
                totalMinted += fee;
            }
        }
    }
    
    /**
     * @dev Get user's total debt including accrued interest
     */
    function getTotalDebt(address user) external view returns (uint256) {
        CreditLine memory credit = creditLines[user];
        
        if (!credit.isActive || credit.usedCredit == 0) return credit.accruedInterest;
        
        uint256 timeElapsed = block.timestamp - credit.lastAccrualTime;
        uint256 annualInterest = (credit.usedCredit * credit.interestRate) / BASIS_POINTS;
        uint256 newInterest = (annualInterest * timeElapsed) / SECONDS_PER_YEAR;
        
        return credit.usedCredit + credit.accruedInterest + newInterest;
    }
    
    /**
     * @dev Check daily transfer limit
     */
    function _checkDailyTransferLimit(address from, uint256 amount) internal {
        // Reset daily amount if it's a new day
        if (block.timestamp >= lastTransferReset[from] + 1 days) {
            dailyTransferAmounts[from] = 0;
            lastTransferReset[from] = block.timestamp;
        }
        
        uint256 limit = dailyTransferLimits[from] > 0 ? dailyTransferLimits[from] : defaultDailyLimit;
        
        require(dailyTransferAmounts[from] + amount <= limit, "Daily transfer limit exceeded");
        
        dailyTransferAmounts[from] += amount;
        
        if (dailyTransferAmounts[from] + amount > limit) {
            emit DailyLimitExceeded(from, amount, limit);
        }
    }
    
    /**
     * @dev Override transfer to include blacklist, fee logic, and transfer limits
     */
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable) {
        require(!blacklisted[from], "Sender blacklisted");
        require(!blacklisted[to], "Recipient blacklisted");
        
        // Check transfer limits for regular transfers (not minting/burning)
        if (from != address(0) && to != address(0)) {
            if (!feeExempt[from] && dailyTransferLimits[from] > 0) {
                _checkDailyTransferLimit(from, value);
            }
            
            // Apply transfer fee if not exempt
            if (transferFee > 0 && !feeExempt[from] && !feeExempt[to]) {
                uint256 fee = (value * transferFee) / BASIS_POINTS;
                if (fee > 0) {
                    super._update(from, feeRecipient, fee);
                    value -= fee;
                }
            }
        }
        
        super._update(from, to, value);
    }
    
    // Admin functions
    function setPriceOracle(address _priceOracle) external onlyOwner {
        require(_priceOracle != address(0), "Invalid oracle address");
        priceOracle = IPriceOracle(_priceOracle);
        emit PriceOracleUpdated(_priceOracle);
    }
    
    function addMinter(address minter) external onlyOwner {
        minters[minter] = true;
        emit MinterAdded(minter);
    }
    
    function removeMinter(address minter) external onlyOwner {
        minters[minter] = false;
        emit MinterRemoved(minter);
    }
    
    function addBurner(address burner) external onlyOwner {
        burners[burner] = true;
        emit BurnerAdded(burner);
    }
    
    function removeBurner(address burner) external onlyOwner {
        burners[burner] = false;
        emit BurnerRemoved(burner);
    }
    
    function authorizeSavingsVault(address vault) external onlyOwner {
        authorizedSavingsVaults[vault] = true;
    }
    
    function deauthorizeSavingsVault(address vault) external onlyOwner {
        authorizedSavingsVaults[vault] = false;
    }
    
    function authorizeCreditFacility(address facility) external onlyOwner {
        authorizedCreditFacilities[facility] = true;
    }
    
    function deauthorizeCreditFacility(address facility) external onlyOwner {
        authorizedCreditFacilities[facility] = false;
    }
    
    function setSavingsRate(uint256 _savingsRate) external onlyOwner {
        require(_savingsRate <= 1000, "Rate too high"); // Max 10%
        savingsRate = _savingsRate;
    }
    
    function setCreditInterestRate(uint256 _creditInterestRate) external onlyOwner {
        require(_creditInterestRate <= 2000, "Rate too high"); // Max 20%
        creditInterestRate = _creditInterestRate;
    }
    
    function setCreditFee(uint256 _creditFee) external onlyOwner {
        require(_creditFee <= 1000, "Fee too high"); // Max 10%
        creditFee = _creditFee;
    }
    
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }
    
    function setFeeExempt(address account, bool exempt) external onlyOwner {
        feeExempt[account] = exempt;
    }
    
    function setDailyTransferLimit(address account, uint256 limit) external onlyOwner {
        dailyTransferLimits[account] = limit;
    }
    
    function setDefaultDailyLimit(uint256 limit) external onlyOwner {
        defaultDailyLimit = limit;
    }
    
    function blacklistAddress(address account) external onlyOwner {
        blacklisted[account] = true;
        emit AddressBlacklisted(account);
    }
    
    function unblacklistAddress(address account) external onlyOwner {
        blacklisted[account] = false;
        emit AddressUnblacklisted(account);
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
    
    function emergencyWithdrawETH() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
    
    /**
     * @dev Emergency function to seize funds from blacklisted address
     */
    function seizeFunds(address from, uint256 amount) external onlyOwner {
        require(blacklisted[from], "Address not blacklisted");
        require(balanceOf(from) >= amount, "Insufficient balance");
        
        _transfer(from, owner(), amount);
    }
}