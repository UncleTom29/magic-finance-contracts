// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./MagicInterfaces.sol";

/**
 * @title LstBTCToken
 * @dev Liquid Staked Bitcoin token with yield accrual and price oracle integration
 * Represents staked BTC that earns yield while remaining liquid
 */
contract LstBTCToken is ERC20, ERC20Burnable, ERC20Pausable, Ownable, ReentrancyGuard {
    using Math for uint256;
    
    // Core contracts
    IPriceOracle public priceOracle;
    IERC20 public immutable btcToken;
    
    // Authorized minters (MagicVault, etc.)
    mapping(address => bool) public authorizedMinters;
    
    // Yield tracking
    uint256 public totalYieldGenerated;
    uint256 public yieldRate = 520; // 5.2% APY in basis points
    uint256 public lastYieldUpdate;
    uint256 public accumulatedYieldPerShare; // Scaled by 1e18
    
    // User yield tracking
    mapping(address => uint256) public userYieldDebt;
    mapping(address => uint256) public pendingYield;
    
    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant SECONDS_IN_YEAR = 365 days;
    uint256 public constant YIELD_PRECISION = 1e18;
    
    // Exchange rate (lstBTC to BTC)
    uint256 public exchangeRate = 1e18; // 1:1 initially (18 decimals precision)
    
    // Events
    event YieldDistributed(uint256 totalYield, uint256 yieldPerShare);
    event YieldClaimed(address indexed user, uint256 amount);
    event YieldRateUpdated(uint256 newRate);
    event ExchangeRateUpdated(uint256 newRate);
    event AuthorizedMinterUpdated(address indexed minter, bool status);
    event PriceOracleUpdated(address indexed newOracle);

    modifier onlyAuthorizedMinter() {
        require(authorizedMinters[msg.sender], "Not authorized minter");
        _;
    }

    constructor(
        address _btcToken,
        address _priceOracle,
        address _owner
    ) ERC20("Liquid Staked Bitcoin", "lstBTC") Ownable(_owner) {
        btcToken = IERC20(_btcToken);
        priceOracle = IPriceOracle(_priceOracle);
        lastYieldUpdate = block.timestamp;
        
        // Add deployer as authorized minter initially
        authorizedMinters[_owner] = true;
        emit AuthorizedMinterUpdated(_owner, true);
    }

    /**
     * @dev Returns 18 decimals for lstBTC (different from BTC's 8 decimals for better precision)
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /**
     * @dev Mint lstBTC tokens (only authorized minters like MagicVault)
     * @param to Address to mint tokens to
     * @param amount Amount of lstBTC to mint (18 decimals)
     */
    function mint(address to, uint256 amount) external onlyAuthorizedMinter whenNotPaused {
        require(to != address(0), "Cannot mint to zero address");
        require(amount > 0, "Amount must be greater than zero");
        
        _updateYield();
        _updateUserYield(to);
        
        _mint(to, amount);
    }

    /**
     * @dev Burn lstBTC tokens (only authorized minters)
     * @param from Address to burn tokens from
     * @param amount Amount of lstBTC to burn (18 decimals)
     */
    function burnFrom(address from, uint256 amount) public override onlyAuthorizedMinter whenNotPaused {
        require(from != address(0), "Cannot burn from zero address");
        require(amount > 0, "Amount must be greater than zero");
        
        _updateYield();
        _updateUserYield(from);
        
        super.burnFrom(from, amount);
    }

    /**
     * @dev Convert BTC amount to lstBTC amount using current exchange rate
     * @param btcAmount Amount in BTC (8 decimals)
     * @return lstBTCAmount Amount in lstBTC (18 decimals)
     */
    function btcToLstBTC(uint256 btcAmount) public view returns (uint256 lstBTCAmount) {
        // Convert BTC (8 decimals) to 18 decimals, then apply exchange rate
        uint256 btcIn18Decimals = btcAmount * 1e10;
        return (btcIn18Decimals * 1e18) / exchangeRate;
    }

    /**
     * @dev Convert lstBTC amount to BTC amount using current exchange rate
     * @param lstBTCAmount Amount in lstBTC (18 decimals)
     * @return btcAmount Amount in BTC (8 decimals)
     */
    function lstBTCtoBTC(uint256 lstBTCAmount) public view returns (uint256 btcAmount) {
        // Apply exchange rate, then convert from 18 decimals to 8 decimals
        uint256 btcIn18Decimals = (lstBTCAmount * exchangeRate) / 1e18;
        return btcIn18Decimals / 1e10;
    }

    /**
     * @dev Get current BTC price from oracle
     * @return price BTC price in USD (18 decimals)
     */
    function getBTCPrice() external view returns (uint256 price) {
        return priceOracle.getPrice("BTC");
    }

    /**
     * @dev Calculate USD value of lstBTC amount
     * @param lstBTCAmount Amount in lstBTC (18 decimals)
     * @return usdValue USD value in 18 decimals
     */
    function calculateUSDValue(uint256 lstBTCAmount) external view returns (uint256 usdValue) {
        uint256 btcPrice = priceOracle.getPrice("BTC");
        uint256 btcAmount = lstBTCtoBTC(lstBTCAmount);
        // Convert BTC amount to 18 decimals, then multiply by price
        return (btcAmount * 1e10 * btcPrice) / 1e18;
    }

    /**
     * @dev Update yield for all users
     */
    function updateYield() external {
        _updateYield();
    }

    /**
     * @dev Claim pending yield for caller
     */
    function claimYield() external nonReentrant whenNotPaused {
        _updateYield();
        _updateUserYield(msg.sender);
        
        uint256 yield = pendingYield[msg.sender];
        require(yield > 0, "No yield to claim");
        
        pendingYield[msg.sender] = 0;
        
        // Convert yield to BTC and transfer
        // Note: In a real implementation, this would come from the yield-generating mechanism
        // For now, we'll emit an event and track the claim
        
        emit YieldClaimed(msg.sender, yield);
    }

    /**
     * @dev Get pending yield for a user
     * @param user User address
     * @return yield Pending yield amount
     */
    function getPendingYield(address user) external view returns (uint256 yield) {
        if (totalSupply() == 0) return pendingYield[user];
        
        uint256 newYieldPerShare = accumulatedYieldPerShare;
        uint256 timeElapsed = block.timestamp - lastYieldUpdate;
        
        if (timeElapsed > 0 && totalSupply() > 0) {
            uint256 totalYield = (totalSupply() * yieldRate * timeElapsed) / (BASIS_POINTS * SECONDS_IN_YEAR);
            newYieldPerShare += (totalYield * YIELD_PRECISION) / totalSupply();
        }
        
        uint256 accruedYield = (balanceOf(user) * newYieldPerShare) / YIELD_PRECISION;
        return pendingYield[user] + accruedYield - userYieldDebt[user];
    }

    /**
     * @dev Get total value locked in USD
     * @return totalValueUSD Total value in USD (18 decimals)
     */
    function getTotalValueUSD() external view returns (uint256 totalValueUSD) {
        if (totalSupply() == 0) return 0;
        
        uint256 btcPrice = priceOracle.getPrice("BTC");
        uint256 totalBTCValue = lstBTCtoBTC(totalSupply());
        
        return (totalBTCValue * 1e10 * btcPrice) / 1e18;
    }

    /**
     * @dev Get current exchange rate (lstBTC to BTC)
     * @return rate Exchange rate in 18 decimals
     */
    function getExchangeRate() external view returns (uint256 rate) {
        return exchangeRate;
    }

    /**
     * @dev Internal function to update global yield
     */
    function _updateYield() internal {
        if (totalSupply() == 0) {
            lastYieldUpdate = block.timestamp;
            return;
        }
        
        uint256 timeElapsed = block.timestamp - lastYieldUpdate;
        if (timeElapsed == 0) return;
        
        // Calculate total yield generated
        uint256 totalYield = (totalSupply() * yieldRate * timeElapsed) / (BASIS_POINTS * SECONDS_IN_YEAR);
        
        if (totalYield > 0) {
            // Update accumulated yield per share
            accumulatedYieldPerShare += (totalYield * YIELD_PRECISION) / totalSupply();
            totalYieldGenerated += totalYield;
            
            // Update exchange rate to reflect yield
            uint256 newExchangeRate = exchangeRate + (totalYield * 1e18) / totalSupply();
            exchangeRate = newExchangeRate;
            
            emit YieldDistributed(totalYield, accumulatedYieldPerShare);
            emit ExchangeRateUpdated(newExchangeRate);
        }
        
        lastYieldUpdate = block.timestamp;
    }

    /**
     * @dev Internal function to update user-specific yield
     */
    function _updateUserYield(address user) internal {
        if (balanceOf(user) == 0) {
            userYieldDebt[user] = 0;
            return;
        }
        
        uint256 accruedYield = (balanceOf(user) * accumulatedYieldPerShare) / YIELD_PRECISION;
        pendingYield[user] += accruedYield - userYieldDebt[user];
        userYieldDebt[user] = accruedYield;
    }

    /**
     * @dev Override transfer to update yield for both sender and receiver
     */
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable) {
        _updateYield();
        
        if (from != address(0)) {
            _updateUserYield(from);
        }
        if (to != address(0)) {
            _updateUserYield(to);
        }
        
        super._update(from, to, value);
        
        // Update yield debt after balance changes
        if (from != address(0)) {
            userYieldDebt[from] = (balanceOf(from) * accumulatedYieldPerShare) / YIELD_PRECISION;
        }
        if (to != address(0)) {
            userYieldDebt[to] = (balanceOf(to) * accumulatedYieldPerShare) / YIELD_PRECISION;
        }
    }

    // Admin functions
    
    /**
     * @dev Set authorized minter status
     */
    function setAuthorizedMinter(address minter, bool status) external onlyOwner {
        require(minter != address(0), "Invalid minter address");
        authorizedMinters[minter] = status;
        emit AuthorizedMinterUpdated(minter, status);
    }

    /**
     * @dev Update yield rate
     */
    function setYieldRate(uint256 _yieldRate) external onlyOwner {
        require(_yieldRate <= 5000, "Yield rate too high"); // Max 50% APY
        _updateYield();
        yieldRate = _yieldRate;
        emit YieldRateUpdated(_yieldRate);
    }

    /**
     * @dev Update price oracle
     */
    function setPriceOracle(address _priceOracle) external onlyOwner {
        require(_priceOracle != address(0), "Invalid oracle address");
        priceOracle = IPriceOracle(_priceOracle);
        emit PriceOracleUpdated(_priceOracle);
    }

    /**
     * @dev Manually update exchange rate (emergency only)
     */
    function setExchangeRate(uint256 _exchangeRate) external onlyOwner {
        require(_exchangeRate > 0, "Invalid exchange rate");
        exchangeRate = _exchangeRate;
        emit ExchangeRateUpdated(_exchangeRate);
    }

    /**
     * @dev Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Emergency withdrawal
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(token != address(this), "Cannot withdraw own tokens");
        IERC20(token).transfer(owner(), amount);
    }

    // View functions
    
    function isAuthorizedMinter(address minter) external view returns (bool) {
        return authorizedMinters[minter];
    }

    function getYieldInfo() external view returns (
        uint256 currentYieldRate,
        uint256 totalYield,
        uint256 lastUpdate,
        uint256 yieldPerShare
    ) {
        return (
            yieldRate,
            totalYieldGenerated,
            lastYieldUpdate,
            accumulatedYieldPerShare
        );
    }

    function getUserYieldInfo(address user) external view returns (
        uint256 balance,
        uint256 pending,
        uint256 debt,
        uint256 usdValue
    ) {
        balance = balanceOf(user);
        pending = this.getPendingYield(user);
        debt = userYieldDebt[user];
        usdValue = this.calculateUSDValue(balance);
    }
}