//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// TODO: view function to query NFT owner

contract OPJEG is ERC721Enumerable, ERC721Holder, Ownable {
    using Strings for uint256;

    address immutable nftAddress;
    string nftName;

    uint256 mintFee = 0.0 ether;
    uint256 backendBip = 50;

    uint256 totalFee;
    uint256 lastidx;

    /// @dev tokenID only valid for call option
    struct Option {
        uint256 tokenID;
        uint256 strikePrice;
        address issuer;
        uint32 deadline;
        bool isPut;
    }

    /// @dev main data
    mapping(uint256 => Option) optionData;
    mapping(address => uint256) ethBal;
    mapping(address => uint256[]) nftBal;

    constructor(string memory _nftName, address _nftAddress)
        ERC721(
            string(abi.encodePacked("OPJEG-", _nftName)),
            string(abi.encodePacked("OPJEG-", _nftName))
        )
    {
        nftAddress = _nftAddress;
        nftName = _nftName;
    }

    /// @dev exercise to sell NFT
    function mintPut(uint256 _strikePrice, uint256 _deadline) public payable {
        require(msg.value >= _strikePrice + mintFee, "invalid payment");
        totalFee += mintFee; // claim excess msg.value for protocol

        optionData[lastidx + 1] = Option({
            tokenID: 0, // tokenID is irrelavant for put
            deadline: uint32(_deadline),
            strikePrice: _strikePrice,
            issuer: msg.sender,
            isPut: true
        });
        _mint(msg.sender, lastidx + 1);
        lastidx += 1;
    }

    /// @dev exercise to buy NFT
    function mintCall(
        uint256 _tokenID,
        uint256 _strikePrice,
        uint256 _deadline
    ) public payable {
        require(msg.value >= mintFee, "invalid payment");
        totalFee += mintFee; // claim excess msg.value for protocol

        ERC721(nftAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenID
        );

        optionData[lastidx + 1] = Option({
            tokenID: _tokenID,
            deadline: uint32(_deadline),
            strikePrice: _strikePrice,
            issuer: msg.sender,
            isPut: false
        });
        totalFee += mintFee; // remove!
        _mint(msg.sender, lastidx + 1);
        lastidx += 1;
    }

    /// @dev NFT to issuer - mooney to option HODLER
    function exercisePut(uint256 optionID, uint256 tokenID) public {
        Option memory opt = optionData[optionID];

        require(ownerOf(optionID) == msg.sender, "not your option");
        require(block.timestamp < opt.deadline, "expired");
        require(opt.isPut, "wrong endpoint");

        _burn(optionID);

        ERC721(nftAddress).safeTransferFrom(msg.sender, address(this), tokenID);
        nftBal[opt.issuer].push(tokenID);

        payable(msg.sender).transfer(
            (opt.strikePrice * (10_000 - backendBip)) / 10_000
        );
        totalFee += (opt.strikePrice * backendBip) / 10_000;
    }

    /// @dev end option. return asset to issuer. can be call if issuer own the option or option expired
    function burnOption(uint256 optionID) public {
        Option memory opt = optionData[optionID];

        // anyone can burn expired option
        if (block.timestamp < opt.deadline) {
            require(ownerOf(optionID) == msg.sender, "not your option");
            require(msg.sender == opt.issuer, "not your");
        }

        _burn(optionID);

        if (opt.isPut) {
            payable(opt.issuer).transfer(opt.strikePrice);
        } else {
            ERC721(nftAddress).transferFrom(
                address(this),
                opt.issuer,
                opt.tokenID
            );
        }
    }

    /// @dev NFT to option HODLER - mooney to issuer
    function exerciseCall(uint256 optionID) public payable {
        Option memory opt = optionData[optionID];

        require(ownerOf(optionID) == msg.sender, "not your option");
        require(block.timestamp < opt.deadline, "expired");
        require(!opt.isPut, "wrong endpoint");

        _burn(optionID);
        require(msg.value >= opt.strikePrice);
        ERC721(nftAddress).safeTransferFrom(
            address(this),
            msg.sender,
            opt.tokenID
        );
        ethBal[opt.issuer] += opt.strikePrice;
    }

    /// @dev ez money
    function claimETH() public {
        uint256 toSend = ethBal[msg.sender];
        ethBal[msg.sender] = 0;

        payable(msg.sender).transfer((toSend * (10_000 - backendBip)) / 10_000);
        totalFee += (toSend * backendBip) / 10_000;
    }

    /// @dev loop claim NFT.
    function claimNFT() public {
        for (uint256 i = 0; i < nftBal[msg.sender].length; i++) {
            ERC721(nftAddress).safeTransferFrom(
                address(this),
                msg.sender,
                nftBal[msg.sender][i]
            );
        }
        delete nftBal[msg.sender];
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

    /// @dev ez mooney
    function claim() public onlyOwner {
        uint256 toPay = totalFee;
        totalFee = 0;
        payable(msg.sender).transfer(toPay);
    }
}
