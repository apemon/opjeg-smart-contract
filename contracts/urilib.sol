pragma solidity 0.8.13;

import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

library URILib {
    using Strings for uint256;

    function renderContractURI(string memory name)
        internal
        view
        returns (string memory)
    {
        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "OPJEG - ',
                        name,
                        '","description": "OPtion to optimize your JPEG"}'
                    )
                )
            )
        );
        string memory output = string(
            abi.encodePacked("data:application/json;base64,", json)
        );
        return output;
    }

    function renderURI(
        bool isPut,
        string memory name,
        uint256 tokenID,
        uint256 priceWei,
        uint256 deadline
    ) internal view returns (string memory) {
        if (isPut) {
            return renderPut(name, tokenID, priceWei, deadline);
        }
        return renderCall(name, tokenID, priceWei, deadline);
    }

    function renderPut(
        string memory name,
        uint256 tokenID,
        uint256 priceWei,
        uint256 deadline
    ) internal view returns (string memory) {
        string memory img = string(
            abi.encodePacked(
                '<svg width="690" height="420" fill="none" xmlns="http://www.w3.org/2000/svg"> ',
                " <style> ",
                ".put { font: italic 40px serif; fill: red; } ",
                ".call { font: italic 40px serif; fill: green; } ",
                "</style> ",
                '<text x="10" y="40" class="put">option to sell ',
                name,
                "</text>"
            )
        );

        img = string(
            abi.encodePacked(
                img,
                '<text x="10" y="80" class="put">token ID - any</text>',
                '<text x="10" y="120" class="put">at ',
                string(weiToEth(priceWei)),
                " </text>",
                '<text x="10" y="160" class="put">expired in ',
                string(timeRemain(deadline)),
                "</text>",
                '<text x="10" y="200" class="put">check out TW @opjegfinance</text>',
                "</svg>"
            )
        );

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "OPJEG - PUT - ',
                        name,
                        '", "description": "OPtion to optimize your JPEG", "image": "data:image/svg+xml;base64,',
                        Base64.encode(bytes(img)),
                        '","attributes": [{"trait_type": "Type", "value": "PUT"}]}'
                    )
                )
            )
        );
        string memory output = string(
            abi.encodePacked("data:application/json;base64,", json)
        );

        return output;
    }

    function renderCall(
        string memory name,
        uint256 tokenID,
        uint256 priceWei,
        uint256 deadline
    ) internal view returns (string memory) {
        string memory img = string(
            abi.encodePacked(
                '<svg width="690" height="420" fill="none" xmlns="http://www.w3.org/2000/svg"> ',
                " <style> ",
                ".put { font: italic 40px serif; fill: red; } ",
                ".call { font: italic 40px serif; fill: green; } ",
                "</style> ",
                '<text x="10" y="40" class="call">option to buy ',
                name,
                "</text>"
            )
        );

        img = string(
            abi.encodePacked(
                img,
                '<text x="10" y="80" class="call">token ID - ',
                tokenID.toString(),
                "</text>",
                '<text x="10" y="120" class="call">at ',
                string(weiToEth(priceWei)),
                " </text>",
                '<text x="10" y="160" class="call">expired in ',
                string(timeRemain(deadline)),
                "</text>",
                '<text x="10" y="200" class="call">check out TW @opjegfinance</text>',
                "</svg>"
            )
        );

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "OPJEG - CALL - ',
                        name,
                        '", "description": "OPtion to optimize your JPEG", "image": "data:image/svg+xml;base64,',
                        Base64.encode(bytes(img)),
                        '","attributes": [{"trait_type": "Type", "value": "CALL"}]}'
                    )
                )
            )
        );
        string memory output = string(
            abi.encodePacked("data:application/json;base64,", json)
        );

        return output;
    }

    function weiToEth(uint256 price) internal view returns (string memory) {
        uint256 eth = price / 1 ether;
        uint256 deci = ((price % 1 ether) * 1000) / 1 ether;
        return
            string(
                abi.encodePacked(eth.toString(), ".", deci.toString(), " ETH")
            );
    }

    function timeRemain(uint256 time) internal view returns (string memory) {
        if (block.timestamp > time) {
            return " Expired";
        }
        uint256 remain = time - block.timestamp;
        uint256 day = remain / 1 days;
        uint256 hour = (remain % 1 days) / 1 hours;
        return
            string(
                abi.encodePacked(
                    day.toString(),
                    " days ",
                    hour.toString(),
                    " hours"
                )
            );
    }
}
