async function main() {
  const vaultAddress = '0x787C8Bf872D0Df6b9A445615dF2F63a2301722E0';
  const strategyAddress = '0xef998B0088701aF7D301d7DFC667cD9450abD511';

  const Vault = await ethers.getContractFactory('ReaperVaultv1_3');
  const vault = Vault.attach(vaultAddress);
  const options = { gasPrice: 250000000000, gasLimit: 9000000 };

  await vault.initialize(strategyAddress, options);
  console.log('Vault initialized');
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
