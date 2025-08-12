// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./MagicInterfaces.sol";

/**
 * @title CoreToken
 * @dev CORE token implementation with price oracle integration for Magic Finance
 */
contract CoreToken is ERC20, ERC20Burnable, ERC20Pausable, Ownable, ReentrancyGuard {
    
    // Price Oracle integration
    IPriceOracle public priceOracle;
    string public constant PRICE_FEED_ID = "CORE";
    
    // Token economics
    uint256 public constant MAX_SUPPLY = 2_100_000_000 * 10**18; // 2.1 billion tokens
    uint256 public constant INITIAL_SUPPLY = 210_000_000 * 10**18; // 210 million initial supply (10%)
    
    // Minting controls
    mapping(address => bool) public minters;
    uint256 public totalMinted;
    uint256 public maxMintPerCall = 1_000_000 * 10**18; // 1 million tokens per call
    
    // Staking functionality
    struct StakingPosition {
        uint256 amount;
        uint256 startTime;
        uint256 lastRewardClaim;
        uint256 rewardMultiplier; // Basis points (10000 = 1x)
        bool isActive;
    }
    
    mapping(address => StakingPosition[]) public stakingPositions;
    mapping(address => uint256) public totalStaked;
    uint256 public totalStakedSupply;
    
    // Reward settings
    uint256 public stakingRewardRate = 500; // 5% annual reward
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant SECONDS_PER_YEAR = 365 days;
    
    // Fee structure
    uint256 public transferFee = 0; // No transfer fee initially
    address public feeRecipient;
    mapping(address => bool) public feeExempt;
    
    // Events
    event PriceOracleUpdated(address indexed newOracle);
    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
    event TokensStaked(address indexed user, uint256 amount, uint256 positionId);
    event TokensUnstaked(address indexed user, uint256 amount, uint256 positionId);
    event StakingRewardsClaimed(address indexed user, uint256 amount);
    event TransferFeeUpdated(uint256 newFee);
    
    modifier onlyMinter() {
        require(minters[msg.sender] || msg.sender == owner(), "Not authorized to mint");
        _;
    }
    
    constructor(
        address _priceOracle,
        address _feeRecipient,
        address _owner
    ) ERC20("Core DAO", "CORE") Ownable(_owner) {
        priceOracle = IPriceOracle(_priceOracle);
        feeRecipient = _feeRecipient;
        
        // Mint initial supply to owner
        _mint(_owner, INITIAL_SUPPLY);
        totalMinted = INITIAL_SUPPLY;
        
        // Owner is fee exempt
        feeExempt[_owner] = true;
        feeExempt[address(this)] = true;
        
        emit PriceOracleUpdated(_priceOracle);
    }
    
    /**
     * @dev Get current CORE price from oracle
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
     * @dev Calculate USD value of token amount
     */
    function calculateUSDValue(uint256 tokenAmount) external view returns (uint256) {
        uint256 price = priceOracle.getPrice(PRICE_FEED_ID);
        return (tokenAmount * price) / 10**18;
    }
    
    /**
     * @dev Calculate token amount for USD value
     */
    function calculateTokenAmount(uint256 usdValue) external view returns (uint256) {
        uint256 price = priceOracle.getPrice(PRICE_FEED_ID);
        require(price > 0, "Invalid price");
        return (usdValue * 10**18) / price;
    }
    
    /**
     * @dev Mint new tokens (only by authorized minters)
     */
    function mint(address to, uint256 amount) external onlyMinter {
        require(amount <= maxMintPerCall, "Exceeds max mint per call");
        require(totalMinted + amount <= MAX_SUPPLY, "Exceeds max supply");
        
        _mint(to, amount);
        totalMinted += amount;
    }
    
    /**
     * @dev Batch mint to multiple addresses
     */
    function batchMint(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyMinter {
        require(recipients.length == amounts.length, "Array length mismatch");
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        
        require(totalAmount <= maxMintPerCall, "Exceeds max mint per call");
        require(totalMinted + totalAmount <= MAX_SUPPLY, "Exceeds max supply");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amounts[i]);
        }
        
        totalMinted += totalAmount;
    }
    
    /**
     * @dev Stake tokens for rewards
     */
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Invalid amount");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        // Transfer tokens to this contract
        _transfer(msg.sender, address(this), amount);
        
        // Create staking position
        stakingPositions[msg.sender].push(StakingPosition({
            amount: amount,
            startTime: block.timestamp,
            lastRewardClaim: block.timestamp,
            rewardMultiplier: BASIS_POINTS, // 1x multiplier initially
            isActive: true
        }));
        
        totalStaked[msg.sender] += amount;
        totalStakedSupply += amount;
        
        uint256 positionId = stakingPositions[msg.sender].length - 1;
        emit TokensStaked(msg.sender, amount, positionId);
    }
    
    /**
     * @dev Unstake tokens
     */
    function unstake(uint256 positionId) external nonReentrant {
        require(positionId < stakingPositions[msg.sender].length, "Invalid position");
        
        StakingPosition storage position = stakingPositions[msg.sender][positionId];
        require(position.isActive, "Position not active");
        
        uint256 amount = position.amount;
        
        // Claim any pending rewards first
        _claimStakingRewards(msg.sender, positionId);
        
        // Update state
        position.isActive = false;
        position.amount = 0;
        totalStaked[msg.sender] -= amount;
        totalStakedSupply -= amount;
        
        // Transfer tokens back to user
        _transfer(address(this), msg.sender, amount);
        
        emit TokensUnstaked(msg.sender, amount, positionId);
    }
    
    /**
     * @dev Claim staking rewards for a specific position
     */
    function claimStakingRewards(uint256 positionId) external nonReentrant {
        _claimStakingRewards(msg.sender, positionId);
    }
    
    /**
     * @dev Claim all staking rewards for user
     */
    function claimAllStakingRewards() external nonReentrant {
        uint256 totalRewards = 0;
        
        for (uint256 i = 0; i < stakingPositions[msg.sender].length; i++) {
            if (stakingPositions[msg.sender][i].isActive) {
                uint256 rewards = _claimStakingRewards(msg.sender, i);
                totalRewards += rewards;
            }
        }
        
        require(totalRewards > 0, "No rewards to claim");
    }
    
    function _claimStakingRewards(address user, uint256 positionId) internal returns (uint256) {
        require(positionId < stakingPositions[user].length, "Invalid position");
        
        StakingPosition storage position = stakingPositions[user][positionId];
        require(position.isActive, "Position not active");
        
        uint256 rewards = calculateStakingRewards(user, positionId);
        
        if (rewards > 0) {
            position.lastRewardClaim = block.timestamp;
            
            // Mint rewards (if within max supply)
            if (totalMinted + rewards <= MAX_SUPPLY) {
                _mint(user, rewards);
                totalMinted += rewards;
            }
            
            emit StakingRewardsClaimed(user, rewards);
        }
        
        return rewards;
    }
    
    /**
     * @dev Calculate pending staking rewards
     */
    function calculateStakingRewards(address user, uint256 positionId) public view returns (uint256) {
        if (positionId >= stakingPositions[user].length) return 0;
        
        StakingPosition memory position = stakingPositions[user][positionId];
        if (!position.isActive) return 0;
        
        uint256 stakingDuration = block.timestamp - position.lastRewardClaim;
        uint256 annualReward = (position.amount * stakingRewardRate) / BASIS_POINTS;
        uint256 rewards = (annualReward * stakingDuration) / SECONDS_PER_YEAR;
        
        // Apply multiplier
        rewards = (rewards * position.rewardMultiplier) / BASIS_POINTS;
        
        return rewards;
    }
    
    /**
     * @dev Get total pending rewards for user
     */
    function getTotalPendingRewards(address user) external view returns (uint256) {
        uint256 totalRewards = 0;
        
        for (uint256 i = 0; i < stakingPositions[user].length; i++) {
            if (stakingPositions[user][i].isActive) {
                totalRewards += calculateStakingRewards(user, i);
            }
        }
        
        return totalRewards;
    }
    
    /**
     * @dev Get user's staking positions
     */
    function getUserStakingPositions(address user) external view returns (StakingPosition[] memory) {
        return stakingPositions[user];
    }
    
    /**
     * @dev Override transfer to include fees
     */
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable) {
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
    
    function setMaxMintPerCall(uint256 _maxMintPerCall) external onlyOwner {
        maxMintPerCall = _maxMintPerCall;
    }
    
    function setStakingRewardRate(uint256 _stakingRewardRate) external onlyOwner {
        require(_stakingRewardRate <= 2000, "Rate too high"); // Max 20%
        stakingRewardRate = _stakingRewardRate;
    }
    
    function setTransferFee(uint256 _transferFee) external onlyOwner {
        require(_transferFee <= 500, "Fee too high"); // Max 5%
        transferFee = _transferFee;
        emit TransferFeeUpdated(_transferFee);
    }
    
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }
    
    function setFeeExempt(address account, bool exempt) external onlyOwner {
        feeExempt[account] = exempt;
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
}