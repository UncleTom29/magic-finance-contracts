# Magic Finance 🪄₿

> **Bitcoin-Backed DeFi Neobank on Core DAO**

Magic Finance transforms idle Bitcoin into a productive, spendable asset through liquid staking, overcollateralized lending, and seamless payment integration—all secured by Core DAO's Bitcoin infrastructure.

[![Core DAO](https://img.shields.io/badge/Built%20on-Core%20DAO-orange)](https://coredao.org)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-blue)](https://soliditylang.org/)
[![Hardhat](https://img.shields.io/badge/Framework-Hardhat-yellow)](https://hardhat.org/)
[![License](https://img.shields.io/badge/License-MIT-green)](./LICENSE)

## 🎯 Overview

Magic Finance is a comprehensive Bitcoin-backed DeFi neobank that enables users to:

- **💰 Stake BTC** → Earn yield through lstBTC liquid staking tokens
- **🏦 Borrow Stablecoins** → Access liquidity without selling Bitcoin
- **💳 Spend Seamlessly** → Bitcoin-backed credit cards for everyday transactions
- **📊 Unified Management** → Single dashboard for all Bitcoin DeFi activities

### 🌟 Core Innovation

Magic Finance bridges the gap between Bitcoin's store-of-value nature and DeFi's utility, creating the first true **Bitcoin neobank experience** on Core DAO.

---

## 🏗️ Architecture

### Smart Contract Ecosystem

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   MagicVault    │────│   lstBTC Token  │────│  LendingPool    │
│                 │    │                 │    │                 │
│ • BTC Staking   │    │ • Yield Bearing │    │ • Overcollat.   │
│ • lstBTC Mint   │    │ • 1:1 Redeemable│    │ • Liquidations  │
│ • 4 Vault Types │    │ • Price Oracles │    │ • Multi-asset   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ CreditFacility  │────│  PriceOracle    │────│RewardsDistributor│
│                 │    │                 │    │                 │
│ • BTC-backed CC │    │ • Pyth Network  │    │ • Yield Distrib.│
│ • Spending Mgmt │    │ • Multi-asset   │    │ • Staking Pools │
│ • Auto-payments │    │ • Circuit Break │    │ • Fee Management│
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### 🔧 Core Components

| Contract | Purpose | Key Features |
|----------|---------|--------------|
| **MagicVault** | BTC Staking & lstBTC Minting | 4 staking periods, yield optimization, liquid staking |
| **lstBTC Token** | Liquid Staked Bitcoin | Yield accrual, 1:1 redeemability, price oracle integration |
| **LendingPool** | Overcollateralized Lending | Multi-asset support, liquidation engine, dynamic rates |
| **CreditFacility** | Bitcoin Credit Cards | Spending limits, auto-payments, collateral management |
| **PriceOracle** | Pyth Network Integration | Multi-asset prices, circuit breakers, staleness checks |
| **RewardsDistributor** | Yield Distribution | Multi-pool rewards, staking positions, fee management |

---

## 🚀 Deployed Contracts (Core Testnet)

| Contract | Address | Explorer |
|----------|---------|----------|
| **Credit Facility** | `0x4Af4eA278DE08529ce1F77e8561ef4f1B985Aec3` | [View →](https://scan.test2.btcs.network/address/0x4Af4eA278DE08529ce1F77e8561ef4f1B985Aec3) |
| **Magic Vault** | `0x1D7f1713eE2732648264f6f52c087D5eE871F674` | [View →](https://scan.test2.btcs.network/address/0x1D7f1713eE2732648264f6f52c087D5eE871F674) |
| **lstBTC Token** | `0xF1853bbC4456ae6d95d3526211bf7c465c8C1058` | [View →](https://scan.test2.btcs.network/address/0xF1853bbC4456ae6d95d3526211bf7c465c8C1058) |
| **Lending Pool** | `0xe9b76d5Ff7b523aE313641e68260c6cd85CAFB7b` | [View →](https://scan.test2.btcs.network/address/0xe9b76d5Ff7b523aE313641e68260c6cd85CAFB7b) |
| **Price Oracle** | `0xcE48924fE33B1dCD0c4CFbB3Cc99149a18CA439E` | [View →](https://scan.test2.btcs.network/address/0xcE48924fE33B1dCD0c4CFbB3Cc99149a18CA439E) |
| **BTC Token** | `0x734F53765a9eEe59A4509a71C75fa15FAF73184C` | [View →](https://scan.test2.btcs.network/address/0x734F53765a9eEe59A4509a71C75fa15FAF73184C) |
| **USDT Token** | `0x68f041e183E49CD644362938C477b7e5cd7b32C0` | [View →](https://scan.test2.btcs.network/address/0x68f041e183E49CD644362938C477b7e5cd7b32C0) |
| **USDC Token** | `0x5daD757B8D3caDEc9cfD99e74766573176C1eAC2` | [View →](https://scan.test2.btcs.network/address/0x5daD757B8D3caDEc9cfD99e74766573176C1eAC2) |
| **CORE Token** | `0xe730899a822497909eFA7d51CE1f580Ed04a9F39` | [View →](https://scan.test2.btcs.network/address/0xe730899a822497909eFA7d51CE1f580Ed04a9F39) |

---

## 🛠️ Prerequisites

Before running Magic Finance locally, ensure you have:

### Required Software
- **Node.js** >= 16.0.0
- **npm** or **yarn**
- **Git**

### Development Tools
- **Hardhat** (included in dependencies)
- **TypeScript** support
- **Core DAO RPC** access

### External Dependencies
- **Pyth Network** price feeds
- **Core Testnet** CORE tokens for gas
- **MetaMask** or compatible wallet

---

## 🏁 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/UncleTom29/magic-finance-contracts.git
cd magic-finance-contracts
```

### 2. Install Dependencies

```bash
npm install
# or
yarn install
```

### 3. Environment Configuration

Create a `.env` file in the root directory:

```bash
# Copy the example environment file
cp .env.example .env
```

Configure your `.env` file:

```bash
# Private key for deployment (never commit this!)
PRIVATE_KEY=your_private_key_here

# Core Testnet Configuration
CORE_TESTNET_RPC=https://rpc.test2.btcs.network
CORE_TESTNET_CHAIN_ID=1114

# Contract Addresses (auto-populated after deployment)
PRICE_ORACLE=0xcE48924fE33B1dCD0c4CFbB3Cc99149a18CA439E
BTC_TOKEN=0x734F53765a9eEe59A4509a71C75fa15FAF73184C
LSTBTC_TOKEN=0xF1853bbC4456ae6d95d3526211bf7c465c8C1058
MAGIC_VAULT=0x1D7f1713eE2732648264f6f52c087D5eE871F674
REWARDS_DISTRIBUTOR=0x[RewardsDistributor_Address]

# Optional: Report gas usage
REPORT_GAS=true
```

### 4. Get Core Testnet Tokens

Visit the [Core DAO Faucet](https://scan.test2.btcs.network/faucet) to get testnet CORE tokens for gas fees.

---

## 🧪 Development Workflow

### Compile Contracts

```bash
npm run compile
# or
npx hardhat compile
```

### Run Tests

```bash
npm run test
# or
npx hardhat test
```

### Deploy to Core Testnet

Deploy individual contracts:

```bash
# Deploy Price Oracle first
npm run deploy:oracle

# Deploy BTC Token
npm run deploy:btc

# Deploy lstBTC Token
npm run deploy:lstbtc

# Deploy Rewards Distributor
npm run deploy:rewards

# Deploy Magic Vault
npm run deploy:vault

# Deploy Lending Pool
npm run deploy:lending

# Deploy Credit Facility
npm run deploy:credit
```

Or use the deployment scripts directly:

```bash
npx hardhat run scripts/priceOracle.ts --network coreTestnet
npx hardhat run scripts/btc.ts --network coreTestnet
npx hardhat run scripts/lstbtc.ts --network coreTestnet
npx hardhat run scripts/reward.ts --network coreTestnet
npx hardhat run scripts/magicVault.ts --network coreTestnet
npx hardhat run scripts/lendingPool.ts --network coreTestnet
npx hardhat run scripts/creditFacility.ts --network coreTestnet
```

### Local Development

Start a local Hardhat network:

```bash
npx hardhat node
```

Deploy to local network:

```bash
npx hardhat run scripts/deploy-all.ts --network localhost
```

---

## 📋 Available Scripts

| Script | Command | Description |
|--------|---------|-------------|
| **Compile** | `npm run compile` | Compile all smart contracts |
| **Test** | `npm run test` | Run contract tests |
| **Deploy Oracle** | `npm run deploy:oracle` | Deploy PriceOracle contract |
| **Deploy BTC** | `npm run deploy:btc` | Deploy BTC token contract |
| **Deploy lstBTC** | `npm run deploy:lstbtc` | Deploy lstBTC token contract |
| **Deploy Vault** | `npm run deploy:vault` | Deploy MagicVault contract |
| **Deploy Lending** | `npm run deploy:lending` | Deploy LendingPool contract |
| **Deploy Credit** | `npm run deploy:credit` | Deploy CreditFacility contract |
| **Deploy Rewards** | `npm run deploy:rewards` | Deploy RewardsDistributor contract |
| **Verify** | `npm run verify` | Verify contracts on Core scan |

---

## 🔧 Network Configuration

### Core Testnet
```javascript
networks: {
  coreTestnet: {
    url: "https://rpc.test2.btcs.network",
    chainId: 1114,
    accounts: [PRIVATE_KEY],
    gasPrice: 10000000000, // 10 gwei
  }
}
```

### Supported Networks
- **Core Testnet** (Primary)
- **Core Mainnet** (Future)
- **Local Hardhat** (Development)

---

## 🏦 How Magic Finance Works

### 1. **BTC Vault + Liquid Staking**
Users deposit BTC into the Magic Vault, which converts deposits into **lstBTC**—a liquid staking token that earns native Bitcoin staking rewards while remaining fully liquid.

```solidity
// Stake BTC for yield
function stake(uint256 amount, uint8 vaultType) external {
    // 4 vault types: flexible, 30-day, 90-day, 365-day
    // Higher APY for longer lock periods
}
```

### 2. **Borrowing Without Selling**
lstBTC serves as collateral to borrow stablecoins (USDT, USDC), offering instant liquidity without triggering taxable events or losing BTC exposure.

```solidity
// Borrow stablecoins against lstBTC collateral
function borrow(address asset, uint256 amount, uint256 collateralAmount) external {
    // Up to 80% LTV ratio
    // Dynamic interest rates
    // Automatic liquidation protection
}
```

### 3. **Credit Card Integration**
Users can seamlessly spend BTC or borrowed stablecoins via virtual/physical credit cards, turning Bitcoin into a spendable currency for everyday use.

```solidity
// Issue BTC-backed credit card
function issueCard(uint256 collateralAmount, uint256 creditLimit) external {
    // lstBTC collateral backing
    // Flexible payment sources
    // Real-time spending controls
}
```

### 4. **Liquidity Automation**
Behind the scenes, Magic Finance manages liquidity routing between BTC staking yield, borrowing markets, and spending needs while maintaining optimal collateral ratios.

---

## 🎯 Key Features

### ✅ **BTC-Backed Neobank**
Complete financial ecosystem combining yield generation, borrowing, and seamless payments in a single platform.

### ✅ **lstBTC Integration**
Converts idle BTC into yield-bearing assets without compromising liquidity or security.

### ✅ **Core Blockchain Advantage**
Leverages Core's BTC staking, Satoshi Plus consensus, and native ecosystem integration.

### ✅ **Secure Collateral Management**
BTC collateral is cryptographically verified with trusted Pyth Network oracles.

### ✅ **Transparent Interest Model**
Algorithmic interest rates based on market utilization and real-time collateral health.

---

## 🔍 Contract Interactions

### MagicVault Operations

```javascript
// Stake BTC in flexible vault (5.2% APY)
await magicVault.stake(ethers.parseEther("1"), 0);

// Check pending rewards
const rewards = await magicVault.calculatePendingRewards(userAddress, positionId);

// Unstake position
await magicVault.unstake(positionId);
```

### Lending Pool Operations

```javascript
// Borrow USDT against lstBTC
await lendingPool.borrow(
  usdtAddress, 
  ethers.parseEther("1000"), 
  ethers.parseEther("0.5")
);

// Repay loan
await lendingPool.repay(loanId, ethers.parseEther("500"));

// Check health factor
const healthFactor = await lendingPool.calculateHealthFactor(userAddress);
```

### Credit Card Operations

```javascript
// Issue new credit card
await creditFacility.issueCard(
  ethers.parseEther("2"), // 2 lstBTC collateral
  ethers.parseEther("5000") // $5000 credit limit
);

// Process purchase
await creditFacility.processPurchase(
  cardId,
  ethers.parseEther("100"),
  merchantAddress,
  "dining"
);
```

---

## 🧮 Vault Types & APY

| Vault Type | Lock Period | APY Rate | Min. Stake |
|------------|-------------|----------|------------|
| **Flexible** | No lock | 5.2% | 0.001 BTC |
| **30-day** | 30 days | 6.8% | 0.01 BTC |
| **90-day** | 90 days | 8.5% | 0.01 BTC |
| **365-day** | 365 days | 12.3% | 0.1 BTC |

---

## 🔐 Security Features

### Smart Contract Security
- **OpenZeppelin** standard libraries
- **Reentrancy** protection
- **Pausable** emergency controls
- **Access control** with role-based permissions

### Oracle Security
- **Pyth Network** price feeds
- **Circuit breaker** for extreme price movements
- **Staleness checks** for price freshness
- **Confidence interval** validation

### Collateral Security
- **Real-time** health factor monitoring
- **Liquidation** protection mechanisms
- **Multi-asset** collateral support
- **Dynamic LTV** adjustments

---

## 📚 Resources

### Documentation
- [Hardhat Documentation](https://hardhat.org/docs)
- [Core DAO Developer Docs](https://docs.coredao.org/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- [Pyth Network](https://pyth.network/developers)

### Core DAO Ecosystem
- [Core DAO Website](https://coredao.org/)
- [Core Scan Explorer](https://scan.test2.btcs.network/)
- [Core DAO Faucet](https://scan.test2.btcs.network/faucet)
- [Core DAO Discord](https://discord.gg/coredaoofficial)

---

## 🐛 Troubleshooting

### Common Issues

**❌ "insufficient funds for intrinsic transaction cost"**
- Get testnet CORE tokens from the [faucet](https://scan.test2.btcs.network/faucet)

**❌ "nonce too high"**
- Reset MetaMask account: Settings → Advanced → Reset Account

**❌ "contract not deployed"**
- Check contract addresses in `.env` file
- Ensure you're connected to Core Testnet (Chain ID: 1114)

**❌ "price oracle failed"**
- Pyth Network integration requires proper price feed IDs
- Check oracle contract deployment and configuration

### Getting Help
- Create an [Issue](https://github.com/UncleTom29/magic-finance-contracts/issues)
- Join [Core DAO Discord](https://discord.gg/coredaoofficial)
- Contact [@UncleTom29](https://github.com/UncleTom29)

---

## 📜 License

This project is licensed under the **MIT License** - see the [LICENSE](./LICENSE) file for details.

---

## 🏆 Hackathon Submission

**Magic Finance** is proudly submitted to the **Core DAO Hackathon** as a groundbreaking Bitcoin-backed DeFi neobank that showcases:

- **Deep Core Integration** with BTC staking and native ecosystem
- **Technical Innovation** in liquid staking and cross-chain Bitcoin DeFi
- **Real-world Utility** through credit card integration and seamless UX
- **Economic Impact** by driving TVL and user activity to Core DAO

**Built with ❤️ on Core DAO**

---

## 📞 Contact & Support

- **GitHub:** [@UncleTom29](https://github.com/UncleTom29)
- **Project Repository:** [magic-finance-contracts](https://github.com/UncleTom29/magic-finance-contracts)
- **Core Testnet Explorer:** [Contract Addresses](#-deployed-contracts-core-testnet)

---

*Magic Finance - Transforming Bitcoin into the ultimate DeFi experience on Core DAO* ✨