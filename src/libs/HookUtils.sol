// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReputationLogic} from "../ReputationLogic.sol";

library HookUtils {
    error ZeroAddress(string field);
    error AutomationIntervalTooShort(uint24 automationInterval);
    error BaseFeeOutOfRange(uint24 _baseFee);

    function validateUniswapParams(
        address _admin,
        address _reputationOracle,
        uint24 _automationInterval,
        uint24 _baseFee
    ) internal pure {
        if (_admin == address(0)) {
            revert ZeroAddress("Admin address");
        }

        if (_reputationOracle == address(0)) {
            revert ZeroAddress("Reputation oracle address");
        }

        if (_automationInterval < 5 minutes) {
            revert AutomationIntervalTooShort(_automationInterval);
        }

        if (_baseFee < 1000 || _baseFee > 10000) {
            revert BaseFeeOutOfRange(_baseFee);
        }
    }

    function deployReputationLogic(
        address implementation,
        address admin,
        address reputationOracle,
        uint24 automationInterval
    ) internal returns (address) {
        address clone = Clones.clone(implementation);

        ReputationLogic(payable(clone)).initialize(
            admin,
            reputationOracle,
            automationInterval
        );

        return clone;
    }
}
