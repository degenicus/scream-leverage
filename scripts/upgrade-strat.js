async function main() {
  const vaultAddress = '0xC2cE269f3646a5F5bF1cCDa73c6cAB50f64012b6';
  const Vault = await ethers.getContractFactory('ReaperVaultv1_3');
  const vault = Vault.attach(vaultAddress);

  await vault.upgradeStrat();
  console.log('Strategy upgraded!');
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
