// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VotingStreakNFTStrategy} from "../src/implementation/strategies/VotingStreakNFTStrategy.sol";
import {MockBreadkitNFT} from "./mocks/MockBreadkitNFT.sol";
import {MockRecipientRegistry} from "./mocks/MockRecipientRegistry.sol";

contract VotingStreakNFTStrategyTest is Test {
    VotingStreakNFTStrategy public strategy;
    MockBreadkitNFT public mockNft;
    MockRecipientRegistry public recipientRegistry;

    address public user = address(0xBEEF);
    address public user1 = address(0xCAFE);
    address public user2 = address(0xF00D);
    address public nonOwner = address(0xDEAD);

    function setUp() public {
        // Arrange
        mockNft = new MockBreadkitNFT();

        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;
        recipientRegistry = new MockRecipientRegistry(recipients);

        strategy = new VotingStreakNFTStrategy();
        strategy.initialize(
            address(0x1234), // non-zero yield token (unused by executeStrategy path)
            address(recipientRegistry),
            address(this), // distribution manager
            address(mockNft)
        );
    }

    function test_ConsecutiveVotesIncrementStreak() public {
        // Arrange
        address[] memory users = new address[](1);
        users[0] = user;

        // Act
        strategy.executeStrategy(users);
        strategy.executeStrategy(users);
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

        // Act
        strategy.executeStrategy(users);      // cycle 1: user votes
        strategy.executeStrategy(emptyUsers); // cycle 2: user misses
        strategy.executeStrategy(users);      // cycle 3: user votes again

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

        // Act
        for (uint256 i = 0; i < 10; ) {
            strategy.executeStrategy(users);
            unchecked {
                ++i;
            }
        }

        // Assert
        assertEq(mockNft.balanceOf(user), 1);
        (uint256 streak, uint256 lastVoteCycle, bool mintPending) = strategy.userActivity(user);
        assertEq(streak, 10);
        assertEq(mintPending, false); // Successfully minted, flag should be cleared
    }

    function test_GracefulDegradationOnMintFail() public {
        // Arrange
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        // Bring both users to 9 streak first
        for (uint256 i = 0; i < 9; ) {
            strategy.executeStrategy(users);
            unchecked {
                ++i;
            }
        }

        mockNft.setShouldFail(true);

        // Act
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
    }

    function test_MintRetrySucceedsOnNextCycle() public {
        // Arrange
        address[] memory users = new address[](1);
        users[0] = user;

        // Bring user to 9 streak
        for (uint256 i = 0; i < 9; ) {
            strategy.executeStrategy(users);
            unchecked {
                ++i;
            }
        }

        mockNft.setShouldFail(true);

        // Act: 10th vote - mint fails
        strategy.executeStrategy(users);

        (uint256 streak1, , bool mintPending1) = strategy.userActivity(user);
        assertEq(streak1, 10);
        assertEq(mintPending1, true);
        assertEq(mockNft.balanceOf(user), 0);

        // Act: 11th vote - retry should succeed
        mockNft.setShouldFail(false);
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
            strategy.executeStrategy(users);
            unchecked {
                ++i;
            }
        }

        mockNft.setShouldFail(true);

        // Act: 10th vote - mint fails
        strategy.executeStrategy(users);
        (uint256 streak1, , bool mintPending1) = strategy.userActivity(user);
        assertEq(mintPending1, true);

        // 11th vote - still fails
        strategy.executeStrategy(users);
        (uint256 streak2, , bool mintPending2) = strategy.userActivity(user);
        assertEq(streak2, 11);
        assertEq(mintPending2, true); // Still pending

        // 12th vote - succeeds
        mockNft.setShouldFail(false);
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
            strategy.executeStrategy(users);
            unchecked {
                ++i;
            }
        }

        mockNft.setShouldFail(true);

        // Act: 10th vote - mint fails, mintPending = true
        strategy.executeStrategy(users);
        (, , bool mintPending1) = strategy.userActivity(user);
        assertEq(mintPending1, true);

        // User misses next cycle
        strategy.executeStrategy(emptyUsers);

        // User votes again - this triggers the miss detection
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
            strategy.executeStrategy(users);
            unchecked {
                ++i;
            }
        }

        assertEq(mockNft.balanceOf(user), 1);
        (, , bool mintPending1) = strategy.userActivity(user);
        assertEq(mintPending1, false);

        // Act: User continues voting, no second mint should occur
        strategy.executeStrategy(users);
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