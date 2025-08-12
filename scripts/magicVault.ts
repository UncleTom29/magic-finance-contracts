// scripts/deploy-magic-vault.ts
import { ethers } from "hardhat";

async function main() {
  console.log("🚀 Deploying MagicVault...");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

 const BTC_TOKEN = process.env.LSTBTC_TOKEN
  const PRICE_ORACLE = process.env.PRICE_ORACLE
  const REWARDS_DISTRIBUTOR = process.env.REWARDS_DISTRIBUTOR
  const FEE_RECIPIENT = deployer.address;
  const OWNER = deployer.address;

  const MagicVault = await ethers.getContractFactory("MagicVault");
  const magicVault = await MagicVault.deploy(
    BTC_TOKEN,
    PRICE_ORACLE,
    REWARDS_DISTRIBUTOR,
    FEE_RECIPIENT,
    OWNER
  );

  await magicVault.waitForDeployment();
  const address = await magicVault.getAddress();

  console.log("✅ MagicVault deployed to:", address);
  console.log("📄 Constructor args:", [BTC_TOKEN, PRICE_ORACLE, REWARDS_DISTRIBUTOR, FEE_RECIPIENT, OWNER]);

  // Save deployment info
  const deploymentInfo = {
    contract: "MagicVault",
    address: address,
    deployer: deployer.address,
    constructorArgs: [BTC_TOKEN, PRICE_ORACLE, REWARDS_DISTRIBUTOR, FEE_RECIPIENT, OWNER],
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