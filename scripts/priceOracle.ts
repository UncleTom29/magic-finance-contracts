// scripts/deploy-price-oracle.ts
import { ethers } from "hardhat";

async function main() {
  console.log("🚀 Deploying PriceOracle...");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const PYTH_CONTRACT = "0x8D254a21b3C86D32F7179855531CE99164721933"; 
  const OWNER = deployer.address;

  const PriceOracle = await ethers.getContractFactory("PriceOracle");
  const priceOracle = await PriceOracle.deploy(PYTH_CONTRACT, OWNER);

  await priceOracle.waitForDeployment();
  const address = await priceOracle.getAddress();

  console.log("✅ PriceOracle deployed to:", address);
  console.log("📄 Constructor args:", [PYTH_CONTRACT, OWNER]);

  // Save deployment info
  const deploymentInfo = {
    contract: "PriceOracle",
    address: address,
    deployer: deployer.address,
    constructorArgs: [PYTH_CONTRACT, OWNER],
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