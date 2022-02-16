async function main() {
  const vaultAddress = '0x34ffdF13Daf7e4379F06e5cA6F0E7FDa558A9dd1';
  const strategyAddress = '0x3f831a885b3d032510BD29d30615dE6794fE9614';

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
