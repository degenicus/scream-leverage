async function main() {
  const Vault = await ethers.getContractFactory('ReaperVaultv1_3');

  //const usdcAddress = "0x04068da6c83afcfa0e13ba15a6696662335d5b75";
  //const fUSDTAddress = "0x049d68029688eabf473097a2fc38ef61633a3c7a";
  const linkAddress = '0xb3654dc3d10ea7645f8319668e8f54d2574fbdc8';
  const tokenName = 'LINK SCREAM Single Sided';
  const tokenSymbol = 'rf-scLINK';
  const depositFee = 0;
  const tvlCap = ethers.utils.parseEther('2000');

  const vault = await Vault.deploy(linkAddress, tokenName, tokenSymbol, depositFee, tvlCap);

  await vault.deployed();
  console.log('Vault deployed to:', vault.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
