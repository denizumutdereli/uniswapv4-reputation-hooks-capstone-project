// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IEigenLayerModule {
    function depositCollateral(address _pool) external payable;

    function withdrawCollateral(address _recipient, uint256 _amount) external;

    function slashCollateral(address _pool, uint256 _amount) external;

    function onROTokensMinted(uint256 _amount) external;
}
