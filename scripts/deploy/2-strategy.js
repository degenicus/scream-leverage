const hre = require('hardhat');

async function main() {
  const vaultAddress = '0xbD81110596651c1B00B6A7d9D93e8831E227Eae9';

  const Strategy = await ethers.getContractFactory('ReaperAutoCompoundScreamLeverage');
  const treasuryAddress = '0x0e7c5313E9BB80b654734d9b7aB1FB01468deE3b';
  const paymentSplitterAddress = '0x63cbd4134c2253041F370472c130e92daE4Ff174';
  const strategist1 = '0x1E71AEE6081f62053123140aacC7a06021D77348';
  const strategist2 = '0x81876677843D00a7D792E1617459aC2E93202576';
  const strategist3 = '0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4';
  //const scUSDC = "0xE45Ac34E528907d0A0239ab5Db507688070B20bf";
  //const scfUSDT = '0x02224765bc8d54c21bb51b0951c80315e1c263f9';
  const scTUSD = '0x789b5dbd47d7ca3799f8e9fdce01bc5e356fcdf1';

  // const options = { gasPrice: 2000000000000, gasLimit: 9000000 };

  const strategy = await hre.upgrades.deployProxy(
    Strategy,
    [vaultAddress, [treasuryAddress, paymentSplitterAddress], [strategist1, strategist2, strategist3], scTUSD],
    { kind: 'uups' },
  );
  await strategy.deployed();
  console.log('Strategy deployed to:', strategy.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
