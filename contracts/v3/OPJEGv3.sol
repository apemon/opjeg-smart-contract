//SPDX-License-Identifier: MIT
// author yoyoismee.eth , unnawut.eth
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./OPJEGReceipt.sol";
import "../urilib.sol";

contract OPJEGv3 is ERC721Enumerable, ERC721Holder, Ownable, EIP712 {
    using Strings for uint256;

    address immutable nftAddress;
    string nftName;

    uint256 constant mintFee = 0.0 ether;
    uint256 constant backendBip = 50;
    uint256 constant LiquidatorBip = 50; // bonus to liquidator if greater than min
    uint256 constant minDebtSize = 0.5 ether; // to garantee bounty

    uint256 totalFee;
    uint256 lastidx;
    uint256 constant collateralFactor = 9000; // 90 %
    uint256 constant collateralBuffer = 500; // 5 % Factor - buffer = borrowable

    uint256 liquidationDeadlineBuffer = 1 days;

    mapping(address => mapping(uint256 => bool)) nonceUsed;

    OPJEGReceipt receipt;

    /// @dev tokenID only valid for call option
    struct Option {
        uint256 tokenID;
        uint256 strikePrice;
        address issuer;
        uint32 deadline;
        bool isPut;
        bool allowLend;
        uint16 rate;
    }

    struct Debt {
        uint256 amount;
        uint256 collateral; // duo used either balance or tokenID
        uint32 lastTs;
        bool exist;
    }

    /// @dev main data
    mapping(uint256 => Option) optionData;
    mapping(uint256 => Debt) debtData;

    mapping(address => uint256) ethBal;
    mapping(address => uint256[]) nftBal;

    constructor(string memory _nftName, address _nftAddress)
        ERC721(
            string(abi.encodePacked("OPJEG-", _nftName)),
            string(abi.encodePacked("OPJEG-", _nftName))
        )
        EIP712(string(abi.encodePacked("OPJEG-", _nftName)), "1.0.0")
    {
        nftAddress = _nftAddress;
        nftName = _nftName;

        string memory tmp = string(abi.encodePacked("OPJEG-", _nftName));

        receipt = new OPJEGReceipt(tmp, tmp);
    }

    function deposit() public payable {
        ethBal[msg.sender] += msg.value;
    }

    function _hashPut(
        uint256 _strikePrice,
        uint256 _deadline,
        bool _allowLend,
        uint16 _rate,
        uint256 premium,
        uint256 nonce
    ) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256(
                            "PUT(uint256 _strikePrice,uint256 _deadline,bool _allowLend,uint16 _rate,uint256 premium,uint256 nonce)"
                        ),
                        _strikePrice,
                        _deadline,
                        _allowLend,
                        _rate,
                        premium
                    )
                )
            );
    }

    function _hashCall(
        uint256 _tokenID,
        uint256 _strikePrice,
        uint256 _deadline,
        bool _allowLend,
        uint16 _rate,
        uint256 premium,
        uint256 nonce
    ) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256(
                            "CALL(uint256 _tokenID,uint256 _strikePrice,uint256 _deadline,bool _allowLend,uint16 _rate,uint256 premium,uint256 nonce)"
                        ),
                        _tokenID,
                        _strikePrice,
                        _deadline,
                        _allowLend,
                        _rate,
                        premium
                    )
                )
            );
    }

    function cancle(uint256 nonce) public {
        nonceUsed[msg.sender][nonce] = true;
    }

    function buyPut(
        uint256 _strikePrice,
        uint256 _deadline,
        bool _allowLend,
        uint16 _rate,
        uint256 premium,
        uint256 nonce,
        bytes memory signature
    ) public payable {
        address seller = ECDSA.recover(
            _hashPut(
                _strikePrice,
                _deadline,
                _allowLend,
                _rate,
                premium,
                nonce
            ),
            signature
        );

        require(!nonceUsed[seller][nonce]);
        nonceUsed[seller][nonce] = true;

        require(msg.value >= premium);

        ethBal[seller] -= _strikePrice;
        ethBal[seller] += (premium * (10_000 - backendBip)) / 10_000;
        totalFee += (premium * backendBip) / 10_000;

        optionData[lastidx + 1] = Option({
            tokenID: 0, // tokenID is irrelavant for put
            deadline: uint32(_deadline),
            strikePrice: _strikePrice,
            issuer: seller,
            isPut: true,
            allowLend: _allowLend,
            rate: _rate
        });
        _mint(msg.sender, lastidx + 1);
        lastidx += 1;
    }

    function buyCall(
        uint256 _tokenID,
        uint256 _strikePrice,
        uint256 _deadline,
        bool _allowLend,
        uint16 _rate,
        uint256 premium,
        uint256 nonce,
        bytes memory signature
    ) public payable {
        address seller = ECDSA.recover(
            _hashCall(
                _tokenID,
                _strikePrice,
                _deadline,
                _allowLend,
                _rate,
                premium,
                nonce
            ),
            signature
        );

        require(!nonceUsed[seller][nonce]);
        nonceUsed[seller][nonce] = true;

        require(msg.value >= premium);
        ethBal[seller] += (premium * (10_000 - backendBip)) / 10_000;
        totalFee += (premium * backendBip) / 10_000;

        ERC721(nftAddress).safeTransferFrom(seller, address(this), _tokenID);

        optionData[lastidx + 1] = Option({
            tokenID: _tokenID,
            deadline: uint32(_deadline),
            strikePrice: _strikePrice,
            issuer: seller,
            isPut: false,
            allowLend: _allowLend,
            rate: _rate
        });
        totalFee += mintFee; // remove!
        _mint(msg.sender, lastidx + 1);

        receipt.mintTo(seller, _tokenID);
        lastidx += 1;
    }

    /// @dev exercise to sell NFT
    function mintPut(uint256 _strikePrice, uint256 _deadline) public payable {
        mintPut(_strikePrice, _deadline, false, 0);
    }

    /// @dev exercise to sell NFT
    function mintPut(
        uint256 _strikePrice,
        uint256 _deadline,
        bool _allowLend,
        uint16 _rate
    ) public payable {
        require(msg.value >= _strikePrice + mintFee, "invalid payment");
        totalFee += mintFee; // claim excess msg.value for protocol

        optionData[lastidx + 1] = Option({
            tokenID: 0, // tokenID is irrelavant for put
            deadline: uint32(_deadline),
            strikePrice: _strikePrice,
            issuer: msg.sender,
            isPut: true,
            allowLend: _allowLend,
            rate: _rate
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
        mintCall(_tokenID, _strikePrice, _deadline, false, 0);
    }

    /// @dev exercise to buy NFT
    function mintCall(
        uint256 _tokenID,
        uint256 _strikePrice,
        uint256 _deadline,
        bool _allowLend,
        uint16 _rate
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
            isPut: false,
            allowLend: _allowLend,
            rate: _rate
        });
        totalFee += mintFee; // remove!
        _mint(msg.sender, lastidx + 1);

        receipt.mintTo(msg.sender, _tokenID);

        lastidx += 1;
    }

    /// @dev NFT to issuer - mooney to option HODLER
    function exercisePut(uint256 optionID, uint256 tokenID) public {
        require(!debtData[optionID].exist, "have outstanding debt");

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
        require(!debtData[optionID].exist, "have outstanding debt");

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
            receipt.burn(opt.tokenID);
            ERC721(nftAddress).transferFrom(
                address(this),
                opt.issuer,
                opt.tokenID
            );
        }
    }

    /// @dev NFT to option HODLER - mooney to issuer
    function exerciseCall(uint256 optionID) public payable {
        require(!debtData[optionID].exist, "have outstanding debt");

        Option memory opt = optionData[optionID];

        require(ownerOf(optionID) == msg.sender, "not your option");
        require(block.timestamp < opt.deadline, "expired");
        require(!opt.isPut, "wrong endpoint");

        _burn(optionID);
        require(msg.value >= opt.strikePrice);
        receipt.burn(opt.tokenID);
        ERC721(nftAddress).safeTransferFrom(
            address(this),
            msg.sender,
            opt.tokenID
        );
        ethBal[opt.issuer] +=
            (opt.strikePrice * (10_000 - backendBip)) /
            10_000;
        totalFee += (opt.strikePrice * backendBip) / 10_000;
    }

    /// @dev ez money
    function claimETH() public {
        uint256 toSend = ethBal[msg.sender];
        ethBal[msg.sender] = 0;
        payable(msg.sender).transfer(toSend);
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
        Option memory token = optionData[tokenId];
        return
            URILib.renderURI(
                token.isPut,
                nftName,
                token.tokenID,
                token.strikePrice,
                token.deadline
            );
    }

    /// @dev ez mooney
    function claim() public onlyOwner {
        uint256 toPay = totalFee;
        totalFee = 0;
        payable(msg.sender).transfer(toPay);
    }

    /// @notice unlock NFT from call option with ETH as collateral
    function borrowNFT(uint256 optionID) public payable {
        require(ownerOf(optionID) == msg.sender, "not your option");

        Option memory opt = optionData[optionID];
        require(opt.strikePrice > minDebtSize);

        require(!debtData[optionID].exist, "have outstanding debt");
        require(opt.allowLend);
        require(!opt.isPut);
        require(opt.deadline > block.timestamp + liquidationDeadlineBuffer);
        uint256 buffer = (opt.strikePrice * LiquidatorBip) / 10_000;
        require(msg.value >= buffer + opt.strikePrice);

        receipt.burn(opt.tokenID);

        debtData[optionID] = Debt({
            amount: opt.tokenID,
            collateral: msg.value,
            lastTs: uint32(block.timestamp),
            exist: true
        });
        ERC721(nftAddress).safeTransferFrom(
            address(this),
            msg.sender,
            opt.tokenID
        );
    }

    /// @notice unlock ETH from put option with NFT as collateral
    function borrowETH(
        uint256 optionID,
        uint256 tokenID,
        uint256 amount
    ) public payable {
        require(ownerOf(optionID) == msg.sender, "not your option");
        require(amount > minDebtSize);

        Option memory opt = optionData[optionID];

        require(!debtData[optionID].exist, "have outstanding debt");
        require(opt.allowLend);
        require(opt.isPut);
        require(opt.deadline > block.timestamp + liquidationDeadlineBuffer);
        require(
            amount <=
                (opt.strikePrice * (collateralFactor - collateralBuffer)) /
                    10_000
        );

        debtData[optionID] = Debt({
            amount: amount,
            collateral: tokenID,
            lastTs: uint32(block.timestamp),
            exist: true
        });
        ERC721(nftAddress).safeTransferFrom(msg.sender, address(this), tokenID);
        payable(msg.sender).transfer(amount);
    }

    function addCol(uint256 optionID) public payable {
        require(debtData[optionID].exist);
        Option memory opt = optionData[optionID];
        require(!opt.isPut);
        debtData[optionID].collateral += msg.value;
    }

    function debtInterest(
        uint256 init,
        uint256 rate,
        uint256 time
    ) internal pure returns (uint256) {
        return (((init * rate) / 10_000) * time) / 365 days;
    }

    function repayETH(uint256 optionID) public payable {
        require(ownerOf(optionID) == msg.sender, "not your debt");
        Debt storage debt = debtData[optionID];
        Option memory opt = optionData[optionID];

        require(debt.exist);
        require(opt.isPut);
        uint256 interest = debtInterest(
            debt.amount,
            opt.rate,
            block.timestamp - debt.lastTs
        );

        require(msg.value > interest);

        ethBal[opt.issuer] += (interest * (10_000 - backendBip)) / 10_000;
        totalFee += (interest * (backendBip)) / 10_000;

        if (msg.value >= debt.amount + interest) {
            debt.amount = 0;
            debt.exist = false;
            debt.lastTs = 0;
            debt.collateral = 0;
            ERC721(nftAddress).safeTransferFrom(
                address(this),
                msg.sender,
                debt.collateral
            );
        } else {
            debt.amount = debt.amount + interest - msg.value;
            debt.lastTs = uint32(block.timestamp);
        }
    }

    function returnNFT(uint256 optionID) public {
        require(ownerOf(optionID) == msg.sender, "not your debt");
        Debt storage debt = debtData[optionID];
        require(debt.exist);
        Option memory opt = optionData[optionID];
        require(!opt.isPut);

        uint256 interest = debtInterest(
            opt.strikePrice,
            opt.rate,
            block.timestamp - debt.lastTs
        );
        ERC721(nftAddress).safeTransferFrom(
            msg.sender,
            address(this),
            opt.tokenID
        );

        debt.amount = 0;
        uint256 toPay = debt.collateral - interest;
        debt.collateral = 0;
        debt.exist = false;

        ethBal[opt.issuer] += (interest * (10_000 - backendBip)) / 10_000;
        totalFee += (interest * (backendBip)) / 10_000;

        receipt.mintTo(opt.issuer, opt.tokenID);
        payable(msg.sender).transfer(toPay);
    }

    /// @notice liquidate ETH dept by seize NFT
    function liquidateETHDept(uint256 optionID) public {
        Debt storage debt = debtData[optionID];
        require(debt.exist);
        Option storage opt = optionData[optionID];
        require(opt.isPut);
        uint256 interest = debtInterest(
            debt.amount,
            opt.rate,
            block.timestamp - debt.lastTs
        );

        bool valid = false;
        if (block.timestamp + liquidationDeadlineBuffer > opt.deadline) {
            valid = true;
        } else if (
            debt.amount + interest >
            (opt.strikePrice * collateralFactor) / 10_000
        ) {
            valid = true;
        }

        if (!valid) {
            return;
        }

        address borrower = ownerOf(optionID);
        _burn(optionID);

        nftBal[opt.issuer].push(debt.collateral);

        ethBal[opt.issuer] += (interest * (10_000 - backendBip)) / 10_000;
        uint256 bounty = (opt.strikePrice * LiquidatorBip) / 10_000;
        uint256 fee = ((opt.strikePrice + interest) * backendBip) / 10_000;
        totalFee += fee;
        ethBal[borrower] += opt.strikePrice - interest - bounty - fee;

        payable(msg.sender).transfer(bounty);
    }

    /// @notice liquidate NFT dept by seize ETH
    function liquidateNFTDept(uint256 optionID) public {
        Debt storage debt = debtData[optionID];
        require(debt.exist);
        Option storage opt = optionData[optionID];
        require(!opt.isPut);
        uint256 interest = debtInterest(
            opt.strikePrice,
            opt.rate,
            block.timestamp - debt.lastTs
        );

        bool valid = false;
        if (block.timestamp + liquidationDeadlineBuffer > opt.deadline) {
            valid = true;
        } else if (opt.strikePrice + interest > debt.collateral) {
            valid = true;
        }

        if (!valid) {
            return;
        }

        _burn(optionID);

        uint256 bounty = (opt.strikePrice * LiquidatorBip) / 10_000;
        uint256 fee = ((opt.strikePrice + interest) * backendBip) / 10_000;
        ethBal[opt.issuer] += debt.collateral - bounty - fee;

        payable(msg.sender).transfer(bounty);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        require(!debtData[tokenId].exist, "have outstanding debt");
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function contractURI() external view returns (string memory) {
        return URILib.renderContractURI(nftName);
    }
}
