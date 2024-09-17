// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../interfaces/mocks/IEigenLayerModule.sol";
import "../interfaces/mocks/ISlasher.sol";
import "../interfaces/mocks/IStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MockStETH.sol";

contract MockEigenLayerModule is IEigenLayerModule, IStrategy {
    // Simulated total collateral (for testing)
    uint256 public totalCollateral;

    // Event to track collateral deposits (for testing)
    event CollateralDeposited(address indexed pool, uint256 amount);

    // Mock stETH token
    MockStETH public mockStETH;

    constructor() {
        // Create a mock stETH token
        mockStETH = new MockStETH("Mock stETH", "mstETH");
    }

    // Function to simulate collateral deposits (now mints mock stETH)
    function depositCollateral(address _pool) external payable override {
        totalCollateral += msg.value;
        emit CollateralDeposited(_pool, msg.value);

        // Mint mock stETH to the pool, representing their staked ETH
        mockStETH.mint(_pool, msg.value);
    }

    // Function to simulate collateral withdrawals (burns mock stETH)
    function withdrawCollateral(
        address _recipient,
        uint256 _amount
    ) external override {
        require(totalCollateral >= _amount, "Insufficient collateral");
        totalCollateral -= _amount;

        // Burn mock stETH from the recipient before transferring ETH
        require(
            mockStETH.burnFrom(_recipient, _amount),
            "stETH burn failed"
        );

        payable(_recipient).transfer(_amount);
    }

    // Function to simulate slashing collateral
    function slashCollateral(address, uint256 _amount) external override {
        require(totalCollateral >= _amount, "Insufficient collateral");
        totalCollateral -= _amount;
    }

    // Function to simulate RO token minting notification (no real action needed here)
    function onROTokensMinted(uint256) external override {}

    // --- IStrategy Mock Implementations ---

    function deposit(
        IERC20,
        uint256
    ) external pure override returns (uint256) {
        revert("Not implemented in mock");
    }

    function withdraw(
        address,
        IERC20,
        uint256
    ) external pure override {
        revert("Not implemented in mock");
    }

    function sharesToUnderlying(
        uint256
    ) external pure override returns (uint256) {
        revert("Not implemented in mock");
    }

    function underlyingToShares(
        uint256
    ) external pure override returns (uint256) {
        revert("Not implemented in mock");
    }

    function userUnderlying(address) external pure override returns (uint256) {
        revert("Not implemented in mock");
    }

    function shares(address) external pure override returns (uint256) {
        revert("Not implemented in mock");
    }

    function sharesToUnderlyingView(
        uint256
    ) external pure override returns (uint256) {
        revert("Not implemented in mock");
    }

    function underlyingToSharesView(
        uint256
    ) external pure override returns (uint256) {
        revert("Not implemented in mock");
    }

    function userUnderlyingView(
        address
    ) external pure override returns (uint256) {
        revert("Not implemented in mock");
    }

    function underlyingToken() external view override returns (IERC20) {
        return mockStETH;
    }

    function totalShares() external pure override returns (uint256) {
        revert("Not implemented in mock");
    }

    function explanation() external pure override returns (string memory) {
        revert("Not implemented in mock");
    }

    function sendYield(
        address _receivingAddres,
        uint256 _amount
    ) external {
        IERC20(address(mockStETH)).transfer(_receivingAddres, _amount);
    }

    // slashing (for testing)
    function mockOptIntoSlashing(address _slasherContract) external {
        ISlasher(_slasherContract).optIntoSlashing(address(this));
    }
}
