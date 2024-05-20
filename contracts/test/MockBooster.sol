// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Booster} from "../Booster.sol";

contract MockBooster is Booster {
    constructor(
        address randomiser_,
        address tokenAddress_,
        RarityAmount[] memory rarityAmountsPerPack_
    ) Booster(randomiser_, tokenAddress_, rarityAmountsPerPack_) {}

    function testOpen(uint256 seed, address receiver) external {
        _finishOpen(seed, receiver);
    }
}