// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DistributionManager} from "./DistributionManager.sol";
import {IDistributionStrategy} from "../interfaces/IDistributionStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MultiStrategyDistributionManager
/// @notice Concrete implementation of DistributionManager that distributes to multiple strategies equally
/// @dev Distributes yield equally across all configured strategies
contract MultiStrategyDistributionManager is DistributionManager {
    using SafeERC20 for IERC20;

    address[] public strategies;

    event StrategiesInitialized(address[] strategies);

    /// @notice Initializes the MultiStrategyDistributionManager with multiple strategies
    /// @param _cycleManager Address of the cycle manager
    /// @param _recipientRegistry Address of the recipient registry
    /// @param _baseToken Address of the base token with yield
    /// @param _votingModule Address of the voting module
    /// @param _strategies Array of distribution strategy addresses to distribute to
    function initialize(
        address _cycleManager,
        address _recipientRegistry,
        address _baseToken,
        address _votingModule,
        address[] calldata _strategies
    ) external initializer {
        // Initialize parent DistributionManager
        __DistributionManager_init(_cycleManager, _recipientRegistry, _baseToken, _votingModule);

        // Store strategies
        require(_strategies.length > 0, "No strategies provided");
        strategies = _strategies;
        emit StrategiesInitialized(_strategies);
    }

    /// @notice Claims yield and distributes equally to all strategies
    /// @dev Can be called by owner or cycle manager
    function claimAndDistribute() external override {
        // Allow both owner and cycle manager to call this
        require(msg.sender == owner() || msg.sender == cycleManager, "Unauthorized");

        if (!isDistributionReady()) revert DistributionNotReady();
        require(strategies.length > 0, "No strategies configured");

        // Get the amount of yield available
        uint256 yieldAmount = yieldModule.yieldAccrued();
        if (yieldAmount == 0) revert NoYieldAvailable();

        // Claim yield to this contract
        yieldModule.claimYield(yieldAmount, address(this));
        emit YieldClaimed(yieldAmount);

        // Calculate amount per strategy (equal distribution)
        uint256 amountPerStrategy = yieldAmount / strategies.length;

        // Distribute to each strategy
        for (uint256 i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];

            // Transfer tokens to strategy
            baseToken.safeTransfer(strategy, amountPerStrategy);

            // Trigger distribution in strategy
            IDistributionStrategy(strategy).distribute(amountPerStrategy);

            emit YieldDistributed(strategy, amountPerStrategy);
        }
    }

    /// @notice Gets all configured strategies
    /// @return Array of strategy addresses
    function getStrategies() external view returns (address[] memory) {
        return strategies;
    }

    /// @notice Gets the number of configured strategies
    /// @return The number of strategies
    function getStrategyCount() external view returns (uint256) {
        return strategies.length;
    }
}
