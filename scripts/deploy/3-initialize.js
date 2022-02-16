async function main() {
  const vaultAddress = '0x43716d2c54d8714fB20a0FaF7fb64EDc43062A8A';
  const strategyAddress = '0x49D77552b4710bBf2F8176835e08BE885744734c';

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
