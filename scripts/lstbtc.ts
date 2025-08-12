// scripts/deploy-lstbtc-token.ts
import { ethers } from "hardhat";

async function main() {
  console.log("🚀 Deploying lstBTC Token...");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

 const BTC_TOKEN = process.env.BTC_TOKEN
  const PRICE_ORACLE = process.env.PRICE_ORACLE
  const OWNER = deployer.address;

  const LstBTCToken = await ethers.getContractFactory("LstBTCToken");
  const lstBTCToken = await LstBTCToken.deploy(
    BTC_TOKEN,
    PRICE_ORACLE,
    OWNER
  );

  await lstBTCToken.waitForDeployment();
  const address = await lstBTCToken.getAddress();

  console.log("✅ lstBTC Token deployed to:", address);
  console.log("📄 Constructor args:", [BTC_TOKEN, PRICE_ORACLE, OWNER]);

  // Get some info about the deployed token
  const name = await lstBTCToken.name();
  const symbol = await lstBTCToken.symbol();
  const decimals = await lstBTCToken.decimals();
  const exchangeRate = await lstBTCToken.getExchangeRate();
  const yieldInfo = await lstBTCToken.getYieldInfo();

  console.log(`📊 Token Info:`);
  console.log(`   Name: ${name}`);
  console.log(`   Symbol: ${symbol}`);
  console.log(`   Decimals: ${decimals}`);
  console.log(`   Exchange Rate: ${ethers.formatEther(exchangeRate)}`);
  console.log(`   Yield Rate: ${yieldInfo.currentYieldRate} basis points (${Number(yieldInfo.currentYieldRate) / 100}%)`);

  // Save deployment info
  const deploymentInfo = {
    contract: "LstBTCToken",
    address: address,
    deployer: deployer.address,
    constructorArgs: [BTC_TOKEN, PRICE_ORACLE, OWNER],
    network: (await ethers.provider.getNetwork()).name,
    blockNumber: await ethers.provider.getBlockNumber(),
    timestamp: new Date().toISOString(),
    tokenInfo: {
      name,
      symbol,
      decimals,
      exchangeRate: exchangeRate.toString(),
      yieldRate: yieldInfo.currentYieldRate.toString()
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