// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionManager} from "../interfaces/IDistributionManager.sol";
import {IYieldModule} from "../interfaces/IYieldModule.sol";
import {IVotingModule} from "../interfaces/IVotingModule.sol";
import {IRecipientRegistry} from "../interfaces/IRecipientRegistry.sol";
import {ICycleModule} from "../interfaces/ICycleModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title AbstractDistributionManager
/// @notice Abstract contract that manages yield claiming and distribution to strategies
/// @dev Claims yield from base token and distributes to the base strategy when conditions are met
abstract contract AbstractDistributionManager is Initializable, OwnableUpgradeable, IDistributionManager {
    using SafeERC20 for IERC20;

    /// @notice Module that exposes yield accrual on the base token
    IYieldModule public yieldModule;
    /// @notice Module that tracks voting power and distribution weights
    IVotingModule public votingModule;
    /// @notice Registry of eligible distribution recipients
    IRecipientRegistry public recipientRegistry;
    /// @notice Cycle module that governs distribution timing
    ICycleModule public cycleManager;
    /// @notice ERC-20 token from which yield is claimed and distributed
    IERC20 public baseToken;

    /// @dev Initializes the distribution manager
    /// @param _cycleManager Address of the cycle manager
    /// @param _recipientRegistry Address of the recipient registry
    /// @param _baseToken Address of the base token with yield
    /// @param _votingModule Address of the voting module
    function __AbstractDistributionManager_init(
        address _cycleManager,
        address _recipientRegistry,
        address _baseToken,
        address _votingModule
    ) internal onlyInitializing {
        __Ownable_init(msg.sender);
        __AbstractDistributionManager_init_unchained(_cycleManager, _recipientRegistry, _baseToken, _votingModule);
    }

    function __AbstractDistributionManager_init_unchained(
        address _cycleManager,
        address _recipientRegistry,
        address _baseToken,
        address _votingModule
    ) internal onlyInitializing {
        if (_cycleManager == address(0)) revert ZeroAddress();
        if (_recipientRegistry == address(0)) revert ZeroAddress();
        if (_baseToken == address(0)) revert ZeroAddress();
        if (_votingModule == address(0)) revert ZeroAddress();

        cycleManager = ICycleModule(_cycleManager);
        recipientRegistry = IRecipientRegistry(_recipientRegistry);
        baseToken = IERC20(_baseToken);
        votingModule = IVotingModule(_votingModule);

        // Assume base token implements IYieldModule
        yieldModule = IYieldModule(_baseToken);
    }

    /// @notice Checks if distribution is ready
    /// @dev Must be implemented by child contracts with their own readiness criteria
    function isDistributionReady() public view virtual override returns (bool ready);

    /// @notice Claims yield from the base token and distributes
    /// @dev Must be implemented by child contracts
    function claimAndDistribute() external virtual;

    /// @notice Gets the total current voting power from voting module
    /// @dev This should sum up all active votes or return total voting power
    /// @return totalPower The total voting power currently active
    function getTotalCurrentVotingPower() public view virtual returns (uint256 totalPower) {
        // Get current voting distribution and sum it up
        uint256[] memory distribution = votingModule.getCurrentVotingDistribution();
        for (uint256 i = 0; i < distribution.length; i++) {
            totalPower += distribution[i];
        }
    }
}
