// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "../interfaces/IStrategy.sol";
import "../interfaces/IVault.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

abstract contract ReaperBaseStrategy is
    IStrategy,
    UUPSUpgradeable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable
{
    uint256 public constant PERCENT_DIVISOR = 10_000;
    uint256 public constant ONE_YEAR = 365 days;
    uint256 public constant UPGRADE_TIMELOCK = 1 hours; // minimum 48 hours for RF

    struct Harvest {
        uint256 timestamp;
        uint256 vaultSharePrice;
    }

    Harvest[] public harvestLog;
    uint256 public harvestLogCadence;
    uint256 public lastHarvestTimestamp;

    /**
     * Reaper Roles
     */
    bytes32 public constant STRATEGIST = keccak256("STRATEGIST");
    bytes32 public constant STRATEGIST_MULTISIG = keccak256("STRATEGIST_MULTISIG");

    /**
     * @dev Reaper contracts:
     * {treasury} - Address of the Reaper treasury
     * {vault} - Address of the vault that controls the strategy's funds.
     * {strategistRemitter} - Address where strategist fee is remitted to.
     */
    address public treasury;
    address public vault;
    address public strategistRemitter;

    /**
     * Fee related constants:
     * {MAX_FEE} - Maximum fee allowed by the strategy. Hard-capped at 10%.
     * {STRATEGIST_MAX_FEE} - Maximum strategist fee allowed by the strategy (as % of treasury fee).
     *                        Hard-capped at 50%
     * {MAX_SECURITY_FEE} - Maximum security fee charged on withdrawal to prevent
     *                      flash deposit/harvest attacks.
     */
    uint256 public constant MAX_FEE = 1000;
    uint256 public constant STRATEGIST_MAX_FEE = 5000;
    uint256 public constant MAX_SECURITY_FEE = 10;

    /**
     * @dev Distribution of fees earned, expressed as % of the profit from each harvest.
     * {totalFee} - divided by 10,000 to determine the % fee. Set to 4.5% by default and
     * lowered as necessary to provide users with the most competitive APY.
     *
     * {callFee} - Percent of the totalFee reserved for the harvester (1000 = 10% of total fee: 0.45% by default)
     * {treasuryFee} - Percent of the totalFee taken by maintainers of the software (9000 = 90% of total fee: 4.05% by default)
     * {strategistFee} - Percent of the treasuryFee taken by strategist (2500 = 25% of treasury fee: 1.0125% by default)
     *
     * {securityFee} - Fee taxed when a user withdraws funds. Taken to prevent flash deposit/harvest attacks.
     * These funds are redistributed to stakers in the pool.
     */
    uint256 public totalFee;
    uint256 public callFee;
    uint256 public treasuryFee;
    uint256 public strategistFee;
    uint256 public securityFee;

    /**
     * {TotalFeeUpdated} Event that is fired each time the total fee is updated.
     * {FeesUpdated} Event that is fired each time callFee+treasuryFee+strategistFee are updated.
     * {StratHarvest} Event that is fired each time the strategy gets harvested.
     * {StrategistRemitterUpdated} Event that is fired each time the strategistRemitter address is updated.
     */
    event TotalFeeUpdated(uint256 newFee);
    event FeesUpdated(uint256 newCallFee, uint256 newTreasuryFee, uint256 newStrategistFee);
    event StratHarvest(address indexed harvester);
    event StrategistRemitterUpdated(address newStrategistRemitter);

    uint256 public upgradeProposalTime;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function __ReaperBaseStrategy_init(
        address _vault,
        address[] memory _feeRemitters,
        address[] memory _strategists
    ) internal onlyInitializing {
        __UUPSUpgradeable_init();
        __AccessControlEnumerable_init();
        __Pausable_init_unchained();

        harvestLogCadence = 1 hours;
        totalFee = 450;
        callFee = 1000;
        treasuryFee = 9000;
        strategistFee = 2500;
        securityFee = 10;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        clearUpgradeCooldown();

        vault = _vault;
        treasury = _feeRemitters[0];
        strategistRemitter = _feeRemitters[1];

        for (uint256 i = 0; i < _strategists.length; i++) {
            _grantRole(STRATEGIST, _strategists[i]);
        }

        harvestLog.push(Harvest({timestamp: block.timestamp, vaultSharePrice: IVault(_vault).getPricePerFullShare()}));
    }

    /**
     * @dev harvest() function that takes care of logging. Subcontracts should
     *      override _harvestCore() and implement their specific logic in it.
     */
    function harvest() external override whenNotPaused {
        _harvestCore();

        if (block.timestamp >= harvestLog[harvestLog.length - 1].timestamp + harvestLogCadence) {
            harvestLog.push(
                Harvest({timestamp: block.timestamp, vaultSharePrice: IVault(vault).getPricePerFullShare()})
            );
        }

        lastHarvestTimestamp = block.timestamp;
        emit StratHarvest(msg.sender);
    }

    function harvestLogLength() external view returns (uint256) {
        return harvestLog.length;
    }

    /**
     * @dev Returns a slice of the harvest log containing the _n latest harvests.
     */
    function latestHarvestLogSlice(uint256 _n) external view returns (Harvest[] memory slice) {
        slice = new Harvest[](_n);
        uint256 sliceCounter = 0;

        for (uint256 i = harvestLog.length - _n; i < harvestLog.length; i++) {
            slice[sliceCounter++] = harvestLog[i];
        }
    }

    /**
     * @dev Traverses the harvest log backwards until it hits _timestamp,
     *      and returns the average APR calculated across all the included
     *      log entries. APR is multiplied by PERCENT_DIVISOR to retain precision.
     */
    function averageAPRSince(uint256 _timestamp) external view returns (int256) {
        require(harvestLog.length >= 2, "need at least 2 log entries");

        int256 runningAPRSum;
        int256 numLogsProcessed;

        for (uint256 i = harvestLog.length - 1; i > 0 && harvestLog[i].timestamp >= _timestamp; i--) {
            runningAPRSum += calculateAPRUsingLogs(i - 1, i);
            numLogsProcessed++;
        }

        return runningAPRSum / numLogsProcessed;
    }

    /**
     * @dev Traverses the harvest log backwards _n items,
     *      and returns the average APR calculated across all the included
     *      log entries. APR is multiplied by PERCENT_DIVISOR to retain precision.
     */
    function averageAPRAcrossLastNHarvests(int256 _n) external view returns (int256) {
        require(harvestLog.length >= 2, "need at least 2 log entries");

        int256 runningAPRSum;
        int256 numLogsProcessed;

        for (uint256 i = harvestLog.length - 1; i > 0 && numLogsProcessed < _n; i--) {
            runningAPRSum += calculateAPRUsingLogs(i - 1, i);
            numLogsProcessed++;
        }

        return runningAPRSum / numLogsProcessed;
    }

    /**
     * @dev Only strategist or owner can edit the log cadence.
     */
    function updateHarvestLogCadence(uint256 _newCadenceInSeconds) external {
        _onlyStrategistOrOwner();
        harvestLogCadence = _newCadenceInSeconds;
    }

    /**
     * @dev updates the total fee, capped at 5%; only owner.
     */
    function updateTotalFee(uint256 _totalFee) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_totalFee <= MAX_FEE, "Fee Too High");
        totalFee = _totalFee;
        emit TotalFeeUpdated(totalFee);
    }

    /**
     * @dev updates the call fee, treasury fee, and strategist fee
     *      call Fee + treasury Fee must add up to PERCENT_DIVISOR
     *
     *      strategist fee is expressed as % of the treasury fee and
     *      must be no more than STRATEGIST_MAX_FEE
     *
     *      only owner
     */
    function updateFees(
        uint256 _callFee,
        uint256 _treasuryFee,
        uint256 _strategistFee
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        require(_callFee + _treasuryFee == PERCENT_DIVISOR, "sum != PERCENT_DIVISOR");
        require(_strategistFee <= STRATEGIST_MAX_FEE, "strategist fee > STRATEGIST_MAX_FEE");

        callFee = _callFee;
        treasuryFee = _treasuryFee;
        strategistFee = _strategistFee;
        emit FeesUpdated(callFee, treasuryFee, strategistFee);
        return true;
    }

    function updateSecurityFee(uint256 _securityFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_securityFee <= MAX_SECURITY_FEE, "fee to high!");
        securityFee = _securityFee;
    }

    /**
     * @dev only owner can update treasury address.
     */
    function updateTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        treasury = newTreasury;
        return true;
    }

    /**
     * @dev Updates the current strategistRemitter.
     *      If there is only one strategist this function may be called by
     *      that strategist. However if there are multiple strategists
     *      this function may only be called by the STRATEGIST_MULTISIG role.
     */
    function updateStrategistRemitter(address _newStrategistRemitter) external {
        if (getRoleMemberCount(STRATEGIST) == 1) {
            _checkRole(STRATEGIST, msg.sender);
        } else {
            _checkRole(STRATEGIST_MULTISIG, msg.sender);
        }

        require(_newStrategistRemitter != address(0), "!0");
        strategistRemitter = _newStrategistRemitter;
        emit StrategistRemitterUpdated(_newStrategistRemitter);
    }

    /**
     * @dev DEFAULT_ADMIN_ROLE must call this function prior to upgrading the implementation
     *      and wait UPGRADE_TIMELOCK seconds before executing the upgrade.
     */
    function initiateUpgradeCooldown() external onlyRole(DEFAULT_ADMIN_ROLE) {
        upgradeProposalTime = block.timestamp;
    }

    /**
     * @dev This function is called:
     *      - in initialize()
     *      - as part of a successful upgrade
     *      - manually by DEFAULT_ADMIN_ROLE to clear the upgrade cooldown.
     */
    function clearUpgradeCooldown() public onlyRole(DEFAULT_ADMIN_ROLE) {
        upgradeProposalTime = block.timestamp + (ONE_YEAR * 100);
    }

    /**
     * @dev Only allow access to strategist or owner
     */
    function _onlyStrategistOrOwner() internal view {
        require(hasRole(STRATEGIST, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not authorized");
    }

    function calculateAPRUsingLogs(uint256 _startIndex, uint256 _endIndex) public view returns (int256) {
        Harvest storage start = harvestLog[_startIndex];
        Harvest storage end = harvestLog[_endIndex];
        bool increasing = true;
        if (end.vaultSharePrice < start.vaultSharePrice) {
            increasing = false;
        }

        uint256 unsignedSharePriceChange;
        if (increasing) {
            unsignedSharePriceChange = end.vaultSharePrice - start.vaultSharePrice;
        } else {
            unsignedSharePriceChange = start.vaultSharePrice - end.vaultSharePrice;
        }

        uint256 unsignedPercentageChange = (unsignedSharePriceChange * 1e18) / start.vaultSharePrice;
        uint256 timeDifference = end.timestamp - start.timestamp;

        uint256 yearlyUnsignedPercentageChange = (unsignedPercentageChange * ONE_YEAR) / timeDifference;
        yearlyUnsignedPercentageChange /= 1e14; // restore basis points precision

        if (increasing) {
            return int256(yearlyUnsignedPercentageChange);
        }

        return -int256(yearlyUnsignedPercentageChange);
    }

    /**
     * @dev Returns the approx amount of profit from harvesting plus fee that
     *      would be returned to harvest caller.
     */
    function estimateHarvest() external view virtual returns (uint256 profit, uint256 callFeeToUser);

    function balanceOf() public view virtual override returns (uint256);

    /**
     * @dev subclasses should add their custom harvesting logic in this function
     *      including charging any fees.
     */
    function _harvestCore() internal virtual;

    /**
     * @dev This function must be overriden simply for access control purposes.
     *      Only DEFAULT_ADMIN_ROLE can upgrade the implementation once the timelock
     *      has passed.
     */
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(upgradeProposalTime + UPGRADE_TIMELOCK < block.timestamp, "cooldown not initiated or still active");
        clearUpgradeCooldown();
    }
}