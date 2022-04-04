async function main() {
  const vaultAddress = '0x2415EFaeEf98C62a8D71F8B2454517885B180812';
  const strategyAddress = '0x8F3b2812EDafa0D020942b1cd16b554541FfE46C';

  const Vault = await ethers.getContractFactory('ReaperVaultv1_3');
  const vault = Vault.attach(vaultAddress);
  const options = { gasPrice: 150000000000, gasLimit: 9000000 };

  await vault.initialize(strategyAddress, options);
  console.log('Vault initialized');
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
