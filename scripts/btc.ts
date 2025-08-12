// scripts/deploy-btc-token.ts
import { ethers } from "hardhat";

async function main() {
  console.log("🚀 Deploying BTC Token...");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  
  const PRICE_ORACLE = process.env.PRICE_ORACLE; 
  const FEE_RECIPIENT = deployer.address;
  const OWNER = deployer.address;

  const BTCToken = await ethers.getContractFactory("BTCToken");
  const btcToken = await BTCToken.deploy(
    PRICE_ORACLE,
    FEE_RECIPIENT,
    OWNER
  );

  await btcToken.waitForDeployment();
  const address = await btcToken.getAddress();

  console.log("✅ BTC Token deployed to:", address);
  console.log("📄 Constructor args:", [PRICE_ORACLE, FEE_RECIPIENT, OWNER]);

  // Get some info about the deployed token
  const name = await btcToken.name();
  const symbol = await btcToken.symbol();
  const decimals = await btcToken.decimals();
  const maxSupply = await btcToken.MAX_SUPPLY();

  console.log(`📊 Token Info:`);
  console.log(`   Name: ${name}`);
  console.log(`   Symbol: ${symbol}`);
  console.log(`   Decimals: ${decimals}`);
  console.log(`   Max Supply: ${ethers.formatUnits(maxSupply, decimals)} BTC`);

  // Save deployment info
  const deploymentInfo = {
    contract: "BTCToken",
    address: address,
    deployer: deployer.address,
    constructorArgs: [PRICE_ORACLE, FEE_RECIPIENT, OWNER],
    network: (await ethers.provider.getNetwork()).name,
    blockNumber: await ethers.provider.getBlockNumber(),
    timestamp: new Date().toISOString(),
    tokenInfo: {
      name,
      symbol,
      decimals,
      maxSupply: maxSupply.toString()
    }
  };

  console.log("💾 Deployment info:", JSON.stringify(deploymentInfo, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });