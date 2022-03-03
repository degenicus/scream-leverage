async function main() {
  const vaultAddress = '0xE56998F7C797577b44B067e6f3F2f3eBD34c3b16';
  const strategyAddress = '0xdd9D8D594d73eB2638B8FDd9311cc9f58b572202';

  const Vault = await ethers.getContractFactory('ReaperVaultv1_3');
  const vault = Vault.attach(vaultAddress);

  const options = { gasPrice: 600000000000, gasLimit: 9000000 };
  await vault.initialize(strategyAddress, options);
  console.log('Vault initialized');
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
