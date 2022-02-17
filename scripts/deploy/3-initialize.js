async function main() {
  const vaultAddress = '0xA9C97CA3fd524C09bd95b07d5F0E5d81614d8c8d';
  const strategyAddress = '0x6CB5d51dDDCC9ce59504e5b313C95002278DC975';

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
