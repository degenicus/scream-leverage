async function main() {
  const vaultAddress = '0x9e18D17F982824CDaaca7B03111F5ea6a0839BfD';
  const strategyAddress = '0xf414e03A3dEB50c9D1Eb728a40D259830bc4C03A';

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
