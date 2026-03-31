// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICrowdstakeNFT} from "../../src/interfaces/ICrowdstakeNFT.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockCrowdstakeNFT is ERC721, ICrowdstakeNFT {
    bool public shouldFail;
    uint256 private _nextTokenId = 1;

    constructor() ERC721("Mock Crowdstake NFT", "MBNFT") {}

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function mint(address to) external override returns (uint256 tokenId) {
        if (shouldFail) revert("Mock: Mint failed");

        tokenId = _nextTokenId;
        unchecked {
            ++_nextTokenId;
        }

        _safeMint(to, tokenId);
    }

}