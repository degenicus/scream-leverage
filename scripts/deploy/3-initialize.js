async function main() {
  const vaultAddress = '0x4a77fff08F2e935E5953F925968ecf695080a729';
  const strategyAddress = '0xDcCf355BCeB10607856847733b1055b47af4A751';

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
