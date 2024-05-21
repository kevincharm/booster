// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC165, ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {FeistelShuffleOptimised} from "./lib/FeistelShuffleOptimised.sol";
import {Withdrawable} from "./lib/Withdrawable.sol";
import {IRandomiserCallback} from "./interfaces/IRandomiserCallback.sol";
import {IAnyrand} from "./interfaces/IAnyrand.sol";

contract Booster is ERC165, IERC1155Receiver, Withdrawable, Ownable {
    /// @notice Anyrand
    address public immutable randomiser;
    /// @notice Address of ERC1155 that can be loaded into this contract
    address public immutable tokenAddress;
    /// @notice How many tokens per pack
    uint256 public immutable tokensPerPack;
    /// @notice How many tokens per rarity per pack. index = rarity
    uint256[] public rarityAmountsPerPack;

    uint256 public totalTokens;
    /// @notice Token ID list according to rarities
    mapping(uint256 rarity => uint256[] tokenIds) public tokenIdsPerRarity;
    /// @notice True if packs are ready to open
    bool public isActive;
    /// @notice Request id mapping to receiver
    mapping(uint256 requestId => address receiver)
        internal requestIdsToReceiver;

    event PackOpeningRequested(
        uint256 indexed requestId,
        address indexed receiver
    );
    event PackOpened(
        uint256 indexed requestId,
        address indexed receiver,
        uint256[] tokenIds
    );

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
        uint256[] memory rarityAmountsPerPack_
    ) Ownable(msg.sender) {
        randomiser = randomiser_;
        tokenAddress = tokenAddress_;

        uint256 tokensPerPack_;
        for (uint256 i; i < rarityAmountsPerPack_.length; ++i) {
            rarityAmountsPerPack.push(rarityAmountsPerPack_[i]);
            tokensPerPack_ += rarityAmountsPerPack_[i];
        }
        tokensPerPack = tokensPerPack_;
    }

    function _assertIsActive() internal view {
        if (!isActive) revert Inactive();
    }

    function _assertIsNotActive() internal view {
        if (isActive) revert AlreadyActive();
    }

    function _authoriseWithdrawal() internal override onlyOwner {}

    function activate() external onlyOwner {
        _assertIsNotActive();
        isActive = true;
    }

    function deactivate() external onlyOwner {
        _assertIsActive();
        isActive = false;
    }

    function open() external payable {
        _assertIsActive();
        if (totalTokens < tokensPerPack) revert InsufficientTokens();
        totalTokens -= tokensPerPack;

        uint256 requestPrice = IAnyrand(randomiser).getRequestPrice(2_000_000);
        if (address(this).balance < requestPrice) {
            revert InsufficientPayment(requestPrice);
        }
        uint256 requestId = IAnyrand(randomiser).requestRandomness{
            value: requestPrice
        }(block.timestamp + 30, 2_000_000);
        requestIdsToReceiver[requestId] = msg.sender;
        emit PackOpeningRequested(requestId, msg.sender);
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
        uint256[] memory tokenIds = _finishOpen(seed, receiver);
        emit PackOpened(requestId, receiver, tokenIds);
    }

    function _finishOpen(
        uint256 seed,
        address receiver
    ) internal returns (uint256[] memory tokenIds) {
        tokenIds = new uint256[](tokensPerPack);
        uint256 counter;
        for (uint256 i; i < rarityAmountsPerPack.length; ++i) {
            uint256 rarity = i;
            uint256 rarityAmount = rarityAmountsPerPack[i];
            for (uint256 j; j < rarityAmount; ++j) {
                seed = uint256(keccak256(abi.encodePacked(seed)));
                uint256[] storage rarityTokenIds = tokenIdsPerRarity[rarity];
                uint256 domain = rarityTokenIds.length;
                uint256 shuffled = FeistelShuffleOptimised.shuffle(
                    0,
                    domain,
                    seed,
                    4
                );
                uint256 tokenId = rarityTokenIds[shuffled];
                tokenIds[counter++] = tokenId;
                // Switch this one with last
                rarityTokenIds[shuffled] = rarityTokenIds[domain - 1];
                // Remove last
                rarityTokenIds.pop();
            }
        }
        // Do actual transfers
        for (uint256 i; i < tokenIds.length; ++i) {
            ERC1155(tokenAddress).safeTransferFrom(
                address(this),
                receiver,
                tokenIds[i],
                1,
                ""
            );
        }
    }

    function loadCommons(
        uint256[] calldata ids,
        uint256[] calldata values
    ) external {
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
    ) external {
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
        _assertIsNotActive();
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
        _assertIsNotActive();
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
