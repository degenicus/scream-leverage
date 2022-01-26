async function main() {
  const vaultAddress = '0xC2cE269f3646a5F5bF1cCDa73c6cAB50f64012b6';
  const strategyAddress = '0xb2C1De1f7f03054BDCbeC35f9f8370C09719fF1D';

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
