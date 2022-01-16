// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface IPaymentRouter {
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    function STRATEGIST() external view returns (bytes32);

    function addStrategy(
        address _strategy,
        address[] calldata _strategists,
        uint256[] calldata _shares
    ) external;

    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    function getRoleMember(bytes32 role, uint256 index)
        external
        view
        returns (address);

    function getRoleMemberCount(bytes32 role) external view returns (uint256);

    function grantRole(bytes32 role, address account) external;

    function hasRole(bytes32 role, address account)
        external
        view
        returns (bool);

    function release(address _token) external;

    function renounceRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function routePayment(address _token, uint256 _amount) external;

    function splitterForStrategy(address) external view returns (address);

    function splittersForStrategist(address, uint256)
        external
        view
        returns (address);

    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
