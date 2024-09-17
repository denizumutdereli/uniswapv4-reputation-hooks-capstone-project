// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// solhint-disable no-inline-assembly

library WordCodec {
    
    /**
     * @dev Inserts an unsigned integer of `bitLength`, shifted by an `offset`, into a 256-bit word (`bytes32`).
     * It replaces the old value in the word and returns the new word.
     * ------------------------------------------------------------------------------
     * |        Unused bits         | Inserted value (bitLength) |    Remaining     |
     * | <---(256 - offset - bitLength)---> | <---bitLength---> | <---offset---> |
     * ------------------------------------------------------------------------------
     * 
     * @param word The original 256-bit word.
     * @param value The value to be inserted.
     * @param offset The bit offset where the value will be inserted.
     * @param bitLength The length in bits of the value to be inserted.
     * @return result The new word with the value inserted.
     */
    function insertUint(bytes32 word, uint256 value, uint256 offset, uint256 bitLength) internal pure returns (bytes32 result) {
        assembly {
            let mask := sub(shl(bitLength, 1), 1)        // Mask to isolate the bitLength size portion
            let clearedWord := and(word, not(shl(offset, mask)))  // Clear old value at offset
            result := or(clearedWord, shl(offset, value)) // Insert new value at offset
        }
    }

    /**
     * @dev Decodes an unsigned integer of `bitLength` from a `bytes32` word, shifted by an `offset`.
     * ------------------------------------------------------------------------------
     * |        Unused bits         | Extracted value (bitLength) |    Remaining     |
     * | <---(256 - offset - bitLength)---> | <---bitLength---> | <---offset---> |
     * ------------------------------------------------------------------------------
     * 
     * @param word The original 256-bit word.
     * @param offset The bit offset where the value is located.
     * @param bitLength The length in bits of the value to be extracted.
     * @return result The extracted unsigned integer value.
     */
    function decodeUint(bytes32 word, uint256 offset, uint256 bitLength) internal pure returns (uint256 result) {
        assembly {
            result := and(shr(offset, word), sub(shl(bitLength, 1), 1)) // Right shift, mask, and return value
        }
    }

    /**
     * @dev Inserts a signed integer shifted by an `offset` into a 256-bit word, replacing the old value.
     * ------------------------------------------------------------------------------
     * |        Unused bits         | Inserted value (bitLength) |    Remaining     |
     * | <---(256 - offset - bitLength)---> | <---bitLength---> | <---offset---> |
     * ------------------------------------------------------------------------------
     *
     * @param word The original 256-bit word.
     * @param value The signed integer value to insert.
     * @param offset The bit offset where the value will be inserted.
     * @param bitLength The length in bits of the value to be inserted.
     * @return result The new word with the signed integer inserted.
     */
    function insertInt(bytes32 word, int256 value, uint256 offset, uint256 bitLength) internal pure returns (bytes32) {
        unchecked {
            uint256 mask = (1 << bitLength) - 1;  // Mask to isolate the bitLength size portion
            bytes32 clearedWord = bytes32(uint256(word) & ~(mask << offset)); // Clear old value at offset
            return clearedWord | bytes32((uint256(value) & mask) << offset);  // Insert new value at offset
        }
    }

    /**
     * @dev Decodes a signed integer of `bitLength` from a `bytes32` word, shifted by an `offset`.
     * ------------------------------------------------------------------------------
     * |        Unused bits         | Extracted value (bitLength) |    Remaining     |
     * | <---(256 - offset - bitLength)---> | <---bitLength---> | <---offset---> |
     * ------------------------------------------------------------------------------
     *
     * @param word The original 256-bit word.
     * @param offset The bit offset where the value is located.
     * @param bitLength The length in bits of the value to be extracted.
     * @return result The extracted signed integer value.
     */
    function decodeInt(bytes32 word, uint256 offset, uint256 bitLength) internal pure returns (int256 result) {
        unchecked {
            int256 maxInt = int256((1 << (bitLength - 1)) - 1);  // Maximum positive value for bitLength
            uint256 mask = (1 << bitLength) - 1;                 // Mask to isolate the bitLength size portion
            int256 value = int256(uint256(word >> offset) & mask); // Extract value
            // If value exceeds maxInt, it's a negative number. Adjust using two's complement.
            assembly {
                result := or(mul(gt(value, maxInt), not(mask)), value)
            }
        }
    }

    /**
     * @dev Decodes a boolean value shifted by an `offset` from a 256-bit word.
     * ------------------------------------------------------------------------------
     * |        Unused bits         |       1-bit Boolean Value       |    Remaining     |
     * | <---(256 - offset - 1)---> | <---Boolean---> | <---offset---> |
     * ------------------------------------------------------------------------------
     * 
     * @param word The original 256-bit word.
     * @param offset The bit offset where the boolean is located.
     * @return result The extracted boolean value.
     */
    function decodeBool(bytes32 word, uint256 offset) internal pure returns (bool result) {
        assembly {
            result := and(shr(offset, word), 1) // Extract the boolean value by shifting and masking
        }
    }

    /**
     * @dev Inserts a boolean value shifted by an `offset` into a 256-bit word.
     * ------------------------------------------------------------------------------
     * |        Unused bits         |       1-bit Boolean Value       |    Remaining     |
     * | <---(256 - offset - 1)---> | <---Boolean---> | <---offset---> |
     * ------------------------------------------------------------------------------
     * 
     * @param word The original 256-bit word.
     * @param value The boolean value to insert.
     * @param offset The bit offset where the boolean will be inserted.
     * @return result The new word with the boolean inserted.
     */
    function insertBool(bytes32 word, bool value, uint256 offset) internal pure returns (bytes32 result) {
        assembly {
            let clearedWord := and(word, not(shl(offset, 1)))  // Clear old value at offset
            result := or(clearedWord, shl(offset, value))      // Insert new value
        }
    }

    /**
     * @dev Clears a portion of the `word` by setting a range of bits to zero, defined by the `offset` and `bitLength`.
     * ------------------------------------------------------------------------------
     * |        Unused bits         |         Cleared bits (bitLength)        |    Remaining     |
     * | <---(256 - offset - bitLength)---> | <---bitLength---> | <---offset---> |
     * ------------------------------------------------------------------------------
     * 
     * @param word The original 256-bit word.
     * @param offset The bit offset where the cleared portion starts.
     * @param bitLength The length in bits of the cleared portion.
     * @return clearedWord The word with the cleared portion.
     */
    function clearWordAtPosition(bytes32 word, uint256 offset, uint256 bitLength) internal pure returns (bytes32 clearedWord) {
        unchecked {
            uint256 mask = (1 << bitLength) - 1;  // Mask to isolate the bitLength size portion
            clearedWord = bytes32(uint256(word) & ~(mask << offset)); // Clear specified range at offset
        }
    }

    /**
     * @dev Encodes an address into a 256-bit word at a given `offset`.
     * ------------------------------------------------------------------------------
     * |        Unused bits         |       Encoded address (160 bits)        |    Remaining     |
     * | <---(256 - offset - 160)---> | <---160 bits---> | <---offset---> |
     * ------------------------------------------------------------------------------
     *
     * @param word The original 256-bit word.
     * @param value The address to encode.
     * @param offset The bit offset where the address will be inserted.
     * @return result The new word with the address inserted.
     */
    function insertAddress(bytes32 word, address value, uint256 offset) internal pure returns (bytes32 result) {
        assembly {
            let clearedWord := and(word, not(shl(offset, 0xffffffffffffffffffffffffffffffffffffffff))) // Clear old address
            result := or(clearedWord, shl(offset, value))  // Insert new address at offset
        }
    }

    /**
     * @dev Decodes an address from a 256-bit word at a given `offset`.
     * ------------------------------------------------------------------------------
     * |        Unused bits         |       Extracted address (160 bits)        |    Remaining     |
     * | <---(256 - offset - 160)---> | <---160 bits---> | <---offset---> |
     * ------------------------------------------------------------------------------
     *
     * @param word The original 256-bit word.
     * @param offset The bit offset where the address is located.
     * @return result The decoded address.
     */
    function decodeAddress(bytes32 word, uint256 offset) internal pure returns (address result) {
        assembly {
            result := and(shr(offset, word), 0xffffffffffffffffffffffffffffffffffffffff)  // Extract address
        }
    }

    /**
     * @dev Encodes an enum value into a 256-bit word at a given `offset`.
     * ------------------------------------------------------------------------------
     * |        Unused bits         |      Enum value (8 bits)       |    Remaining     |
     * | <---(256 - offset - 8)---> | <---8 bits---> | <---offset---> |
     * ------------------------------------------------------------------------------
     *
     * @param word The original 256-bit word.
     * @param value The enum value to encode.
     * @param offset The bit offset where the enum value will be inserted.
     * @return result The new word with the enum value inserted.
     */
    function insertEnum(bytes32 word, uint8 value, uint256 offset) internal pure returns (bytes32 result) {
        assembly {
            let clearedWord := and(word, not(shl(offset, 0xff))) // Clear old enum value
            result := or(clearedWord, shl(offset, value))  // Insert new enum value
        }
    }

    /**
     * @dev Decodes an enum value from a 256-bit word at a given `offset`.
     * ------------------------------------------------------------------------------
     * |        Unused bits         |      Extracted enum value (8 bits)       |    Remaining     |
     * | <---(256 - offset - 8)---> | <---8 bits---> | <---offset---> |
     * ------------------------------------------------------------------------------
     *
     * @param word The original 256-bit word.
     * @param offset The bit offset where the enum value is located.
     * @return result The decoded enum value.
     */
    function decodeEnum(bytes32 word, uint256 offset) internal pure returns (uint8 result) {
        assembly {
            result := and(shr(offset, word), 0xff)  // Extract enum value
        }
    }
}
