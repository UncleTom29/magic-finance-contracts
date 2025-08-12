import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-ignition";
import * as dotenv from "dotenv";

dotenv.config();

// Load environment variables
const PRIVATE_KEY = process.env.PRIVATE_KEY || "0000000000000000000000000000000000000000000000000000000000000000";




const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
    
  }, 
  networks: {
   
    coreTestnet: {
      url: "https://rpc.test2.btcs.network",
      gas: "auto",
      chainId: 1114,
      accounts: [PRIVATE_KEY],
      gasPrice: 10000000000, // 10 gwei
    },
    // // Local network
    // hardhat: {
    //   chainId: 31337,
    //   gas: 12000000,
    //   blockGasLimit: 12000000,
    //   allowUnlimitedContractSize: true,
    // },
    // localhost: {
    //   url: "http://127.0.0.1:8545",
    //   chainId: 31337,
    // },
  },

  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
    ignition: "./ignition",
  },
  mocha: {
    timeout: 60000,
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
};

export default config;