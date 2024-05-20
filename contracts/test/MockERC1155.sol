// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract MockERC1155 is ERC1155 {
    constructor() ERC1155("ipfs://") {
        // commons
        for (uint256 i = 1; i <= 20; ++i) {
            _mint(msg.sender, i, 2, "");
        }
        // rare
        for (uint256 i = 21; i <= 25; ++i) {
            _mint(msg.sender, i, 2, "");
        }
    }
}
