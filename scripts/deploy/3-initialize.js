async function main() {
  const vaultAddress = '0x089fF2BaC6F5610ee3b54eF9cf13E6E196488dAB';
  const strategyAddress = '0x2a4a7B7AC87a416aE83772fEd196259A5fd47C63';

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
