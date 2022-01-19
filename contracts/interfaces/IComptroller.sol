// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import './CTokenI.sol';
interface IComptroller {
    function claimComp(address holder, CTokenI[] memory _scTokens) external;
    function claimComp(address holder) external;
    function enterMarkets(address[] memory _scTokens) external;
    function pendingComptrollerImplementation() external view returns (address implementation);
}