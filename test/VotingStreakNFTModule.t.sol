// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VotingStreakNFTModule} from "../src/implementation/VotingStreakNFTModule.sol";
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

    /// @notice Exposes the tokenIds array for testing
    /// @dev Allows tests to verify token IDs are correctly stored in EIP-7201 storage
    function exposed_getTokenIds(address user) external view returns (uint256[] memory) {
        return this.getTokenIds(user);
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
/// @dev Tests voting streak tracking and NFT minting on 10-vote streaks
contract VotingStreakNFTModuleTest is Test {
    // ============ Events ============
    
    /// @notice Emitted when an NFT is minted as a streak reward
    event NFTMinted(address indexed user, uint256 indexed tokenId, uint256 streak);

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
        (uint256 streak1, uint256 lastVoteCycle1) = harness.userActivity(user);

        // Assert Cycle 1
        assertEq(streak1, 1, "Streak should be 1 after first vote");
        assertEq(lastVoteCycle1, 1, "lastVoteCycle should be 1");

        // Act - Cycle 2: Advance cycle and vote again
        cycleModule.advanceCycle();
        harness.exposed_processVote(user, points, VOTING_POWER);
        (uint256 streak2, uint256 lastVoteCycle2) = harness.userActivity(user);

        // Assert Cycle 2
        assertEq(streak2, 2, "Streak should be 2 after consecutive vote");
        assertEq(lastVoteCycle2, 2, "lastVoteCycle should be 2");

        // Act - Cycle 3: Advance cycle and vote again
        cycleModule.advanceCycle();
        harness.exposed_processVote(user, points, VOTING_POWER);
        (uint256 streak3, uint256 lastVoteCycle3) = harness.userActivity(user);

        // Assert Cycle 3
        assertEq(streak3, 3, "Streak should be 3 after third consecutive vote");
        assertEq(lastVoteCycle3, 3, "lastVoteCycle should be 3");
    }

    /// @notice Test: Streak break resets streak from 1 to 1
    /// @dev Voting in cycle 1, skipping cycle 2, voting in cycle 3 should reset streak
    function test_StreakBreakResetsStreak() public {
        // Arrange
        uint256[] memory points = new uint256[](2);
        points[0] = 50;
        points[1] = 50;

        // Act - Cycle 1: User votes
        harness.exposed_processVote(user, points, VOTING_POWER);
        (uint256 streak1, ) = harness.userActivity(user);
        assertEq(streak1, 1, "Streak should be 1 after first vote");

        // Act - Cycle 2: Advance cycle but don't vote (user misses this cycle)
        cycleModule.advanceCycle();

        // Act - Cycle 3: Advance cycle and vote again
        cycleModule.advanceCycle();
        harness.exposed_processVote(user, points, VOTING_POWER);

        // Assert - Streak should reset to 1 because cycle 1+1 != 3
        (uint256 streak, uint256 lastVoteCycle) = harness.userActivity(user);
        assertEq(streak, 1, "Streak should reset to 1 after missing a cycle");
        assertEq(lastVoteCycle, 3, "lastVoteCycle should be 3");
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
        (uint256 streak, uint256 lastVoteCycle) = harness.userActivity(user);
        assertEq(streak, 10, "Streak should be 10");
        assertEq(lastVoteCycle, 10, "lastVoteCycle should be 10");
    }







    /// @notice Test: Recasting vote in same cycle does not increment streak
    /// @dev User votes twice in cycle 1; streak should remain 1
    function test_ReCastVoteDoesNotIncrementStreak() public {
        // Arrange
        uint256[] memory points = new uint256[](2);
        points[0] = 50;
        points[1] = 50;

        // Act - First vote in cycle 1
        harness.exposed_processVote(user, points, VOTING_POWER);
        (uint256 streakAfterFirst, uint256 lastVoteCycleAfterFirst) = harness.userActivity(user);

        // Assert after first vote
        assertEq(streakAfterFirst, 1, "Streak should be 1 after first vote in cycle 1");
        assertEq(lastVoteCycleAfterFirst, 1, "lastVoteCycle should be 1");

        // Act - Cast the same vote again in cycle 1 (recast)
        harness.exposed_processVote(user, points, VOTING_POWER);

        // Assert after recast - streak should NOT increment
        (uint256 streakAfterRecast, uint256 lastVoteCycleAfterRecast) = harness.userActivity(user);
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
        (uint256 streak1, ) = harness.userActivity(user);
        assertEq(streak1, 3, "Streak should be 3");

        // Act - Miss a cycle to break streak
        cycleModule.advanceCycle();
        cycleModule.advanceCycle();

        // Act - Vote again, streak resets to 1
        harness.exposed_processVote(user, points, VOTING_POWER);
        (uint256 streak2, ) = harness.userActivity(user);
        assertEq(streak2, 1, "Streak should reset to 1 after gap");

        // Act - Build streak again to 5
        for (uint256 i = 0; i < 4; i++) {
            cycleModule.advanceCycle();
            harness.exposed_processVote(user, points, VOTING_POWER);
        }
        (uint256 streak3, ) = harness.userActivity(user);
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
        (uint256 streak1_c1, ) = harness.userActivity(user1);
        assertEq(streak1_c1, 1, "user1 streak should be 1 in cycle 1");

        // Act & Assert - user2 doesn't vote in cycle 1
        (uint256 streak2_c1, ) = harness.userActivity(user2);
        assertEq(streak2_c1, 0, "user2 streak should be 0 if never voted");

        // Act - Advance to cycle 2
        cycleModule.advanceCycle();

        // Act & Assert - user1 votes again in cycle 2 (builds streak to 2)
        harness.exposed_processVote(user1, points, VOTING_POWER);
        (uint256 streak1_c2, ) = harness.userActivity(user1);
        assertEq(streak1_c2, 2, "user1 streak should be 2 in cycle 2");

        // Act & Assert - user2 votes for first time in cycle 2 (starts at 1)
        harness.exposed_processVote(user2, points, VOTING_POWER);
        (uint256 streak2_c2, ) = harness.userActivity(user2);
        assertEq(streak2_c2, 1, "user2 streak should be 1 (first vote)");

        // Assert final state
        (uint256 finalStreak1, ) = harness.userActivity(user1);
        (uint256 finalStreak2, ) = harness.userActivity(user2);
        assertEq(finalStreak1, 2, "user1 should maintain streak of 2");
        assertEq(finalStreak2, 1, "user2 should have streak of 1");
    }

    // ============ New Tests: Streak Milestones, Token Storage, Event Emission ============

    /// @notice Test: NFT is minted at 10th and 20th consecutive votes (modulo logic)
    /// @dev Verifies that the mint function is called at stride intervals (every 10 votes)
    ///      and that streak tracking correctly identifies milestone votes
    function test_MultipleStreakMilestonesMintMultipleNFTs() public {
        // Arrange
        uint256[] memory points = new uint256[](2);
        points[0] = 50;
        points[1] = 50;

        uint256 votesNeeded = 20; // Test up to 20th vote (2 NFT mints)
        uint256 expectedMints = 2; // Should mint at 10 and 20

        // Act & Assert - Vote 20 consecutive times
        for (uint256 i = 0; i < votesNeeded; i++) {
            harness.exposed_processVote(user, points, VOTING_POWER);

            uint256 expectedNFTBalance = (i + 1) / 10; // 0 NFTs at vote 1-9, 1 at vote 10, 2 at vote 20
            uint256 actualNFTBalance = mockNft.balanceOf(user);

            assertEq(
                actualNFTBalance,
                expectedNFTBalance,
                string(abi.encodePacked("Vote ", vm.toString(i + 1), ": Expected ", vm.toString(expectedNFTBalance), " NFTs"))
            );

            if (i < votesNeeded - 1) {
                cycleModule.advanceCycle();
            }
        }

        // Final Assert
        assertEq(
            mockNft.balanceOf(user),
            expectedMints,
            "User should have 2 NFTs after 20 consecutive votes"
        );

        (uint256 finalStreak, ) = harness.userActivity(user);
        assertEq(finalStreak, 20, "Streak should be 20");
    }

    /// @notice Test: Token IDs are correctly pushed into user's tokenIds array
    /// @dev Verifies that tokenIds returned from mint are stored in EIP-7201 storage
    ///      and can be retrieved in the correct order
    function test_TokenIdsStoredCorrectlyInArray() public {
        // Arrange
        uint256[] memory points = new uint256[](2);
        points[0] = 50;
        points[1] = 50;

        // Act - Vote 20 times to trigger 2 mints (at votes 10 and 20)
        for (uint256 i = 0; i < 20; i++) {
            harness.exposed_processVote(user, points, VOTING_POWER);
            if (i < 19) {
                cycleModule.advanceCycle();
            }
        }

        // Assert - Retrieve stored token IDs
        uint256[] memory storedTokenIds = harness.exposed_getTokenIds(user);

        assertEq(
            storedTokenIds.length,
            2,
            "Should have 2 token IDs stored (minted at 10th and 20th votes)"
        );

        // Verify token IDs are stored in order
        // Assuming mockNft starts minting from tokenId = 1
        assertEq(storedTokenIds[0], 1, "First minted token ID should be 1");
        assertEq(storedTokenIds[1], 2, "Second minted token ID should be 2");

        // Verify NFT balance matches stored token count
        assertEq(
            mockNft.balanceOf(user),
            storedTokenIds.length,
            "NFT balance should match stored token IDs count"
        );
    }

    /// @notice Test: NFTMinted event is correctly emitted with all parameters
    /// @dev Uses vm.expectEmit to verify event signature and indexed parameters
    ///      at the 10th consecutive vote
    function test_NFTMintedEventEmittedOnTenthVote() public {
        // Arrange
        uint256[] memory points = new uint256[](2);
        points[0] = 50;
        points[1] = 50;

        // Vote 9 times to reach just before the milestone
        for (uint256 i = 0; i < 9; i++) {
            harness.exposed_processVote(user, points, VOTING_POWER);
            cycleModule.advanceCycle();
        }

        // Act - We expect the NFTMinted event on the 10th vote
        // Assuming mockNft.mint returns tokenId = 1 for the first mint
        vm.expectEmit(true, true, false, true);
        emit NFTMinted(user, 1, 10); // user (indexed), tokenId (indexed), streak (not indexed)

        harness.exposed_processVote(user, points, VOTING_POWER);

        // Assert - Verify streak was updated correctly
        (uint256 streak, ) = harness.userActivity(user);
        assertEq(streak, 10, "Streak should be 10 after 10 consecutive votes");

        // Verify NFT was minted
        assertEq(mockNft.balanceOf(user), 1, "User should have 1 NFT");
    }

    /// @notice Test: NFTMinted event is emitted at 20th vote (second milestone)
    /// @dev Verifies modulo logic runs correctly: streak % 10 == 0 at 20
    function test_NFTMintedEventEmittedOnTwentiethVote() public {
        // Arrange
        uint256[] memory points = new uint256[](2);
        points[0] = 50;
        points[1] = 50;

        // Vote 19 times to reach just before the second milestone
        for (uint256 i = 0; i < 19; i++) {
            harness.exposed_processVote(user, points, VOTING_POWER);
            if (i < 18) {
                cycleModule.advanceCycle();
            }
        }

        // Verify we have 1 NFT from the 10th vote
        assertEq(mockNft.balanceOf(user), 1, "User should have 1 NFT after vote 10");

        // Act - Advance to cycle 20 and expect the second NFTMinted event
        cycleModule.advanceCycle();

        vm.expectEmit(true, true, false, true);
        emit NFTMinted(user, 2, 20); // user (indexed), tokenId (indexed), streak (not indexed)

        harness.exposed_processVote(user, points, VOTING_POWER);

        // Assert - Verify second NFT was minted
        assertEq(mockNft.balanceOf(user), 2, "User should have 2 NFTs after vote 20");

        (uint256 streak, ) = harness.userActivity(user);
        assertEq(streak, 20, "Streak should be 20 after 20 consecutive votes");

        // Verify both token IDs are stored
        uint256[] memory storedTokenIds = harness.exposed_getTokenIds(user);
        assertEq(storedTokenIds.length, 2, "Should have 2 token IDs stored");
    }

}
