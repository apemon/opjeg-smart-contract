const hre = require("hardhat");

async function main() {

  const nftAddress = '0xb4d06d46a8285f4ec79fd294f78a881799d8ced9' // 3Landers
  const nftName = '3Landers'
  const [signer] = await hre.ethers.getSigners()
  const Opjeg = await hre.ethers.getContractFactory("OPJEGv2");
  const opjeg = await Opjeg.deploy(nftName, nftAddress);

  await opjeg.deployed();

  console.log("Deploying contracts with the account:", signer.address);
  console.log("opjeg deployed to:", opjeg.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
