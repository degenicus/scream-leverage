async function main() {
  const vaultAddress = '0xF5D9B1fb7B973eCA04DdB49c5D9A61a43D972e59';
  const strategyAddress = '0x0A7a9E16AAE33124bF29979e13d8E0fa94639334';

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
