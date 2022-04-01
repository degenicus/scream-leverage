const tusdProxy = '0x175D6eF56e2F5335D5d8f37C5c580CA438f83e9f';
const options = { gasPrice: 1000000000000 };

const getVault = async () => {
  const vaultAddress = '0xbD81110596651c1B00B6A7d9D93e8831E227Eae9';
  const Vault = await ethers.getContractFactory('ReaperVaultv1_3');
  const vault = Vault.attach(vaultAddress);
  return vault;
};

const getStrategy = async () => {
  const Strategy = await ethers.getContractFactory('ReaperAutoCompoundScreamLeverage');
  const strategy = Strategy.attach(tusdProxy);
  return strategy;
};

const upgradeProxy = async () => {
  const stratFactory = await ethers.getContractFactory('ReaperAutoCompoundScreamLeverage');
  await hre.upgrades.upgradeProxy(tusdProxy, stratFactory, { ...options, timeout: 0 });
  console.log('upgradeProxy');
};

const clearUpgradeCooldown = async () => {
  const strategy = await getStrategy();
  await strategy.clearUpgradeCooldown(options);
  console.log('clearUpgradeCooldown');
};

const setSlippage = async () => {
  const strategy = await getStrategy();
  await strategy.setWithdrawSlippageTolerance(50, options);
  console.log('setSlippage');
};

const unpause = async () => {
  const strategy = await getStrategy();
  await strategy.unpause(options);
  console.log('unpause');
};

const setTargetLTV = async () => {
  const strategy = await getStrategy();
  await strategy.setTargetLtv(ethers.utils.parseEther('0.72', options));
  console.log('setTargetLTV');
};

const earn = async () => {
  const vault = await getVault(options);
  await vault.earn();
  console.log('earn');
};

async function main() {
  //await upgradeProxy();
  //await clearUpgradeCooldown();
  //await setSlippage();
  //await setTargetLTV();
  //await unpause();
  await earn();
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
