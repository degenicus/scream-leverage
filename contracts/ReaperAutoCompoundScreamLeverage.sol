// SPDX-License-Identifier: MIT

import './abstract/ReaperBaseStrategy.sol';
import './interfaces/IUniswapRouter.sol';
import './interfaces/CErc20I.sol';
import './interfaces/IComptroller.sol';
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

pragma solidity 0.8.11;

/**
 * @dev This strategy will deposit and leverage a token on Scream to maximize yield by farming Scream tokens
 */
contract ReaperAutoCompoundScreamLeverage is ReaperBaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**
     * @dev Tokens Used:
     * {WFTM} - Required for liquidity routing when doing swaps. Also used to charge fees on yield.
     * {SCREAM} - The reward token for farming
     * {want} - The vault token the strategy is maximizing
     * {cWant} - The Scream version of the want token
     */
    address public constant WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address public constant SCREAM = 0xe0654C8e6fd4D733349ac7E09f6f23DA256bF475;
    address public want;
    CErc20I public cWant;

    /**
     * @dev Third Party Contracts:
     * {UNI_ROUTER} - the UNI_ROUTER for target DEX
     * {comptroller} - Scream contract to enter market and to claim Scream tokens
     */
    address public constant UNI_ROUTER = 0xF491e7B69E4244ad4002BC14e878a34207E38c29;
    IComptroller public comptroller;

    /**
     * @dev Routes we take to swap tokens
     * {screamToWftmRoute} - Route we take to get from {SCREAM} into {WFTM}.
     * {wftmToWantRoute} - Route we take to get from {WFTM} into {want}.
     */
    address[] public screamToWftmRoute;
    address[] public wftmToWantRoute;

    /**
     * @dev Scream variables
     * {markets} - Contains the Scream tokens to farm, used to enter markets and claim Scream
     * {MANTISSA} - The unit used by the Compound protocol
     */
    address[] public markets;
    uint256 public constant MANTISSA = 1e18;

    /**
     * @dev Strategy variables
     * {targetLTV} - The target loan to value for the strategy where 1 ether = 100%
     * {allowedLTVDrift} - How much the strategy can deviate from the target ltv where 0.01 ether = 1%
     * {balanceOfPool} - The total balance deposited into Scream (supplied - borrowed)
     * {borrowDepth} - The maximum amount of loops used to leverage and deleverage
     * {minWantToLeverage} - The minimum amount of want to leverage in a loop
     * {withdrawSlippageTolerance} - Maximum slippage authorized when withdrawing
     */
    uint256 public targetLTV;
    uint256 public allowedLTVDrift;
    uint256 public balanceOfPool;
    uint256 public borrowDepth;
    uint256 public minWantToLeverage;
    uint256 public maxBorrowDepth;
    uint256 public withdrawSlippageTolerance;

    /**
     * @dev Initializes the strategy. Sets parameters, saves routes, and gives allowances.
     * @notice see documentation for each variable above its respective declaration.
     */
    function initialize(
        address _vault,
        address[] memory _feeRemitters,
        address[] memory _strategists,
        address _scWant
    ) public initializer {
        __ReaperBaseStrategy_init(_vault, _feeRemitters, _strategists);
        cWant = CErc20I(_scWant);
        markets = [_scWant];
        comptroller = IComptroller(cWant.comptroller());
        want = cWant.underlying();
        wftmToWantRoute = [WFTM, want];
        screamToWftmRoute = [SCREAM, WFTM];

        targetLTV = 0.72 ether;
        allowedLTVDrift = 0.01 ether;
        balanceOfPool = 0;
        borrowDepth = 12;
        minWantToLeverage = 1000;
        maxBorrowDepth = 15;
        withdrawSlippageTolerance = 50;

        _giveAllowances();

        comptroller.enterMarkets(markets);
    }

    /**
     * @dev Withdraws funds and sents them back to the vault.
     * It withdraws {want} from Scream
     * The available {want} minus fees is returned to the vault.
     */
    function withdraw(uint256 _withdrawAmount) external doUpdateBalance {
        require(msg.sender == vault);

        uint256 ltv = _calculateLTV(_withdrawAmount);

        if (ltv < targetLTV - allowedLTVDrift) {
            // Strategy is underleveraged so can withdraw underlying directly
            _withdrawUnderlyingToVault(_withdrawAmount, true);
            _leverMax();
        } else if (ltv > targetLTV + allowedLTVDrift) {
            _deleverage(_withdrawAmount);

            // Strategy has deleveraged to the point where it can withdraw underlying
            _withdrawUnderlyingToVault(_withdrawAmount, true);
        } else {
            // LTV is in the acceptable range so the underlying can be withdrawn directly
            _withdrawUnderlyingToVault(_withdrawAmount, true);
        }
    }

    /**
     * @dev Calculates the LTV using existing exchange rate,
     * depends on the cWant being updated to be accurate.
     * Does not update in order provide a view function for LTV.
     */
    function calculateLTV() external view returns (uint256 ltv) {
        (, uint256 cWantBalance, uint256 borrowed, uint256 exchangeRate) = cWant.getAccountSnapshot(address(this));

        uint256 supplied = (cWantBalance * exchangeRate) / MANTISSA;

        if (supplied == 0 || borrowed == 0) {
            return 0;
        }

        ltv = (MANTISSA * borrowed) / supplied;
    }

    /**
     * @dev Returns the approx amount of profit from harvesting.
     *      Profit is denominated in WFTM, and takes fees into account.
     */
    function estimateHarvest() external view override returns (uint256 profit, uint256 callFeeToUser) {
        uint256 rewards = predictScreamAccrued();
        if (rewards == 0) {
            return (0, 0);
        }
        profit = IUniswapRouter(UNI_ROUTER).getAmountsOut(rewards, screamToWftmRoute)[1];
        uint256 wftmFee = (profit * totalFee) / PERCENT_DIVISOR;
        callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
        profit -= wftmFee;
    }

    /**
     * @dev Emergency function to deleverage in case regular deleveraging breaks
     */
    function manualDeleverage(uint256 amount) external {
        _onlyStrategistOrOwner();
        require(cWant.redeemUnderlying(amount) == 0);
        require(cWant.repayBorrow(amount) == 0);
    }

    /**
     * @dev Emergency function to deleverage in case regular deleveraging breaks
     */
    function manualReleaseWant(uint256 amount) external {
        _onlyStrategistOrOwner();
        require(cWant.redeemUnderlying(amount) == 0);
    }

    /**
     * @dev Sets a new LTV for leveraging.
     * Should be in units of 1e18
     */
    function setTargetLtv(uint256 _ltv) external {
        _onlyStrategistOrOwner();
        (, uint256 collateralFactorMantissa, ) = comptroller.markets(address(cWant));
        require(collateralFactorMantissa > _ltv + allowedLTVDrift);
        targetLTV = _ltv;
    }

    /**
     * @dev Sets a new allowed LTV drift
     * Should be in units of 1e18
     */
    function setAllowedLtvDrift(uint256 _drift) external {
        _onlyStrategistOrOwner();
        (, uint256 collateralFactorMantissa, ) = comptroller.markets(address(cWant));
        require(collateralFactorMantissa > targetLTV + _drift);
        allowedLTVDrift = _drift;
    }

    /**
     * @dev Sets a new borrow depth (how many loops for leveraging+deleveraging)
     */
    function setBorrowDepth(uint8 _borrowDepth) external {
        _onlyStrategistOrOwner();
        require(_borrowDepth <= maxBorrowDepth);
        borrowDepth = _borrowDepth;
    }


    /**
     * @dev Sets the minimum want to leverage/deleverage (loop) for
     */
    function setMinWantToLeverage(uint256 _minWantToLeverage) external {
        _onlyStrategistOrOwner();
        minWantToLeverage = _minWantToLeverage;
    }

    /**
     * @dev Sets the maximum slippage authorized when withdrawing
     */
    function setWithdrawSlippageTolerance(uint256 _withdrawSlippageTolerance) external {
        _onlyStrategistOrOwner();
        withdrawSlippageTolerance = _withdrawSlippageTolerance;
    }
    /**
     * @dev Function to retire the strategy. Claims all rewards and withdraws
     *      all principal from external contracts, and sends everything back to
     *      the vault. Can only be called by strategist or owner.
     *
     * Note: this is not an emergency withdraw function. For that, see panic().
     */
    function retireStrat() external doUpdateBalance {
        _onlyStrategistOrOwner();
        comptroller.claimComp(address(this));
        _swapRewardsToWftm();
        _swapToWant();

        _deleverage(type(uint256).max);
        _withdrawUnderlyingToVault(type(uint256).max, false);
    }

    /**
     * @dev Pauses supplied. Withdraws all funds from Scream, leaving rewards behind.
     */
    function panic() external doUpdateBalance {
        _onlyStrategistOrOwner();
        _deleverage(type(uint256).max);
        pause();
    }

    /**
     * @dev Unpauses the strat.
     */
    function unpause() external {
        _onlyStrategistOrOwner();
        _unpause();
        _giveAllowances();
        deposit();
    }

    /**
     * @dev Pauses the strat.
     */
    function pause() public {
        _onlyStrategistOrOwner();
        _pause();
        _removeAllowances();
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone supplied in the strategy's vault contract.
     * It supplies {want} Scream to farm {SCREAM}
     */
    function deposit() public whenNotPaused doUpdateBalance {
        CErc20I(cWant).mint(balanceOfWant());
        uint256 ltv = _calculateLTV(0);

        if (ltv < targetLTV - allowedLTVDrift) {
            _leverMax();
        } else if (ltv > targetLTV + allowedLTVDrift) {
            _deleverage(0);
        }
    }

    /**
     * @dev Calculates the total amount of {want} held by the strategy
     * which is the balance of want + the total amount supplied to Scream.
     */
    function balanceOf() public view override returns (uint256) {
        return balanceOfWant() + balanceOfPool;
    }

    /**
     * @dev Calculates the balance of want held directly by the strategy
     */
    function balanceOfWant() public view returns (uint256) {
        return IERC20Upgradeable(want).balanceOf(address(this));
    }

    /**
     * @dev Calculates how many blocks until we are in liquidation based on current interest rates
     * WARNING does not include compounding so the estimate becomes more innacurate the further ahead we look
     * Compound doesn't include compounding for most blocks
     * Equation: ((supplied*colateralThreshold - borrowed) / (borrowed*borrowrate - supplied*colateralThreshold*interestrate));
     */
    function getblocksUntilLiquidation() public view returns (uint256) {
        (, uint256 collateralFactorMantissa, ) = comptroller.markets(address(cWant));

        (uint256 supplied, uint256 borrowed) = getCurrentPosition();

        uint256 borrrowRate = cWant.borrowRatePerBlock();

        uint256 supplyRate = cWant.supplyRatePerBlock();

        uint256 collateralisedDeposit = (supplied * collateralFactorMantissa) / MANTISSA;

        uint256 borrowCost = borrowed * borrrowRate;
        uint256 supplyGain = collateralisedDeposit * supplyRate;

        if (supplyGain >= borrowCost) {
            return type(uint256).max;
        } else {
            uint256 netSupplied = collateralisedDeposit - borrowed;
            uint256 totalCost = borrowCost - supplyGain;
            //minus 1 for this block
            return (netSupplied * MANTISSA) / totalCost;
        }
    }

    /**
     * @dev Returns the current position in Scream. Does not accrue interest
     * so might not be accurate, but the cWant is usually updated.
     */
    function getCurrentPosition() public view returns (uint256 supplied, uint256 borrowed) {
        (, uint256 cWantBalance, uint256 borrowBalance, uint256 exchangeRate) = cWant.getAccountSnapshot(address(this));
        borrowed = borrowBalance;

        supplied = (cWantBalance * exchangeRate) / MANTISSA;
    }

    /**
     * @dev This function makes a prediction on how much {SCREAM} is accrued.
     *      It is not 100% accurate as it uses current balances in Compound to predict into the past.
     */
    function predictScreamAccrued() public view returns (uint256) {
        // Has no previous log to compare harvest time to
        if (harvestLog.length == 0) {
            return 0;
        }
        (uint256 supplied, uint256 borrowed) = getCurrentPosition();
        if (supplied == 0) {
            return 0; // should be impossible to have 0 balance and positive comp accrued
        }

        uint256 distributionPerBlock = comptroller.compSpeeds(address(cWant));

        uint256 totalBorrow = cWant.totalBorrows();

        //total supply needs to be exchanged to underlying using exchange rate
        uint256 totalSupplyCtoken = cWant.totalSupply();
        uint256 totalSupply = totalSupplyCtoken
            * cWant.exchangeRateStored()
            / MANTISSA;

        uint256 blockShareSupply = 0;
        if (totalSupply > 0) {
            blockShareSupply = supplied * distributionPerBlock / totalSupply;
        }

        uint256 blockShareBorrow = 0;
        if (totalBorrow > 0) {
            blockShareBorrow = borrowed * distributionPerBlock / totalBorrow;
        }

        //how much we expect to earn per block
        uint256 blockShare = blockShareSupply + blockShareBorrow;
        uint256 secondsPerBlock = 1; // Average FTM block speed

        //last time we ran harvest
        uint256 lastHarvestTime = harvestLog[harvestLog.length - 1].timestamp;
        uint256 blocksSinceLast = block.timestamp - lastHarvestTime / secondsPerBlock;

        return blocksSinceLast * blockShare;
    }

    /**
     * @dev Updates the balance. This is the state changing version so it sets
     * balanceOfPool to the latest value.
     */
    function updateBalance() public {
        uint256 supplyBalance = CErc20I(cWant).balanceOfUnderlying(address(this));
        uint256 borrowBalance = CErc20I(cWant).borrowBalanceCurrent(address(this));
        balanceOfPool = supplyBalance - borrowBalance;
    }

    /**
     * @dev Levers the strategy up to the targetLTV
     */
    function _leverMax() internal {
        uint256 supplied = cWant.balanceOfUnderlying(address(this));
        uint256 borrowed = cWant.borrowBalanceStored(address(this));

        uint256 realSupply = supplied - borrowed;
        uint256 newBorrow = (realSupply * targetLTV) / (MANTISSA - targetLTV);
        uint256 amountLeftToBorrow = newBorrow - borrowed;

        for (uint256 i = 0; i < borrowDepth && amountLeftToBorrow > minWantToLeverage; i++) {
            amountLeftToBorrow -= _leverUpStep(amountLeftToBorrow);
        }
    }

    /**
     * @dev Does one step of leveraging
     */
    function _leverUpStep(uint256 _borrowAmount) internal returns (uint256) {
        if (_borrowAmount == 0) {
            return 0;
        }

        uint256 supplied = cWant.balanceOfUnderlying(address(this));
        uint256 borrowed = cWant.borrowBalanceStored(address(this));
        (, uint256 collateralFactorMantissa, ) = comptroller.markets(address(cWant));
        uint256 canBorrow = (supplied * collateralFactorMantissa) / MANTISSA;

        canBorrow -= borrowed;

        if (canBorrow < _borrowAmount) {
            _borrowAmount = canBorrow;
        }

        if (_borrowAmount > 10) {
            // borrow available amount
            CErc20I(cWant).borrow(_borrowAmount);

            // deposit available want as collateral
            CErc20I(cWant).mint(balanceOfWant());
        }

        return _borrowAmount;
    }

    /**
     * @dev This is the state changing calculation of LTV that is more accurate
     * to be used internally. It returns what the LTV will be after withdrawing
     * {_withdrawAmount}, which may be 0--in which case we get the current LTV.
     */
    function _calculateLTV(uint256 _withdrawAmount) internal returns (uint256 ltv) {
        uint256 supplied = cWant.balanceOfUnderlying(address(this));
        uint256 borrowed = cWant.borrowBalanceStored(address(this));
        supplied = supplied - _withdrawAmount;

        if (supplied == 0 || borrowed == 0) {
            return 0;
        }
        ltv = (MANTISSA * borrowed) / supplied;
    }

    /**
     * @dev Withdraws want to the vault by redeeming the underlying
     */
    function _withdrawUnderlyingToVault(uint256 _withdrawAmount, bool _useWithdrawFee) internal {
        uint256 initialWithdrawAmount = _withdrawAmount;
        uint256 supplied = cWant.balanceOfUnderlying(address(this));
        uint256 borrowed = cWant.borrowBalanceStored(address(this));
        uint256 realSupplied = supplied - borrowed;

        if (realSupplied == 0) {
            return;
        }

        if (_withdrawAmount > realSupplied) {
            _withdrawAmount = realSupplied;
        }

        uint256 minAllowedSupply = (borrowed * MANTISSA) / (targetLTV + allowedLTVDrift);
        if (supplied >= minAllowedSupply) {
            uint256 redeemable = supplied - minAllowedSupply;
            uint256 balance = cWant.balanceOf(address(this));
            if (balance > 1) {
                if (redeemable < _withdrawAmount) {
                    _withdrawAmount = redeemable;
                }
            }
        }

        if (_useWithdrawFee) {
            uint256 withdrawFee = (_withdrawAmount * securityFee) / PERCENT_DIVISOR;
            _withdrawAmount -= (withdrawFee + 1);
        } else {
            _withdrawAmount -= 1;
        }

        if(_withdrawAmount < initialWithdrawAmount) {
            require(
                _withdrawAmount >=
                    (initialWithdrawAmount *
                        (PERCENT_DIVISOR - withdrawSlippageTolerance)) /
                        PERCENT_DIVISOR
            );
        }

        CErc20I(cWant).redeemUnderlying(_withdrawAmount);
        IERC20Upgradeable(want).safeTransfer(vault, _withdrawAmount);
    }

    /**
     * @dev For a given withdraw amount, figures out how much we need to reduce borrow by to
     * maintain LTV at targerLTV.
     */
    function _getBorrowDifference(uint256 _withdrawAmount) internal returns (uint256 difference) {
        uint256 supplied = cWant.balanceOfUnderlying(address(this));
        uint256 borrowed = cWant.borrowBalanceStored(address(this));
        uint256 realSupply = supplied - borrowed;

        if (_withdrawAmount > realSupply) {
            _withdrawAmount = realSupply;
        }
        uint256 desiredSupply = realSupply - _withdrawAmount;

        //(ds *c)/(1-c)
        uint256 desiredBorrow = (desiredSupply * targetLTV) / (MANTISSA - targetLTV);
        if (desiredBorrow > 1e5) {
            //stop us going right up to the wire
            desiredBorrow = desiredBorrow - 1e5;
        }

        difference = borrowed - desiredBorrow;
    }

    /**
     * @dev For a given withdraw amount, deleverages to a borrow level
     * that will maintain the target LTV
     */
    function _deleverage(uint256 _withdrawAmount) internal {
        uint256 borrowDifference = _getBorrowDifference(_withdrawAmount);

        for (uint256 i = 0; i < borrowDepth && borrowDifference > minWantToLeverage; i++) {
            borrowDifference -= _leverDownStep(borrowDifference);
        }
    }

    /**
     * @dev Deleverages one step
     */
    function _leverDownStep(uint256 _releaseAmount) internal returns (uint256 deleveragedAmount) {
        uint256 supplied = cWant.balanceOfUnderlying(address(this));
        uint256 borrowed = cWant.borrowBalanceStored(address(this));
        (, uint256 collateralFactorMantissa, ) = comptroller.markets(address(cWant));

        uint256 minAllowedSupply = (borrowed * MANTISSA) / collateralFactorMantissa;
        uint256 maxAllowedDeleverageAmount = supplied - minAllowedSupply;

        deleveragedAmount = maxAllowedDeleverageAmount;

        if (deleveragedAmount > borrowed) {
            deleveragedAmount = borrowed;
        }
        if (deleveragedAmount > _releaseAmount) {
            deleveragedAmount = _releaseAmount;
        }

        uint256 exchangeRateStored = cWant.exchangeRateStored();
        //redeemTokens = redeemAmountIn * 1e18 / exchangeRate. must be more than 0
        //a rounding error means we need another small addition
        if (deleveragedAmount * MANTISSA >= exchangeRateStored && deleveragedAmount > 10) {
            deleveragedAmount -= 10; // Amount can be slightly off for tokens with less decimals (USDC), so redeem a bit less
            cWant.redeemUnderlying(deleveragedAmount);
            //our borrow has been increased by no more than _releaseAmount
            cWant.repayBorrow(deleveragedAmount);
        }
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     * @notice Assumes the deposit will take care of the TVL rebalancing.
     * 1. Claims {SCREAM} from the comptroller.
     * 2. Swaps {SCREAM} to {WFTM}.
     * 3. Claims fees for the harvest caller and treasury.
     * 4. Swaps the {WFTM} token for {want}
     * 5. Deposits.
     */
    function _harvestCore() internal override {
        comptroller.claimComp(address(this));
        _swapRewardsToWftm();
        _chargeFees();
        _swapToWant();
        deposit();
    }

    /**
     * @dev Core harvest function.
     * Swaps {SCREAM} to {WFTM}
     */
    function _swapRewardsToWftm() internal {
        uint256 screamBalance = IERC20Upgradeable(SCREAM).balanceOf(address(this));
        if (screamBalance != 0) {
            IUniswapRouter router = IUniswapRouter(UNI_ROUTER);

            uint256 wftmOutput = router.getAmountsOut(screamBalance, screamToWftmRoute)[1];
            if (wftmOutput != 0) {
                router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    screamBalance,
                    0,
                    screamToWftmRoute,
                    address(this),
                    block.timestamp + 600
                );
            }
        }
    }

    /**
     * @dev Core harvest function.
     * Charges fees based on the amount of WFTM gained from reward
     */
    function _chargeFees() internal {
        IERC20Upgradeable wftm = IERC20Upgradeable(WFTM);
        uint256 wftmFee = (wftm.balanceOf(address(this)) * totalFee) / PERCENT_DIVISOR;
        if (wftmFee != 0) {
            uint256 callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
            uint256 treasuryFeeToVault = (wftmFee * treasuryFee) / PERCENT_DIVISOR;
            uint256 feeToStrategist = (treasuryFeeToVault * strategistFee) / PERCENT_DIVISOR;
            treasuryFeeToVault -= feeToStrategist;

            wftm.safeTransfer(msg.sender, callFeeToUser);
            wftm.safeTransfer(treasury, treasuryFeeToVault);
            wftm.safeTransfer(strategistRemitter, feeToStrategist);
        }
    }

    /**
     * @dev Core harvest function.
     * Swaps {WFTM} for {want}
     */
    function _swapToWant() internal {
        if (want == WFTM) {
            return;
        }
        
        uint256 wftmBalance = IERC20Upgradeable(WFTM).balanceOf(address(this));
        if (wftmBalance != 0) {
            IUniswapRouter(UNI_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                wftmBalance,
                0,
                wftmToWantRoute,
                address(this),
                block.timestamp + 600
            );
        }
    }

    /**
     * @dev Gives the necessary allowances to mint cWant, swap rewards etc
     */
    function _giveAllowances() internal {
        IERC20Upgradeable(want).safeIncreaseAllowance(
            address(cWant),
            type(uint256).max - IERC20Upgradeable(want).allowance(address(this), address(cWant))
        );
        IERC20Upgradeable(WFTM).safeIncreaseAllowance(
            UNI_ROUTER,
            type(uint256).max - IERC20Upgradeable(WFTM).allowance(address(this), UNI_ROUTER)
        );
        IERC20Upgradeable(SCREAM).safeIncreaseAllowance(
            UNI_ROUTER,
            type(uint256).max - IERC20Upgradeable(SCREAM).allowance(address(this), UNI_ROUTER)
        );
    }

    /**
     * @dev Removes all allowance that were given
     */
    function _removeAllowances() internal {
        IERC20Upgradeable(want).safeDecreaseAllowance(address(cWant), IERC20Upgradeable(want).allowance(address(this), address(cWant)));
        IERC20Upgradeable(WFTM).safeDecreaseAllowance(UNI_ROUTER, IERC20Upgradeable(WFTM).allowance(address(this), UNI_ROUTER));
        IERC20Upgradeable(SCREAM).safeDecreaseAllowance(UNI_ROUTER, IERC20Upgradeable(SCREAM).allowance(address(this), UNI_ROUTER));
    }

    modifier doUpdateBalance {
        _;
        updateBalance();
    }
}
