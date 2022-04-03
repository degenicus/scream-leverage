async function main() {
  const vaultAddress = '0x1aFEf9fDD98F05733E837228E80224d61bd01BE3';
  const strategyAddress = '0xF30BDaF0C4fd5e3b1ba98ca3e2AA1110B65B50C9';

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
