const hre = require("hardhat");
const nftAbi = require('../artifacts/@openzeppelin/contracts/token/ERC721/ERC721.sol/ERC721.json')

async function main() {

  const nftAddress = '0xb4d06d46a8285f4ec79fd294f78a881799d8ced9' // 3Landers
  const nftName = '3Landers'
  const [deployer, signer] = await hre.ethers.getSigners()
  const Opjeg = await hre.ethers.getContractFactory("OPJEGv2");
  const opjeg = await Opjeg.connect(deployer).deploy(nftName, nftAddress);

  await opjeg.deployed();

  console.log("Deploying contracts with the account:", deployer.address);
  console.log("opjeg deployed to:", opjeg.address);

  // transfer some nft to signer
  await hre.network.provider.request({
    method: 'hardhat_impersonateAccount',
    params: ['0x03d15Ec11110DdA27dF907e12e7ac996841D95E4']
  })
  const o = await hre.ethers.getSigner('0x03d15Ec11110DdA27dF907e12e7ac996841D95E4')
  const nft = new hre.ethers.Contract(nftAddress, nftAbi.abi, hre.ethers.provider)
  await nft.connect(o).approve(signer.address, '2729')
  await nft.connect(signer).transferFrom(o.address,signer.address, '2729')
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
