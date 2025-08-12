// scripts/deploy-lending-pool.ts
import { ethers } from "hardhat";

async function main() {
  console.log("🚀 Deploying LendingPool...");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const LSTBTC_TOKEN = process.env.LSTBTC_TOKEN
  const PRICE_ORACLE = process.env.PRICE_ORACLE
  const FEE_RECIPIENT = deployer.address;
  const LIQUIDATION_BOT = deployer.address; 
  const OWNER = deployer.address;

  const LendingPool = await ethers.getContractFactory("LendingPool");
  const lendingPool = await LendingPool.deploy(
    LSTBTC_TOKEN,
    PRICE_ORACLE,
    FEE_RECIPIENT,
    LIQUIDATION_BOT,
    OWNER
  );

  await lendingPool.waitForDeployment();
  const address = await lendingPool.getAddress();

  console.log("✅ LendingPool deployed to:", address);
  console.log("📄 Constructor args:", [LSTBTC_TOKEN, PRICE_ORACLE, FEE_RECIPIENT, LIQUIDATION_BOT, OWNER]);

  // Save deployment info
  const deploymentInfo = {
    contract: "LendingPool",
    address: address,
    deployer: deployer.address,
    constructorArgs: [LSTBTC_TOKEN, PRICE_ORACLE, FEE_RECIPIENT, LIQUIDATION_BOT, OWNER],
    network: (await ethers.provider.getNetwork()).name,
    blockNumber: await ethers.provider.getBlockNumber(),
    timestamp: new Date().toISOString()
  };

  console.log("💾 Deployment info:", JSON.stringify(deploymentInfo, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
