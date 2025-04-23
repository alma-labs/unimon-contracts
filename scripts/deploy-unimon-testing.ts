import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  const UnimonTesting = await ethers.getContractFactory("UnimonTesting");
  const unimonTesting = await UnimonTesting.deploy(deployer.address);
  await unimonTesting.waitForDeployment();

  const address = await unimonTesting.getAddress();
  console.log("UnimonTesting deployed to:", address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 