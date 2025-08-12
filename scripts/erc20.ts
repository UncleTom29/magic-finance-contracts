// scripts/deploy-btc-token.ts
import { ethers } from "hardhat";

async function main() {

  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));


  const PRICE_ORACLE = process.env.PRICE_ORACLE
  const FEE_RECIPIENT = deployer.address;

  // Deploy CORE Token
        console.log("📄 Deploying CORE Token...");
        const CoreToken = await ethers.getContractFactory("CoreToken");
        const coreToken = await CoreToken.deploy(
            PRICE_ORACLE,
            FEE_RECIPIENT,
            deployer.address
        );
        await coreToken.waitForDeployment();
      const coreAddress = await coreToken.getAddress();
        console.log("✅ CORE Token deployed at:", coreAddress);
        
        
        // Deploy USDT Token
        console.log("📄 Deploying USDT Token...");
        const USDTToken = await ethers.getContractFactory("USDTToken");
        const usdtToken = await USDTToken.deploy(
            PRICE_ORACLE,
            FEE_RECIPIENT,
            deployer.address
        );
        await usdtToken.waitForDeployment();
       const usdtAddress = await usdtToken.getAddress();
        console.log("✅ USDT Token deployed at:", usdtAddress);
        
        // Deploy USDC Token
        console.log("📄 Deploying USDC Token...");
        const USDCToken = await ethers.getContractFactory("USDCToken");
        const usdcToken = await USDCToken.deploy(
            PRICE_ORACLE,
            FEE_RECIPIENT,
            deployer.address
        );
        await usdcToken.waitForDeployment();
        const usdcAddress = await usdcToken.getAddress();
        console.log("✅ USDC Token deployed at:", usdcAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });