async function main() {
  const Vault = await ethers.getContractFactory('ReaperVaultv1_3');

  //const usdcAddress = "0x04068da6c83afcfa0e13ba15a6696662335d5b75";
  //const fUSDTAddress = "0x049d68029688eabf473097a2fc38ef61633a3c7a";
  const wftmAddress = '0x21be370d5312f44cb42ce377bc9b8a0cef1a4c83';
  const tokenName = 'WFTM SCREAM Single Sided';
  const tokenSymbol = 'rf-scWFTM';
  const depositFee = 0;
  const tvlCap = ethers.utils.parseEther('20000');

  const vault = await Vault.deploy(wftmAddress, tokenName, tokenSymbol, depositFee, tvlCap);

  await vault.deployed();
  console.log('Vault deployed to:', vault.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
