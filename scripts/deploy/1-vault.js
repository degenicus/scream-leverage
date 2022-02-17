async function main() {
  const Vault = await ethers.getContractFactory('ReaperVaultv1_3');

  const usdcAddress = '0x04068da6c83afcfa0e13ba15a6696662335d5b75';
  const tokenName = 'USDC SCREAM Single Sided';
  const tokenSymbol = 'rf-scUSDC';
  const depositFee = 0;
  const tvlCap = ethers.utils.parseEther('40000');

  const vault = await Vault.deploy(usdcAddress, tokenName, tokenSymbol, depositFee, tvlCap);

  await vault.deployed();
  console.log('Vault deployed to:', vault.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
