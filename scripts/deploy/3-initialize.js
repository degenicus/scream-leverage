async function main() {
  const vaultAddress = '0x2B473d132ce3b652aa9Fe1f92E8c347A747D1ad8';
  const strategyAddress = '0xA0821bBa2639B46bF2dFFf5537fD4952f41Dcd0f';

  const Vault = await ethers.getContractFactory('ReaperVaultv1_3');
  const vault = Vault.attach(vaultAddress);

  //const options = { gasPrice: 2000000000000, gasLimit: 9000000 };
  await vault.initialize(strategyAddress);
  console.log('Vault initialized');
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
