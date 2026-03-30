// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VotingStreakNFTStrategy} from "../src/implementation/strategies/VotingStreakNFTStrategy.sol";
import {MockBreadkitNFT} from "./mocks/MockBreadkitNFT.sol";
import {MockRecipientRegistry} from "./mocks/MockRecipientRegistry.sol";
import {MockCycleModule} from "./mocks/MockCycleModule.sol";
import {MockDistributionManagerForVotingStreak} from "./mocks/MockDistributionManagerForVotingStreak.sol";

contract VotingStreakNFTStrategyTest is Test {
    VotingStreakNFTStrategy public strategy;
    MockBreadkitNFT public mockNft;
    MockRecipientRegistry public recipientRegistry;
    MockDistributionManagerForVotingStreak public distributionManager;
    MockCycleModule public cycleModule;

    address public user = address(0xBEEF);
    address public user1 = address(0xCAFE);
    address public user2 = address(0xF00D);
    address public nonOwner = address(0xDEAD);
    address public mockYieldToken = address(0x1111);
    address public mockVotingModule = address(0x2222);

    function setUp() public {
        // Create mock cycle module
        cycleModule = new MockCycleModule();

        // Create recipient registry
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;
        recipientRegistry = new MockRecipientRegistry(recipients);

        // Create mock distribution manager
        distributionManager = new MockDistributionManagerForVotingStreak(
            address(cycleModule),
            address(recipientRegistry),
            mockYieldToken,
            mockVotingModule
        );

        // Create mock NFT
        mockNft = new MockBreadkitNFT();

        // Create and initialize strategy
        strategy = new VotingStreakNFTStrategy();
        strategy.initialize(
            mockYieldToken,
            address(recipientRegistry),
            address(distributionManager),
            address(mockNft)
        );
    }

    function test_ConsecutiveVotesIncrementStreak() public {
        // Arrange
        address[] memory users = new address[](1);
        users[0] = user;

        // Act - Cycle 1
        vm.prank(address(distributionManager));
        strategy.executeStrategy(users);
        (uint256 streak1, uint256 lastVoteCycle1, ) = strategy.userActivity(user);
        assertEq(streak1, 1);
        assertEq(lastVoteCycle1, 1);

        // Advance to Cycle 2
        distributionManager.advanceCycle();
        vm.prank(address(distributionManager));
        strategy.executeStrategy(users);
        (uint256 streak2, uint256 lastVoteCycle2, ) = strategy.userActivity(user);
        assertEq(streak2, 2);
        assertEq(lastVoteCycle2, 2);

        // Advance to Cycle 3
        distributionManager.advanceCycle();
        vm.prank(address(distributionManager));
        strategy.executeStrategy(users);

        // Assert
        (uint256 streak, uint256 lastVoteCycle, bool mintPending) = strategy.userActivity(user);
        assertEq(streak, 3);
        assertEq(lastVoteCycle, 3);
        assertEq(mintPending, false);
    }

    function test_MissedVoteResetsStreak() public {
        // Arrange
        address[] memory users = new address[](1);
        users[0] = user;

        address[] memory emptyUsers = new address[](0);

        // Act - Cycle 1: user votes
        vm.prank(address(distributionManager));
        strategy.executeStrategy(users);
        (uint256 streak1, , ) = strategy.userActivity(user);
        assertEq(streak1, 1);

        // Cycle 2: user misses
        distributionManager.advanceCycle();
        vm.prank(address(distributionManager));
        strategy.executeStrategy(emptyUsers);

        // Cycle 3: user votes again - streak resets
        distributionManager.advanceCycle();
        vm.prank(address(distributionManager));
        strategy.executeStrategy(users);

        // Assert
        (uint256 streak, uint256 lastVoteCycle, bool mintPending) = strategy.userActivity(user);
        assertEq(streak, 1);
        assertEq(lastVoteCycle, 3);
        assertEq(mintPending, false);
    }

    function test_TenVotesMintsNFT() public {
        // Arrange
        address[] memory users = new address[](1);
        users[0] = user;

        // Act - Vote 10 consecutive cycles
        for (uint256 i = 0; i < 10; ) {
            vm.prank(address(distributionManager));
            strategy.executeStrategy(users);
            if (i < 9) {
                distributionManager.advanceCycle();
            }
            unchecked {
                ++i;
            }
        }

        // Assert
        assertEq(mockNft.balanceOf(user), 1);
        (uint256 streak, uint256 lastVoteCycle, bool mintPending) = strategy.userActivity(user);
        assertEq(streak, 10);
        assertEq(lastVoteCycle, 10);
        assertEq(mintPending, false);
    }

    function test_GracefulDegradationOnMintFail() public {
        // Arrange
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        // Bring both users to 9 streak first
        for (uint256 i = 0; i < 9; ) {
            vm.prank(address(distributionManager));
            strategy.executeStrategy(users);
            if (i < 8) {
                distributionManager.advanceCycle();
            }
            unchecked {
                ++i;
            }
        }

        mockNft.setShouldFail(true);

        // Act: Advance to cycle 10
        distributionManager.advanceCycle();
        vm.prank(address(distributionManager));
        strategy.executeStrategy(users); // 10th vote for both; mint should fail internally but not revert

        // Assert
        (uint256 streak1, uint256 lastVoteCycle1, bool mintPending1) = strategy.userActivity(user1);
        (uint256 streak2, uint256 lastVoteCycle2, bool mintPending2) = strategy.userActivity(user2);

        assertEq(streak1, 10);
        assertEq(streak2, 10);
        assertEq(mintPending1, true); // Mint failed, flag should remain true for retry
        assertEq(mintPending2, true);
        assertEq(mockNft.balanceOf(user1), 0);
        assertEq(mockNft.balanceOf(user2), 0);

        // Act: Advance to cycle 11 - retry should succeed for both users
        mockNft.setShouldFail(false);
        distributionManager.advanceCycle();
        vm.prank(address(distributionManager));
        strategy.executeStrategy(users);

        // Assert: Both users should have successful mints after retry
        (uint256 streak1Retry, , bool mintPending1Retry) = strategy.userActivity(user1);
        (uint256 streak2Retry, , bool mintPending2Retry) = strategy.userActivity(user2);

        assertEq(streak1Retry, 11);
        assertEq(streak2Retry, 11);
        assertEq(mintPending1Retry, false); // Successfully minted after retry, flag cleared
        assertEq(mintPending2Retry, false);
        assertEq(mockNft.balanceOf(user1), 1); // NFT minted after retry
        assertEq(mockNft.balanceOf(user2), 1);
    }

    function test_MintRetrySucceedsOnNextCycle() public {
        // Arrange
        address[] memory users = new address[](1);
        users[0] = user;

        // Bring user to 9 streak
        for (uint256 i = 0; i < 9; ) {
            vm.prank(address(distributionManager));
            strategy.executeStrategy(users);
            if (i < 8) {
                distributionManager.advanceCycle();
            }
            unchecked {
                ++i;
            }
        }

        mockNft.setShouldFail(true);

        // Act: Advance to cycle 10 - mint fails
        distributionManager.advanceCycle();
        vm.prank(address(distributionManager));
        strategy.executeStrategy(users);

        (uint256 streak1, , bool mintPending1) = strategy.userActivity(user);
        assertEq(streak1, 10);
        assertEq(mintPending1, true);
        assertEq(mockNft.balanceOf(user), 0);

        // Act: Advance to cycle 11 - retry should succeed
        mockNft.setShouldFail(false);
        distributionManager.advanceCycle();
        vm.prank(address(distributionManager));
        strategy.executeStrategy(users);

        // Assert
        (uint256 streak2, , bool mintPending2) = strategy.userActivity(user);
        assertEq(streak2, 11);
        assertEq(mintPending2, false); // Successfully minted, flag cleared
        assertEq(mockNft.balanceOf(user), 1); // NFT minted after retry
    }

    function test_MintRetryMultipleCycles() public {
        // Arrange
        address[] memory users = new address[](1);
        users[0] = user;

        // Bring user to 9 streak
        for (uint256 i = 0; i < 9; ) {
            vm.prank(address(distributionManager));
            strategy.executeStrategy(users);
            if (i < 8) {
                distributionManager.advanceCycle();
            }
            unchecked {
                ++i;
            }
        }

        mockNft.setShouldFail(true);

        // Act: Cycle 10 - mint fails
        distributionManager.advanceCycle();
        vm.prank(address(distributionManager));
        strategy.executeStrategy(users);
        (uint256 streak1, , bool mintPending1) = strategy.userActivity(user);
        assertEq(mintPending1, true);

        // Cycle 11 - still fails
        distributionManager.advanceCycle();
        vm.prank(address(distributionManager));
        strategy.executeStrategy(users);
        (uint256 streak2, , bool mintPending2) = strategy.userActivity(user);
        assertEq(streak2, 11);
        assertEq(mintPending2, true); // Still pending

        // Cycle 12 - succeeds
        mockNft.setShouldFail(false);
        distributionManager.advanceCycle();
        vm.prank(address(distributionManager));
        strategy.executeStrategy(users);

        // Assert
        (uint256 streak3, , bool mintPending3) = strategy.userActivity(user);
        assertEq(streak3, 12);
        assertEq(mintPending3, false);
        assertEq(mockNft.balanceOf(user), 1);
    }

    function test_StreakBreakClearsMintPending() public {
        // Arrange
        address[] memory users = new address[](1);
        users[0] = user;

        address[] memory emptyUsers = new address[](0);

        // Bring user to 9 streak
        for (uint256 i = 0; i < 9; ) {
            vm.prank(address(distributionManager));
            strategy.executeStrategy(users);
            if (i < 8) {
                distributionManager.advanceCycle();
            }
            unchecked {
                ++i;
            }
        }

        mockNft.setShouldFail(true);

        // Act: Cycle 10 - mint fails, mintPending = true
        distributionManager.advanceCycle();
        vm.prank(address(distributionManager));
        strategy.executeStrategy(users);
        (, , bool mintPending1) = strategy.userActivity(user);
        assertEq(mintPending1, true);

        // Cycle 11: User misses
        distributionManager.advanceCycle();
        vm.prank(address(distributionManager));
        strategy.executeStrategy(emptyUsers);

        // Cycle 12: User votes again - this triggers the miss detection
        distributionManager.advanceCycle();
        vm.prank(address(distributionManager));
        strategy.executeStrategy(users);

        // Assert
        (uint256 streak, , bool mintPending2) = strategy.userActivity(user);
        assertEq(streak, 1); // Streak reset
        assertEq(mintPending2, false); // mintPending cleared when streak broke
    }

    function test_NotRetryIfAlreadyMinted() public {
        // Arrange
        address[] memory users = new address[](1);
        users[0] = user;

        // Bring user to 10 streak and mint successfully
        for (uint256 i = 0; i < 10; ) {
            vm.prank(address(distributionManager));
            strategy.executeStrategy(users);
            if (i < 9) {
                distributionManager.advanceCycle();
            }
            unchecked {
                ++i;
            }
        }

        assertEq(mockNft.balanceOf(user), 1);
        (, , bool mintPending1) = strategy.userActivity(user);
        assertEq(mintPending1, false);

        // Act: User continues voting, no second mint should occur
        distributionManager.advanceCycle();
        vm.prank(address(distributionManager));
        strategy.executeStrategy(users);
        
        distributionManager.advanceCycle();
        vm.prank(address(distributionManager));
        strategy.executeStrategy(users);

        // Assert
        assertEq(mockNft.balanceOf(user), 1); // Still only 1 NFT
        (, , bool mintPending2) = strategy.userActivity(user);
        assertEq(mintPending2, false); // Not pending
    }

    function test_RevertIf_NotOwnerSetsNft() public {
        // Arrange
        MockBreadkitNFT newMockNft = new MockBreadkitNFT();

        // Act + Assert
        vm.prank(nonOwner);
        vm.expectRevert();
        strategy.setNFTContract(address(newMockNft));
    }
}