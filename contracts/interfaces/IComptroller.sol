// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import './CTokenI.sol';
interface IComptroller {
    function claimComp(address holder, CTokenI[] memory _scTokens) external;
    function claimComp(address holder) external;
    function enterMarkets(address[] memory _scTokens) external;
    function pendingComptrollerImplementation() view external returns (address implementation);
    function markets(address ctoken)
        external
        view
        returns (
            bool,
            uint256,
            bool
        );

}