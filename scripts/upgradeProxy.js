async function main() {
  const dolaProxy = '0x3f831a885b3d032510BD29d30615dE6794fE9614';
  const stratFactory = await ethers.getContractFactory('ReaperAutoCompoundScreamLeverage');
  const options = { gasPrice: 1500000000000, gasLimit: 15000000, call: { fn: 'clearUpgradeCooldown' } };
  const stratContract = await hre.upgrades.upgradeProxy(dolaProxy, stratFactory, options);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
