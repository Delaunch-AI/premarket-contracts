// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./interfaces/IPremarket.sol";

/**
 * @title Premarket
 * @dev A decentralized OTC market for pre-TGE token trading
 */
contract Premarket is Ownable, ReentrancyGuard, IPremarket {
    using ECDSA for bytes32;

    // State variables
    uint256 public marketCounter;
    mapping(uint256 => Market) private markets;
    mapping(bytes32 => OrderStatus) public orderStatus;
    mapping(bytes32 => address) private orderMakers;
    mapping(bytes32 => uint256) private orderCollateral;
    mapping(bytes32 => uint256) private orderDeadlines;
    mapping(bytes32 => address) private orderTakers;
    mapping(bytes32 => uint256) private orderTakerCollateral;

    constructor() Ownable(msg.sender) {
        marketCounter = 0;
    }

    function _verifySignature(
        address maker,
        bytes calldata signature,
        bytes32 orderHash
    ) internal pure {
        if (maker != orderHash.recover(signature)) revert InvalidSignature();
    }

    /**
     * @dev Creates a new market
     */
    function createMarket(
        Lot[] calldata lots,
        uint256 fulfillWindow,
        uint256 platformFeeRate,
        string calldata metadataURI,
        bool defaultCollateralToBuyer
    ) external onlyOwner returns (uint256) {
        if (
            lots.length == 0 || fulfillWindow == 0 || platformFeeRate > 1000 // Max 10% fee
        ) {
            revert InvalidMarketParameters();
        }

        uint256 marketId = ++marketCounter;
        markets[marketId] = Market({
            metadataURI: metadataURI,
            tokenAmount: 0,
            tokenAddress: address(0),
            lots: lots,
            fulfillWindow: fulfillWindow,
            platformFeeRate: platformFeeRate,
            isActive: true,
            hasToken: false,
            hasTokenAmount: false,
            defaultCollateralToBuyer: defaultCollateralToBuyer
        });

        emit MarketCreated(marketId);
        return marketId;
    }

    /**
     * @dev Updates the default collateral recipient setting for a market
     */
    function setDefaultCollateralRecipient(
        uint256 marketId,
        bool defaultCollateralToBuyer
    ) external onlyOwner {
        Market storage market = markets[marketId];
        market.defaultCollateralToBuyer = defaultCollateralToBuyer;
        emit DefaultCollateralSettingUpdated(marketId, defaultCollateralToBuyer);
    }

    /**
     * @dev Sets token address for a market after TGE
     */
    function setMarketTokenAddress(
        uint256 marketId,
        address tokenAddress
    ) external onlyOwner {
        Market storage market = markets[marketId];

        // Test empty transfer so we can check if it's a valid token
        bool success = IERC20(tokenAddress).transfer(address(this), 0);
        if (!success || tokenAddress == address(0)) {
            revert InvalidMarketParameters();
        }

        market.tokenAddress = tokenAddress;
        market.hasToken = true;
        emit TokenSet(marketId, tokenAddress);
    }

    function setMarketTokenAmount(
        uint256 marketId,
        uint256 tokenAmount
    ) external onlyOwner {
        Market storage market = markets[marketId];
        if (market.hasTokenAmount) {
            revert TokenAmountAlreadySet();
        }
        if (tokenAmount == 0) {
            revert InvalidMarketParameters();
        }

        market.tokenAmount = tokenAmount;
        market.hasTokenAmount = true;
        emit TokenAmountSet(marketId, tokenAmount);
    }

    /**
     * @dev View function to get market details
     */
    function getMarketDetails(
        uint256 marketId
    )
        external
        view
        returns (
            uint256 tokenAmount,
            address tokenAddress,
            Lot[] memory lots,
            uint256 fulfillWindow,
            uint256 platformFeeRate,
            bool isActive,
            bool hasToken,
            bool hasTokenAmount,
            bool defaultCollateralToBuyer
        )
    {
        Market storage market = markets[marketId];
        return (
            market.tokenAmount,
            market.tokenAddress,
            market.lots,
            market.fulfillWindow,
            market.platformFeeRate,
            market.isActive,
            market.hasToken,
            market.hasTokenAmount,
            market.defaultCollateralToBuyer
        );
    }

    /**
     * @dev Validates an order's parameters
     */
    function validateOrder(Order calldata order) public view returns (bool) {
        Market storage market = markets[order.marketId];

        // Check market is active
        if (!market.isActive) return false;

        // Validate lot index
        if (order.lotIndex >= market.lots.length) return false;

        // Check expiration
        if (block.timestamp >= order.expiration) return false;

        return true;
    }

    /**
     * @dev Computes order hash for signing
     */
    function getOrderHash(Order calldata order) public pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    order.maker,
                    order.marketId,
                    order.lotIndex,
                    order.price,
                    order.expiration,
                    order.salt
                )
            );
    }

    /**
     * @dev Creates a new order with collateral
     */
    function createOrder(
        Order calldata order,
        bytes calldata signature
    ) external payable nonReentrant {
        bytes32 orderHash = getOrderHash(order);

        // Verify order parameters
        if (!validateOrder(order)) revert InvalidOrder();

        // Verify signature
        _verifySignature(order.maker, signature, orderHash);

        // Verify sender is maker
        if (msg.sender != order.maker) revert Unauthorized();

        // Verify collateral matches price
        if (msg.value != order.price) revert InsufficientCollateral();

        // Store order details
        orderStatus[orderHash] = OrderStatus.Active;
        orderMakers[orderHash] = order.maker;
        orderCollateral[orderHash] = msg.value;

        emit OrderCreated(orderHash, order.marketId);
    }

    /**
     * @dev Matches an existing order
     */
    function matchOrder(
        Order calldata order,
        bytes calldata signature
    ) external payable nonReentrant {
        bytes32 orderHash = getOrderHash(order);
        Market storage market = markets[order.marketId];

        // Verify order is active
        if (orderStatus[orderHash] != OrderStatus.Active)
            revert OrderNotActive();

        // Verify signature
        _verifySignature(order.maker, signature, orderHash);

        // Verify payment matches price
        if (msg.value != order.price) revert InsufficientCollateral();

        // Update order status
        orderStatus[orderHash] = OrderStatus.Matched;
        orderTakers[orderHash] = msg.sender;
        orderTakerCollateral[orderHash] = msg.value;
        orderDeadlines[orderHash] = block.timestamp + market.fulfillWindow;

        emit OrderMatched(orderHash, msg.sender);
    }

    /**
     * @dev Fulfills a matched order by delivering tokens
     */
    function fulfillOrder(
        Order calldata order,
        bytes calldata signature
    ) external nonReentrant {
        bytes32 orderHash = getOrderHash(order);
        Market storage market = markets[order.marketId];

        // Verify order state
        if (orderStatus[orderHash] != OrderStatus.Matched)
            revert InvalidOrder();

        _verifySignature(order.maker, signature, orderHash);

        if (!market.hasToken) revert TokenNotSet();
        if (msg.sender != orderMakers[orderHash]) revert Unauthorized();
        if (block.timestamp > orderDeadlines[orderHash])
            revert DeadlinePassed();

        // Calculate fees
        uint256 platformFeeRate = market.platformFeeRate;
        uint256 paymentFee = (order.price * platformFeeRate) / 10000;
        uint256 tokenFee = (market.tokenAmount * platformFeeRate) / 10000;

        // Transfer tokens to buyer and platform
        IERC20 token = IERC20(market.tokenAddress);
        if (
            !token.transferFrom(
                msg.sender,
                orderTakers[orderHash],
                market.tokenAmount - tokenFee
            )
        ) {
            revert TransferFailed();
        }
        if (!token.transferFrom(msg.sender, owner(), tokenFee)) {
            revert TransferFailed();
        }

        // Store amounts before clearing storage
        uint256 sellerCollateral = orderCollateral[orderHash];
        uint256 payment = orderTakerCollateral[orderHash];

        // Clear storage before transfers
        orderCollateral[orderHash] = 0;
        orderTakerCollateral[orderHash] = 0;
        orderStatus[orderHash] = OrderStatus.Fulfilled;

        // Return seller's collateral and send payment minus fee
        (bool success1, ) = msg.sender.call{
            value: sellerCollateral + payment - paymentFee
        }("");
        if (!success1) revert TransferFailed();

        // Send fee to platform
        (bool success2, ) = owner().call{value: paymentFee}("");
        if (!success2) revert TransferFailed();

        emit OrderFulfilled(orderHash);
    }

    /**
     * @dev Cancels an unmatched order
     */
    function cancelOrder(
        Order calldata order,
        bytes calldata signature
    ) external nonReentrant {
        bytes32 orderHash = getOrderHash(order);

        // Verify order state and authorization
        if (orderStatus[orderHash] != OrderStatus.Active)
            revert OrderNotActive();
        if (msg.sender != orderMakers[orderHash]) revert Unauthorized();

        _verifySignature(order.maker, signature, orderHash);

        // Store amount before clearing storage
        uint256 refundAmount = orderCollateral[orderHash];

        // Clear storage before transfer
        orderCollateral[orderHash] = 0;
        orderStatus[orderHash] = OrderStatus.Cancelled;

        // Return maker's collateral
        (bool success, ) = msg.sender.call{value: refundAmount}("");
        if (!success) revert TransferFailed();

        emit OrderCancelled(orderHash);
    }

    /**
     * @dev Claims default if seller hasn't fulfilled by deadline
     */
    function claimDefault(
        Order calldata order,
        bytes calldata signature
    ) external nonReentrant {
        bytes32 orderHash = getOrderHash(order);
        Market storage market = markets[order.marketId];

        // Verify order state and authorization
        if (orderStatus[orderHash] != OrderStatus.Matched)
            revert InvalidOrder();
        if (msg.sender != orderTakers[orderHash]) revert Unauthorized();
        _verifySignature(order.maker, signature, orderHash);
        if (block.timestamp <= orderDeadlines[orderHash])
            revert DeadlineNotReached();

        // Store amounts before clearing storage
        uint256 buyerAmount = orderTakerCollateral[orderHash];
        uint256 platformAmount = orderCollateral[orderHash];

        // Clear storage before transfers
        orderCollateral[orderHash] = 0;
        orderTakerCollateral[orderHash] = 0;
        orderStatus[orderHash] = OrderStatus.Defaulted;

        // Return buyer's collateral
        (bool success1, ) = msg.sender.call{value: buyerAmount}("");
        if (!success1) revert TransferFailed();

        // Send seller's collateral to platform or buyer based on market setting
        address collateralRecipient = market.defaultCollateralToBuyer ? msg.sender : owner();
        (bool success2, ) = collateralRecipient.call{value: platformAmount}("");
        if (!success2) revert TransferFailed();

        emit OrderDefaulted(orderHash);
    }

    receive() external payable {}
}
