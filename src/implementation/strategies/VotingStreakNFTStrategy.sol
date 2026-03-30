// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractDistributionStrategy} from "../../abstract/AbstractDistributionStrategy.sol";
import {AbstractDistributionManager} from "../../abstract/AbstractDistributionManager.sol";
import {IBreadkitNFT} from "../../interfaces/IBreadkitNFT.sol";

/// @title VotingStreakNFTStrategy
/// @notice Tracks consecutive voting activity and mints a Breadkit NFT at a 10-vote streak
/// @dev Implements IDistributionStrategy through AbstractDistributionStrategy.
///      Primary compatibility path is distribute(uint256), while executeStrategy(address[]) is
///      exposed for explicit user-list execution.
contract VotingStreakNFTStrategy is AbstractDistributionStrategy {
    // ============ EIP-7201 Namespaced Storage ============

    /// @notice User voting activity state for streak tracking
    /// @param streak Current consecutive voting streak
    /// @param lastVoteCycle Last cycle in which the user was processed
    /// @param mintPending Track if mint is still pending for current streak
    struct UserActivity {
        uint256 streak;
        uint256 lastVoteCycle;
        bool mintPending;
    }

    /// @custom:storage-location erc7201:crowdstake.storage.VotingStreakNFTStrategy
    struct VotingStreakNFTStrategyStorage {
        /// @notice Breadkit NFT contract used for streak rewards
        IBreadkitNFT nftContract;
        /// @notice Per-user streak tracking
        mapping(address => UserActivity) userActivity;
    }

    // keccak256(abi.encode(uint256(keccak256("crowdstake.storage.VotingStreakNFTStrategy")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VOTING_STREAK_NFT_STRATEGY_STORAGE =
        0x378121933e29b8327eb579a304b48403d9f3d86575a5822d7901ea89be3ae900;

    function _getVotingStreakNFTStrategyStorage()
        internal
        pure
        returns (VotingStreakNFTStrategyStorage storage $)
    {
        assembly {
            $.slot := VOTING_STREAK_NFT_STRATEGY_STORAGE
        }
    }

    // ============ Events ============

    /// @notice Emitted when the NFT contract is updated
    /// @param oldAddress Previous NFT contract address
    /// @param newAddress New NFT contract address
    event NFTContractUpdated(address indexed oldAddress, address indexed newAddress);

    /// @notice Emitted when NFT mint fails for a user during graceful degradation
    /// @param user User whose mint failed
    /// @param reason Revert data from the failed external call.
    ///               In `catch Error(string reason)` branches this is the raw UTF-8 bytes of the
    ///               revert string (i.e. `bytes(reason)`), and in other cases it is the raw
    ///               low-level revert payload as returned by the EVM.
    event NFTMintFailed(address indexed user, bytes reason);

    // ============ Views (ABI-compatible getters) ============

    function currentCycle() external view returns (uint256) {
        return AbstractDistributionManager(distributionManager).cycleManager().getCurrentCycle();
    }

    function nftContract() external view returns (IBreadkitNFT) {
        return _getVotingStreakNFTStrategyStorage().nftContract;
    }

    function userActivity(address user) external view returns (uint256 streak, uint256 lastVoteCycle, bool mintPending) {
        VotingStreakNFTStrategyStorage storage $ = _getVotingStreakNFTStrategyStorage();
        UserActivity storage activity = $.userActivity[user];
        return (activity.streak, activity.lastVoteCycle, activity.mintPending);
    }

    // ============ Initializer ============

    /// @notice Initializes the strategy
    /// @param _yieldToken Yield token address (required by AbstractDistributionStrategy)
    /// @param _recipientRegistry Recipient registry address (used by distribute path)
    /// @param _distributionManager Authorized distribution manager with cycle module
    /// @param _nftContract Breadkit NFT contract address
    function initialize(
        address _yieldToken,
        address _recipientRegistry,
        address _distributionManager,
        address _nftContract
    ) external initializer {
        __AbstractDistributionStrategy_init(_yieldToken, _recipientRegistry, _distributionManager);
        if (_nftContract == address(0)) revert ZeroAddress();

        VotingStreakNFTStrategyStorage storage $ = _getVotingStreakNFTStrategyStorage();
        $.nftContract = IBreadkitNFT(_nftContract);
        emit NFTContractUpdated(address(0), _nftContract);
    }

    // ============ Admin ============

    /// @notice Updates the Breadkit NFT contract address
    /// @param _nftContract New NFT contract address
    function setNFTContract(address _nftContract) external onlyOwner {
        if (_nftContract == address(0)) revert ZeroAddress();

        VotingStreakNFTStrategyStorage storage $ = _getVotingStreakNFTStrategyStorage();
        address oldAddress = address($.nftContract);
        $.nftContract = IBreadkitNFT(_nftContract);

        emit NFTContractUpdated(oldAddress, _nftContract);
    }

    // ============ Execution ============

    /// @notice Executes streak updates for an explicit user list
    /// @dev Uses calldata loop optimization and does not revert the full loop on mint failure
    /// @param users Users who participated in the current cycle
    function executeStrategy(address[] calldata users) external onlyDistributionManager {
        uint256 length = users.length;

        for (uint256 i = 0; i < length; ) {
            _processUser(users[i]);
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

        uint256 length = users.length;

        for (uint256 i = 0; i < length; ) {
            _processUser(users[i]);
            unchecked {
                ++i;
            }
        }
    }

    // ============ Internal ============

    /// @dev Updates a single user's streak and attempts mint with retry logic for failures
    function _processUser(address user) internal {
        VotingStreakNFTStrategyStorage storage $ = _getVotingStreakNFTStrategyStorage();
        uint256 cycle = AbstractDistributionManager(distributionManager).cycleManager().getCurrentCycle();
        UserActivity storage activity = $.userActivity[user];

        // Prevent duplicate processing from resetting streak when user appears more than once in same cycle.
        if (activity.lastVoteCycle == cycle) return;

        if (activity.lastVoteCycle + 1 == cycle) {
            unchecked {
                ++activity.streak;
            }
        } else {
            activity.streak = 1;
            activity.mintPending = false;  // Reset when streak breaks
        }

        activity.lastVoteCycle = cycle;

        // Attempt mint at streak == 10 if haven't minted yet for this streak
        if (activity.streak == 10 && !activity.mintPending) {
            activity.mintPending = true;  // Mark attempt begun
            if (_attemptMint(user)) {
                activity.mintPending = false;  // Successfully minted, no retry needed
            }
            // If mint fails, mintPending stays true for retry in next cycle
        } else if (activity.mintPending && activity.streak > 10) {
            // Retry minting in subsequent cycles while streak continues
            if (_attemptMint(user)) {
                activity.mintPending = false;  // Successfully minted
            }
        }
    }

    /// @dev Helper to attempt NFT mint and return success status
    function _attemptMint(address user) internal returns (bool success) {
        VotingStreakNFTStrategyStorage storage $ = _getVotingStreakNFTStrategyStorage();
        try $.nftContract.mint(user) {
            return true;
        } catch Error(string memory reason) {
            emit NFTMintFailed(user, bytes(reason));
            return false;
        } catch (bytes memory lowLevelData) {
            emit NFTMintFailed(user, lowLevelData);
            return false;
        }
    }
}