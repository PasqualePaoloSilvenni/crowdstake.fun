// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionManager} from "../interfaces/IDistributionManager.sol";
import {IYieldModule} from "../interfaces/IYieldModule.sol";
import {IVotingModule} from "../interfaces/IVotingModule.sol";
import {IRecipientRegistry} from "../interfaces/IRecipientRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title DistributionManager
/// @notice Abstract contract that manages yield claiming and distribution to strategies
/// @dev Claims yield from base token and distributes to the base strategy when conditions are met
abstract contract DistributionManager is Initializable, OwnableUpgradeable, IDistributionManager {
    using SafeERC20 for IERC20;

    IYieldModule public yieldModule;
    IVotingModule public votingModule;
    IRecipientRegistry public recipientRegistry;
    address public cycleManager;
    IERC20 public baseToken;

    /// @dev Initializes the distribution manager
    /// @param _cycleManager Address of the cycle manager
    /// @param _recipientRegistry Address of the recipient registry
    /// @param _baseToken Address of the base token with yield
    /// @param _votingModule Address of the voting module
    function __DistributionManager_init(
        address _cycleManager,
        address _recipientRegistry,
        address _baseToken,
        address _votingModule
    ) internal onlyInitializing {
        __Ownable_init(msg.sender);
        __DistributionManager_init_unchained(_cycleManager, _recipientRegistry, _baseToken, _votingModule);
    }

    function __DistributionManager_init_unchained(
        address _cycleManager,
        address _recipientRegistry,
        address _baseToken,
        address _votingModule
    ) internal onlyInitializing {
        if (_cycleManager == address(0)) revert ZeroAddress();
        if (_recipientRegistry == address(0)) revert ZeroAddress();
        if (_baseToken == address(0)) revert ZeroAddress();
        if (_votingModule == address(0)) revert ZeroAddress();

        cycleManager = _cycleManager;
        recipientRegistry = IRecipientRegistry(_recipientRegistry);
        baseToken = IERC20(_baseToken);
        votingModule = IVotingModule(_votingModule);

        // Assume base token implements IYieldModule
        yieldModule = IYieldModule(_baseToken);
    }

    /// @notice Checks if distribution is ready based on votes and yield
    /// @dev Returns true if there are votes > 0 and yield accrued > recipient count
    /// @return ready True if distribution conditions are met
    function isDistributionReady() public view override returns (bool ready) {
        // Get total voting power to check if there are any votes
        uint256 totalVotes = getTotalCurrentVotingPower();
        if (totalVotes == 0) {
            return false;
        }

        // Get recipient count
        uint256 recipientCount = recipientRegistry.getRecipientCount();
        if (recipientCount == 0) {
            return false;
        }

        // Get accrued yield
        uint256 yieldAccrued = yieldModule.yieldAccrued();

        // Distribution is ready if yield >= recipient count (ensures each recipient gets at least 1 wei)
        return yieldAccrued >= recipientCount;
    }

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

    /// @notice Modifier to restrict access to cycle manager
    modifier onlyCycleManager() {
        require(msg.sender == cycleManager, "Only cycle manager");
        _;
    }
}
