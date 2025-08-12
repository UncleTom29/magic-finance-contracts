// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./MagicInterfaces.sol";

/**
 * @title MagicVault
 * @dev Bitcoin staking vault that issues liquid staking tokens (lstBTC)
 * Supports multiple staking periods with different APY rates
 */
contract MagicVault is ERC20, Ownable, ReentrancyGuard, Pausable {
    struct StakePosition {
        uint256 amount;           // Amount of BTC staked
        uint256 lstBTCMinted;     // Amount of lstBTC minted
        uint256 stakingPeriod;    // Staking period in seconds
        uint256 startTime;        // When the staking started
        uint256 lastRewardClaim;  // Last reward claim timestamp
        uint8 vaultType;          // 0=flexible, 1=30day, 2=90day, 3=365day
        bool isActive;            // Whether the position is active
    }

    struct VaultConfig {
        uint256 apyRate;          // APY rate in basis points (e.g., 520 = 5.2%)
        uint256 lockPeriod;       // Lock period in seconds
        uint256 minStakeAmount;   // Minimum stake amount
        bool isActive;            // Whether this vault type is active
    }

    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant SECONDS_IN_YEAR = 365 days;
    
    // State variables
    IERC20 public immutable btcToken;
    IPriceOracle public priceOracle;
    IRewardsDistributor public rewardsDistributor;
    
    // Vault configurations (flexible, 30day, 90day, 365day)
    mapping(uint8 => VaultConfig) public vaultConfigs;
    
    // User positions
    mapping(address => StakePosition[]) public userPositions;
    mapping(address => uint256) public userPositionCount;
    
    // Protocol metrics
    uint256 public totalStaked;
    uint256 public totalLstBTCSupply;
    uint256 public protocolFeeRate = 100; // 1% in basis points
    address public feeRecipient;
    
    // Events
    event Staked(address indexed user, uint256 amount, uint8 vaultType, uint256 positionId);
    event Unstaked(address indexed user, uint256 amount, uint256 positionId);
    event RewardsClaimed(address indexed user, uint256 rewards, uint256 positionId);
    event VaultConfigUpdated(uint8 vaultType, uint256 apyRate, uint256 lockPeriod);
    event PriceOracleUpdated(address newOracle);
    event RewardsDistributorUpdated(address newDistributor);

    constructor(
        address _btcToken,
        address _priceOracle,
        address _rewardsDistributor,
        address _feeRecipient,
        address _owner
    ) ERC20("Liquid Staked Bitcoin", "lstBTC") Ownable(_owner) {
        btcToken = IERC20(_btcToken);
        priceOracle = IPriceOracle(_priceOracle);
        rewardsDistributor = IRewardsDistributor(_rewardsDistributor);
        feeRecipient = _feeRecipient;
        
        // Initialize vault configurations
        _initializeVaultConfigs();
    }

    function _initializeVaultConfigs() private {
        // Flexible staking: 5.2% APY, no lock
        vaultConfigs[0] = VaultConfig({
            apyRate: 520,
            lockPeriod: 0,
            minStakeAmount: 0.001 ether, // 0.001 BTC minimum
            isActive: true
        });
        
        // 30-day fixed: 6.8% APY
        vaultConfigs[1] = VaultConfig({
            apyRate: 680,
            lockPeriod: 30 days,
            minStakeAmount: 0.01 ether,
            isActive: true
        });
        
        // 90-day fixed: 8.5% APY
        vaultConfigs[2] = VaultConfig({
            apyRate: 850,
            lockPeriod: 90 days,
            minStakeAmount: 0.01 ether,
            isActive: true
        });
        
        // 365-day fixed: 12.3% APY
        vaultConfigs[3] = VaultConfig({
            apyRate: 1230,
            lockPeriod: 365 days,
            minStakeAmount: 0.1 ether,
            isActive: true
        });
    }

    /**
     * @dev Stake BTC tokens to earn yield
     * @param amount Amount of BTC to stake
     * @param vaultType Type of vault (0-3)
     */
    function stake(uint256 amount, uint8 vaultType) external nonReentrant whenNotPaused {
        require(vaultType <= 3, "Invalid vault type");
        require(vaultConfigs[vaultType].isActive, "Vault type not active");
        require(amount >= vaultConfigs[vaultType].minStakeAmount, "Amount below minimum");
        
        // Transfer BTC tokens from user
        btcToken.transferFrom(msg.sender, address(this), amount);
        
        // Calculate lstBTC to mint (1:1 ratio initially)
        uint256 lstBTCToMint = amount;
        
        // Create staking position
        StakePosition memory position = StakePosition({
            amount: amount,
            lstBTCMinted: lstBTCToMint,
            stakingPeriod: vaultConfigs[vaultType].lockPeriod,
            startTime: block.timestamp,
            lastRewardClaim: block.timestamp,
            vaultType: vaultType,
            isActive: true
        });
        
        userPositions[msg.sender].push(position);
        uint256 positionId = userPositionCount[msg.sender];
        userPositionCount[msg.sender]++;
        
        // Update protocol metrics
        totalStaked += amount;
        totalLstBTCSupply += lstBTCToMint;
        
        // Mint lstBTC tokens to user
        _mint(msg.sender, lstBTCToMint);
        
        emit Staked(msg.sender, amount, vaultType, positionId);
    }

    /**
     * @dev Unstake BTC tokens and burn lstBTC
     * @param positionId Position ID to unstake
     */
    function unstake(uint256 positionId) external nonReentrant whenNotPaused {
        require(positionId < userPositionCount[msg.sender], "Invalid position");
        
        StakePosition storage position = userPositions[msg.sender][positionId];
        require(position.isActive, "Position not active");
        
        // Check if lock period has passed
        if (position.stakingPeriod > 0) {
            require(
                block.timestamp >= position.startTime + position.stakingPeriod,
                "Position still locked"
            );
        }
        
        // Claim pending rewards first
        _claimRewards(msg.sender, positionId);
        
        uint256 amountToReturn = position.amount;
        uint256 lstBTCToBurn = position.lstBTCMinted;
        
        // Mark position as inactive
        position.isActive = false;
        
        // Update protocol metrics
        totalStaked -= amountToReturn;
        totalLstBTCSupply -= lstBTCToBurn;
        
        // Burn lstBTC tokens
        _burn(msg.sender, lstBTCToBurn);
        
        // Return BTC tokens to user
        btcToken.transfer(msg.sender, amountToReturn);
        
        emit Unstaked(msg.sender, amountToReturn, positionId);
    }

    /**
     * @dev Claim staking rewards for a position
     * @param positionId Position ID to claim rewards for
     */
    function claimRewards(uint256 positionId) external nonReentrant whenNotPaused {
        require(positionId < userPositionCount[msg.sender], "Invalid position");
        _claimRewards(msg.sender, positionId);
    }

    function _claimRewards(address user, uint256 positionId) internal {
        StakePosition storage position = userPositions[user][positionId];
        require(position.isActive, "Position not active");
        
        uint256 rewards = calculatePendingRewards(user, positionId);
        
        if (rewards > 0) {
            position.lastRewardClaim = block.timestamp;
            
            // Calculate protocol fee
            uint256 protocolFee = (rewards * protocolFeeRate) / BASIS_POINTS;
            uint256 userRewards = rewards - protocolFee;
            
            // Distribute rewards through RewardsDistributor
            rewardsDistributor.distributeRewards(user, userRewards);
            
            if (protocolFee > 0) {
                rewardsDistributor.distributeRewards(feeRecipient, protocolFee);
            }
            
            emit RewardsClaimed(user, userRewards, positionId);
        }
    }

    /**
     * @dev Calculate pending rewards for a position
     * @param user User address
     * @param positionId Position ID
     * @return Pending rewards amount
     */
    function calculatePendingRewards(address user, uint256 positionId) public view returns (uint256) {
        if (positionId >= userPositionCount[user]) return 0;
        
        StakePosition memory position = userPositions[user][positionId];
        if (!position.isActive) return 0;
        
        VaultConfig memory config = vaultConfigs[position.vaultType];
        
        uint256 timeElapsed = block.timestamp - position.lastRewardClaim;
        uint256 annualReward = (position.amount * config.apyRate) / BASIS_POINTS;
        uint256 rewards = (annualReward * timeElapsed) / SECONDS_IN_YEAR;
        
        return rewards;
    }

    /**
     * @dev Get user's active positions
     * @param user User address
     * @return Array of active positions
     */
    function getUserPositions(address user) external view returns (StakePosition[] memory) {
        return userPositions[user];
    }

    /**
     * @dev Get user's total staked amount
     * @param user User address
     * @return Total staked amount
     */
    function getUserTotalStaked(address user) external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < userPositionCount[user]; i++) {
            if (userPositions[user][i].isActive) {
                total += userPositions[user][i].amount;
            }
        }
        return total;
    }

    // Admin functions
    function updateVaultConfig(
        uint8 vaultType,
        uint256 apyRate,
        uint256 lockPeriod,
        uint256 minStakeAmount,
        bool isActive
    ) external onlyOwner {
        require(vaultType <= 3, "Invalid vault type");
        
        vaultConfigs[vaultType] = VaultConfig({
            apyRate: apyRate,
            lockPeriod: lockPeriod,
            minStakeAmount: minStakeAmount,
            isActive: isActive
        });
        
        emit VaultConfigUpdated(vaultType, apyRate, lockPeriod);
    }

    function setPriceOracle(address _priceOracle) external onlyOwner {
        priceOracle = IPriceOracle(_priceOracle);
        emit PriceOracleUpdated(_priceOracle);
    }

    function setRewardsDistributor(address _rewardsDistributor) external onlyOwner {
        rewardsDistributor = IRewardsDistributor(_rewardsDistributor);
        emit RewardsDistributorUpdated(_rewardsDistributor);
    }

    function setProtocolFeeRate(uint256 _feeRate) external onlyOwner {
        require(_feeRate <= 1000, "Fee rate too high"); // Max 10%
        protocolFeeRate = _feeRate;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Emergency function to withdraw stuck tokens
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }
}