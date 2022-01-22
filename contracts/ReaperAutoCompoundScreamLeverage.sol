// SPDX-License-Identifier: MIT

import "./abstract/ReaperBaseStrategy.sol";
import "./interfaces/IUniswapRouter.sol";
import "./interfaces/IPaymentRouter.sol";
import "./interfaces/CErc20I.sol";
import "./interfaces/IComptroller.sol";
// import "./interfaces/ISToken.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "hardhat/console.sol";

pragma solidity 0.8.9;

/**
 * @dev This strategy will deposit and leverage a Scream token to maximize yield by farming Scream tokens
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
     */
    address[] public markets;
    uint256 public constant MANTISSA = 1e18;

    /**
     * @dev Scream variables
     * {targetLTV} - The target loan to value for the strategy where 1 ether = 100%
     * {allowedLTVDrift} - How much the strategy can deviate from the target ltv where 0.01 ether = 1%
     */
    uint256 public targetLTV = 0.73 ether;
    uint256 public allowedLTVDrift = 0.01 ether;
    uint256 public balanceOfPool = 0;

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
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract.
     * It deposits {XTAROT} into xBoo (BooMirrorWorld) to farm {xBoo} and finally,
     * xBoo is deposited into other pools to earn additional rewards
     */
    function deposit() public whenNotPaused {
        console.log("-------------------------------------------------");
        console.log("deposit()");
        CErc20I(cWant).mint(balanceOfWant());
        uint256 _ltv = _calculateLTV();
        console.log("_ltv: ", _ltv);

        if(_shouldLeverage(_ltv)) {
            console.log("_shouldLeverage");
            // CErc20I(cWant).redeemUnderlying(minted);
            _leverMax();
            updateBalance();
        } else if (_shouldDeleverage(_ltv)) {
            console.log("_shouldDeleverage");
        } else {
            // LTV is in the acceptable range
            console.log("do nothing");
        }
    }

    function _leverMax() internal {
        console.log("_leverMax()");
        uint256 supplied = cWant.balanceOfUnderlying(address(this));
        uint256 borrowed = cWant.borrowBalanceStored(address(this));

        uint256 minWant = 1000;
        uint256 maxIterations = 8;
        uint256 realSupply = supplied - borrowed;
        uint256 targetCollatRatio = 720000000000000000;
        uint256 newBorrow = _getMaxBorrowFromSupplied(realSupply, targetCollatRatio);
        console.log("newBorrow: ", newBorrow);
        uint256 totalAmountToBorrow = newBorrow - borrowed;
        console.log("totalAmountToBorrow: ", totalAmountToBorrow);

        for (
                uint8 i = 0;
                i < maxIterations && totalAmountToBorrow > minWant;
                i++
            ) {
                console.log("i: ", i);
                totalAmountToBorrow = totalAmountToBorrow -
                    _leverUpStep(totalAmountToBorrow);
            }
    }

    function _leverUpStep(uint256 _amount) internal returns (uint256) {
        if (_amount == 0) {
            return 0;
        }

        console.log("_leverUpStep: ", _amount);

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

        if (canBorrow < _amount) {
            _amount = canBorrow;
        }

        if (_amount > 10) {
            // borrow available amount
            uint256 code1 = CErc20I(cWant).borrow(_amount);
            console.log("borrow: ", _amount);
            console.log("code1: ", code1);

            console.log("mint: ", balanceOfWant());
            // deposit available want as collateral
            uint256 code2 = CErc20I(cWant).mint(balanceOfWant());
            console.log("code2: ", code2);
        }

        return _amount;
    }

    function _getMaxBorrowFromSupplied(uint256 wantSupplied, uint256 collateralFactor) internal view returns(uint256) {
        
        console.log("collateralFactor: ", collateralFactor);
        console.log("wantSupplied * collateralFactor: ", wantSupplied * collateralFactor);
        console.log("MANTISSA - collateralFactor: ", MANTISSA - collateralFactor);
        return
            ((wantSupplied * collateralFactor) /
                (MANTISSA - collateralFactor)
            );
    }

    function _shouldLeverage(uint256 _ltv) public view returns (bool) {
        if (_ltv < targetLTV - allowedLTVDrift) {
            return true;
        }
        return false;
    }

    function _shouldDeleverage(uint256 _ltv) public view returns (bool) {
        if (_ltv > targetLTV + allowedLTVDrift) {
            return true;
        }
        return false;
    }

    function _calculateLTV() internal returns(uint256 ltv) {
        uint256 supplied = cWant.balanceOfUnderlying(address(this));
        uint256 borrowed = cWant.borrowBalanceStored(address(this));
        console.log("supplied: ", supplied);
        console.log("borrowed: ", borrowed);

        if (supplied == 0 || borrowed == 0) {
            return 0;
        }
        ltv = uint256(1e18) * borrowed / supplied;
        console.log("ltv: ", ltv);
    }

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

    //returns our current collateralisation ratio. Should be compared with collateralTarget
    // function storedCollateralisation() public view returns (uint256 collat) {
    //     (uint256 lend, uint256 borrow) = getCurrentPosition();
    //     if (lend == 0) {
    //         return 0;
    //     }
    //     collat = uint256(1e18).mul(borrow).div(lend);
    // }

    // function getLivePosition()
    //     public
    //     returns (uint256 deposits, uint256 borrows)
    // {
    //     deposits = cToken.balanceOfUnderlying(address(this));

    //     //we can use non state changing now because we updated state with balanceOfUnderlying call
    //     borrows = cToken.borrowBalanceStored(address(this));
    // }

    /**
     * @dev Withdraws funds and sents them back to the vault.
     * It withdraws {XTAROT} from the XStakingPoolController pools.
     * The available {XTAROT} minus fees is returned to the vault.
     */
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");
        console.log("withdraw");

        uint256 _ltv = _calculateLTVAfterWithdraw(_amount);
        console.log("_ltv: ", _ltv);

        if(_shouldLeverage(_ltv)) {
            console.log("_shouldLeverage");
            // CErc20I(cWant).redeemUnderlying(minted);
            _leverMax();
            updateBalance();
        } else if (_shouldDeleverage(_ltv)) {
            console.log("_shouldDeleverage");
            _deleverage(_amount);
            console.log("deleveraged");
            uint256 supplied = cWant.balanceOfUnderlying(address(this));
            uint256 borrowed = cWant.borrowBalanceStored(address(this));
            console.log("supplied: ", supplied);
            console.log("borrowed: ", borrowed);

            if (_amount > supplied) {
                _amount = supplied;
            }
            
            uint256 redeemCode = CErc20I(cWant).redeemUnderlying(_amount);
            console.log("redeemCode: ", redeemCode);
            uint256 withdrawFee = _amount * securityFee / PERCENT_DIVISOR;
            uint256 wantBalance = IERC20(want).balanceOf(address(this));
            console.log("wantBalance: ", wantBalance);
            console.log("_amount: ", _amount);
            IERC20(want).safeTransfer(vault, _amount - withdrawFee);
        } else {
            // LTV is in the acceptable range
            console.log("do nothing");
        }
    }

    function _getDesiredBorrow(uint256 _withdrawAmount)
        internal
        returns (uint256 position)
    {
        console.log("_getDesiredBorrow");
        //we want to use statechanging for safety
        // (uint256 deposits, uint256 borrows) = getLivePosition();
        uint256 supplied = cWant.balanceOfUnderlying(address(this));
        uint256 borrowed = cWant.borrowBalanceStored(address(this));

        //When we unwind we end up with the difference between borrow and supply
        uint256 unwoundSupplied = supplied - borrowed;

        //we want to see how close to collateral target we are.
        //So we take our unwound deposits and add or remove the _withdrawAmount we are are adding/removing.
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

    function _deleverage(uint256 _amount) internal returns (bool notAll) {
        console.log("_deleverage");
        uint256 newBorrow = _getDesiredBorrow(_amount);
        // (uint256 position, bool deficit) = _getDesiredBorrow(
        //     _amount,
        //     false
        // );
        uint256 minWant = 1000;
        uint256 iterations = 8;

        // //If there is no deficit we dont need to adjust position
        // //if the position change is tiny do nothing
        if (newBorrow > minWant) {
            uint256 i = 0;
            //position will equal 0 unless we haven't been able to deleverage enough with flash loan
            //if we are not in deficit we dont need to do flash loan
            while (newBorrow > minWant + 100) {
                console.log("while newBorrow: ", newBorrow);
                newBorrow = newBorrow - _normalDeleverage(newBorrow);
                i++;
                //A limit set so we don't run out of gas
                if (i >= iterations) {
                    notAll = true;
                    break;
                }
            }
        }
        // //now withdraw
        // //if we want too much we just take max

        // //This part makes sure our withdrawal does not force us into liquidation
        // (uint256 depositBalance, uint256 borrowBalance) = getCurrentPosition();

        // uint256 tempColla = collateralTarget;

        // uint256 reservedAmount = 0;
        // if (tempColla == 0) {
        //     tempColla = 1e15; // 0.001 * 1e18. lower we have issues
        // }

        // reservedAmount = borrowBalance.mul(1e18).div(tempColla);
        // if (depositBalance >= reservedAmount) {
        //     uint256 redeemable = depositBalance.sub(reservedAmount);
        //     uint256 balan = cToken.balanceOf(address(this));
        //     if (balan > 1) {
        //         if (redeemable < _amount) {
        //             cToken.redeemUnderlying(redeemable);
        //         } else {
        //             cToken.redeemUnderlying(_amount);
        //         }
        //     }
        // }

        // if (
        //     collateralTarget == 0 &&
        //     balanceOfToken(address(want)) > borrowBalance
        // ) {
        //     cToken.repayBorrow(borrowBalance);
        // }
    }

    function _normalDeleverage(
        uint256 maxDeleverage
    ) internal returns (uint256 deleveragedAmount) {
        console.log("_normalDeleverage");
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
     * 1. Claims {REWARD_TOKEN} from the comptroller.
     * 2. Swaps {REWARD_TOKEN} to {WFTM}.
     * 3. Claims fees for the harvest caller and treasury.
     * 4. Swaps the {WFTM} token for {WANT}
     * 5. Deposits. 
     */
    function _harvestCore() internal override {
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
        CTokenI[] memory tokens = new CTokenI[](1);
        tokens[0] = cWant;

        comptroller.claimComp(address(this), tokens);
    }

    /**
     * @dev Core harvest function.
     */
    function _swapRewardsToWftm() internal {
        uint256 screamBal = IERC20(SCREAM).balanceOf(address(this));
        if (screamBal != 0) {
            IUniswapRouter(UNI_ROUTER)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                screamBal,
                0,
                screamToWftmRoute,
                address(this),
                block.timestamp + 600
            );
        }
    }

    function _chargeFees() internal {
        uint256 wftmFee = IERC20(WFTM).balanceOf(address(this)) * totalFee / PERCENT_DIVISOR;

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

    function _swapToWant() internal {
        uint256 wftmBal = IERC20(WFTM).balanceOf(address(this));
        if (wftmBal != 0) {
            IUniswapRouter(UNI_ROUTER)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    wftmBal,
                    0,
                    wftmToWantRoute,
                    address(this),
                    block.timestamp + 600
                );
        }
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
        profit = IUniswapRouter(UNI_ROUTER).getAmountsOut(rewards, screamToWftmRoute)[1];
        uint256 wftmFee = (profit * totalFee) / PERCENT_DIVISOR;
        callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
        profit -= wftmFee;
    }

    // calculate the total underlying {want} held by the strat.
    function balanceOf() public override view returns (uint256) {
        console.log("balanceOfWant(): ", balanceOfWant());
        console.log("balanceOfPool(): ", balanceOfPool);
        return balanceOfWant() + balanceOfPool;
    }

    // it calculates how much {want} this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    //Returns the current position
    //WARNING - this returns just the _withdrawAmount at last time someone touched the cToken token. Does not accrue interst in between
    //cToken is very active so not normally an issue.
    // function balanceOfPool()
    //     public
    //     view
    //     returns (uint256)
    // {
    //     (
    //         ,
    //         uint256 ctokenBalance,
    //         uint256 borrowBalance,
    //         uint256 exchangeRate
    //     ) = cWant.getAccountSnapshot(address(this));

    //     uint256 deposits = ctokenBalance * exchangeRate / 1e18;
    //     return deposits - borrowBalance;
    // }

    function updateBalance() public {
        console.log("updateBalance()");
        uint256 supplyBal = CErc20I(cWant).balanceOfUnderlying(address(this));
        uint256 borrowBal = CErc20I(cWant).borrowBalanceCurrent(address(this));
        console.log("supplyBal: ", supplyBal);
        console.log("borrowBal: ", borrowBal);
        balanceOfPool = supplyBal - borrowBal;
    }

    /**
     * @dev Function that has to be called as part of strat migration. It sends all the available funds back to the
     * vault, ready to be migrated to the new strat.
     */
    function retireStrat() external {
    }

    /**
     * @dev Pauses deposits. Withdraws all funds from the AceLab contract, leaving rewards behind.
     */
    function panic() public {
        _onlyStrategistOrOwner();
        pause();
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
     * @dev Unpauses the strat.
     */
    function unpause() external {
        _onlyStrategistOrOwner();
        _unpause();

        _giveAllowances();

        deposit();
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
    }

    function setTargetLtv(uint256 _ltv)
        external
        
    {
        _onlyStrategistOrOwner();
        (, uint256 collateralFactorMantissa, ) = comptroller.markets(
            address(cWant)
        );
        require(collateralFactorMantissa > _ltv, "Ltv above max level");
        targetLTV = _ltv;
    }
}
