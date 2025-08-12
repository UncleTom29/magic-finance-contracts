// scripts/deploy-btc-token.ts
import { ethers } from "hardhat";

async function main() {

  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));
  const bitcoinToken= "0x734F53765a9eEe59A4509a71C75fa15FAF73184C"
  const usdtToken= "0x68f041e183E49CD644362938C477b7e5cd7b32C0"
  const usdcToken= "0x5daD757B8D3caDEc9cfD99e74766573176C1eAC2"
  const coreToken= "0xe730899a822497909eFA7d51CE1f580Ed04a9F39"


   console.log("\n3️⃣  Deploying Rewards Distributor...");
        const RewardsDistributor = await ethers.getContractFactory("RewardsDistributor");
        const rewardsDistributor = await RewardsDistributor.deploy(
            bitcoinToken,
            usdtToken,
            usdcToken,
            coreToken,
            deployer.address,
            deployer.address
        );
        await rewardsDistributor.waitForDeployment();
        const rewardsAddress = await rewardsDistributor.getAddress();
        console.log("✅ Rewards Distributor deployed at:", rewardsAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });