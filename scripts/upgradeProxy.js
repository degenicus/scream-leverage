const linkProxy = '0x3252d1Aa08D53eb5A9f6bb5c8c41F40d899864d6';
const options = { gasPrice: 1000000000000 };
const targetLTV = ethers.utils.parseEther('0.62');

const getStrategy = async () => {
  const Strategy = await ethers.getContractFactory('ReaperAutoCompoundScreamLeverage');
  const strategy = Strategy.attach(linkProxy);
  return strategy;
};

const upgradeProxy = async () => {
  const stratFactory = await ethers.getContractFactory('ReaperAutoCompoundScreamLeverage');
  await hre.upgrades.upgradeProxy(linkProxy, stratFactory, { ...options, timeout: 0 });
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
  await strategy.setTargetLtv(targetLTV, options);
  console.log('setTargetLTV');
};

async function main() {
  //await upgradeProxy();
  //await clearUpgradeCooldown();
  //await setSlippage();
  //await setTargetLTV();
  await unpause();
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
