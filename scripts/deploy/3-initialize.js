async function main() {
  const vaultAddress = '0xbD81110596651c1B00B6A7d9D93e8831E227Eae9';
  const strategyAddress = '0x175D6eF56e2F5335D5d8f37C5c580CA438f83e9f';

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
