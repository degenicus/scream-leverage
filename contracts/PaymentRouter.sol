// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./interfaces/IPaymentSplitter.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/finance/PaymentSplitter.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract PaymentRouter is AccessControlEnumerable {
    bytes32 public constant STRATEGIST = keccak256("STRATEGIST");

    mapping(address => address) public splitterForStrategy;
    mapping(address => address[]) public splittersForStrategist;

    constructor(address[] memory _strategists) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        for (uint256 i = 0; i < _strategists.length; i++) {
            _grantRole(STRATEGIST, _strategists[i]);
        }
    }

    /**
     * Function to be used by owner or strategists to
     * register a new strategy with the router.
     *
     * @dev creates a new PaymentSplitter contract for
     *      this new strategy
     */
    function addStrategy(
        address _strategy,
        address[] calldata _strategists,
        uint256[] calldata _shares
    ) external {
        _onlyStrategistOrOwner();

        address splitterAddr = address(
            new PaymentSplitter(_strategists, _shares)
        );
        splitterForStrategy[_strategy] = splitterAddr;

        for (uint256 i; i < _strategists.length; i++) {
            splittersForStrategist[_strategists[i]].push(splitterAddr);
        }
    }

    /**
     * Receives payment in given ERC20 token and routes it
     * to the corresponding PaymentSplitter. Contract must
     * be approved to pull the required _amount of _token
     * from msg.sender
     *
     * @dev must be called directly from a startegy
     *      that is registered with this router.
     */
    function routePayment(IERC20 _token, uint256 _amount) external {
        require(_amount != 0, "!0");

        address splitterAddr = splitterForStrategy[msg.sender];
        require(splitterAddr != address(0), "!registered");

        SafeERC20.safeTransferFrom(_token, msg.sender, splitterAddr, _amount);
    }

    /**
     * Used by strategists to pull _token amounts corresponding
     * to their shares across all PaymentSplitters where they
     * are registered as payees.
     *
     * @dev can only be called by STRATEGIST role
     */
    function release(address _token) external onlyRole(STRATEGIST) {
        address[] storage splitters = splittersForStrategist[msg.sender];
        for (uint256 i; i < splitters.length; i++) {
            // don't revert whole tx if individual splitter owes nothing
            try
                IPaymentSplitter(splitters[i]).release(_token, msg.sender)
            {} catch {}
        }
    }

    function _onlyStrategistOrOwner() internal view {
        require(
            hasRole(STRATEGIST, msg.sender) ||
                hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Not authorized"
        );
    }
}
