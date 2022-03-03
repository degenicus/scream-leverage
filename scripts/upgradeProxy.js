const mimProxy = '0x7340d1F5F5C4f6a72F2cAbE7881e5DdeFEA707fF';
const mimVault = '0xCA55757854222d8232a19EC8Aae336594eE3b5E5';
const options = { gasPrice: 1000000000000 };
const targetLTV = ethers.utils.parseEther('0.72');

const getStrategy = async () => {
  const Strategy = await ethers.getContractFactory('ReaperAutoCompoundScreamLeverage');
  const strategy = Strategy.attach(mimProxy);
  return strategy;
};

const getVault = async () => {
  const Vault = await ethers.getContractFactory('ReaperVaultv1_3');
  return Vault.attach(mimVault);
}

const upgradeProxy = async () => {
  const stratFactory = await ethers.getContractFactory('ReaperAutoCompoundScreamLeverage');
  await hre.upgrades.upgradeProxy(mimProxy, stratFactory, { ...options, timeout: 0 });
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
