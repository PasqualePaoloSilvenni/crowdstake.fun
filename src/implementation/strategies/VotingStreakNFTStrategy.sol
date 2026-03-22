// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractDistributionStrategy} from "../../abstract/AbstractDistributionStrategy.sol";
import {IBreadkitNFT} from "../../interfaces/IBreadkitNFT.sol";

/// @title VotingStreakNFTStrategy
/// @notice Tracks consecutive voting activity and mints a Breadkit NFT at a 10-vote streak
/// @dev Implements IDistributionStrategy through AbstractDistributionStrategy.
///      Primary compatibility path is distribute(uint256), while executeStrategy(address[]) is
///      exposed for explicit user-list execution.
contract VotingStreakNFTStrategy is AbstractDistributionStrategy {
    // ============ Storage ============

    /// @notice User voting activity state for streak tracking
    /// @param streak Current consecutive voting streak
    /// @param lastVoteCycle Last cycle in which the user was processed
    struct UserActivity {
        uint256 streak;
        uint256 lastVoteCycle;
    }

    /// @notice Current protocol cycle index
    /// @dev Incremented on every execution path
    uint256 public currentCycle;

    /// @notice Breadkit NFT contract used for streak rewards
    IBreadkitNFT public nftContract;

    /// @notice Per-user streak tracking
    mapping(address => UserActivity) public userActivity;

    // ============ Events ============

    /// @notice Emitted when the NFT contract is updated
    /// @param oldAddress Previous NFT contract address
    /// @param newAddress New NFT contract address
    event NFTContractUpdated(address indexed oldAddress, address indexed newAddress);

    /// @notice Emitted when NFT mint fails for a user during graceful degradation
    /// @param user User whose mint failed
    /// @param reason Revert payload from the failed external call
    event NFTMintFailed(address indexed user, bytes reason);

    // ============ Initializer ============

    /// @notice Initializes the strategy
    /// @param _yieldToken Yield token address (required by AbstractDistributionStrategy)
    /// @param _recipientRegistry Recipient registry address (used by distribute path)
    /// @param _distributionManager Authorized distribution manager
    /// @param _nftContract Breadkit NFT contract address
    function initialize(
        address _yieldToken,
        address _recipientRegistry,
        address _distributionManager,
        address _nftContract
    ) external initializer {
        __AbstractDistributionStrategy_init(_yieldToken, _recipientRegistry, _distributionManager);
        if (_nftContract == address(0)) revert ZeroAddress();

        nftContract = IBreadkitNFT(_nftContract);
        emit NFTContractUpdated(address(0), _nftContract);
    }

    // ============ Admin ============

    /// @notice Updates the Breadkit NFT contract address
    /// @param _nftContract New NFT contract address
    function setNFTContract(address _nftContract) external onlyOwner {
        if (_nftContract == address(0)) revert ZeroAddress();

        address oldAddress = address(nftContract);
        nftContract = IBreadkitNFT(_nftContract);

        emit NFTContractUpdated(oldAddress, _nftContract);
    }

    // ============ Execution ============

    /// @notice Executes streak updates for an explicit user list
    /// @dev Uses calldata loop optimization and does not revert the full loop on mint failure
    /// @param users Users who participated in the current cycle
    function executeStrategy(address[] calldata users) external onlyDistributionManager {
        _incrementCycle();

        uint256 cycle = currentCycle;
        uint256 length = users.length;

        for (uint256 i = 0; i < length; ) {
            _processUser(users[i], cycle);
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc AbstractDistributionStrategy
    /// @dev Compatibility path for IDistributionStrategy callers.
    ///      Uses recipientRegistry recipients as the user set for the cycle.
    function distribute(uint256) external override onlyDistributionManager {
        address[] memory users = recipientRegistry.getRecipients();
        if (users.length == 0) revert NoRecipients();

        _incrementCycle();

        uint256 cycle = currentCycle;
        uint256 length = users.length;

        for (uint256 i = 0; i < length; ) {
            _processUser(users[i], cycle);
            unchecked {
                ++i;
            }
        }
    }

    // ============ Internal ============

    /// @dev Increments cycle counter once per execution
    function _incrementCycle() internal {
        unchecked {
            ++currentCycle;
        }
    }

    /// @dev Updates a single user's streak and attempts mint on exact streak == 10
    function _processUser(address user, uint256 cycle) internal {
        UserActivity storage activity = userActivity[user];

        // Prevent duplicate processing from resetting streak when user appears more than once in same cycle.
        if (activity.lastVoteCycle == cycle) return;

        if (activity.lastVoteCycle + 1 == cycle) {
            unchecked {
                ++activity.streak;
            }
        } else {
            activity.streak = 1;
        }

        activity.lastVoteCycle = cycle;

        // Reward only at exact 10-streak milestone per requirement.
        if (activity.streak == 10) {
            try nftContract.mint(user) {
                // no-op
            } catch Error(string memory reason) {
                emit NFTMintFailed(user, bytes(reason));
            } catch (bytes memory lowLevelData) {
                emit NFTMintFailed(user, lowLevelData);
            }
        }
    }
}