// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title GovernanceToken (MAGIC)
 * @dev ERC20 governance token for Magic Finance protocol
 * Features: Voting, Permit, Burning, Vesting, and Staking rewards
 */
contract MagicToken is ERC20, ERC20Permit, ERC20Votes, ERC20Burnable, Ownable, Pausable {
    
    struct VestingSchedule {
        uint256 totalAmount;      // Total tokens to be vested
        uint256 startTime;        // Vesting start time
        uint256 cliffDuration;    // Cliff period in seconds
        uint256 vestingDuration;  // Total vesting duration in seconds
        uint256 releasedAmount;   // Amount already released
        bool revocable;           // Whether the vesting can be revoked
        bool revoked;             // Whether the vesting has been revoked
    }

    struct StakingInfo {
        uint256 stakedAmount;     // Amount of MAGIC staked
        uint256 stakingTime;      // When staking started
        uint256 rewardDebt;       // Reward debt for calculating rewards
        uint256 pendingRewards;   // Pending rewards to be claimed
    }

    // Constants
    uint256 public constant MAX_SUPPLY = 100_000_000 * 1e18; // 100M MAGIC tokens
    uint256 public constant INITIAL_SUPPLY = 20_000_000 * 1e18; // 20M initial supply
    uint256 public constant STAKING_REWARD_RATE = 1000; // 10% APR in basis points
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant SECONDS_IN_YEAR = 365 days;

    // State variables
    mapping(address => VestingSchedule) public vestingSchedules;
    mapping(address => StakingInfo) public stakingInfo;
    
    uint256 public totalStaked;
    uint256 public stakingRewardPool;
    uint256 public lastRewardUpdate;
    uint256 public accRewardPerShare; // Accumulated rewards per share
    
    // Minting controls
    mapping(address => bool) public minters;
    uint256 public totalMinted;
    
    // Governance parameters
    uint256 public proposalThreshold = 1_000_000 * 1e18; // 1M MAGIC to create proposal
    uint256 public votingDelay = 1 days;
    uint256 public votingPeriod = 7 days;
    
    // Events
    event VestingScheduleCreated(address indexed beneficiary, uint256 amount, uint256 startTime, uint256 duration);
    event TokensVested(address indexed beneficiary, uint256 amount);
    event VestingRevoked(address indexed beneficiary, uint256 unvestedAmount);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);

    modifier onlyMinter() {
        require(minters[msg.sender], "Not authorized minter");
        _;
    }

    constructor(
        address _owner,
        address _treasury
    ) ERC20("Magic Finance", "MAGIC") ERC20Permit("Magic Finance") Ownable(_owner) {
        // Mint initial supply to treasury
        _mint(_treasury, INITIAL_SUPPLY);
        totalMinted = INITIAL_SUPPLY;
        lastRewardUpdate = block.timestamp;
        
        // Add owner as initial minter
        minters[_owner] = true;
        emit MinterAdded(_owner);
    }

    /**
     * @dev Mint new tokens (only by authorized minters)
     */
    function mint(address to, uint256 amount) external onlyMinter whenNotPaused {
        require(totalMinted + amount <= MAX_SUPPLY, "Exceeds max supply");
        
        _mint(to, amount);
        totalMinted += amount;
    }

    /**
     * @dev Create a vesting schedule for a beneficiary
     */
    function createVestingSchedule(
        address beneficiary,
        uint256 amount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration,
        bool revocable
    ) external onlyOwner {
        require(beneficiary != address(0), "Invalid beneficiary");
        require(amount > 0, "Invalid amount");
        require(vestingDuration > 0, "Invalid vesting duration");
        require(cliffDuration <= vestingDuration, "Cliff longer than vesting");
        require(vestingSchedules[beneficiary].totalAmount == 0, "Vesting already exists");
        
        if (startTime == 0) {
            startTime = block.timestamp;
        }
        
        vestingSchedules[beneficiary] = VestingSchedule({
            totalAmount: amount,
            startTime: startTime,
            cliffDuration: cliffDuration,
            vestingDuration: vestingDuration,
            releasedAmount: 0,
            revocable: revocable,
            revoked: false
        });
        
        // Transfer tokens to this contract for vesting
        _transfer(msg.sender, address(this), amount);
        
        emit VestingScheduleCreated(beneficiary, amount, startTime, vestingDuration);
    }

    /**
     * @dev Calculate vested amount for a beneficiary
     */
    function calculateVestedAmount(address beneficiary) public view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[beneficiary];
        
        if (schedule.totalAmount == 0 || schedule.revoked) {
            return schedule.releasedAmount;
        }
        
        if (block.timestamp < schedule.startTime + schedule.cliffDuration) {
            return 0;
        }
        
        if (block.timestamp >= schedule.startTime + schedule.vestingDuration) {
            return schedule.totalAmount;
        }
        
        uint256 timeFromStart = block.timestamp - schedule.startTime;
        uint256 vestedAmount = (schedule.totalAmount * timeFromStart) / schedule.vestingDuration;
        
        return vestedAmount;
    }

    /**
     * @dev Release vested tokens to beneficiary
     */
    function releaseVestedTokens() external whenNotPaused {
        address beneficiary = msg.sender;
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        
        require(schedule.totalAmount > 0, "No vesting schedule");
        require(!schedule.revoked, "Vesting revoked");
        
        uint256 vestedAmount = calculateVestedAmount(beneficiary);
        uint256 releasableAmount = vestedAmount - schedule.releasedAmount;
        
        require(releasableAmount > 0, "No tokens to release");
        
        schedule.releasedAmount += releasableAmount;
        
        _transfer(address(this), beneficiary, releasableAmount);
        
        emit TokensVested(beneficiary, releasableAmount);
    }

    /**
     * @dev Revoke vesting (only for revocable schedules)
     */
    function revokeVesting(address beneficiary) external onlyOwner {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        
        require(schedule.totalAmount > 0, "No vesting schedule");
        require(schedule.revocable, "Vesting not revocable");
        require(!schedule.revoked, "Already revoked");
        
        uint256 vestedAmount = calculateVestedAmount(beneficiary);
        uint256 releasableAmount = vestedAmount - schedule.releasedAmount;
        uint256 unvestedAmount = schedule.totalAmount - vestedAmount;
        
        schedule.revoked = true;
        
        // Release any vested but unreleased tokens
        if (releasableAmount > 0) {
            schedule.releasedAmount += releasableAmount;
            _transfer(address(this), beneficiary, releasableAmount);
        }
        
        // Return unvested tokens to owner
        if (unvestedAmount > 0) {
            _transfer(address(this), owner(), unvestedAmount);
        }
        
        emit VestingRevoked(beneficiary, unvestedAmount);
    }

    /**
     * @dev Stake MAGIC tokens to earn rewards
     */
    function stake(uint256 amount) external whenNotPaused {
        require(amount > 0, "Invalid amount");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        _updateStakingRewards(msg.sender);
        
        StakingInfo storage info = stakingInfo[msg.sender];
        info.stakedAmount += amount;
        info.stakingTime = block.timestamp;
        info.rewardDebt = (info.stakedAmount * accRewardPerShare) / 1e18;
        
        totalStaked += amount;
        
        // Transfer tokens to this contract
        _transfer(msg.sender, address(this), amount);
        
        emit Staked(msg.sender, amount);
    }

    /**
     * @dev Unstake MAGIC tokens
     */
    function unstake(uint256 amount) external whenNotPaused {
        StakingInfo storage info = stakingInfo[msg.sender];
        require(info.stakedAmount >= amount, "Insufficient staked amount");
        
        _updateStakingRewards(msg.sender);
        
        info.stakedAmount -= amount;
        info.rewardDebt = (info.stakedAmount * accRewardPerShare) / 1e18;
        
        totalStaked -= amount;
        
        // Transfer tokens back to user
        _transfer(address(this), msg.sender, amount);
        
        emit Unstaked(msg.sender, amount);
    }

    /**
     * @dev Claim staking rewards
     */
    function claimStakingRewards() external whenNotPaused {
        _updateStakingRewards(msg.sender);
        
        StakingInfo storage info = stakingInfo[msg.sender];
        uint256 rewards = info.pendingRewards;
        
        require(rewards > 0, "No rewards to claim");
        require(stakingRewardPool >= rewards, "Insufficient reward pool");
        
        info.pendingRewards = 0;
        stakingRewardPool -= rewards;
        
        // Mint rewards to user
        if (totalMinted + rewards <= MAX_SUPPLY) {
            _mint(msg.sender, rewards);
            totalMinted += rewards;
        }
        
        emit RewardsClaimed(msg.sender, rewards);
    }

    /**
     * @dev Update staking rewards for a user
     */
    function _updateStakingRewards(address user) internal {
        _updateAccRewardPerShare();
        
        StakingInfo storage info = stakingInfo[user];
        
        if (info.stakedAmount > 0) {
            uint256 pending = (info.stakedAmount * accRewardPerShare) / 1e18 - info.rewardDebt;
            info.pendingRewards += pending;
        }
    }

    /**
     * @dev Update accumulated reward per share
     */
    function _updateAccRewardPerShare() internal {
        if (totalStaked == 0) {
            lastRewardUpdate = block.timestamp;
            return;
        }
        
        uint256 timeElapsed = block.timestamp - lastRewardUpdate;
        uint256 totalRewards = (stakingRewardPool * STAKING_REWARD_RATE * timeElapsed) / 
                              (BASIS_POINTS * SECONDS_IN_YEAR);
        
        if (totalRewards > 0) {
            accRewardPerShare += (totalRewards * 1e18) / totalStaked;
        }
        
        lastRewardUpdate = block.timestamp;
    }

    /**
     * @dev Add tokens to staking reward pool
     */
    function addToRewardPool(uint256 amount) external onlyOwner {
        require(amount > 0, "Invalid amount");
        
        stakingRewardPool += amount;
        
        // Transfer tokens to this contract
        _transfer(msg.sender, address(this), amount);
    }

    /**
     * @dev Calculate pending staking rewards for a user
     */
    function pendingStakingRewards(address user) external view returns (uint256) {
        StakingInfo memory info = stakingInfo[user];
        
        if (info.stakedAmount == 0) {
            return info.pendingRewards;
        }
        
        uint256 currentAccRewardPerShare = accRewardPerShare;
        
        if (totalStaked > 0) {
            uint256 timeElapsed = block.timestamp - lastRewardUpdate;
            uint256 totalRewards = (stakingRewardPool * STAKING_REWARD_RATE * timeElapsed) / 
                                  (BASIS_POINTS * SECONDS_IN_YEAR);
            currentAccRewardPerShare += (totalRewards * 1e18) / totalStaked;
        }
        
        uint256 pending = (info.stakedAmount * currentAccRewardPerShare) / 1e18 - info.rewardDebt;
        return info.pendingRewards + pending;
    }

    // Governance functions
    function setProposalThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold > 0, "Invalid threshold");
        proposalThreshold = newThreshold;
    }

    function setVotingDelay(uint256 newDelay) external onlyOwner {
        require(newDelay > 0, "Invalid delay");
        votingDelay = newDelay;
    }

    function setVotingPeriod(uint256 newPeriod) external onlyOwner {
        require(newPeriod > 0, "Invalid period");
        votingPeriod = newPeriod;
    }

    // Minter management
    function addMinter(address minter) external onlyOwner {
        require(minter != address(0), "Invalid minter");
        minters[minter] = true;
        emit MinterAdded(minter);
    }

    function removeMinter(address minter) external onlyOwner {
        minters[minter] = false;
        emit MinterRemoved(minter);
    }

    // View functions
    function getVestingSchedule(address beneficiary) external view returns (
        uint256 totalAmount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration,
        uint256 releasedAmount,
        uint256 vestedAmount,
        uint256 releasableAmount,
        bool revocable,
        bool revoked
    ) {
        VestingSchedule memory schedule = vestingSchedules[beneficiary];
        uint256 vested = calculateVestedAmount(beneficiary);
        uint256 releasable = vested - schedule.releasedAmount;
        
        return (
            schedule.totalAmount,
            schedule.startTime,
            schedule.cliffDuration,
            schedule.vestingDuration,
            schedule.releasedAmount,
            vested,
            releasable,
            schedule.revocable,
            schedule.revoked
        );
    }

    function getStakingInfo(address user) external view returns (
        uint256 stakedAmount,
        uint256 stakingTime,
        uint256 pendingRewards
    ) {
        StakingInfo memory info = stakingInfo[user];
        uint256 pending = this.pendingStakingRewards(user);
        
        return (info.stakedAmount, info.stakingTime, pending);
    }

    // Override required functions
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    // Pause functions
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Emergency functions
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(this)) {
            // Don't allow withdrawing MAGIC tokens that are part of vesting or staking
            uint256 lockedAmount = 0;
            // This would need to track all locked tokens properly in production
            require(amount <= balanceOf(address(this)) - lockedAmount, "Cannot withdraw locked tokens");
        }
        
        IERC20(token).transfer(owner(), amount);
    }
}