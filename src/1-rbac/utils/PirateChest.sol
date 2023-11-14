// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PirateChest is ERC1155, Ownable {
    uint256 public constant AMULET = 1;
    uint256 public constant PIRATE_CREDENTIAL = 2;

    constructor() ERC1155("https://hook.example/api/item/{id}.json") Ownable(msg.sender) {}

    function mintAmulet(address _recipient) public onlyOwner {
        _mint({to: _recipient, id: AMULET, value: 1, data: ""});
    }

    function mintPirateCredential(address _recipient) public onlyOwner {
        _mint({to: _recipient, id: PIRATE_CREDENTIAL, value: 1, data: ""});
    }
}
