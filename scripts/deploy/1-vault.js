async function main() {
  const Vault = await ethers.getContractFactory('ReaperVaultv1_3');

  const ustAddress = '0x846e4D51d7E2043C1a87E0Ab7490B93FB940357b';
  const tokenName = 'UST SCREAM Single Sided';
  const tokenSymbol = 'rfUST';
  const depositFee = 0;
  const tvlCap = 5000 * 10 ** 6;
  const options = { gasPrice: 330000000000, gasLimit: 9000000 };

  const vault = await Vault.deploy(ustAddress, tokenName, tokenSymbol, depositFee, tvlCap, options);

  await vault.deployed();
  console.log('Vault deployed to:', vault.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
