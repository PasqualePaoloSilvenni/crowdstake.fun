// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICycleModule} from "../../src/interfaces/ICycleModule.sol";
import {IRecipientRegistry} from "../../src/interfaces/IRecipientRegistry.sol";
import {IVotingModule} from "../../src/interfaces/IVotingModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockCycleModule} from "./MockCycleModule.sol";

/// @title MockDistributionManagerForVotingStreak
/// @notice Mock distribution manager for VotingStreakNFTStrategy tests
/// @dev Simple mock without Initializable inheritance to avoid initialization conflicts in tests
contract MockDistributionManagerForVotingStreak {
    MockCycleModule public mockCycleModule;
    IRecipientRegistry public recipientRegistry;
    IERC20 public baseToken;
    IVotingModule public votingModule;

    constructor(
        address _cycleModule,
        address _recipientRegistry,
        address _baseToken,
        address _votingModule
    ) {
        mockCycleModule = MockCycleModule(_cycleModule);
        recipientRegistry = IRecipientRegistry(_recipientRegistry);
        baseToken = IERC20(_baseToken);
        votingModule = IVotingModule(_votingModule);
    }

    /// @notice Returns the cycle manager (same as mockCycleModule)
    function cycleManager() external view returns (ICycleModule) {
        return ICycleModule(address(mockCycleModule));
    }

    function isDistributionReady() public view returns (bool) {
        return true;
    }

    function claimAndDistribute() external {}

    function advanceCycle() external {
        mockCycleModule.advanceCycle();
    }
}
