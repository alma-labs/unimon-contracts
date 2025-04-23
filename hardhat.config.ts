import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import * as dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.26",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
    },
  },
  paths: {
    sources: "contracts",
    tests: "test",
    cache: "./hardhat/cache",
    artifacts: "./hardhat/artifacts"
  },
  networks: {
    unichain: {
      url: "https://mainnet.unichain.org",
      accounts: process.env.DEPLOYER_KEY ? [process.env.DEPLOYER_KEY] : [],
    },
  },
  etherscan: {
    apiKey: {
      unichain: process.env.UNICHAIN_API_KEY || "",
    },
    customChains: [
      {
        network: "unichain",
        chainId: 130,
        urls: {
          apiURL: "https://api.uniscan.xyz/api",
          browserURL: "https://uniscan.xyz",
        },
      },
    ],
  },
  sourcify: {
    enabled: false,
  },
};

export default config;
