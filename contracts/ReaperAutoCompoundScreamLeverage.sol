// SPDX-License-Identifier: MIT

import "./abstract/ReaperBaseStrategy.sol";
import "./interfaces/IUniswapRouter.sol";
import "./interfaces/IPaymentRouter.sol";
import "./interfaces/CErc20I.sol";
import "./interfaces/IComptroller.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "hardhat/console.sol";

pragma solidity 0.8.9;

/**
 * @dev This strategy will deposit and leverage a token on Scream to maximize yield by farming Scream tokens
 */
contract ReaperAutoCompoundScreamLeverage is ReaperBaseStrategy {
    using SafeERC20 for IERC20;

    /**
     * @dev Tokens Used:
     * {WFTM} - Required for liquidity routing when doing swaps. Also used to charge fees on yield.
     * {SCREAM} - The reward token for farming
     * {want} - The vault token the strategy is maximizing
     * {cWant} - The Scream version of the want token
     */
     address public constant WFTM =
        0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address public constant SCREAM = 0xe0654C8e6fd4D733349ac7E09f6f23DA256bF475;
    address public immutable want;
    CErc20I public immutable cWant;
    
    /**
     * @dev Third Party Contracts:
     * {UNI_ROUTER} - the UNI_ROUTER for target DEX
     * {comptroller} - Scream contract to enter market and to claim Scream tokens
     */
    address public constant UNI_ROUTER =
        0xF491e7B69E4244ad4002BC14e878a34207E38c29;
    IComptroller public immutable comptroller;

    /**
     * @dev Routes we take to swap tokens
     * {screamToWftmRoute} - Route we take to get from {SCREAM} into {WFTM}.
     * {wftmToWantRoute} - Route we take to get from {WFTM} into {want}.
     */
    address[] public screamToWftmRoute = [SCREAM, WFTM];
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
     */
    uint256 public targetLTV = 0.73 ether;
    uint256 public allowedLTVDrift = 0.01 ether;
    uint256 public balanceOfPool = 0;
    uint256 public borrowDepth = 10;
    uint256 public minWantToLeverage = 1000;

    /**
     * @dev Initializes the strategy. Sets parameters, saves routes, and gives allowances.
     * @notice see documentation for each variable above its respective declaration.
     */
    constructor(
        address _vault,
        address[] memory _feeRemitters,
        address[] memory _strategists,
        address _scWant
    ) ReaperBaseStrategy(_vault, _feeRemitters, _strategists) {
        cWant = CErc20I(_scWant);
        markets = [_scWant];
        comptroller = IComptroller(cWant.comptroller());
        want = cWant.underlying();
        wftmToWantRoute = [WFTM, want];

        _giveAllowances();

        comptroller.enterMarkets(markets);
    }

    /**
     * @dev Withdraws funds and sents them back to the vault.
     * It withdraws {want} from Scream
     * The available {want} minus fees is returned to the vault.
     */
    function withdraw(uint256 _withdrawAmount) external {
        require(msg.sender == vault, "!vault");
        console.log("withdraw");

        uint256 _ltv = _calculateLTVAfterWithdraw(_withdrawAmount);
        console.log("_ltv: ", _ltv);

        if(_shouldLeverage(_ltv)) {
            console.log("_shouldLeverage");
            // Strategy is underleveraged so can withdraw underlying directly
            _withdrawUnderlyingToVault(_withdrawAmount, true);
            _leverMax();
        } else if (_shouldDeleverage(_ltv)) {
            console.log("_shouldDeleverage");
            _deleverage(_withdrawAmount);
            console.log("deleveraged");
            
            // Strategy has deleveraged to the point where it can withdraw underlying
            _withdrawUnderlyingToVault(_withdrawAmount, true);
        } else {
            // LTV is in the acceptable range so the underlying can be withdrawn directly
            console.log("do nothing");
            _withdrawUnderlyingToVault(_withdrawAmount, true);
        }
        updateBalance();
    }

    /**
     * @dev Calculates the LTV using existing exchange rate,
     * depends on the cWant being updated to be accurate.
     * Does not update in order provide a view function for LTV.
     */
    function calculateLTV()
        external
        view
        returns (uint256 ltv)
    {
        (
            ,
            uint256 cWantBalance,
            uint256 borrowed,
            uint256 exchangeRate
        ) = cWant.getAccountSnapshot(address(this));

        uint256 supplied = cWantBalance * exchangeRate / MANTISSA;

        if (supplied == 0 || borrowed == 0) {
            return 0;
        }

         ltv = MANTISSA * borrowed / supplied;
    }

    /**
     * @dev Returns the approx amount of profit from harvesting.
     *      Profit is denominated in WFTM, and takes fees into account.
     */
    function estimateHarvest()
        external
        view
        override
        returns (uint256 profit, uint256 callFeeToUser)
    {
        uint256 rewards = comptroller.compAccrued(address(this));
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
        require(cWant.redeemUnderlying(amount) == 0, "Scream returned an error");
        require(cWant.repayBorrow(amount) == 0, "Scream returned an error");
    }

    /**
     * @dev Emergency function to deleverage in case regular deleveraging breaks
     */
    function manualReleaseWant(uint256 amount) external {
        _onlyStrategistOrOwner();
        require(cWant.redeemUnderlying(amount) == 0, "Scream returned an error");
    }

    /**
     * @dev Sets a new LTV for leveraging.
     * Should be in units of 1e18
     */
    function setTargetLtv(uint256 _ltv)
        external
        
    {
        _onlyStrategistOrOwner();
        (, uint256 collateralFactorMantissa, ) = comptroller.markets(
            address(cWant)
        );
        require(collateralFactorMantissa > _ltv + allowedLTVDrift, "Ltv above max level");
        targetLTV = _ltv;
    }

    /**
     * @dev Function that has to be called as part of strat migration. It sends all the available funds back to the
     * vault, ready to be migrated to the new strat.
     */
    function retireStrat() external {
        require(msg.sender == vault, "!vault");
        _claimRewards();
        _swapRewardsToWftm();
        _swapToWant();

        uint256 maxAmount = type(uint256).max;
        _deleverage(maxAmount);
        _withdrawUnderlyingToVault(maxAmount, false);
    }

    /**
     * @dev Pauses supplied. Withdraws all funds from the AceLab contract, leaving rewards behind.
     */
    function panic() external {
        console.log("--------------------------------------");
        console.log("panic()");
        _onlyStrategistOrOwner();
    
        uint256 maxAmount = type(uint256).max;
        _deleverage(maxAmount);
        _withdrawUnderlyingToVault(maxAmount, false);

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
    function deposit() public whenNotPaused {
        console.log("-------------------------------------------------");
        console.log("deposit()");
        CErc20I(cWant).mint(balanceOfWant());
        uint256 _ltv = _calculateLTV();
        console.log("_ltv: ", _ltv);

        if(_shouldLeverage(_ltv)) {
            console.log("_shouldLeverage");
            _leverMax();
        } else if (_shouldDeleverage(_ltv)) {
            console.log("_shouldDeleverage");
            _deleverage(0);
        } else {
            console.log("No leveraging");
        }
        updateBalance();
    }

    
    /**
     * @dev Calculates the total amount of {want} held by the strategy
     * which is the balance of want + the total amount supplied to Scream.
     */
    function balanceOf() public override view returns (uint256) {
        console.log("balanceOfWant(): ", balanceOfWant());
        console.log("balanceOfPool(): ", balanceOfPool);
        return balanceOfWant() + balanceOfPool;
    }

    /**
     * @dev Calculates the balance of want held directly by the strategy
     */
    function balanceOfWant() public view returns (uint256) {
        console.log("balanceOfWant()");
        uint256 _balanceOfWant = IERC20(want).balanceOf(address(this));
        console.log("_balanceOfWant: ", _balanceOfWant);
        return IERC20(want).balanceOf(address(this));
    }

    /**
     * @dev Calculates how many blocks until we are in liquidation based on current interest rates
     * WARNING does not include compounding so the estimate becomes more innacurate the further ahead we look
     * Compound doesn't include compounding for most blocks
     * Equation: ((supplied*colateralThreshold - borrowed) / (borrowed*borrowrate - supplied*colateralThreshold*interestrate));
     */
    function getblocksUntilLiquidation() public view returns (uint256) {
        (, uint256 collateralFactorMantissa, ) = comptroller.markets(
            address(cWant)
        );

        (uint256 supplied, uint256 borrowed) = getCurrentPosition();

        uint256 borrrowRate = cWant.borrowRatePerBlock();

        uint256 supplyRate = cWant.supplyRatePerBlock();

        uint256 collateralisedDeposit = supplied
            * collateralFactorMantissa
            / MANTISSA;

        uint256 borrowCost = borrowed * borrrowRate;
        uint256 supplyGain = collateralisedDeposit * supplyRate;

        if (supplyGain >= borrowCost) {
            return type(uint256).max;
        } else {
            uint256 netSupplied = collateralisedDeposit - borrowed;
            uint256 totalCost = borrowCost - supplyGain;
            //minus 1 for this block
            return netSupplied * MANTISSA / totalCost;
        }
    }

    /**
     * @dev Returns the current position in Scream. Does not accrue interest
     * so might not be accurate, but the cWant is usually updated.
     */
    function getCurrentPosition()
        public
        view
        returns (uint256 supplied, uint256 borrowed)
    {
        (
            ,
            uint256 cWantBalance,
            uint256 borrowBalance,
            uint256 exchangeRate
        ) = cWant.getAccountSnapshot(address(this));
        borrowed = borrowBalance;

        supplied = cWantBalance * exchangeRate / MANTISSA;
    }

    /**
     * @dev Updates the balance. This is the state changing version so it sets
     * balanceOfPool to the latest value.
     */
    function updateBalance() public {
        console.log("updateBalance()");
        uint256 supplyBalance = CErc20I(cWant).balanceOfUnderlying(address(this));
        uint256 borrowBalance = CErc20I(cWant).borrowBalanceCurrent(address(this));
        console.log("supplyBal: ", supplyBalance);
        console.log("borrowBal: ", borrowBalance);
        balanceOfPool = supplyBalance - borrowBalance;
    }

    /**
     * @dev Levers the strategy up to the targetLTV
     */
    function _leverMax() internal {
        console.log("_leverMax()");
        uint256 supplied = cWant.balanceOfUnderlying(address(this));
        uint256 borrowed = cWant.borrowBalanceStored(address(this));

        uint256 realSupply = supplied - borrowed;
        uint256 newBorrow = _getMaxBorrowFromSupplied(realSupply, targetLTV);
        console.log("newBorrow: ", newBorrow);
        uint256 totalAmountToBorrow = newBorrow - borrowed;
        console.log("totalAmountToBorrow: ", totalAmountToBorrow);

        for (
                uint8 i = 0;
                i < borrowDepth && totalAmountToBorrow > minWantToLeverage;
                i++
            ) {
                console.log("i: ", i);
                totalAmountToBorrow = totalAmountToBorrow -
                    _leverUpStep(totalAmountToBorrow);
            }
    }

    /**
     * @dev Does one step of leveraging
     */
    function _leverUpStep(uint256 _withdrawAmount) internal returns (uint256) {
        if (_withdrawAmount == 0) {
            return 0;
        }

        console.log("_leverUpStep: ", _withdrawAmount);

        uint256 wantBalance = balanceOfWant();

        console.log("wantBalance: ", wantBalance);

        // calculate how much borrow can I take
        uint256 supplied = cWant.balanceOfUnderlying(address(this));
        uint256 borrowed = cWant.borrowBalanceStored(address(this));
        console.log("supplied: ", supplied);
        console.log("borrowed: ", borrowed);
        (, uint256 collateralFactorMantissa, ) = comptroller.markets(
            address(cWant)
        );
        uint256 canBorrow = supplied * collateralFactorMantissa / MANTISSA;

        canBorrow = canBorrow - borrowed;

        if (canBorrow < _withdrawAmount) {
            _withdrawAmount = canBorrow;
        }

        if (_withdrawAmount > 10) {
            // borrow available amount
            uint256 code1 = CErc20I(cWant).borrow(_withdrawAmount);
            console.log("borrow: ", _withdrawAmount);
            console.log("code1: ", code1);

            console.log("mint: ", balanceOfWant());
            // deposit available want as collateral
            uint256 code2 = CErc20I(cWant).mint(balanceOfWant());
            console.log("code2: ", code2);
        }

        return _withdrawAmount;
    }

    /**
     * @dev Gets the maximum amount allowed to be borrowed for a given collateral factor and amount supplied
     */
    function _getMaxBorrowFromSupplied(uint256 wantSupplied, uint256 collateralFactor) internal view returns(uint256) {
        
        console.log("collateralFactor: ", collateralFactor);
        console.log("wantSupplied * collateralFactor: ", wantSupplied * collateralFactor);
        console.log("MANTISSA - collateralFactor: ", MANTISSA - collateralFactor);
        return
            ((wantSupplied * collateralFactor) /
                (MANTISSA - collateralFactor)
            );
    }

    /**
     * @dev Returns if the strategy should leverage with the given ltv level
     */
    function _shouldLeverage(uint256 _ltv) internal view returns (bool) {
        if (_ltv < targetLTV - allowedLTVDrift) {
            return true;
        }
        return false;
    }

    /**
     * @dev Returns if the strategy should deleverage with the given ltv level
     */
    function _shouldDeleverage(uint256 _ltv) internal view returns (bool) {
        if (_ltv > targetLTV + allowedLTVDrift) {
            return true;
        }
        return false;
    }

    /**
     * @dev This is the state changing calculation of LTV that is more accurate
     * to be used internally.
     */
    function _calculateLTV() internal returns(uint256 ltv) {
        uint256 supplied = cWant.balanceOfUnderlying(address(this));
        uint256 borrowed = cWant.borrowBalanceStored(address(this));
        console.log("supplied: ", supplied);
        console.log("borrowed: ", borrowed);

        if (supplied == 0 || borrowed == 0) {
            return 0;
        }
        ltv = MANTISSA * borrowed / supplied;
        console.log("ltv: ", ltv);
    }

    /**
     * @dev Calculates what the LTV will be after withdrawing
     */
    function _calculateLTVAfterWithdraw(uint256 _withdrawAmount) internal returns(uint256 ltv) {
        console.log("_calculateLTVAfterWithdraw: ");
        uint256 supplied = cWant.balanceOfUnderlying(address(this));
        uint256 borrowed = cWant.borrowBalanceStored(address(this));
        console.log("supplied: ", supplied);
        console.log("borrowed: ", borrowed);
        console.log("_withdrawAmount: ", _withdrawAmount);
        supplied = supplied - _withdrawAmount;

        if (supplied == 0 || borrowed == 0) {
            return 0;
        }
        ltv = uint256(1e18) * borrowed / supplied;
        console.log("ltv: ", ltv);
    }

    /**
     * @dev Withdraws want to the vault by redeeming the underlying
     */
    function _withdrawUnderlyingToVault(uint256 _withdrawAmount, bool _useWithdrawFee) internal {
            console.log("_withdrawUnderlyingToVault");
            console.log("_withdrawAmount: ", _withdrawAmount);
            console.log("_useWithdrawFee: ", _useWithdrawFee);
            uint256 supplied = cWant.balanceOfUnderlying(address(this));
            uint256 borrowed = cWant.borrowBalanceStored(address(this));
            uint256 realSupplied = supplied - borrowed;
            
            if (_withdrawAmount > realSupplied) {
                _withdrawAmount = realSupplied;
            }

            console.log("supplied: ", supplied);
            console.log("borrowed: ", borrowed);
            console.log("realSupplied: ", realSupplied);


            uint256 withdrawAmount;

            if(_useWithdrawFee) {
                uint256 withdrawFee = _withdrawAmount * securityFee / PERCENT_DIVISOR;
                withdrawAmount = _withdrawAmount - withdrawFee;
            } else {
                withdrawAmount = _withdrawAmount;
            }
            
            uint256 redeemCode = CErc20I(cWant).redeemUnderlying(withdrawAmount);
            console.log("redeemCode: ", redeemCode);
            uint256 wantBalance = IERC20(want).balanceOf(address(this));
            console.log("wantBalance: ", wantBalance);
            console.log("_withdrawAmount: ", _withdrawAmount);
            console.log("withdrawAmount: ", withdrawAmount);
            IERC20(want).safeTransfer(vault, withdrawAmount);
    }

    /**
     * @dev For a given withdraw amount, figures out the new borrow with the current supply
     * that will maintain the target LTV
     */
    function _getDesiredBorrow(uint256 _withdrawAmount)
        internal
        returns (uint256 position)
    {
        console.log("_getDesiredBorrow");
        //we want to use statechanging for safety
        uint256 supplied = cWant.balanceOfUnderlying(address(this));
        uint256 borrowed = cWant.borrowBalanceStored(address(this));

        //When we unwind we end up with the difference between borrow and supply
        uint256 unwoundSupplied = supplied - borrowed;

        //we want to see how close to collateral target we are.
        //So we take our unwound supplied and add or remove the _withdrawAmount we are are adding/removing.
        //This gives us our desired future undwoundDeposit (desired supply)

        uint256 desiredSupply = 0;
        if (_withdrawAmount > unwoundSupplied) {
            _withdrawAmount = unwoundSupplied;
        }
        desiredSupply = unwoundSupplied - _withdrawAmount;

        //(ds *c)/(1-c)
        uint256 num = desiredSupply * targetLTV;
        uint256 den = uint256(1e18) - targetLTV;

        uint256 desiredBorrow = num / den;
        if (desiredBorrow > 1e5) {
            //stop us going right up to the wire
            desiredBorrow = desiredBorrow - 1e5;
        }

        position = borrowed - desiredBorrow;
        console.log("position: ", position);
    }

    /**
     * @dev For a given withdraw amount, deleverages to a borrow level
     * that will maintain the target LTV
     */
    function _deleverage(uint256 _withdrawAmount) internal {
        console.log("_deleverage");
        uint256 newBorrow = _getDesiredBorrow(_withdrawAmount);

        // //If there is no deficit we dont need to adjust position
        // //if the position change is tiny do nothing
        if (newBorrow > minWantToLeverage) {
            uint256 i = 0;
            while (newBorrow > minWantToLeverage + 100) {
                console.log("while newBorrow: ", newBorrow);
                newBorrow = newBorrow - _leverDownStep(newBorrow);
                i++;
                //A limit set so we don't run out of gas
                if (i >= borrowDepth) {
                    break;
                }
            }
        }
    }

    /**
     * @dev Deleverages one step
     */
    function _leverDownStep(
        uint256 maxDeleverage
    ) internal returns (uint256 deleveragedAmount) {
        console.log("_leverDownStep");
        uint256 minAllowedSupply = 0;
        uint256 supplied = cWant.balanceOfUnderlying(address(this));
        uint256 borrowed = cWant.borrowBalanceStored(address(this));
        (, uint256 collateralFactorMantissa, ) = comptroller.markets(
            address(cWant)
        );

        //collat ration should never be 0. if it is something is very wrong... but just incase
        if (collateralFactorMantissa != 0) {
            minAllowedSupply = borrowed * MANTISSA / collateralFactorMantissa;
        }
        uint256 maxAllowedDeleverageAmount = supplied - minAllowedSupply;

        deleveragedAmount = maxAllowedDeleverageAmount;

        if (deleveragedAmount >= borrowed) {
            deleveragedAmount = borrowed;
        }
        if (deleveragedAmount >= maxDeleverage) {
            deleveragedAmount = maxDeleverage;
        }
        uint256 exchangeRateStored = cWant.exchangeRateStored();
        //redeemTokens = redeemAmountIn * 1e18 / exchangeRate. must be more than 0
        //a rounding error means we need another small addition
        if (
            deleveragedAmount * MANTISSA >= exchangeRateStored
            //deleveragedAmount > 10
        ) {
            // deleveragedAmount = deleveragedAmount - uint256(10);
            cWant.redeemUnderlying(deleveragedAmount);
            console.log("redeemUnderlying: ", deleveragedAmount);

            //our borrow has been increased by no more than maxDeleverage
            cWant.repayBorrow(deleveragedAmount);
            console.log("repayBorrow: ", deleveragedAmount);
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
        console.log("_harvestCore()");
        _claimRewards();
        _swapRewardsToWftm();
        _chargeFees();
        _swapToWant();
        deposit();
    }

    /**
     * @dev Core harvest function.
     * Get rewards from markets entered
     */
    function _claimRewards() internal {
        console.log("_claimRewards()");
        CTokenI[] memory tokens = new CTokenI[](1);
        tokens[0] = cWant;

        comptroller.claimComp(address(this), tokens);
    }

    /**
     * @dev Core harvest function.
     * Swaps {SCREAM} to {WFTM}
     */
    function _swapRewardsToWftm() internal {
        console.log("_swapRewardsToWftm");
        uint256 screamBalance = IERC20(SCREAM).balanceOf(address(this));
        console.log("screamBalance: ", screamBalance);
        if (screamBalance != 0) {
            IUniswapRouter(UNI_ROUTER)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                screamBalance,
                0,
                screamToWftmRoute,
                address(this),
                block.timestamp + 600
            );
        }
    }

    /**
     * @dev Core harvest function.
     * Charges fees based on the amount of WFTM gained from reward
     */
    function _chargeFees() internal {
        console.log("_chargeFees()");
        uint256 wftmFee = IERC20(WFTM).balanceOf(address(this)) * totalFee / PERCENT_DIVISOR;
        console.log("wftmFee: ", wftmFee);
        if (wftmFee != 0) {
            uint256 callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
            uint256 treasuryFeeToVault = (wftmFee * treasuryFee) /
                PERCENT_DIVISOR;
            uint256 feeToStrategist = (treasuryFeeToVault * strategistFee) /
                PERCENT_DIVISOR;
            treasuryFeeToVault -= feeToStrategist;

            IERC20(WFTM).safeTransfer(msg.sender, callFeeToUser);
            IERC20(WFTM).safeTransfer(treasury, treasuryFeeToVault);
            IERC20(WFTM).safeIncreaseAllowance(
                strategistRemitter,
                feeToStrategist
            );
            IPaymentRouter(strategistRemitter).routePayment(
                WFTM,
                feeToStrategist
            );
        }
    }

    /**
     * @dev Core harvest function.
     * Swaps {WFTM} for {want}
     */
    function _swapToWant() internal {
        console.log("_swapToWant()");
        uint256 wftmBalance = IERC20(WFTM).balanceOf(address(this));
        if (wftmBalance != 0) {
            IUniswapRouter(UNI_ROUTER)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    wftmBalance,
                    0,
                    wftmToWantRoute,
                    address(this),
                    block.timestamp + 600
                );
        }
    }

    /**
     * @dev Gives max allowance of {XTAROT} for the {xBoo} contract,
     * {xBoo} allowance for the {POOL_CONTROLLER} contract,
     * {WFTM} allowance for the {UNI_ROUTER}
     * in addition to allowance to all pool rewards for the {UNI_ROUTER}.
     */
    function _giveAllowances() internal {
        IERC20(want).safeApprove(address(cWant), 0);
        IERC20(WFTM).safeApprove(UNI_ROUTER, 0);
        IERC20(SCREAM).safeApprove(UNI_ROUTER, 0);
        IERC20(want).safeApprove(address(cWant), type(uint256).max);
        IERC20(WFTM).safeApprove(UNI_ROUTER, type(uint256).max);
        IERC20(SCREAM).safeApprove(UNI_ROUTER, type(uint256).max);
    }

    /**
     * @dev Removes all allowance of {stakingToken} for the {xToken} contract,
     * {xToken} allowance for the {aceLab} contract,
     * {wftm} allowance for the {uniRouter}
     * in addition to allowance to all pool rewards for the {uniRouter}.
     */
    function _removeAllowances() internal {
        IERC20(want).safeApprove(address(cWant), 0);
        IERC20(WFTM).safeApprove(UNI_ROUTER, 0);
        IERC20(SCREAM).safeApprove(UNI_ROUTER, 0);
    }
}
