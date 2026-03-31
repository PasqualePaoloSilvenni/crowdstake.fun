// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title Interface for the Crowdstake NFT contract
/// @dev Extends IERC721 by adding the mint and burn functions required by the module.
interface ICrowdstakeNFT is IERC721 {
    /// @notice Mints a new NFT to the specified address.
    /// @param to The address that will receive the NFT.
    /// @return tokenId The unique ID of the newly minted NFT.
    function mint(address to) external returns (uint256);

    /// @notice Burns a specific NFT.
    /// @param tokenId The ID of the NFT to burn.
    function burn(uint256 tokenId) external;
}