// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./MagicInterfaces.sol";

/**
 * @title BTCToken
 * @dev Wrapped Bitcoin token on Core DAO with price oracle integration
 * Represents 1:1 backed Bitcoin with 8 decimal places (same as native Bitcoin)
 */
contract BTCToken is ERC20, ERC20Burnable, ERC20Pausable, Ownable, ReentrancyGuard {
    
    // Price oracle for getting BTC/USD price
    IPriceOracle public priceOracle;
    
    // Bridge operators who can mint/burn tokens
    mapping(address => bool) public bridgeOperators;
    
    // Minting limits for security
    uint256 public dailyMintLimit = 100 * 1e8; // 100 BTC per day
    uint256 public dailyMinted;
    uint256 public lastMintDay;
    
    // Fee structure
    uint256 public transferFeeRate = 0; // 0% transfer fee initially
    uint256 public constant MAX_FEE_RATE = 50; // 0.5% maximum fee
    address public feeRecipient;
    
    // Total supply cap (21 million BTC)
    uint256 public constant MAX_SUPPLY = 21_000_000 * 1e8;
    
    // Events
    event BridgeOperatorUpdated(address indexed operator, bool status);
    event PriceOracleUpdated(address indexed newOracle);
    event DailyMintLimitUpdated(uint256 newLimit);
    event TransferFeeUpdated(uint256 newFeeRate);
    event FeeRecipientUpdated(address indexed newRecipient);
    event TokensMinted(address indexed to, uint256 amount, string txHash);
    event TokensBurned(address indexed from, uint256 amount, string btcAddress);

    modifier onlyBridgeOperator() {
        require(bridgeOperators[msg.sender], "Not a bridge operator");
        _;
    }

    modifier checkDailyLimit(uint256 amount) {
        uint256 currentDay = block.timestamp / 1 days;
        
        if (currentDay > lastMintDay) {
            dailyMinted = 0;
            lastMintDay = currentDay;
        }
        
        require(dailyMinted + amount <= dailyMintLimit, "Daily mint limit exceeded");
        dailyMinted += amount;
        _;
    }

    constructor(
        address _priceOracle,
        address _feeRecipient,
        address _owner
    ) ERC20("Wrapped Bitcoin", "BTC") Ownable(_owner) {
        priceOracle = IPriceOracle(_priceOracle);
        feeRecipient = _feeRecipient;
        lastMintDay = block.timestamp / 1 days;
        
        // Add deployer as initial bridge operator
        bridgeOperators[_owner] = true;
        emit BridgeOperatorUpdated(_owner, true);
    }

    /**
     * @dev Returns 8 decimals to match Bitcoin's precision
     */
    function decimals() public pure override returns (uint8) {
        return 8;
    }

    /**
     * @dev Mint tokens when Bitcoin is locked on Bitcoin network
     * @param to Address to mint tokens to
     * @param amount Amount of BTC tokens to mint (8 decimals)
     * @param btcTxHash Bitcoin transaction hash for reference
     */
    function mint(
        address to, 
        uint256 amount, 
        string memory btcTxHash
    ) external onlyBridgeOperator checkDailyLimit(amount) whenNotPaused nonReentrant {
        require(to != address(0), "Cannot mint to zero address");
        require(amount > 0, "Amount must be greater than zero");
        require(totalSupply() + amount <= MAX_SUPPLY, "Would exceed max supply");
        
        _mint(to, amount);
        
        emit TokensMinted(to, amount, btcTxHash);
    }

    /**
     * @dev Burn tokens to unlock Bitcoin on Bitcoin network
     * @param amount Amount of BTC tokens to burn
     * @param btcAddress Bitcoin address to send unlocked BTC to
     */
    function burnForBitcoin(
        uint256 amount, 
        string memory btcAddress
    ) external whenNotPaused nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(bytes(btcAddress).length > 0, "Bitcoin address required");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        _burn(msg.sender, amount);
        
        emit TokensBurned(msg.sender, amount, btcAddress);
    }

    /**
     * @dev Get current BTC price in USD from oracle
     * @return price BTC price in 18 decimals (USD)
     */
    function getCurrentPrice() external view returns (uint256 price) {
        return priceOracle.getPrice("BTC");
    }

    /**
     * @dev Get detailed price information
     * @return price BTC price in USD (18 decimals)
     * @return timestamp Last update timestamp
     * @return confidence Price confidence interval
     * @return isStale Whether the price is stale
     */
    function getPriceData() external view returns (
        uint256 price,
        uint256 timestamp,
        uint256 confidence,
        bool isStale
    ) {
        return priceOracle.getPriceData("BTC");
    }

    /**
     * @dev Calculate USD value of BTC amount
     * @param btcAmount Amount in BTC (8 decimals)
     * @return usdValue USD value in 18 decimals
     */
    function calculateUSDValue(uint256 btcAmount) external view returns (uint256 usdValue) {
        uint256 btcPrice = priceOracle.getPrice("BTC");
        // Convert BTC amount to 18 decimals, then multiply by price
        return (btcAmount * 1e10 * btcPrice) / 1e18;
    }

    /**
     * @dev Override transfer to include fee mechanism
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Pausable) {
        if (from != address(0) && to != address(0) && transferFeeRate > 0) {
            uint256 fee = (value * transferFeeRate) / 10000;
            if (fee > 0) {
                super._update(from, feeRecipient, fee);
                value = value - fee;
            }
        }
        
        super._update(from, to, value);
    }

    // Admin functions
    
    /**
     * @dev Add or remove bridge operator
     */
    function setBridgeOperator(address operator, bool status) external onlyOwner {
        require(operator != address(0), "Invalid operator address");
        bridgeOperators[operator] = status;
        emit BridgeOperatorUpdated(operator, status);
    }

    /**
     * @dev Update price oracle address
     */
    function setPriceOracle(address _priceOracle) external onlyOwner {
        require(_priceOracle != address(0), "Invalid oracle address");
        priceOracle = IPriceOracle(_priceOracle);
        emit PriceOracleUpdated(_priceOracle);
    }

    /**
     * @dev Update daily mint limit
     */
    function setDailyMintLimit(uint256 _dailyMintLimit) external onlyOwner {
        require(_dailyMintLimit > 0, "Limit must be greater than zero");
        dailyMintLimit = _dailyMintLimit;
        emit DailyMintLimitUpdated(_dailyMintLimit);
    }

    /**
     * @dev Update transfer fee rate
     */
    function setTransferFeeRate(uint256 _feeRate) external onlyOwner {
        require(_feeRate <= MAX_FEE_RATE, "Fee rate too high");
        transferFeeRate = _feeRate;
        emit TransferFeeUpdated(_feeRate);
    }

    /**
     * @dev Update fee recipient
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "Invalid recipient address");
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }

    /**
     * @dev Pause contract (emergency only)
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
     * @dev Emergency withdrawal of stuck tokens
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(token != address(this), "Cannot withdraw own tokens");
        IERC20(token).transfer(owner(), amount);
    }

    // View functions for bridge operators and limits
    
    function getRemainingDailyMintLimit() external view returns (uint256) {
        uint256 currentDay = block.timestamp / 1 days;
        
        if (currentDay > lastMintDay) {
            return dailyMintLimit;
        }
        
        return dailyMintLimit - dailyMinted;
    }

    function getDailyMintInfo() external view returns (
        uint256 limit,
        uint256 minted,
        uint256 remaining,
        uint256 resetTime
    ) {
        uint256 currentDay = block.timestamp / 1 days;
        
        limit = dailyMintLimit;
        
        if (currentDay > lastMintDay) {
            minted = 0;
            remaining = dailyMintLimit;
        } else {
            minted = dailyMinted;
            remaining = dailyMintLimit - dailyMinted;
        }
        
        resetTime = (currentDay + 1) * 1 days;
    }

    function isBridgeOperator(address operator) external view returns (bool) {
        return bridgeOperators[operator];
    }
}