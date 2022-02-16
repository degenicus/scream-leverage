async function main() {
  const vaultAddress = '0x085c658E0A0Ddf485A7d848b60bc09C65dbdeF60';
  const strategyAddress = '0x3252d1Aa08D53eb5A9f6bb5c8c41F40d899864d6';

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
