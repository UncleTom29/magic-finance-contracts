// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title RewardsDistributor
 * @dev Distributes yield and staking rewards to users across the Magic Finance ecosystem
 */
contract RewardsDistributor is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    struct RewardPool {
        IERC20 rewardToken;       // Token being distributed as rewards
        uint256 totalRewards;     // Total rewards in this pool
        uint256 distributedRewards; // Already distributed rewards
        uint256 rewardRate;       // Rewards per second
        uint256 lastUpdateTime;   // Last time rewards were updated
        uint256 rewardPerTokenStored; // Accumulated reward per token
        uint256 periodFinish;     // When current reward period ends
        bool isActive;            // Whether this pool is active
    }

    struct UserRewards {
        uint256 userRewardPerTokenPaid; // User's reward per token paid
        uint256 rewards;                // Pending rewards
        uint256 totalEarned;           // Total rewards earned historically
        uint256 lastClaimTime;         // Last time user claimed rewards
    }

    struct StakingPosition {
        uint256 amount;           // Amount of tokens staked
        uint256 timestamp;        // When the position was created
        uint256 multiplier;       // Reward multiplier (basis points)
        bool isActive;           // Whether position is active
    }

    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant REWARD_DURATION = 7 days;
    uint256 public constant MIN_REWARD_AMOUNT = 1e6; // Minimum reward amount (1 USDC/USDT)

    // State variables
    mapping(string => RewardPool) public rewardPools;
    mapping(address => mapping(string => UserRewards)) public userRewards;
    mapping(address => mapping(string => StakingPosition)) public stakingPositions;
    
    string[] public activePoolIds;
    mapping(address => bool) public authorizedDistributors; // Contracts that can distribute rewards
    
    // Reward tokens
    IERC20 public btcToken;
    IERC20 public usdtToken;
    IERC20 public usdcToken;
    IERC20 public coreToken;
    
    // Protocol metrics
    uint256 public totalStakedAcrossPools;
    mapping(string => uint256) public totalStakedInPool;
    
    // Fee structure
    uint256 public performanceFeeRate = 1000; // 10% performance fee
    address public feeRecipient;
    
    // Events
    event RewardPoolCreated(string poolId, address rewardToken, uint256 rewardAmount);
    event RewardsDistributed(address indexed user, string poolId, uint256 amount);
    event RewardsClaimed(address indexed user, string poolId, uint256 amount);
    event StakingPositionCreated(address indexed user, string poolId, uint256 amount);
    event StakingPositionClosed(address indexed user, string poolId, uint256 amount);
    event RewardPoolUpdated(string poolId, uint256 newRewardAmount);

    modifier onlyAuthorized() {
        require(authorizedDistributors[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }

    modifier updateReward(address user, string memory poolId) {
        _updateReward(user, poolId);
        _;
    }

    constructor(
        address _btcToken,
        address _usdtToken,
        address _usdcToken,
        address _coreToken,
        address _feeRecipient,
        address _owner
    ) Ownable(_owner) {
        btcToken = IERC20(_btcToken);
        usdtToken = IERC20(_usdtToken);
        usdcToken = IERC20(_usdcToken);
        coreToken = IERC20(_coreToken);
        feeRecipient = _feeRecipient;
        
        _initializeRewardPools();
    }

    function _initializeRewardPools() private {
        // Create BTC yield pool
        _createRewardPool(
            "BTC_YIELD",
            address(btcToken),
            0, // Will be funded separately
            0  // Will be set when funding
        );
        
        // Create USDT lending pool
        _createRewardPool(
            "USDT_LENDING",
            address(usdtToken),
            0,
            0
        );
        
        // Create USDC lending pool
        _createRewardPool(
            "USDC_LENDING",
            address(usdcToken),
            0,
            0
        );
        
        // Create CORE staking pool
        _createRewardPool(
            "CORE_STAKING",
            address(coreToken),
            0,
            0
        );
    }

    /**
     * @dev Create a new reward pool
     */
    function createRewardPool(
        string memory poolId,
        address rewardToken,
        uint256 rewardAmount,
        uint256 duration
    ) external onlyOwner {
        _createRewardPool(poolId, rewardToken, rewardAmount, duration);
    }

    function _createRewardPool(
        string memory poolId,
        address rewardToken,
        uint256 rewardAmount,
        uint256 duration
    ) internal {
        require(bytes(poolId).length > 0, "Invalid pool ID");
        require(rewardToken != address(0), "Invalid reward token");
        require(!rewardPools[poolId].isActive, "Pool already exists");
        
        if (duration == 0) {
            duration = REWARD_DURATION;
        }
        
        uint256 rewardRate = rewardAmount > 0 ? rewardAmount / duration : 0;
        
        rewardPools[poolId] = RewardPool({
            rewardToken: IERC20(rewardToken),
            totalRewards: rewardAmount,
            distributedRewards: 0,
            rewardRate: rewardRate,
            lastUpdateTime: block.timestamp,
            rewardPerTokenStored: 0,
            periodFinish: block.timestamp + duration,
            isActive: true
        });
        
        activePoolIds.push(poolId);
        
        emit RewardPoolCreated(poolId, rewardToken, rewardAmount);
    }

    /**
     * @dev Fund a reward pool with additional rewards
     */
    function fundRewardPool(
        string memory poolId,
        uint256 rewardAmount,
        uint256 duration
    ) external onlyOwner updateReward(address(0), poolId) {
        require(rewardPools[poolId].isActive, "Pool not active");
        require(rewardAmount >= MIN_REWARD_AMOUNT, "Reward amount too small");
        
        if (duration == 0) {
            duration = REWARD_DURATION;
        }
        
        RewardPool storage pool = rewardPools[poolId];
        
        // Transfer reward tokens to this contract
        pool.rewardToken.safeTransferFrom(msg.sender, address(this), rewardAmount);
        
        // Calculate new reward rate
        uint256 remainingRewards = 0;
        if (block.timestamp < pool.periodFinish) {
            remainingRewards = (pool.periodFinish - block.timestamp) * pool.rewardRate;
        }
        
        pool.rewardRate = (rewardAmount + remainingRewards) / duration;
        pool.totalRewards += rewardAmount;
        pool.lastUpdateTime = block.timestamp;
        pool.periodFinish = block.timestamp + duration;
        
        emit RewardPoolUpdated(poolId, rewardAmount);
    }

    /**
     * @dev Distribute rewards to a user (called by authorized contracts)
     */
    function distributeRewards(
        address user,
        uint256 amount
    ) external onlyAuthorized nonReentrant {
        require(user != address(0), "Invalid user");
        require(amount > 0, "Invalid amount");
        
        // For now, distribute as USDT (can be extended to support multiple tokens)
        string memory poolId = "USDT_LENDING";
        
        // Calculate performance fee
        uint256 performanceFee = (amount * performanceFeeRate) / BASIS_POINTS;
        uint256 userReward = amount - performanceFee;
        
        // Update user rewards
        userRewards[user][poolId].rewards += userReward;
        userRewards[user][poolId].totalEarned += userReward;
        
        // Distribute performance fee
        if (performanceFee > 0) {
            userRewards[feeRecipient][poolId].rewards += performanceFee;
        }
        
        emit RewardsDistributed(user, poolId, userReward);
    }

    /**
     * @dev Create a staking position for yield calculation
     */
    function createStakingPosition(
        address user,
        string memory poolId,
        uint256 amount,
        uint256 multiplier
    ) external onlyAuthorized updateReward(user, poolId) {
        require(rewardPools[poolId].isActive, "Pool not active");
        require(amount > 0, "Invalid amount");
        require(multiplier > 0 && multiplier <= 50000, "Invalid multiplier"); // Max 5x multiplier
        
        stakingPositions[user][poolId] = StakingPosition({
            amount: amount,
            timestamp: block.timestamp,
            multiplier: multiplier,
            isActive: true
        });
        
        totalStakedInPool[poolId] += amount;
        totalStakedAcrossPools += amount;
        
        emit StakingPositionCreated(user, poolId, amount);
    }

    /**
     * @dev Update staking position amount
     */
    function updateStakingPosition(
        address user,
        string memory poolId,
        uint256 newAmount
    ) external onlyAuthorized updateReward(user, poolId) {
        require(stakingPositions[user][poolId].isActive, "Position not active");
        
        uint256 oldAmount = stakingPositions[user][poolId].amount;
        stakingPositions[user][poolId].amount = newAmount;
        
        if (newAmount > oldAmount) {
            uint256 increase = newAmount - oldAmount;
            totalStakedInPool[poolId] += increase;
            totalStakedAcrossPools += increase;
        } else if (newAmount < oldAmount) {
            uint256 decrease = oldAmount - newAmount;
            totalStakedInPool[poolId] -= decrease;
            totalStakedAcrossPools -= decrease;
        }
    }

    /**
     * @dev Close a staking position
     */
    function closeStakingPosition(
        address user,
        string memory poolId
    ) external onlyAuthorized updateReward(user, poolId) {
        require(stakingPositions[user][poolId].isActive, "Position not active");
        
        uint256 amount = stakingPositions[user][poolId].amount;
        stakingPositions[user][poolId].isActive = false;
        stakingPositions[user][poolId].amount = 0;
        
        totalStakedInPool[poolId] -= amount;
        totalStakedAcrossPools -= amount;
        
        emit StakingPositionClosed(user, poolId, amount);
    }

    /**
     * @dev Claim pending rewards
     */
    function claimRewards(string memory poolId) external nonReentrant updateReward(msg.sender, poolId) {
        uint256 reward = userRewards[msg.sender][poolId].rewards;
        require(reward > 0, "No rewards to claim");
        
        userRewards[msg.sender][poolId].rewards = 0;
        userRewards[msg.sender][poolId].lastClaimTime = block.timestamp;
        
        RewardPool memory pool = rewardPools[poolId];
        pool.rewardToken.safeTransfer(msg.sender, reward);
        
        emit RewardsClaimed(msg.sender, poolId, reward);
    }

    /**
     * @dev Claim rewards from multiple pools
     */
    function claimMultipleRewards(string[] memory poolIds) external nonReentrant {
        for (uint256 i = 0; i < poolIds.length; i++) {
            _updateReward(msg.sender, poolIds[i]);
            
            uint256 reward = userRewards[msg.sender][poolIds[i]].rewards;
            if (reward > 0) {
                userRewards[msg.sender][poolIds[i]].rewards = 0;
                userRewards[msg.sender][poolIds[i]].lastClaimTime = block.timestamp;
                
                RewardPool memory pool = rewardPools[poolIds[i]];
                pool.rewardToken.safeTransfer(msg.sender, reward);
                
                emit RewardsClaimed(msg.sender, poolIds[i], reward);
            }
        }
    }

    /**
     * @dev Update reward calculations
     */
    function _updateReward(address account, string memory poolId) internal {
        RewardPool storage pool = rewardPools[poolId];
        
        pool.rewardPerTokenStored = rewardPerToken(poolId);
        pool.lastUpdateTime = lastTimeRewardApplicable(poolId);
        
        if (account != address(0)) {
            userRewards[account][poolId].rewards = earned(account, poolId);
            userRewards[account][poolId].userRewardPerTokenPaid = pool.rewardPerTokenStored;
        }
    }

    /**
     * @dev Calculate reward per token
     */
    function rewardPerToken(string memory poolId) public view returns (uint256) {
        RewardPool memory pool = rewardPools[poolId];
        
        if (totalStakedInPool[poolId] == 0) {
            return pool.rewardPerTokenStored;
        }
        
        return pool.rewardPerTokenStored + (
            (lastTimeRewardApplicable(poolId) - pool.lastUpdateTime) *
            pool.rewardRate * 1e18 / totalStakedInPool[poolId]
        );
    }

    /**
     * @dev Get last time reward is applicable
     */
    function lastTimeRewardApplicable(string memory poolId) public view returns (uint256) {
        RewardPool memory pool = rewardPools[poolId];
        return block.timestamp < pool.periodFinish ? block.timestamp : pool.periodFinish;
    }

    /**
     * @dev Calculate earned rewards for a user
     */
    function earned(address account, string memory poolId) public view returns (uint256) {
        StakingPosition memory position = stakingPositions[account][poolId];
        
        if (!position.isActive) {
            return userRewards[account][poolId].rewards;
        }
        
        uint256 effectiveBalance = (position.amount * position.multiplier) / BASIS_POINTS;
        
        return (effectiveBalance * 
                (rewardPerToken(poolId) - userRewards[account][poolId].userRewardPerTokenPaid) 
                / 1e18) + userRewards[account][poolId].rewards;
    }

    // View functions
    function getRewardPool(string memory poolId) external view returns (
        address rewardToken,
        uint256 totalRewards,
        uint256 distributedRewards,
        uint256 rewardRate,
        uint256 periodFinish,
        bool isActive
    ) {
        RewardPool memory pool = rewardPools[poolId];
        return (
            address(pool.rewardToken),
            pool.totalRewards,
            pool.distributedRewards,
            pool.rewardRate,
            pool.periodFinish,
            pool.isActive
        );
    }

    function getUserRewards(address user, string memory poolId) external view returns (
        uint256 pendingRewards,
        uint256 totalEarned,
        uint256 lastClaimTime
    ) {
        return (
            earned(user, poolId),
            userRewards[user][poolId].totalEarned,
            userRewards[user][poolId].lastClaimTime
        );
    }

    function getStakingPosition(address user, string memory poolId) external view returns (
        uint256 amount,
        uint256 timestamp,
        uint256 multiplier,
        bool isActive
    ) {
        StakingPosition memory position = stakingPositions[user][poolId];
        return (position.amount, position.timestamp, position.multiplier, position.isActive);
    }

    function getActivePoolIds() external view returns (string[] memory) {
        return activePoolIds;
    }

    // Admin functions
    function setAuthorizedDistributor(address distributor, bool authorized) external onlyOwner {
        authorizedDistributors[distributor] = authorized;
    }

    function setPerformanceFeeRate(uint256 feeRate) external onlyOwner {
        require(feeRate <= 2000, "Fee rate too high"); // Max 20%
        performanceFeeRate = feeRate;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }

    function pauseRewardPool(string memory poolId) external onlyOwner {
        rewardPools[poolId].isActive = false;
    }

    function unpauseRewardPool(string memory poolId) external onlyOwner {
        rewardPools[poolId].isActive = true;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Emergency functions
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
}