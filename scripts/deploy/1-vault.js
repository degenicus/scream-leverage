async function main() {
  const Vault = await ethers.getContractFactory('ReaperVaultv1_3');

  // const usdcAddress = "0x04068da6c83afcfa0e13ba15a6696662335d5b75";
  // const fUSDTAddress = "0x049d68029688eabf473097a2fc38ef61633a3c7a";
  const daiAddress = '0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E';
  const tokenName = 'DAI SCREAM Crypt';
  const tokenSymbol = 'rfDAI';
  const depositFee = 0;
  const tvlCap = ethers.constants.MaxUint256;

  const vault = await Vault.deploy(daiAddress, tokenName, tokenSymbol, depositFee, tvlCap);

  await vault.deployed();
  console.log('Vault deployed to:', vault.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
