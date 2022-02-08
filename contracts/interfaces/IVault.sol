// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.8.11;

interface IVault {
    function getPricePerFullShare() external view returns (uint256);
}