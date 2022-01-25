const hre = require("hardhat");
const chai = require("chai");
const { solidity } = require("ethereum-waffle");
chai.use(solidity);
const { expect } = chai;

const moveTimeForward = async (seconds) => {
  await network.provider.send("evm_increaseTime", [seconds]);
  await network.provider.send("evm_mine");
};

const toEther = (num) => ethers.utils.parseEther(num);

describe("Vaults", function () {
  let Vault;
  let Strategy;
  let PaymentRouter;
  let Treasury;
  let Want;
  let vault;
  let strategy;
  let paymentRouter;
  const paymentRouterAddress = "0x603e60d22af05ff77fdcf05c063f582c40e55aae";
  let treasury;
  let want;
  const wantAddress = "0x8d11ec38a3eb5e956b052f67da8bdc9bef8abf3e"; // DAI
  const scWantAddress = "0x8D9AED9882b4953a0c9fa920168fa1FDfA0eBE75"; // scDAI
  let self;
  let wantWhale;
  let selfAddress;
  let strategist;
  let owner;

  beforeEach(async function () {
    //reset network
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: "https://rpc.ftm.tools/",
            blockNumber: 28485212,
          },
        },
      ],
    });
    console.log("providers");
    //get signers
    [owner, addr1, addr2, addr3, addr4, ...addrs] = await ethers.getSigners();
    const wantHolder = "0xc4867e5d3f25b47a3be0a15bd70c69d7b93b169e";
    const wantWhaleAddress = "0x93c08a3168fc469f3fc165cd3a471d19a37ca19e";
    const strategistAddress = "0x3b410908e71Ee04e7dE2a87f8F9003AFe6c1c7cE";
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [wantHolder],
    });
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [wantWhaleAddress],
    });
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [strategistAddress],
    });
    self = await ethers.provider.getSigner(wantHolder);
    wantWhale = await ethers.provider.getSigner(wantWhaleAddress);
    strategist = await ethers.provider.getSigner(strategistAddress);
    selfAddress = await self.getAddress();
    ownerAddress = await owner.getAddress();
    console.log("addresses");

    //get artifacts
    Strategy = await ethers.getContractFactory(
      "ReaperAutoCompoundScreamLeverage"
    );
    PaymentRouter = await ethers.getContractFactory("PaymentRouter");
    Vault = await ethers.getContractFactory("ReaperVaultv1_3");
    Treasury = await ethers.getContractFactory("ReaperTreasury");
    Want = await ethers.getContractFactory(
      "@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20"
    );
    console.log("artifacts");

    //deploy contracts
    treasury = await Treasury.deploy();
    console.log("treasury");
    want = await Want.attach(wantAddress);
    console.log("want attached");
    vault = await Vault.deploy(
      wantAddress,
      "Scream Single Stake Vault",
      "rfScream",
      432000,
      0,
      ethers.utils.parseEther("999999")
    );
    console.log("vault");

    console.log(`vault.address: ${vault.address}`);
    console.log(`treasury.address: ${treasury.address}`);

    strategy = await Strategy.deploy(
      vault.address,
      [treasury.address, paymentRouterAddress],
      [strategistAddress],
      scWantAddress
    );
    console.log("strategy");

    paymentRouter = await PaymentRouter.attach(paymentRouterAddress);
    await paymentRouter
      .connect(strategist)
      .addStrategy(strategy.address, [strategistAddress], [100]);

    await vault.initialize(strategy.address);

    console.log(`Strategy deployed to ${strategy.address}`);
    console.log(`Vault deployed to ${vault.address}`);
    console.log(`Treasury deployed to ${treasury.address}`);

    //approving LP token and vault share spend
    await want.approve(vault.address, ethers.utils.parseEther("1000000000"));
    console.log("approvals1");
    await want
      .connect(self)
      .approve(vault.address, ethers.utils.parseEther("1000000000"));
    console.log("approvals2");
    console.log("approvals3");
    await want
      .connect(wantWhale)
      .approve(vault.address, ethers.utils.parseEther("1000000000"));
    console.log("approvals4");
    await vault
      .connect(wantWhale)
      .approve(vault.address, ethers.utils.parseEther("1000000000"));
  });

  describe("Deploying the vault and strategy", function () {
    xit("should initiate vault with a 0 balance", async function () {
      console.log(1);
      const totalBalance = await vault.balance();
      console.log(2);
      const availableBalance = await vault.available();
      console.log(3);
      const pricePerFullShare = await vault.getPricePerFullShare();
      console.log(4);
      expect(totalBalance).to.equal(0);
      console.log(5);
      expect(availableBalance).to.equal(0);
      console.log(6);
      expect(pricePerFullShare).to.equal(ethers.utils.parseEther("1"));
    });
  });
  describe("Vault Tests", function () {
    xit("should allow deposits and account for them correctly", async function () {
      const userBalance = await want.balanceOf(selfAddress);
      console.log(`userBalance: ${userBalance}`);
      const vaultBalance = await vault.balance();
      console.log("vaultBalance");
      console.log(vaultBalance);
      const depositAmount = ethers.utils.parseEther(".1");
      console.log("depositAmount");
      console.log(depositAmount);
      await vault.connect(self).deposit(depositAmount);
      const newVaultBalance = await vault.balance();
      console.log(`newVaultBalance: ${newVaultBalance}`);
      console.log(`depositAmount: ${depositAmount}`);
      const newUserBalance = await want.balanceOf(selfAddress);

      console.log(`newUserBalance: ${newUserBalance}`);
      console.log(
        `userBalance - depositAmount: ${userBalance - depositAmount}`
      );
      console.log(
        `userBalance - newUserBalance: ${userBalance - newUserBalance}`
      );
      const deductedAmount = userBalance.sub(newUserBalance);
      console.log("deductedAmount");
      console.log(deductedAmount);
      await vault.connect(self).deposit(depositAmount);
      expect(vaultBalance).to.equal(0);
      // Compound mint reduces balance by a small amount
      const smallDifference = depositAmount * 0.00000001;
      const isSmallBalanceDifference =
        depositAmount.sub(newVaultBalance) < smallDifference;
      expect(isSmallBalanceDifference).to.equal(true);

      const ltv = await strategy.calculateLTV();
      console.log(`ltv: ${ltv}`);
      const allowedLTVDrift = toEther("0.01");
      expect(ltv).to.be.closeTo(toEther("0.73"), allowedLTVDrift);
    });
    xit("should trigger deleveraging on deposit when LTV is too high", async function () {
      const depositAmount = toEther("100");
      await vault.connect(self).deposit(depositAmount);
      const ltvBefore = await strategy.calculateLTV();
      console.log(`ltvBefore: ${ltvBefore}`);
      const allowedLTVDrift = toEther("0.01");
      expect(ltvBefore).to.be.closeTo(toEther("0.73"), allowedLTVDrift);
      const newLTV = toEther("0.6");
      await strategy.setTargetLtv(newLTV);
      const smallDepositAmount = toEther("1");
      await vault.connect(self).deposit(smallDepositAmount);
      const ltvAfter = await strategy.calculateLTV();
      console.log(`ltvAfter: ${ltvAfter}`);
      expect(ltvAfter).to.be.closeTo(newLTV, allowedLTVDrift);
    });
    xit("should not change leverage when LTV is within the allowed drift on deposit", async function () {
      const depositAmount = toEther("1");
      const ltv = toEther("0.73");
      await vault.connect(self).deposit(depositAmount);
      const ltvBefore = await strategy.calculateLTV();
      console.log(`ltvBefore: ${ltvBefore}`);
      const allowedLTVDrift = toEther("0.01");
      expect(ltvBefore).to.be.closeTo(ltv, allowedLTVDrift);
      const smallDepositAmount = allowedLTVDrift.div(2);
      await vault.connect(self).deposit(smallDepositAmount);
      const ltvAfter = await strategy.calculateLTV();
      console.log(`ltvAfter: ${ltvAfter}`);
      expect(ltvAfter).to.be.closeTo(ltv, allowedLTVDrift);
    });
    it("should mint user their pool share", async function () {
      console.log("---------------------------------------------");
      const userBalance = await want.balanceOf(selfAddress);
      console.log(userBalance.toString());
      const selfDepositAmount = ethers.utils.parseEther("0.005");
      await vault.connect(self).deposit(selfDepositAmount);
      console.log((await vault.balance()).toString());

      const whaleDepositAmount = ethers.utils.parseEther("100");
      await vault.connect(wantWhale).deposit(whaleDepositAmount);
      const selfWantBalance = await vault.balanceOf(selfAddress);
      console.log(selfWantBalance.toString());
      const ownerDepositAmount = ethers.utils.parseEther("1");
      await want.connect(self).transfer(ownerAddress, ownerDepositAmount);
      const ownerBalance = await want.balanceOf(ownerAddress);

      console.log(ownerBalance.toString());
      await vault.deposit(ownerDepositAmount);
      console.log((await vault.balance()).toString());
      const ownerVaultWantBalance = await vault.balanceOf(ownerAddress);
      console.log(
        `ownerVaultWantBalance.toString(): ${ownerVaultWantBalance.toString()}`
      );
      await vault.withdrawAll();
      const ownerWantBalance = await want.balanceOf(ownerAddress);
      console.log(`ownerWantBalance: ${ownerWantBalance}`);
      const ownerVaultWantBalanceAfterWithdraw = await vault.balanceOf(
        ownerAddress
      );
      console.log(
        `ownerVaultWantBalanceAfterWithdraw: ${ownerVaultWantBalanceAfterWithdraw}`
      );
      const allowedImprecision = toEther("0.01");
      expect(ownerWantBalance).to.be.closeTo(
        ownerDepositAmount,
        allowedImprecision
      );
      expect(selfWantBalance).to.equal(selfDepositAmount);
    });
    xit("should allow withdrawals", async function () {
      const userBalance = await want.balanceOf(selfAddress);
      console.log(`userBalance: ${userBalance}`);
      const depositAmount = ethers.BigNumber.from(ethers.utils.parseEther("1"));
      await vault.connect(self).deposit(depositAmount);
      console.log(
        `await want.balanceOf(selfAddress): ${await want.balanceOf(
          selfAddress
        )}`
      );

      await vault.connect(self).withdrawAll();
      const newUserVaultBalance = await vault.balanceOf(selfAddress);
      console.log(`newUserVaultBalance: ${newUserVaultBalance}`);
      const userBalanceAfterWithdraw = await want.balanceOf(selfAddress);
      const securityFee = 10;
      const percentDivisor = 10000;
      const withdrawFee = (depositAmount * securityFee) / percentDivisor;
      const expectedBalance = userBalance.sub(withdrawFee);
      const smallDifference = expectedBalance * 0.0000001;
      console.log(
        `expectedBalance.sub(userBalanceAfterWithdraw): ${expectedBalance.sub(
          userBalanceAfterWithdraw
        )}`
      );
      console.log(`smallDifference: ${smallDifference}`);
      const isSmallBalanceDifference =
        expectedBalance.sub(userBalanceAfterWithdraw) < smallDifference;
      expect(isSmallBalanceDifference).to.equal(true);
    });
    xit("should trigger leveraging on withdraw when LTV is too low", async function () {
      const startingLTV = toEther("0.6");
      await strategy.setTargetLtv(startingLTV);
      const depositAmount = toEther("100");

      await vault.connect(self).deposit(depositAmount);
      const ltvBefore = await strategy.calculateLTV();
      console.log(`ltvBefore: ${ltvBefore}`);
      const allowedLTVDrift = toEther("0.01");
      expect(ltvBefore).to.be.closeTo(startingLTV, allowedLTVDrift);
      const newLTV = toEther("0.7");
      await strategy.setTargetLtv(newLTV);
      const smallWithdrawAmount = toEther("1");
      const userBalance = await want.balanceOf(selfAddress);
      await vault.connect(self).withdraw(smallWithdrawAmount);
      const userBalanceAfterWithdraw = await want.balanceOf(selfAddress);
      const ltvAfter = await strategy.calculateLTV();
      console.log(`ltvAfter: ${ltvAfter}`);
      expect(ltvAfter).to.be.closeTo(newLTV, allowedLTVDrift);

      const securityFee = 10;
      const percentDivisor = 10000;
      const withdrawFee = smallWithdrawAmount
        .mul(securityFee)
        .div(percentDivisor);
      const expectedBalance = userBalance
        .add(smallWithdrawAmount)
        .sub(withdrawFee);

      expect(userBalanceAfterWithdraw).to.be.closeTo(
        expectedBalance,
        toEther("0.0000001")
      );
    });
    xit("should trigger deleveraging on withdraw when LTV is too high", async function () {
      const startingLTV = toEther("0.7");
      await strategy.setTargetLtv(startingLTV);
      const depositAmount = toEther("100");

      await vault.connect(self).deposit(depositAmount);
      const ltvBefore = await strategy.calculateLTV();
      console.log(`ltvBefore: ${ltvBefore}`);
      const allowedLTVDrift = toEther("0.01");
      expect(ltvBefore).to.be.closeTo(startingLTV, allowedLTVDrift);
      const newLTV = toEther("0.6");
      await strategy.setTargetLtv(newLTV);
      const smallWithdrawAmount = toEther("1");
      const userBalance = await want.balanceOf(selfAddress);
      await vault.connect(self).withdraw(smallWithdrawAmount);
      const userBalanceAfterWithdraw = await want.balanceOf(selfAddress);
      const ltvAfter = await strategy.calculateLTV();
      console.log(`ltvAfter: ${ltvAfter}`);
      expect(ltvAfter).to.be.closeTo(newLTV, allowedLTVDrift);

      const securityFee = 10;
      const percentDivisor = 10000;
      const withdrawFee = smallWithdrawAmount
        .mul(securityFee)
        .div(percentDivisor);
      const expectedBalance = userBalance
        .add(smallWithdrawAmount)
        .sub(withdrawFee);

      expect(userBalanceAfterWithdraw).to.be.closeTo(
        expectedBalance,
        toEther("0.0000001")
      );
    });
    xit("should not change leverage on withdraw when still in the allowed LTV", async function () {
      const startingLTV = toEther("0.7");
      await strategy.setTargetLtv(startingLTV);
      const depositAmount = toEther("100");

      await vault.connect(self).deposit(depositAmount);
      const ltvBefore = await strategy.calculateLTV();
      console.log(`ltvBefore: ${ltvBefore}`);
      const allowedLTVDrift = toEther("0.01");
      expect(ltvBefore).to.be.closeTo(startingLTV, allowedLTVDrift);

      const userBalance = await want.balanceOf(selfAddress);
      const smallWithdrawAmount = allowedLTVDrift.div(2);
      await vault.connect(self).withdraw(smallWithdrawAmount);
      const userBalanceAfterWithdraw = await want.balanceOf(selfAddress);
      const ltvAfter = await strategy.calculateLTV();
      console.log(`ltvAfter: ${ltvAfter}`);
      expect(ltvAfter).to.be.closeTo(startingLTV, allowedLTVDrift);

      const securityFee = 10;
      const percentDivisor = 10000;
      const withdrawFee = smallWithdrawAmount
        .mul(securityFee)
        .div(percentDivisor);
      const expectedBalance = userBalance
        .add(smallWithdrawAmount)
        .sub(withdrawFee);

      expect(userBalanceAfterWithdraw).to.be.closeTo(
        expectedBalance,
        toEther("0.0000001")
      );
    });
    xit("should allow small withdrawal", async function () {
      const userBalance = await want.balanceOf(selfAddress);
      console.log(`userBalance: ${userBalance}`);
      const depositAmount = ethers.BigNumber.from(ethers.utils.parseEther("1"));
      await vault.connect(self).deposit(depositAmount);
      console.log(
        `await want.balanceOf(selfAddress): ${await want.balanceOf(
          selfAddress
        )}`
      );

      const whaleDepositAmount = ethers.utils.parseEther("10000");
      await vault.connect(wantWhale).deposit(whaleDepositAmount);

      await vault.connect(self).withdrawAll();
      const newUserVaultBalance = await vault.balanceOf(selfAddress);
      console.log(`newUserVaultBalance: ${newUserVaultBalance}`);
      const userBalanceAfterWithdraw = await want.balanceOf(selfAddress);
      const securityFee = 10;
      const percentDivisor = 10000;
      const withdrawFee = (depositAmount * securityFee) / percentDivisor;
      const expectedBalance = userBalance.sub(withdrawFee);
      const smallDifference = depositAmount * 0.00001;
      console.log(
        `expectedBalance.sub(userBalanceAfterWithdraw): ${expectedBalance.sub(
          userBalanceAfterWithdraw
        )}`
      );
      console.log(`smallDifference: ${smallDifference}`);
      const isSmallBalanceDifference =
        expectedBalance.sub(userBalanceAfterWithdraw) < smallDifference;
      expect(isSmallBalanceDifference).to.equal(true);
    });
    xit("should handle small deposit + withdraw", async function () {
      const userBalance = await want.balanceOf(selfAddress);
      console.log(`userBalance: ${userBalance}`);
      const depositAmount = ethers.BigNumber.from(
        ethers.utils.parseEther("0.0000000000001")
      );
      await vault.connect(self).deposit(depositAmount);
      console.log(
        `await want.balanceOf(selfAddress): ${await want.balanceOf(
          selfAddress
        )}`
      );

      await vault.connect(self).withdraw(depositAmount);
      console.log(
        `await want.balanceOf(selfAddress): ${await want.balanceOf(
          selfAddress
        )}`
      );
      const newUserVaultBalance = await vault.balanceOf(selfAddress);
      console.log(`newUserVaultBalance: ${newUserVaultBalance}`);
      const userBalanceAfterWithdraw = await want.balanceOf(selfAddress);
      const securityFee = 10;
      const percentDivisor = 10000;
      const withdrawFee = (depositAmount * securityFee) / percentDivisor;
      const expectedBalance = userBalance.sub(withdrawFee);
      const isSmallBalanceDifference =
        expectedBalance.sub(userBalanceAfterWithdraw) < 5;
      expect(isSmallBalanceDifference).to.equal(true);
    });
    xit("should be able to harvest", async function () {
      await vault.connect(self).deposit(100000);
      const estimatedGas = await strategy.estimateGas.harvest();
      console.log(`estimatedGas: ${estimatedGas}`);
      await strategy.connect(self).harvest();
    });
    xit("should provide yield", async function () {
      const timeToSkip = 3600;
      const initialUserBalance = await want.balanceOf(selfAddress);
      const depositAmount = initialUserBalance.div(10);

      await vault.connect(self).deposit(depositAmount);
      const initialVaultBalance = await vault.balance();

      await strategy.updateHarvestLogCadence(timeToSkip / 2);

      const numHarvests = 2;
      for (let i = 0; i < numHarvests; i++) {
        await moveTimeForward(timeToSkip);
        await vault.connect(self).deposit(depositAmount);
        await strategy.harvest();
      }

      const finalVaultBalance = await vault.balance();
      expect(finalVaultBalance).to.be.gt(initialVaultBalance);

      const averageAPR = await strategy.averageAPRAcrossLastNHarvests(
        numHarvests
      );
      console.log(
        `Average APR across ${numHarvests} harvests is ${averageAPR} basis points.`
      );
    });
  });
  describe("Strategy", function () {
    xit("should be able to pause and unpause", async function () {
      await strategy.pause();
      const depositAmount = ethers.utils.parseEther(".05");
      await expect(vault.connect(self).deposit(depositAmount)).to.be.reverted;
      await strategy.unpause();
      await expect(vault.connect(self).deposit(depositAmount)).to.not.be
        .reverted;
    });
    xit("should be able to panic", async function () {
      const depositAmount = ethers.utils.parseEther(".05");
      await vault.connect(self).deposit(depositAmount);
      const vaultBalance = await vault.balance();
      const strategyBalance = await strategy.balanceOf();
      await strategy.panic();
      expect(vaultBalance).to.equal(strategyBalance);
      const newVaultBalance = await vault.balance();
      const newStrategyBalance = await strategy.balanceOf();
      const allowedImprecision = toEther("0.000000001");
      expect(newVaultBalance).to.be.closeTo(vaultBalance, allowedImprecision);
      expect(newStrategyBalance).to.be.lt(allowedImprecision);
    });
    xit("should be able to retire strategy", async function () {
      const depositAmount = ethers.utils.parseEther(".05");
      await vault.connect(self).deposit(depositAmount);
      const vaultBalance = await vault.balance();
      const strategyBalance = await strategy.balanceOf();
      expect(vaultBalance).to.equal(strategyBalance);
      // Test needs the require statement to be commented out during the test
      await expect(strategy.retireStrat()).to.not.be.reverted;
      const newVaultBalance = await vault.balance();
      const newStrategyBalance = await strategy.balanceOf();
      const allowedImprecision = toEther("0.00000001");
      expect(newVaultBalance).to.be.closeTo(vaultBalance, allowedImprecision);
      expect(newStrategyBalance).to.be.lt(allowedImprecision);
    });
    xit("should be able to retire strategy with no balance", async function () {
      // Test needs the require statement to be commented out during the test
      await expect(strategy.retireStrat()).to.not.be.reverted;
    });
    xit("should be able to estimate harvest", async function () {
      const whaleDepositAmount = ethers.utils.parseEther("327171");
      await vault.connect(wantWhale).deposit(whaleDepositAmount);
      await strategy.harvest();
      const minute = 60;
      const hour = 60 * minute;
      const day = 24 * hour;
      await moveTimeForward(10 * day);
      await vault.connect(wantWhale).deposit(ethers.utils.parseEther("1"));
      const [profit, callFeeToUser] = await strategy.estimateHarvest();
      const hasProfit = profit.gt(0);
      const hasCallFee = callFeeToUser.gt(0);
      expect(hasProfit).to.equal(true);
      expect(hasCallFee).to.equal(true);
    });
    xit("should be able to estimate blocks until liquidation", async function () {
      const whaleDepositAmount = ethers.utils.parseEther("327171");
      await vault.connect(wantWhale).deposit(whaleDepositAmount);
      const blocksUntilLiquidation = await strategy.getblocksUntilLiquidation();
      console.log(`blocksUntilLiquidation: ${blocksUntilLiquidation}`);
      expect(blocksUntilLiquidation.gt(0)).to.equal(true);
    });
  });
});
