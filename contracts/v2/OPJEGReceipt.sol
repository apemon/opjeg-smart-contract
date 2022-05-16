//SPDX-License-Identifier: MIT
// author yoyoismee.eth , unnawut.eth
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";



/// @notice just a non transferable NFT to use as receipt. 
contract OPJEGReceipt is ERC721, Ownable {
    using Strings for uint256;
    event notTransfer(address from, address to, uint256 tokenId);

    constructor(string memory name, string memory symbol)
        ERC721(name, symbol)
    {}

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        emit notTransfer(from, to, tokenId); 
        revert("OPJEGReceipt: non tranferable");
    }

    function mintTo(address wallet, uint256 tokenId) public onlyOwner {
        _mint(wallet, tokenId);
    }

    function burn(uint256 tokenId) public onlyOwner {
        _burn(tokenId);
    }

    /// @dev todo
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(tokenId));
        return string(abi.encodePacked("yolo - ", tokenId.toString())); // let's do SVG on this later
    }
}
