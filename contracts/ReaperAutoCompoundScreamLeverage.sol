// SPDX-License-Identifier: MIT

import "./abstract/ReaperBaseStrategy.sol";
import "./interfaces/IUniswapRouter.sol";
import "./interfaces/IPaymentRouter.sol";
import "./interfaces/CErc20I.sol";
import "./interfaces/IComptroller.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
     * {scWant} - The Scream version of the want token
     */
     address public constant WFTM =
        0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address public constant SCREAM = 0xe0654C8e6fd4D733349ac7E09f6f23DA256bF475;
    address public immutable want;
    CErc20I public immutable scWant;
    
    /**
     * @dev Third Party Contracts:
     * {UNI_ROUTER} - the UNI_ROUTER for target DEX
     * {comptroller} - Scream contract to enter market and to claim Scream tokens
     */
    address public constant UNI_ROUTER =
        0xF491e7B69E4244ad4002BC14e878a34207E38c29;
    address public immutable comptroller;

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
        scWant = CErc20I(_scWant);
        markets = [_scWant];
        comptroller = scWant.comptroller();
        want = scWant.underlying();
        wftmToWantRoute = [WFTM, want];

        _giveAllowances();

        IComptroller(comptroller).enterMarkets(markets);
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract.
     * It mints {want} into xBoo (BooMirrorWorld) to farm {xBoo} and finally,
     * xBoo is deposited into other pools to earn additional rewards
     */
    function deposit() public whenNotPaused {
        uint256 _ltv = _calculateLTV();
    }

    function _calculateLTV() internal returns(uint256 ltv) {
        
    }

    /**
     * @dev Withdraws funds and sents them back to the vault.
     * It withdraws {XTAROT} from the XStakingPoolController pools.
     * The available {XTAROT} minus fees is returned to the vault.
     */
    function withdraw(uint256 _amount) external {
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     * 1. Claims {REWARD_TOKEN} from the comptroller.
     * 2. Swaps {REWARD_TOKEN} to {WFTM}.
     * 2. Adjusts the position if necessary.
     * 3. Claims fees for the harvest caller and treasury.
            The strat does not need to try to claim fees from the {WANT} as borrow APY > lending APY
     * 4. Swaps the {WFTM} token for {WANT}
     * 5. Deposits.
     */
    function _harvestCore() internal override {
        //todo
        //_claimRewards();
        //  profit = _swapRewardToWftm();
        //  profit = _adjustPosition(profit);
        //  _chargeFees(profit);
        //  _swapToWant();
        //  deposit();
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
    }

    // calculate the total underlying {want} held by the strat.
    function balanceOf() public override view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much {want} this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    //Returns the current position
    //WARNING - this returns just the balance at last time someone touched the cToken token. Does not accrue interst in between
    //cToken is very active so not normally an issue.
    function balanceOfPool()
        public
        view
        returns (uint256)
    {
        (
            ,
            uint256 ctokenBalance,
            uint256 borrowBalance,
            uint256 exchangeRate
        ) = scWant.getAccountSnapshot(address(this));

        uint256 deposits = ctokenBalance * exchangeRate / 1e18;
        return deposits - borrowBalance;
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
    }

    /**
     * @dev Removes all allowance of {stakingToken} for the {xToken} contract,
     * {xToken} allowance for the {aceLab} contract,
     * {wftm} allowance for the {uniRouter}
     * in addition to allowance to all pool rewards for the {uniRouter}.
     */
    function _removeAllowances() internal {
    }
}
