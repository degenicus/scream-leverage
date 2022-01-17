// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;
interface IComptroller {
    function claimComp(address holder, address[] calldata _scTokens) external;
    function claimComp(address holder) external;
    function enterMarkets(address[] memory _scTokens) external;
    function pendingComptrollerImplementation() view external returns (address implementation);
}