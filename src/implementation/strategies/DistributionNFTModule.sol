// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IBreadkitNFT.sol"; // <-- Importiamo l'interfaccia esterna

/// @title Distribution NFT Module for the Breadkit ecosystem
/// @notice Manages the distribution and revocation of NFTs based on an ERC20 token balance.
/// @dev Implements the issue's diagram logic, optimized for gas.
contract DistributionNFTModule is Ownable {
    /// @notice The ERC20 token used to check eligibility.
    IERC20 public immutable baseToken;
    
    /// @notice The NFT contract used to reward users.
    IBreadkitNFT public immutable nftContract;
    
    /// @notice The minimum baseToken balance required to hold or receive the NFT.
    uint256 public minHoldings;

    /// @notice Maps a user to their assigned NFT ID.
    mapping(address => uint256) public userToTokenId;
    
    /// @notice Tracks whether a user currently holds an NFT from this module.
    mapping(address => bool) public hasNFT;

    /// @notice Emitted when an NFT is awarded to a user.
    event NFTAwarded(address indexed user, uint256 tokenId);
    
    /// @notice Emitted when an NFT is revoked from a user.
    event NFTBurned(address indexed user, uint256 tokenId);
    
    /// @notice Emitted when the minimum holding requirements are updated.
    event MinHoldingsUpdated(uint256 oldHoldings, uint256 newHoldings);

    /// @param _baseToken The address of the ERC20 contract.
    /// @param _nftContract The address of the NFT contract (must implement IBreadkitNFT).
    /// @param _minHoldings The minimum required balance.
    /// @param _initialOwner The address of the module administrator.
    constructor(
        address _baseToken,
        address _nftContract,
        uint256 _minHoldings,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_baseToken != address(0), "Invalid base token");
        require(_nftContract != address(0), "Invalid NFT contract");
        
        baseToken = IERC20(_baseToken);
        nftContract = IBreadkitNFT(_nftContract);
        minHoldings = _minHoldings;
    }

    /// @notice Updates the minimum threshold required for eligibility.
    /// @param _newMinHoldings The new threshold value.
    function setMinHoldings(uint256 _newMinHoldings) external onlyOwner {
        uint256 oldHoldings = minHoldings;
        minHoldings = _newMinHoldings;
        emit MinHoldingsUpdated(oldHoldings, _newMinHoldings);
    }

    /// @notice Executes the distribution logic for a list of users.
    /// @dev Optimized using calldata, memory caching, and unchecked math for the loop.
    /// @param users An array of user addresses to process.
    function executeDistribution(address[] calldata users) external onlyOwner {
        // Caching of state variables in memory to save gas
        uint256 length = users.length;
        uint256 currentMinHoldings = minHoldings;

        for (uint256 i = 0; i < length; ) {
            address user = users[i];
            uint256 balance = baseToken.balanceOf(user);
            bool currentlyHasNFT = hasNFT[user];

            if (balance >= currentMinHoldings) {
                // If eligible and does not have the NFT, execute mint
                if (!currentlyHasNFT) {
                    uint256 tokenId = nftContract.mint(user);
                    userToTokenId[user] = tokenId;
                    hasNFT[user] = true;
                    
                    emit NFTAwarded(user, tokenId);
                }
            } else {
                // If not eligible but has the NFT, execute burn
                if (currentlyHasNFT) {
                    uint256 tokenId = userToTokenId[user];
                    nftContract.burn(tokenId);
                    
                    hasNFT[user] = false;
                    delete userToTokenId[user]; // Gas refund by deleting data from storage
                    
                    emit NFTBurned(user, tokenId);
                }
            }

            // Gas optimization: index cannot overflow
            unchecked { ++i; }
        }
    }
}