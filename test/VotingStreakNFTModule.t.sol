// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VotingStreakNFTModule} from "../src/implementation/VotingStreakNFTModule.sol";
import {BasisPointsVotingModule} from "../src/base/BasisPointsVotingModule.sol";
import {IVotingPowerStrategy} from "../src/interfaces/IVotingPowerStrategy.sol";
import {ICrowdstakeNFT} from "../src/interfaces/ICrowdstakeNFT.sol";
import {MockCrowdstakeNFT} from "./mocks/MockCrowdstakeNFT.sol";
import {MockRecipientRegistry} from "./mocks/MockRecipientRegistry.sol";
import {MockCycleModule} from "./mocks/MockCycleModule.sol";

// ============ Test Harness ============

/// @title VotingStreakBasisPointsModuleHarness
/// @notice Test harness that exposes the protected _processVote function for testing
/// @dev Allows tests to directly call streak logic without generating EIP-712 signatures
contract VotingStreakBasisPointsModuleHarness is VotingStreakNFTModule {
    /// @notice Exposes the internal _processVote for testing
    /// @dev Allows direct testing of voting streak logic without signature requirements
    function exposed_processVote(address voter, uint256[] calldata points, uint256 votingPower) external {
        _processVote(voter, points, votingPower);
    }
}

// ============ Mock Voting Power Strategy ============

/// @title MockVotingPowerStrategy
/// @notice Simple mock voting power strategy that returns a fixed amount
contract MockVotingPowerStrategy is IVotingPowerStrategy {
    uint256 public constant VOTING_POWER = 100e18;

    function getCurrentVotingPower(address account) external pure override returns (uint256) {
        // Return a fixed amount for all addresses
        return VOTING_POWER;
    }
}

// ============ Main Test Contract ============

