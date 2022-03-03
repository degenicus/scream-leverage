const daiProxy = '0x9CF36ffC181fc70882EC8c05eBfeB4Bd45fb4B67';
const daiVault = '0x85ea7Ee24204B3DFEEA5d28b3Fd791D8fD1409b8';
const options = { gasPrice: 1000000000000 };
const targetLTV = ethers.utils.parseEther('0.72');

const getStrategy = async () => {
  const Strategy = await ethers.getContractFactory('ReaperAutoCompoundScreamLeverage');
  const strategy = Strategy.attach(daiProxy);
  return strategy;
};

const getVault = async () => {
  const Vault = await ethers.getContractFactory('ReaperVaultv1_3');
  return Vault.attach(daiVault);
};

const upgradeProxy = async () => {
  const stratFactory = await ethers.getContractFactory('ReaperAutoCompoundScreamLeverage');
  await hre.upgrades.upgradeProxy(daiProxy, stratFactory, { ...options, timeout: 0 });
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

const earn = async () => {
  const vault = await getVault();
  await vault.earn();
  console.log('earn');
};

async function main() {
  // await upgradeProxy();
  // await clearUpgradeCooldown();
  // await setSlippage();
  // await setTargetLTV();
  // await unpause();
  await earn();
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
