// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPriceOracle
 * @dev Interface for Pyth-based price oracle
 */
interface IPriceOracle {
    function getPrice(string memory asset) external view returns (uint256);
    
    function getPriceData(string memory asset) external view returns (
        uint256 price,
        uint256 timestamp,
        uint256 confidence,
        bool isStale
    );
    
    function isPriceStale(string memory asset) external view returns (bool);
    
    function getSupportedAssets() external view returns (string[] memory);
    
    function getMultiplePrices(string[] memory assets) external view returns (
        uint256[] memory prices,
        uint256[] memory timestamps,
        uint256[] memory confidences
    );
    
    function updatePrices(bytes[] calldata priceUpdateData) external payable;
    
    function getUpdateFee(bytes[] calldata priceUpdateData) external view returns (uint256);
}


/**
 * @title IRewardsDistributor
 * @dev Interface for rewards distributor contract
 */
interface IRewardsDistributor {
    function distributeRewards(address user, uint256 amount) external;
    function createStakingPosition(
        address user,
        string memory poolId,
        uint256 amount,
        uint256 multiplier
    ) external;
    function updateStakingPosition(
        address user,
        string memory poolId,
        uint256 newAmount
    ) external;
    function closeStakingPosition(address user, string memory poolId) external;
    function earned(address account, string memory poolId) external view returns (uint256);
}

/**
 * @title IMagicVault
 * @dev Interface for Magic Vault contract
 */
interface IMagicVault {
    struct StakePosition {
        uint256 amount;
        uint256 lstBTCMinted;
        uint256 stakingPeriod;
        uint256 startTime;
        uint256 lastRewardClaim;
        uint8 vaultType;
        bool isActive;
    }
    
    function stake(uint256 amount, uint8 vaultType) external;
    function unstake(uint256 positionId) external;
    function claimRewards(uint256 positionId) external;
    function calculatePendingRewards(address user, uint256 positionId) external view returns (uint256);
    function getUserPositions(address user) external view returns (StakePosition[] memory);
    function getUserTotalStaked(address user) external view returns (uint256);
}

/**
 * @title ILendingPool
 * @dev Interface for lending pool contract
 */
interface ILendingPool {
    struct LoanPosition {
        uint256 collateralAmount;
        uint256 borrowedAmount;
        uint256 interestRate;
        uint256 lastInterestAccrual;
        uint256 accruedInterest;
        address borrower;
        address asset;
        bool isActive;
        uint256 liquidationThreshold;
    }
    
    function borrow(address asset, uint256 amount, uint256 collateralAmount) external;
    function repay(uint256 loanId, uint256 amount) external;
    function addCollateral(uint256 loanId, uint256 amount) external;
    function removeCollateral(uint256 loanId, uint256 amount) external;
    function liquidate(uint256 loanId, uint256 debtToCover) external;
    function getLoanDetails(uint256 loanId) external view returns (LoanPosition memory);
    function calculateHealthFactor(address user) external view returns (uint256);
}

/**
 * @title ICreditFacility
 * @dev Interface for credit facility contract
 */
interface ICreditFacility {
    enum PaymentSource {
        BTC_YIELD,
        CREDIT_LINE,
        MANUAL_PAYMENT
    }
    
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
    }
    
    function issueCard(uint256 collateralAmount, uint256 requestedCreditLimit) external;
    function processPurchase(uint256 cardId, uint256 amount, address merchant, string memory category) external;
    function makePayment(uint256 cardId, uint256 amount, address paymentToken) external;
    function addCollateral(uint256 cardId, uint256 amount) external;
    function removeCollateral(uint256 cardId, uint256 amount) external;
    function getCardDetails(uint256 cardId) external view returns (CreditCard memory);
    function calculateHealthFactor(uint256 cardId) external view returns (uint256);
}

/**
 * @title IGovernanceToken
 * @dev Interface for governance token contract
 */
interface IGovernanceToken {
    function mint(address to, uint256 amount) external;
    function createVestingSchedule(
        address beneficiary,
        uint256 amount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration,
        bool revocable
    ) external;
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function claimStakingRewards() external;
    function pendingStakingRewards(address user) external view returns (uint256);
}