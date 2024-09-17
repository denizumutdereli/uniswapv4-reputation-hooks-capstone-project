// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";

abstract contract CustomAccessControl is AccessControl {
    function _initializeAccessControl(address admin) internal {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }
}
