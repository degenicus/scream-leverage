async function main() {
  const vaultAddress = '0x4a77fff08F2e935E5953F925968ecf695080a729';
  const ERC20 = await ethers.getContractFactory('contracts/ERC20.sol:ERC20');
  //const fUSDTAddress = '0x049d68029688eabf473097a2fc38ef61633a3c7a';
  const wftmAddress = '0x21be370d5312f44cb42ce377bc9b8a0cef1a4c83';
  const erc20 = await ERC20.attach(wftmAddress);
  await erc20.approve(vaultAddress, ethers.utils.parseEther('1000'));
  console.log('wftm approved');
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
