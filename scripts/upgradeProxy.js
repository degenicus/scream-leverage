async function main() {
  const fUSDTProxy = '0x512A00B3BbC54BAeefcf2FbD82E082E04bc5dffd';
  const stratFactory = await ethers.getContractFactory('ReaperAutoCompoundScreamLeverage');
  const stratContract = await hre.upgrades.upgradeProxy(fUSDTProxy, stratFactory);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
