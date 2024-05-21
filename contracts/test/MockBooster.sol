// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Booster} from "../Booster.sol";

contract MockBooster is Booster {
    constructor(
        address randomiser_,
        address tokenAddress_,
        uint256[] memory rarityAmountsPerPack_
    ) Booster(randomiser_, tokenAddress_, rarityAmountsPerPack_) {}

    function testOpen(
        uint256 seed,
        address receiver
    ) external returns (uint256[] memory) {
        return _finishOpen(seed, receiver);
    }
}