/// @title VotingStreakNFTModuleTest
/// @notice Comprehensive test suite for VotingStreakNFTModule
/// @dev Tests voting streak tracking, NFT minting, and graceful degradation
contract VotingStreakNFTModuleTest is Test {
    VotingStreakBasisPointsModuleHarness public harness;
    MockCrowdstakeNFT public mockNft;
    MockRecipientRegistry public recipientRegistry;
    MockCycleModule public cycleModule;
    MockVotingPowerStrategy public votingPowerStrategy;

    address public user = address(0xBEEF);
    address public user1 = address(0xCAFE);
    address public user2 = address(0xF00D);
    address public nonOwner = address(0xDEAD);
    address public admin = address(0xADEF);

    uint256 public constant MAX_POINTS = 100;
    uint256 public constant VOTING_POWER = 100e18;

    // ============ Setup ============

    function setUp() public {
        // Create cycle module (starts at cycle 1)
        cycleModule = new MockCycleModule();

        // Create recipient registry with 2 recipients
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;
        recipientRegistry = new MockRecipientRegistry(recipients);

        // Create voting power strategy
        votingPowerStrategy = new MockVotingPowerStrategy();

        // Create mock NFT
        mockNft = new MockCrowdstakeNFT();

        // Create harness (this is our VotingStreakNFTModule)
        harness = new VotingStreakBasisPointsModuleHarness();

        // Set up voting power strategies array
        IVotingPowerStrategy[] memory strategies = new IVotingPowerStrategy[](1);
        strategies[0] = votingPowerStrategy;

        // Initialize the harness with all required dependencies
        // initialize(maxPoints, strategies, distributionModule, recipientRegistry, cycleModule, nftContract)
        harness.initialize(
            MAX_POINTS, // _maxPoints = 100
            strategies, // _strategies
            address(this), // _distributionModule (dummy)
            address(recipientRegistry), // _recipientRegistry
            address(cycleModule), // _cycleModule
            address(mockNft) // _nftContract
        );

        // Transfer ownership to admin for testing (optional, but good practice)
        harness.transferOwnership(admin);
    }

    // ============ Test Cases ============

    /// @notice Test: Consecutive votes in cycles 1, 2, 3 increment streak to 3
    /// @dev AAA Pattern: Arrange -> Act -> Assert
    function test_ConsecutiveVotesIncrementStreak() public {
        // Arrange
        uint256[] memory points = new uint256[](2);
        points[0] = 50;
        points[1] = 50;

        // Act - Cycle 1: User votes
        harness.exposed_processVote(user, points, VOTING_POWER);
        (uint256 streak1, uint256 lastVoteCycle1, ) = harness.userActivity(user);

        // Assert Cycle 1
        assertEq(streak1, 1, "Streak should be 1 after first vote");
        assertEq(lastVoteCycle1, 1, "lastVoteCycle should be 1");

        // Act - Cycle 2: Advance cycle and vote again
        cycleModule.advanceCycle();
        harness.exposed_processVote(user, points, VOTING_POWER);
        (uint256 streak2, uint256 lastVoteCycle2, ) = harness.userActivity(user);

        // Assert Cycle 2
        assertEq(streak2, 2, "Streak should be 2 after consecutive vote");
        assertEq(lastVoteCycle2, 2, "lastVoteCycle should be 2");

        // Act - Cycle 3: Advance cycle and vote again
        cycleModule.advanceCycle();
        harness.exposed_processVote(user, points, VOTING_POWER);
        (uint256 streak3, uint256 lastVoteCycle3, ) = harness.userActivity(user);

        // Assert Cycle 3
        assertEq(streak3, 3, "Streak should be 3 after third consecutive vote");
        assertEq(lastVoteCycle3, 3, "lastVoteCycle should be 3");
    }

    /// @notice Test: Missed vote resets streak from 1 to 1
    /// @dev Voting in cycle 1, skipping cycle 2, voting in cycle 3 should reset streak
    function test_MissedVoteResetsStreak() public {
        // Arrange
        uint256[] memory points = new uint256[](2);
        points[0] = 50;
        points[1] = 50;

        // Act - Cycle 1: User votes
        harness.exposed_processVote(user, points, VOTING_POWER);
        (uint256 streak1, , ) = harness.userActivity(user);
        assertEq(streak1, 1, "Streak should be 1 after first vote");

        // Act - Cycle 2: Advance cycle but don't vote (user misses this cycle)
        cycleModule.advanceCycle();

        // Act - Cycle 3: Advance cycle and vote again
        cycleModule.advanceCycle();
        harness.exposed_processVote(user, points, VOTING_POWER);

        // Assert - Streak should reset to 1 because cycle 1+1 != 3
        (uint256 streak, uint256 lastVoteCycle, bool mintPending) = harness.userActivity(user);
        assertEq(streak, 1, "Streak should reset to 1 after missing a cycle");
        assertEq(lastVoteCycle, 3, "lastVoteCycle should be 3");
        assertEq(mintPending, false, "mintPending should be false");
    }

    /// @notice Test: 10 consecutive votes mints an NFT
    /// @dev After reaching 10 consecutive votes, mockNft balance should be 1
    function test_TenVotesMintsNFT() public {
        // Arrange
        uint256[] memory points = new uint256[](2);
        points[0] = 50;
        points[1] = 50;

        uint256 nftBalanceBefore = mockNft.balanceOf(user);
        assertEq(nftBalanceBefore, 0, "User should have 0 NFTs initially");

        // Act - Vote in cycles 1 through 10
        for (uint256 i = 0; i < 10; i++) {
            harness.exposed_processVote(user, points, VOTING_POWER);
            if (i < 9) {
                cycleModule.advanceCycle();
            }
        }

        // Assert
        assertEq(
            mockNft.balanceOf(user),
            1,
            "User should have 1 NFT after 10 consecutive votes"
        );
        (uint256 streak, uint256 lastVoteCycle, bool mintPending) = harness.userActivity(user);
        assertEq(streak, 10, "Streak should be 10");
        assertEq(lastVoteCycle, 10, "lastVoteCycle should be 10");
        assertEq(mintPending, false, "mintPending should be false after successful mint");
    }

    /// @notice Test: Graceful degradation when NFT mint fails at 10 votes
    /// @dev Transaction should not revert, streak = 10, balance = 0, mintPending = true
    function test_GracefulDegradationOnMintFail() public {
        // Arrange
        uint256[] memory points = new uint256[](2);
        points[0] = 50;
        points[1] = 50;

        // Bring user to 9 consecutive votes
        for (uint256 i = 0; i < 9; i++) {
            harness.exposed_processVote(user, points, VOTING_POWER);
            if (i < 8) {
                cycleModule.advanceCycle();
            }
        }

        // Make NFT contracts fail
        mockNft.setShouldFail(true);

        // Act - Cycle 10: Vote when mint will fail
        cycleModule.advanceCycle();
        harness.exposed_processVote(user, points, VOTING_POWER); // This should NOT revert

        // Assert - Streak and state are correct, but NFT wasn't minted
        (uint256 streak, uint256 lastVoteCycle, bool mintPending) = harness.userActivity(user);
        assertEq(streak, 10, "Streak should be 10");
        assertEq(lastVoteCycle, 10, "lastVoteCycle should be 10");
        assertEq(mintPending, true, "mintPending should be true (mint failed and needs retry)");
        assertEq(
            mockNft.balanceOf(user),
            0,
            "User should have 0 NFTs (mint failed)"
        );
    }

    /// @notice Test: Mint retry succeeds on next cycle after initial failure
    /// @dev Fail at cycle 10, recover at cycle 11
    function test_MintRetrySucceedsOnNextCycle() public {
        // Arrange
        uint256[] memory points = new uint256[](2);
        points[0] = 50;
        points[1] = 50;

        // Bring user to 9 consecutive votes
        for (uint256 i = 0; i < 9; i++) {
            harness.exposed_processVote(user, points, VOTING_POWER);
            if (i < 8) {
                cycleModule.advanceCycle();
            }
        }

        // Make NFT contracts fail
        mockNft.setShouldFail(true);

        // Act - Cycle 10: Vote with mint failure
        cycleModule.advanceCycle();
        harness.exposed_processVote(user, points, VOTING_POWER);
        (uint256 streakAfterFail, , bool mintPendingAfterFail) = harness.userActivity(user);
        assertEq(streakAfterFail, 10, "Streak should be 10 after failed mint");
        assertEq(mintPendingAfterFail, true, "mintPending should be true after failure");

        // Act - Cycle 11: Recover and try again
        mockNft.setShouldFail(false);
        cycleModule.advanceCycle();
        harness.exposed_processVote(user, points, VOTING_POWER);

        // Assert - Now mint should succeed on retry
        (uint256 streakAfterRetry, uint256 lastVoteCycleAfterRetry, bool mintPendingAfterRetry) =
            harness.userActivity(user);
        assertEq(streakAfterRetry, 11, "Streak should be 11");
        assertEq(lastVoteCycleAfterRetry, 11, "lastVoteCycle should be 11");
        assertEq(mintPendingAfterRetry, false, "mintPending should be false after successful retry");
        assertEq(
            mockNft.balanceOf(user),
            1,
            "User should have 1 NFT (successfully minted on retry)"
        );
    }

    /// @notice Test: Retry continues across multiple cycles until success
    /// @dev Fail at cycles 10, 11, 12; succeed at 13
    function test_MintRetryMultipleCycles() public {
        // Arrange
        uint256[] memory points = new uint256[](2);
        points[0] = 50;
        points[1] = 50;

        // Bring user to 9 consecutive votes
        for (uint256 i = 0; i < 9; i++) {
            harness.exposed_processVote(user, points, VOTING_POWER);
            if (i < 8) {
                cycleModule.advanceCycle();
            }
        }

        // Set NFT to fail
        mockNft.setShouldFail(true);

        // Act - Cycles 10, 11, 12: Vote with mint failures
        for (uint256 i = 10; i <= 12; i++) {
            cycleModule.advanceCycle();
            harness.exposed_processVote(user, points, VOTING_POWER);
            (uint256 streak, , bool mintPending) = harness.userActivity(user);
            assertEq(streak, i, "Streak should increment even if mint fails");
            assertEq(mintPending, true, "mintPending should remain true across retries");
            assertEq(mockNft.balanceOf(user), 0, "Should have 0 NFTs during failures");
        }

        // Act - Cycle 13: Recover and retry
        mockNft.setShouldFail(false);
        cycleModule.advanceCycle();
        harness.exposed_processVote(user, points, VOTING_POWER);

        // Assert - Finally mint on cycle 13
        (uint256 finalStreak, uint256 lastVoteCycleFinal, bool mintPendingFinal) = harness.userActivity(user);
        assertEq(finalStreak, 13, "Streak should be 13");
        assertEq(lastVoteCycleFinal, 13, "lastVoteCycle should be 13");
        assertEq(mintPendingFinal, false, "mintPending should be false after successful mint at cycle 13");
        assertEq(
            mockNft.balanceOf(user),
            1,
            "User should have 1 NFT after successful retry at cycle 13"
        );
    }

    /// @notice Test: Streak break clears mintPending flag
    /// @dev Fail at cycle 10 (mintPending=true), miss cycle 11, vote at cycle 12
    /// @dev Streak resets to 1 and mintPending becomes false
    function test_StreakBreakClearsMintPending() public {
        // Arrange
        uint256[] memory points = new uint256[](2);
        points[0] = 50;
        points[1] = 50;

        // Bring user to 9 consecutive votes
        for (uint256 i = 0; i < 9; i++) {
            harness.exposed_processVote(user, points, VOTING_POWER);
            if (i < 8) {
                cycleModule.advanceCycle();
            }
        }

        // Set NFT to fail
        mockNft.setShouldFail(true);

        // Act - Cycle 10: Vote with mint failure, mintPending becomes true
        cycleModule.advanceCycle();
        harness.exposed_processVote(user, points, VOTING_POWER);
        (uint256 streakAt10, , bool mintPendingAt10) = harness.userActivity(user);
        assertEq(streakAt10, 10, "Streak should be 10");
        assertEq(mintPendingAt10, true, "mintPending should be true");

        // Act - Cycle 11: User misses this cycle (does not vote)
        cycleModule.advanceCycle();

        // Act - Cycle 12: User votes again - this breaks the streak
        cycleModule.advanceCycle();
        harness.exposed_processVote(user, points, VOTING_POWER);

        // Assert - Streak resets to 1 and mintPending is cleared
        (uint256 streakAt12, uint256 lastVoteCycleAt12, bool mintPendingAt12) = harness.userActivity(user);
        assertEq(streakAt12, 1, "Streak should reset to 1 when broken");
        assertEq(lastVoteCycleAt12, 12, "lastVoteCycle should be 12");
        assertEq(mintPendingAt12, false, "mintPending should be cleared when streak is broken");
    }

    /// @notice Test: Recasting vote in same cycle does not increment streak
    /// @dev NEW: User votes twice in cycle 1; streak should remain 1
    function test_ReCastVoteDoesNotIncrementStreak() public {
        // Arrange
        uint256[] memory points = new uint256[](2);
        points[0] = 50;
        points[1] = 50;

        // Act - First vote in cycle 1
        harness.exposed_processVote(user, points, VOTING_POWER);
        (uint256 streakAfterFirst, uint256 lastVoteCycleAfterFirst, ) = harness.userActivity(user);

        // Assert after first vote
        assertEq(streakAfterFirst, 1, "Streak should be 1 after first vote in cycle 1");
        assertEq(lastVoteCycleAfterFirst, 1, "lastVoteCycle should be 1");

        // Act - Cast the same vote again in cycle 1 (recast)
        harness.exposed_processVote(user, points, VOTING_POWER);

        // Assert after recast - streak should NOT increment
        (uint256 streakAfterRecast, uint256 lastVoteCycleAfterRecast, ) = harness.userActivity(user);
        assertEq(
            streakAfterRecast,
            1,
            "Streak should remain 1 after recasting vote in same cycle"
        );
        assertEq(lastVoteCycleAfterRecast, 1, "lastVoteCycle should still be 1");
    }

    /// @notice Test: Only owner can set NFT contract
    /// @dev Non-owner should revert when calling setNFTContract
    function test_RevertIf_NotOwnerSetsNft() public {
        // Arrange
        address newNftAddress = address(0x9999);

        // Act & Assert - Non-owner should revert
        vm.prank(nonOwner);
        vm.expectRevert();
        harness.setNFTContract(newNftAddress);

        // Act & Assert - Owner should succeed
        vm.prank(admin);
        harness.setNFTContract(newNftAddress);

        // Verify the NFT contract was updated
        ICrowdstakeNFT retrievedNft = harness.nftContract();
        assertEq(address(retrievedNft), newNftAddress, "NFT contract should be updated by owner");
    }

    // ============ Additional Edge Case Tests ============

    /// @notice Test: User can vote again after streak is properly reset through pattern
    /// @dev Verifies that streak tracking works correctly across multiple reset cycles
    function test_StreakResetAndRebuild() public {
        // Arrange
        uint256[] memory points = new uint256[](2);
        points[0] = 50;
        points[1] = 50;

        // Act & Assert - Build streak to 3
        for (uint256 i = 0; i < 3; i++) {
            harness.exposed_processVote(user, points, VOTING_POWER);
            if (i < 2) cycleModule.advanceCycle();
        }
        (uint256 streak1, , ) = harness.userActivity(user);
        assertEq(streak1, 3, "Streak should be 3");

        // Act - Miss a cycle to break streak
        cycleModule.advanceCycle();
        cycleModule.advanceCycle();

        // Act - Vote again, streak resets to 1
        harness.exposed_processVote(user, points, VOTING_POWER);
        (uint256 streak2, , ) = harness.userActivity(user);
        assertEq(streak2, 1, "Streak should reset to 1 after gap");

        // Act - Build streak again to 5
        for (uint256 i = 0; i < 4; i++) {
            cycleModule.advanceCycle();
            harness.exposed_processVote(user, points, VOTING_POWER);
        }
        (uint256 streak3, , ) = harness.userActivity(user);
        assertEq(streak3, 5, "Streak should build to 5 again");
    }

    /// @notice Test: Multiple users can track streaks independently
    /// @dev Verifies that streak state is properly isolated per user
    function test_MultipleUsersIndependentStreaks() public {
        // Arrange
        uint256[] memory points = new uint256[](2);
        points[0] = 50;
        points[1] = 50;

        // Act & Assert - user1 votes in cycle 1
        harness.exposed_processVote(user1, points, VOTING_POWER);
        (uint256 streak1_c1, , ) = harness.userActivity(user1);
        assertEq(streak1_c1, 1, "user1 streak should be 1 in cycle 1");

        // Act & Assert - user2 doesn't vote in cycle 1
        (uint256 streak2_c1, , ) = harness.userActivity(user2);
        assertEq(streak2_c1, 0, "user2 streak should be 0 if never voted");

        // Act - Advance to cycle 2
        cycleModule.advanceCycle();

        // Act & Assert - user1 votes again in cycle 2 (builds streak to 2)
        harness.exposed_processVote(user1, points, VOTING_POWER);
        (uint256 streak1_c2, , ) = harness.userActivity(user1);
        assertEq(streak1_c2, 2, "user1 streak should be 2 in cycle 2");

        // Act & Assert - user2 votes for first time in cycle 2 (starts at 1)
        harness.exposed_processVote(user2, points, VOTING_POWER);
        (uint256 streak2_c2, , ) = harness.userActivity(user2);
        assertEq(streak2_c2, 1, "user2 streak should be 1 (first vote)");

        // Assert final state
        (uint256 finalStreak1, , ) = harness.userActivity(user1);
        (uint256 finalStreak2, , ) = harness.userActivity(user2);
        assertEq(finalStreak1, 2, "user1 should maintain streak of 2");
        assertEq(finalStreak2, 1, "user2 should have streak of 1");
    }

}
