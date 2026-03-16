// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionStrategy} from "../../interfaces/IDistributionStrategy.sol";
import {IRecipientRegistry} from "../../interfaces/IRecipientRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title BaseDistributionStrategy
/// @notice Abstract base for distribution strategies that split yield among registry recipients
/// @dev Concrete strategies implement `_distribute` to define how yield is allocated
abstract contract BaseDistributionStrategy is Initializable, IDistributionStrategy, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroAmount();
    error NoRecipients();

    /// @notice ERC-20 token being distributed as yield
    IERC20 public yieldToken;
    /// @notice Registry that supplies the list of eligible recipients
    IRecipientRegistry public recipientRegistry;

    /// @dev Initializes the base distribution strategy
    /// @param _yieldToken Address of the yield token to distribute
    /// @param _recipientRegistry Address of the recipient registry
    function __BaseDistributionStrategy_init(address _yieldToken, address _recipientRegistry)
        internal
        onlyInitializing
    {
        __Ownable_init(msg.sender);
        __BaseDistributionStrategy_init_unchained(_yieldToken, _recipientRegistry);
    }

    function __BaseDistributionStrategy_init_unchained(address _yieldToken, address _recipientRegistry)
        internal
        onlyInitializing
    {
        if (_yieldToken == address(0)) revert ZeroAddress();
        if (_recipientRegistry == address(0)) revert ZeroAddress();
        yieldToken = IERC20(_yieldToken);
        recipientRegistry = IRecipientRegistry(_recipientRegistry);
    }

    /// @inheritdoc IDistributionStrategy
    function distribute(uint256 amount) public virtual override {
        if (amount == 0) revert ZeroAmount();

        address[] memory recipients = _getRecipients();
        if (recipients.length == 0) revert NoRecipients();

        _distribute(amount, recipients);

        emit Distributed(amount);
    }

    /// @dev Internal distribution logic to be implemented by concrete strategies
    /// @param amount Amount to distribute
    /// @param recipients Array of recipients to distribute to
    function _distribute(uint256 amount, address[] memory recipients) internal virtual;

    /// @dev Gets recipients from the registry
    /// @return Array of recipient addresses
    function _getRecipients() internal view returns (address[] memory) {
        return recipientRegistry.getRecipients();
    }
}
