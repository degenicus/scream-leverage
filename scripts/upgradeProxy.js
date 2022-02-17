async function main() {
  //const fUSDTProxy = '0x512A00B3BbC54BAeefcf2FbD82E082E04bc5dffd';
  const fraxProxy = '0x2a4a7B7AC87a416aE83772fEd196259A5fd47C63';
  const stratFactory = await ethers.getContractFactory('ReaperAutoCompoundScreamLeverage');
  const stratContract = await hre.upgrades.upgradeProxy(fraxProxy, stratFactory);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
