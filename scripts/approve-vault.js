async function main() {
  const vaultAddress = '0x5e071787abcA51fF64Dff517F0Fbbb73CF458DBE';
  const ERC20 = await ethers.getContractFactory('contracts/ERC20.sol:ERC20');
  //const fUSDTAddress = '0x049d68029688eabf473097a2fc38ef61633a3c7a';
  const fraxAddress = '0xdc301622e621166bd8e82f2ca0a26c13ad0be355';
  const erc20 = await ERC20.attach(fraxAddress);
  const [deployer] = await ethers.getSigners();
  console.log(await erc20.allowance(deployer.address, vaultAddress));
  // await erc20.approve(vaultAddress, ethers.utils.parseEther('100'));
  // console.log('erc20 approved');
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
