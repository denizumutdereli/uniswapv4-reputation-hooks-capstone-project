// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract CustomReentrancyGuard {
    uint256 private _status;

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    function _initializeReentrancyGuard() internal {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // Reset _status
        _status = _NOT_ENTERED;
    }
}
