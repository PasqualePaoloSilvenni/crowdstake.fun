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
        (uint256 streak,) = strategy.userActivity(user);
        assertEq(streak, 3);
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
        (uint256 streak,) = strategy.userActivity(user);
        assertEq(streak, 1);
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
        (uint256 streak1,) = strategy.userActivity(user1);
        (uint256 streak2,) = strategy.userActivity(user2);

        assertEq(streak1, 10);
        assertEq(streak2, 10);
        assertEq(mockNft.balanceOf(user1), 0);
        assertEq(mockNft.balanceOf(user2), 0);
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