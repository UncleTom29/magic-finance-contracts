// scripts/deploy-credit-facility.ts
import { ethers } from "hardhat";

async function main() {
  console.log("🚀 Deploying CreditFacility...");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

 
  const LSTBTC_TOKEN = process.env.LSTBTC_TOKEN
  const PRICE_ORACLE = process.env.PRICE_ORACLE
  const MAGIC_VAULT = process.env.MAGIC_VAULT
  const PAYMENT_PROCESSOR = deployer.address; 
  const FEE_RECIPIENT = deployer.address;
  const OWNER = deployer.address;

  const CreditFacility = await ethers.getContractFactory("CreditFacility");
  const creditFacility = await CreditFacility.deploy(
    LSTBTC_TOKEN,
    PRICE_ORACLE,
    MAGIC_VAULT,
    PAYMENT_PROCESSOR,
    FEE_RECIPIENT,
    OWNER
  );

  await creditFacility.waitForDeployment();
  const address = await creditFacility.getAddress();

  console.log("✅ CreditFacility deployed to:", address);
  console.log("📄 Constructor args:", [LSTBTC_TOKEN, PRICE_ORACLE, MAGIC_VAULT, PAYMENT_PROCESSOR, FEE_RECIPIENT, OWNER]);

  // Save deployment info
  const deploymentInfo = {
    contract: "CreditFacility",
    address: address,
    deployer: deployer.address,
    constructorArgs: [LSTBTC_TOKEN, PRICE_ORACLE, MAGIC_VAULT, PAYMENT_PROCESSOR, FEE_RECIPIENT, OWNER],
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