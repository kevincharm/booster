// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC165, ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {FeistelShuffleOptimised} from "./lib/FeistelShuffleOptimised.sol";
import {IRandomiserCallback} from "./interfaces/IRandomiserCallback.sol";
import {IAnyrand} from "./interfaces/IAnyrand.sol";

contract Booster is ERC165, IERC1155Receiver, Ownable {
    struct RarityAmount {
        uint256 rarity;
        uint256 amount;
    }

    /// @notice Anyrand
    address public immutable randomiser;
    /// @notice Address of ERC1155 that can be loaded into this contract
    address public immutable tokenAddress;
    /// @notice How many tokens per pack
    uint256 public immutable tokensPerPack;
    /// @notice How many tokens per rarity per pack
    RarityAmount[] public rarityAmountsPerPack;

    uint256 public totalTokens;
    /// @notice Token ID list according to rarities
    mapping(uint256 rarity => uint256[] tokenIds) public tokenIdsPerRarity;
    /// @notice True if packs are ready to open
    bool public isActive;
    /// @notice Request id mapping to receiver
    mapping(uint256 requestId => address receiver)
        internal requestIdsToReceiver;

    error InsufficientPayment(uint256 requestPrice);

    error InvalidTokenAddress(address expected, address actual);
    error UnexpectedDataLength(uint256 expected, uint256 actual);
    error AlreadyActive();
    error Inactive();
    error RarityAmountsMismatch();
    error InsufficientTokens();

    constructor(
        address randomiser_,
        address tokenAddress_,
        RarityAmount[] memory rarityAmountsPerPack_
    ) Ownable(msg.sender) {
        randomiser = randomiser_;
        tokenAddress = tokenAddress_;

        uint256 tokensPerPack_;
        for (uint256 i; i < rarityAmountsPerPack_.length; ++i) {
            rarityAmountsPerPack.push(rarityAmountsPerPack_[i]);
            tokensPerPack_ += rarityAmountsPerPack_[i].amount;
        }
        tokensPerPack = tokensPerPack_;
    }

    function _assertIsActive() internal view {
        if (!isActive) revert Inactive();
    }

    function activate() external onlyOwner {
        if (isActive) revert AlreadyActive();
        isActive = true;
    }

    function open() external payable {
        _assertIsActive();
        if (totalTokens < tokensPerPack) revert InsufficientTokens();
        totalTokens -= tokensPerPack;

        uint256 requestPrice = IAnyrand(randomiser).getRequestPrice(500_000);
        if (address(this).balance < requestPrice) {
            revert InsufficientPayment(requestPrice);
        }
        uint256 requestId = IAnyrand(randomiser).requestRandomness{
            value: requestPrice
        }(block.timestamp + 30, 2_000_000);
        requestIdsToReceiver[requestId] = msg.sender;
    }

    /// @notice Receive random words from a randomiser.
    /// @dev Ensure that proper access control is enforced on this function;
    ///     only the designated randomiser may call this function and the
    ///     requestId should be as expected from the randomness request.
    /// @param requestId The identifier for the original randomness request
    /// @param randomWords An arbitrary array of random numbers
    function receiveRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) external {
        require(msg.sender == randomiser, "Only callable by Anyrand");
        address receiver = requestIdsToReceiver[requestId];
        require(receiver != address(0), "Unknown requestId");
        requestIdsToReceiver[requestId] = address(0);
        uint256 seed = randomWords[0];
        _finishOpen(seed, receiver);
    }

    function _finishOpen(uint256 seed, address receiver) internal {
        for (uint256 i; i < rarityAmountsPerPack.length; ++i) {
            RarityAmount memory rarityAmount = rarityAmountsPerPack[i];
            uint256 rarity = rarityAmount.rarity;
            for (uint256 j; j < rarityAmount.amount; ++j) {
                uint256 domain = tokenIdsPerRarity[rarity].length;
                uint256 shuffled = FeistelShuffleOptimised.shuffle(
                    0,
                    domain,
                    seed,
                    4
                );
                uint256 tokenId = tokenIdsPerRarity[rarity][shuffled];
                ERC1155(tokenAddress).safeTransferFrom(
                    address(this),
                    receiver,
                    tokenId,
                    1,
                    ""
                );
                // Switch this one with last
                tokenIdsPerRarity[rarity][shuffled] = tokenIdsPerRarity[rarity][
                    domain - 1
                ];
                // Remove last
                tokenIdsPerRarity[rarity].pop();
            }
        }
    }

    function loadCommons(
        uint256[] calldata ids,
        uint256[] calldata values
    ) external onlyOwner {
        ERC1155(tokenAddress).safeBatchTransferFrom(
            msg.sender,
            address(this),
            ids,
            values,
            abi.encode(uint256(0))
        );
    }

    function loadRares(
        uint256[] calldata ids,
        uint256[] calldata values
    ) external onlyOwner {
        ERC1155(tokenAddress).safeBatchTransferFrom(
            msg.sender,
            address(this),
            ids,
            values,
            abi.encode(uint256(1))
        );
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(IERC165, ERC165) returns (bool) {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Handles the receipt of a single ERC1155 token type. This function is
     * called at the end of a `safeTransferFrom` after the balance has been updated.
     *
     * NOTE: To accept the transfer, this must return
     * `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
     * (i.e. 0xf23a6e61, or its own function selector).
     *
     * @param id The ID of the token being transferred
     * @param value The amount of tokens being transferred
     * @param data Additional data with no specified format
     * @return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` if transfer is allowed
     */
    function onERC1155Received(
        address,
        address,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4) {
        if (msg.sender != tokenAddress)
            revert InvalidTokenAddress(tokenAddress, msg.sender);
        if (data.length != 32) revert UnexpectedDataLength(32, data.length);

        uint256 rarity = abi.decode(data, (uint256));
        for (uint256 i; i < value; ++i) {
            tokenIdsPerRarity[rarity].push(id);
        }
        totalTokens += value;

        return IERC1155Receiver.onERC1155Received.selector;
    }

    /**
     * @dev Handles the receipt of a multiple ERC1155 token types. This function
     * is called at the end of a `safeBatchTransferFrom` after the balances have
     * been updated.
     *
     * NOTE: To accept the transfer(s), this must return
     * `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
     * (i.e. 0xbc197c81, or its own function selector).
     *
     * @param ids An array containing ids of each token being transferred (order and length must match values array)
     * @param values An array containing amounts of each token being transferred (order and length must match ids array)
     * @param data Additional data with no specified format
     * @return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))` if transfer is allowed
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4) {
        if (msg.sender != tokenAddress)
            revert InvalidTokenAddress(tokenAddress, msg.sender);
        if (data.length != 32) revert UnexpectedDataLength(32, data.length);

        uint256 rarity = abi.decode(data, (uint256));
        uint256 total;
        for (uint256 i; i < ids.length; ++i) {
            uint256 amount = values[i];
            total += amount;
            for (uint256 j; j < amount; ++j) {
                tokenIdsPerRarity[rarity].push(ids[i]);
            }
        }
        totalTokens += total;

        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }
}
