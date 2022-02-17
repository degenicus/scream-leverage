async function main() {
  const vaultAddress = '0x5e071787abcA51fF64Dff517F0Fbbb73CF458DBE';
  const strategyAddress = '0xac8f38F40EFb46577EEfbB5abf471d1E9A454E75';

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
