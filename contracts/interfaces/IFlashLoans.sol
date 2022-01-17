// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./IFlashLoanRecipient.sol";

interface IFlashLoans {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}