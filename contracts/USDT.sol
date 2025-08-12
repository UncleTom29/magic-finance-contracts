// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./MagicInterfaces.sol";
/**
 * @title USDTToken
 * @dev USDT token implementation with price oracle integration for Magic Finance
 */
contract USDTToken is ERC20, ERC20Burnable, ERC20Pausable, Ownable, ReentrancyGuard {
    
    // Price Oracle integration
    IPriceOracle public priceOracle;
    string public constant PRICE_FEED_ID = "USDT";
    
    // Token configuration
    uint8 private _decimals = 6; // USDT typically uses 6 decimals
    uint256 public constant MAX_SUPPLY = 100_000_000_000 * 10**6; // 100 billion USDT
    
    // Minting controls
    mapping(address => bool) public minters;
    mapping(address => bool) public burners;
    uint256 public totalMinted;
    uint256 public totalBurned;
    
    // Lending pool integration
    mapping(address => uint256) public lendingPoolDeposits;
    mapping(address => uint256) public lendingPoolBorrows;
    mapping(address => bool) public authorizedLendingPools;
    
    // Interest bearing functionality
    struct LendingPosition {
        uint256 principalAmount;
        uint256 interestRate; // Annual rate in basis points
        uint256 lastAccrualTime;
        uint256 accruedInterest;
        bool isActive;
    }
    
    mapping(address => mapping(address => LendingPosition)) public lendingPositions; // user => pool => position
    mapping(address => uint256) public poolTotalDeposits;
    mapping(address => uint256) public poolTotalBorrows;
    
    // Yield settings
    uint256 public baseInterestRate = 500; // 5% base annual interest
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant SECONDS_PER_YEAR = 365 days;
    
    // Fee structure
    uint256 public transferFee = 0; // No transfer fee for stablecoin
    uint256 public lendingFee = 100; // 1% fee on lending interest
    address public feeRecipient;
    mapping(address => bool) public feeExempt;
    
    // Blacklist functionality (required for USDT compliance)
    mapping(address => bool) public blacklisted;
    
    // Events
    event PriceOracleUpdated(address indexed newOracle);
    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
    event BurnerAdded(address indexed burner);
    event BurnerRemoved(address indexed burner);
    event LendingPoolAuthorized(address indexed pool);
    event LendingPoolDeauthorized(address indexed pool);
    event TokensDeposited(address indexed user, address indexed pool, uint256 amount);
    event TokensWithdrawn(address indexed user, address indexed pool, uint256 amount);
    event InterestAccrued(address indexed user, address indexed pool, uint256 interest);
    event AddressBlacklisted(address indexed account);
    event AddressUnblacklisted(address indexed account);
    
    modifier onlyMinter() {
        require(minters[msg.sender] || msg.sender == owner(), "Not authorized to mint");
        _;
    }
    
    modifier onlyBurner() {
        require(burners[msg.sender] || msg.sender == owner(), "Not authorized to burn");
        _;
    }
    
    modifier onlyAuthorizedPool() {
        require(authorizedLendingPools[msg.sender], "Not authorized pool");
        _;
    }
    
    modifier notBlacklisted(address account) {
        require(!blacklisted[account], "Address is blacklisted");
        _;
    }
    
    constructor(
        address _priceOracle,
        address _feeRecipient,
        address _owner
    ) ERC20("Tether USD", "USDT") Ownable(_owner) {
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
     * @dev Get current USDT price from oracle (should be ~$1.00)
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
     * @dev Check if USDT is trading within peg range (0.99 - 1.01 USD)
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
     * @dev Deposit tokens to lending pool for yield generation
     */
    function depositToLendingPool(
        address pool,
        uint256 amount
    ) external nonReentrant notBlacklisted(msg.sender) {
        require(authorizedLendingPools[pool], "Pool not authorized");
        require(amount > 0, "Invalid amount");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        // Accrue any existing interest first
        _accrueInterest(msg.sender, pool);
        
        // Transfer tokens to this contract
        _transfer(msg.sender, address(this), amount);
        
        // Update lending position
        LendingPosition storage position = lendingPositions[msg.sender][pool];
        
        if (!position.isActive) {
            position.interestRate = baseInterestRate;
            position.lastAccrualTime = block.timestamp;
            position.isActive = true;
        }
        
        position.principalAmount += amount;
        lendingPoolDeposits[msg.sender] += amount;
        poolTotalDeposits[pool] += amount;
        
        emit TokensDeposited(msg.sender, pool, amount);
    }
    
    /**
     * @dev Withdraw tokens from lending pool
     */
    function withdrawFromLendingPool(
        address pool,
        uint256 amount
    ) external nonReentrant notBlacklisted(msg.sender) {
        require(authorizedLendingPools[pool], "Pool not authorized");
        require(amount > 0, "Invalid amount");
        
        LendingPosition storage position = lendingPositions[msg.sender][pool];
        require(position.isActive, "No active position");
        
        // Accrue interest first
        _accrueInterest(msg.sender, pool);
        
        uint256 totalAvailable = position.principalAmount + position.accruedInterest;
        require(amount <= totalAvailable, "Insufficient balance");
        
        // Update position
        if (amount <= position.accruedInterest) {
            position.accruedInterest -= amount;
        } else {
            uint256 principalWithdraw = amount - position.accruedInterest;
            position.accruedInterest = 0;
            position.principalAmount -= principalWithdraw;
            lendingPoolDeposits[msg.sender] -= principalWithdraw;
            poolTotalDeposits[pool] -= principalWithdraw;
        }
        
        if (position.principalAmount == 0 && position.accruedInterest == 0) {
            position.isActive = false;
        }
        
        // Transfer tokens back to user
        _transfer(address(this), msg.sender, amount);
        
        emit TokensWithdrawn(msg.sender, pool, amount);
    }
    
    /**
     * @dev Accrue interest for lending position
     */
    function _accrueInterest(address user, address pool) internal {
        LendingPosition storage position = lendingPositions[user][pool];
        
        if (!position.isActive || position.principalAmount == 0) return;
        
        uint256 timeElapsed = block.timestamp - position.lastAccrualTime;
        if (timeElapsed == 0) return;
        
        uint256 annualInterest = (position.principalAmount * position.interestRate) / BASIS_POINTS;
        uint256 interest = (annualInterest * timeElapsed) / SECONDS_PER_YEAR;
        
        if (interest > 0) {
            // Apply lending fee
            uint256 fee = (interest * lendingFee) / BASIS_POINTS;
            uint256 userInterest = interest - fee;
            
            position.accruedInterest += userInterest;
            position.lastAccrualTime = block.timestamp;
            
            // Mint interest (protocol mints new tokens for yield)
            if (totalMinted + interest <= MAX_SUPPLY) {
                _mint(address(this), userInterest);
                if (fee > 0) {
                    _mint(feeRecipient, fee);
                }
                totalMinted += interest;
            }
            
            emit InterestAccrued(user, pool, userInterest);
        }
    }
    
    /**
     * @dev Calculate current accrued interest (view function)
     */
    function calculateAccruedInterest(address user, address pool) external view returns (uint256) {
        LendingPosition memory position = lendingPositions[user][pool];
        
        if (!position.isActive || position.principalAmount == 0) return position.accruedInterest;
        
        uint256 timeElapsed = block.timestamp - position.lastAccrualTime;
        uint256 annualInterest = (position.principalAmount * position.interestRate) / BASIS_POINTS;
        uint256 newInterest = (annualInterest * timeElapsed) / SECONDS_PER_YEAR;
        
        // Apply lending fee
        uint256 fee = (newInterest * lendingFee) / BASIS_POINTS;
        uint256 userInterest = newInterest - fee;
        
        return position.accruedInterest + userInterest;
    }
    
    /**
     * @dev Get user's total balance including lending positions
     */
    function getTotalBalance(address user) external view returns (uint256) {
        uint256 walletBalance = balanceOf(user);
        uint256 lendingBalance = lendingPoolDeposits[user];
        
        // Add accrued interest from all pools
        uint256 totalInterest = 0;
        // Note: In a real implementation, you'd iterate through user's active positions
        // This is simplified for demonstration
        
        return walletBalance + lendingBalance + totalInterest;
    }
    
    /**
     * @dev Override transfer to include blacklist and fee logic
     */
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable) {
        require(!blacklisted[from], "Sender blacklisted");
        require(!blacklisted[to], "Recipient blacklisted");
        
        if (from != address(0) && to != address(0) && transferFee > 0) {
            // Apply transfer fee if not exempt
            if (!feeExempt[from] && !feeExempt[to]) {
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
    
    function authorizeLendingPool(address pool) external onlyOwner {
        authorizedLendingPools[pool] = true;
        emit LendingPoolAuthorized(pool);
    }
    
    function deauthorizeLendingPool(address pool) external onlyOwner {
        authorizedLendingPools[pool] = false;
        emit LendingPoolDeauthorized(pool);
    }
    
    function setBaseInterestRate(uint256 _baseInterestRate) external onlyOwner {
        require(_baseInterestRate <= 1000, "Rate too high"); // Max 10%
        baseInterestRate = _baseInterestRate;
    }
    
    function setLendingFee(uint256 _lendingFee) external onlyOwner {
        require(_lendingFee <= 1000, "Fee too high"); // Max 10%
        lendingFee = _lendingFee;
    }
    
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }
    
    function setFeeExempt(address account, bool exempt) external onlyOwner {
        feeExempt[account] = exempt;
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