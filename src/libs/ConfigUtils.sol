// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library ConfigUtils {
    // Struct to store config data for baseFee, automationInterval, and isDynamicFee flag
    struct ConfigData {
        uint24 baseFee; // Fee applied to transactions
        uint24 automationInterval; // Interval for automatic operations
        bool isDynamicFee; // Flag to indicate if the fee is dynamic
    }

    /**
     * @notice Packs the ConfigData into a single `bytes32` variable using bitwise operations.
     * Packed layout in bytes32:
     * -----------------------------------------------------------------------
     * | baseFee (24 bits) [96:119] | automationInterval (24 bits) [48:71] | isDynamicFee (1 bit) [0] |
     * -----------------------------------------------------------------------
     */

    // Function to pack ConfigData into bytes32
    function packConfig(
        ConfigData memory config
    ) internal pure returns (bytes32) {
        return
            bytes32(
                (uint256(config.baseFee) << 96) | // baseFee is stored in bits [96:119]
                    (uint256(config.automationInterval) << 48) | // automationInterval is stored in bits [48:71]
                    (config.isDynamicFee ? 1 : 0) // isDynamicFee flag stored in the least significant bit [0]
            );
    }

    // Function to unpack bytes32 config data into ConfigData struct
    function unpackConfig(
        bytes32 config
    ) internal pure returns (ConfigData memory) {
        return
            ConfigData({
                // Extract baseFee from bits [96:119]
                baseFee: uint24(uint256(config >> 96) & 0xFFFFFF), // Mask to extract the 24 bits for baseFee
                // Extract automationInterval from bits [48:71]
                automationInterval: uint24(uint256(config >> 48) & 0xFFFFFF), // Mask to extract the 24 bits for automationInterval
                // Extract the isDynamicFee flag from bit [0]
                isDynamicFee: (uint256(config) & 1) == 1 // Use bitwise AND to check if the least significant bit is set
            });
    }

    /**
     * @notice Extracts the baseFee from the packed bytes32 config.
     * Returns the 24-bit baseFee stored at bits [96:119].
     */
    function getBaseFee(bytes32 config) internal pure returns (uint24) {
        return uint24((uint256(config) >> 96) & 0xFFFFFF); // Mask to extract baseFee from bits [96:119]
    }

    /**
     * @notice Extracts the automationInterval from the packed bytes32 config.
     * Returns the 24-bit automationInterval stored at bits [48:71].
     */
    function getAutomationInterval(
        bytes32 config
    ) internal pure returns (uint24) {
        return uint24((uint256(config) >> 48) & 0xFFFFFF); // Mask to extract automationInterval from bits [48:71]
    }

    /**
     * @notice Extracts the isDynamicFee flag from the packed bytes32 config.
     * Returns the boolean value stored at bit [0].
     */
    function isDynamicFee(bytes32 config) internal pure returns (bool) {
        return (uint256(config) & 1) == 1; // Check if the least significant bit [0] is set to determine if the fee is dynamic
    }

    /**
     * @notice Updates the baseFee in the packed bytes32 config.
     * Replaces the 24-bit baseFee in bits [96:119].
     */
    function setBaseFee(
        bytes32 config,
        uint24 newBaseFee
    ) internal pure returns (bytes32) {
        return
            (config & ~(bytes32(uint256(0xFFFFFF) << 96))) |
            (bytes32(uint256(newBaseFee)) << 96); // Clear old baseFee and set new one in bits [96:119]
    }

    /**
     * @notice Updates the automationInterval in the packed bytes32 config.
     * Replaces the 24-bit automationInterval in bits [48:71].
     */
    function setAutomationInterval(
        bytes32 config,
        uint24 newAutomationInterval
    ) internal pure returns (bytes32) {
        return
            (config & ~(bytes32(uint256(0xFFFFFF) << 48))) |
            (bytes32(uint256(newAutomationInterval)) << 48); // Clear old automationInterval and set new one in bits [48:71]
    }

    /**
     * @notice Updates the isDynamicFee flag in the packed bytes32 config.
     * Updates the boolean flag in bit [0].
     */
    function setIsDynamicFee(
        bytes32 config,
        bool newIsDynamicFee
    ) internal pure returns (bytes32) {
        return
            (config & ~bytes32(uint256(1))) |
            (newIsDynamicFee ? bytes32(uint256(1)) : bytes32(0)); // Set or clear the least significant bit [0]
    }

    /**
     * @notice Updates all parameters (baseFee, automationInterval, isDynamicFee) in the packed config.
     */
    function updateConfig(
        bytes32 config,
        uint24 newBaseFee,
        uint24 newAutomationInterval,
        bool newIsDynamicFee
    ) internal pure returns (bytes32) {
        config = setBaseFee(config, newBaseFee); // Update baseFee in bits [96:119]
        config = setAutomationInterval(config, newAutomationInterval); // Update automationInterval in bits [48:71]
        config = setIsDynamicFee(config, newIsDynamicFee); // Update isDynamicFee in bit [0]
        return config;
    }

    /**
     * @notice Updates only the automationInterval in the packed bytes32 config.
     */
    function updateAutomationInterval(
        bytes32 config,
        uint24 newAutomationInterval
    ) internal pure returns (bytes32) {
        return setAutomationInterval(config, newAutomationInterval); // Update only the automationInterval in bits [48:71]
    }
}
