const { ethers } = require('ethers');

const deterministicInput = ethers.utils.defaultAbiCoder.encode(
    ['string', 'uint256'], 
    ['deniz-umut', 12345]
);

// Generate a deterministic vkHash
const vkHash = ethers.utils.keccak256(deterministicInput);
const vkHashBytes32 = ethers.utils.hexZeroPad(vkHash, 32); 

console.log(`Deterministic vkHash: ${vkHashBytes32}`);
