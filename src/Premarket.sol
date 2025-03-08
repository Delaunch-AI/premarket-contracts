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

    address public feeReceiver;
    uint256 public marketCounter;
    mapping(uint256 => Market) private _markets;
    mapping(bytes32 => StoredOrder) private _orders;
    mapping(address => uint256) private _userOrdersCount;
    mapping(address => bytes32[]) private _userOrderHashes;

    constructor() Ownable(msg.sender) {
        feeReceiver = msg.sender;
        marketCounter = 0;
    }

    /**
     * @dev Creates a new market
     */
    function createMarket(
        uint256 fulfillWindow,
        uint256 platformFeeRate,
        uint256 defaultFeeRate,
        string calldata metadataURI,
        bool defaultCollateralToBuyer
    ) external onlyOwner returns (uint256) {
        if (fulfillWindow == 0) {
            revert InvalidMarketParameters();
        }

        uint256 marketId = ++marketCounter;
        _markets[marketId] = Market({
            metadataURI: metadataURI,
            tokenAmount: 0,
            tokenAddress: address(0),
            fulfillWindow: fulfillWindow,
            fulfillDeadline: 0,
            hasDeadline: false,
            platformFeeRate: platformFeeRate,
            defaultFeeRate: defaultFeeRate,
            isActive: true,
            hasTokenDetails: false,
            defaultCollateralToBuyer: defaultCollateralToBuyer,
            initialized: true
        });

        emit MarketCreated(marketId);
        return marketId;
    }

    /**
     * @dev Updates the default fee rate for a market
     */
    function setDefaultFeeRate(
        uint256 marketId,
        uint256 defaultFeeRate
    ) external onlyOwner {
        if (defaultFeeRate > 1000) {
            // Max 10% fee
            revert InvalidMarketParameters();
        }
        Market storage market = _markets[marketId];
        market.defaultFeeRate = defaultFeeRate;
        emit DefaultFeeRateUpdated(marketId, defaultFeeRate);
    }

    /**
     * @dev Updates the default collateral recipient setting for a market
     */
    function setDefaultCollateralRecipient(
        uint256 marketId,
        bool defaultCollateralToBuyer
    ) external onlyOwner {
        Market storage market = _markets[marketId];
        market.defaultCollateralToBuyer = defaultCollateralToBuyer;
        emit DefaultCollateralSettingUpdated(
            marketId,
            defaultCollateralToBuyer
        );
    }

    /**
     * @dev Sets token details for a market after TGE
     */
    function setMarketTokenDetails(
        uint256 marketId,
        uint256 tokenAmount,
        address tokenAddress
    ) external onlyOwner {
        Market storage market = _markets[marketId];

        if (market.hasTokenDetails) {
            revert TokenDetailsAlreadySet();
        }
        if (tokenAmount == 0 || tokenAddress == address(0)) {
            revert InvalidMarketParameters();
        }

        market.tokenAddress = tokenAddress;
        market.tokenAmount = tokenAmount;
        market.hasTokenDetails = true;

        emit TokenDetailsSet(marketId, tokenAmount, tokenAddress);
    }

    /**
     * @dev Stops market for trading
     */
    function stopMarket(uint256 marketId) external onlyOwner {
        if (!_markets[marketId].initialized || !_markets[marketId].isActive)
            revert InvalidMarket();

        Market storage market = _markets[marketId];
        market.isActive = false;

        emit MarketStopped(marketId);
    }

    /**
     * @dev Resumes market for trading
     */
    function startMarket(uint256 marketId) external onlyOwner {
        if (!_markets[marketId].initialized || _markets[marketId].isActive)
            revert InvalidMarket();
        Market storage market = _markets[marketId];
        market.isActive = true;

        emit MarketStarted(marketId);
    }

    /**
     * @dev Overrides token details for a market after TGE
     */
    function overrideMarketTokenDetails(
        uint256 marketId,
        address tokenAddress,
        uint256 tokenAmount
    ) external onlyOwner {
        Market storage market = _markets[marketId];

        if (tokenAmount == 0 || tokenAddress == address(0)) {
            revert InvalidMarketParameters();
        }

        market.tokenAddress = tokenAddress;
        market.tokenAmount = tokenAmount;
        market.hasTokenDetails = true;

        emit TokenDetailsSet(marketId, tokenAmount, tokenAddress);
    }

    /**
     * @dev Sets deadline for a market after TGE, requires token details to be set first
     */
    function setMarketDeadline(uint256 marketId) external onlyOwner {
        Market storage market = _markets[marketId];

        if (
            !market.hasTokenDetails ||
            market.tokenAmount == 0 ||
            market.tokenAddress == address(0)
        ) {
            revert();
        }

        market.fulfillDeadline = block.timestamp + market.fulfillWindow;
        market.hasDeadline = true;

        emit MarketDeadlineSet(marketId, market.fulfillDeadline);
    }

    /**
     * @dev View function to get market details
     */
    function getMarketDetails(
        uint256 marketId
    ) external view returns (Market memory market) {
        Market storage _market = _markets[marketId];
        if (!_market.initialized) revert InvalidMarket();
        return _market;
    }

    /**
     * @dev Validates an order's parameters
     */
    function validateOrder(Order calldata order) public view returns (bool) {
        if (order.price <= 0) return false;

        Market storage market = _markets[order.marketId];

        // Check market is active
        if (!market.isActive || !market.initialized) return false;

        return true;
    }

    /**
     * @dev Computes order hash as identifier
     */
    function getOrderHash(Order calldata order) public pure returns (bytes32) {
        return
            keccak256(
                abi.encode(order.maker, order.marketId, order.price, order.salt)
            );
    }

    /**
     * @dev Creates a new order with collateral
     */
    function createOrder(Order calldata order) external payable nonReentrant {
        bytes32 orderHash = getOrderHash(order);

        StoredOrder memory existingOrder = _orders[orderHash];

        Market memory market = _markets[order.marketId];
        if (!market.isActive || !market.initialized) revert InvalidMarket();

        if (existingOrder.status == OrderStatus.Active) revert ExistingOrder();

        // Verify order parameters
        if (!validateOrder(order)) revert InvalidOrder();

        // Verify sender is maker
        if (msg.sender != order.maker) revert Unauthorized();

        // Verify collateral matches price
        if (msg.value != order.price) revert InsufficientCollateral();

        // Store order details
        StoredOrder memory storedOrder = StoredOrder({
            maker: order.maker,
            marketId: order.marketId,
            price: order.price,
            salt: order.salt,
            taker: address(0),
            collateral: msg.value,
            takerCollateral: 0,
            status: OrderStatus.Active
        });

        _orders[orderHash] = storedOrder;
        _userOrdersCount[msg.sender]++;
        _userOrderHashes[msg.sender].push(orderHash);

        emit OrderCreated(orderHash, order.marketId);
    }

    function getUserOrderCount(address user) public view returns (uint256) {
        return _userOrdersCount[user];
    }
    function getUserOrderHashByIndex(
        address user,
        uint256 index
    ) public view returns (bytes32) {
        if (index >= _userOrderHashes[user].length) revert InvalidOrder();
        return _userOrderHashes[user][index];
    }

    function getOrderByHash(
        bytes32 orderHash
    )
        external
        view
        returns (
            address maker,
            uint256 marketId,
            uint256 price,
            bytes32 salt,
            OrderStatus status
        )
    {
        StoredOrder memory order = _orders[orderHash];
        return (
            order.maker,
            order.marketId,
            order.price,
            order.salt,
            order.status
        );
    }

    /**
     * @dev Matches an existing order
     */
    function matchOrder(Order calldata order) external payable nonReentrant {
        bytes32 orderHash = getOrderHash(order);
        StoredOrder storage storedOrder = _orders[orderHash];
        Market memory market = _markets[order.marketId];
        if (
            !market.isActive ||
            storedOrder.marketId != order.marketId ||
            storedOrder.maker == msg.sender ||
            storedOrder.status != OrderStatus.Active
        ) revert InvalidOrder();

        if (market.hasDeadline) revert MarketEnded();

        // Verify payment matches price
        if (msg.value != storedOrder.price) revert InsufficientCollateral();

        // Update order status
        storedOrder.status = OrderStatus.Matched;
        storedOrder.taker = msg.sender;
        storedOrder.takerCollateral = msg.value;

        emit OrderMatched(orderHash, msg.sender);
    }

    /**
     * @dev Fulfills a matched order by delivering tokens
     */
    function fulfillOrder(Order calldata order) external nonReentrant {
        bytes32 orderHash = getOrderHash(order);
        Market memory market = _markets[order.marketId];
        StoredOrder storage storedOrder = _orders[orderHash];
        if (
            storedOrder.marketId != order.marketId ||
            storedOrder.status != OrderStatus.Matched
        ) revert InvalidOrder();

        if (storedOrder.maker != msg.sender) revert Unauthorized();
        if (!market.hasTokenDetails) revert TokenDetailsNotSet();
        if (!market.hasDeadline) revert DeadlineNotSet();
        if (block.timestamp > market.fulfillDeadline) revert DeadlinePassed();

        // Calculate fees
        uint256 platformFeeRate = market.platformFeeRate;
        uint256 paymentFee = (order.price * platformFeeRate) / 10000;
        uint256 tokenFee = (market.tokenAmount * platformFeeRate) / 10000;

        // Transfer tokens to buyer and platform
        IERC20 token = IERC20(market.tokenAddress);
        if (
            !token.transferFrom(
                msg.sender,
                storedOrder.taker,
                market.tokenAmount - tokenFee
            )
        ) {
            revert TransferFailed();
        }
        if (!token.transferFrom(msg.sender, owner(), tokenFee)) {
            revert TransferFailed();
        }

        // Store amounts before clearing storage
        uint256 sellerCollateral = storedOrder.collateral;
        uint256 payment = storedOrder.takerCollateral;

        // Clear storage before transfers
        storedOrder.collateral = 0;
        storedOrder.takerCollateral = 0;
        storedOrder.status = OrderStatus.Fulfilled;

        // Return seller's collateral and send payment minus fee
        (bool success1, ) = msg.sender.call{
            value: sellerCollateral + payment - paymentFee
        }("");
        if (!success1) revert TransferFailed();

        // Send fee to platform
        (bool success2, ) = feeReceiver.call{value: paymentFee}("");
        if (!success2) revert TransferFailed();

        emit OrderFulfilled(orderHash);
    }

    function setFeeReceiver(address feeReceiver_) external onlyOwner {
        (bool success, ) = feeReceiver_.call{value: 0}("");
        if (!success) revert InvalidFeeReceiver();
        feeReceiver = feeReceiver_;
    }

    /**
     * @dev Cancels an unmatched order, valid for pre & post TGE
     */
    function cancelOrder(Order calldata order) external nonReentrant {
        bytes32 orderHash = getOrderHash(order);

        StoredOrder storage storedOrder = _orders[orderHash];
        if (
            storedOrder.marketId != order.marketId ||
            storedOrder.status != OrderStatus.Active
        ) revert InvalidOrder();

        if (storedOrder.maker != msg.sender) revert Unauthorized();

        // Store amount before clearing storage
        uint256 refundAmount = storedOrder.collateral;

        // Clear storage before transfer
        storedOrder.collateral = 0;
        storedOrder.status = OrderStatus.Cancelled;

        // Return maker's collateral
        (bool success, ) = msg.sender.call{value: refundAmount}("");
        if (!success) revert TransferFailed();

        emit OrderCancelled(orderHash);
    }

    /**
     * @dev Claims default if seller hasn't fulfilled by deadline
     */
    function claimDefault(Order calldata order) external nonReentrant {
        bytes32 orderHash = getOrderHash(order);
        Market memory market = _markets[order.marketId];
        StoredOrder storage storedOrder = _orders[orderHash];
        // Verify order state and authorization
        if (
            storedOrder.marketId != order.marketId ||
            storedOrder.status != OrderStatus.Matched
        ) revert InvalidOrder();

        if (storedOrder.taker != msg.sender) revert Unauthorized();
        if (block.timestamp <= market.fulfillDeadline || !market.hasDeadline)
            revert DeadlineNotReached();

        // Store amounts before clearing storage
        uint256 buyerAmount = storedOrder.takerCollateral;
        uint256 platformAmount = storedOrder.collateral;

        // Clear storage before transfers
        storedOrder.collateral = 0;
        storedOrder.takerCollateral = 0;
        storedOrder.status = OrderStatus.Defaulted;

        // Return buyer's collateral
        (bool success1, ) = msg.sender.call{value: buyerAmount}("");
        if (!success1) revert TransferFailed();

        // Handle seller's collateral based on market setting
        if (market.defaultCollateralToBuyer) {
            // Calculate fee using the market's defaultFeeRate
            uint256 platformFee = (platformAmount * market.defaultFeeRate) /
                10000;
            uint256 buyerShare = platformAmount - platformFee;

            // Send remaining amount to buyer
            (bool success2, ) = msg.sender.call{value: buyerShare}("");
            if (!success2) revert TransferFailed();

            // Send fee to platform
            (bool success3, ) = feeReceiver.call{value: platformFee}("");
            if (!success3) revert TransferFailed();
        } else {
            // If not defaulting to buyer, send entire amount to platform
            (bool success2, ) = feeReceiver.call{value: platformAmount}("");
            if (!success2) revert TransferFailed();
        }

        emit OrderDefaulted(orderHash);
    }

    // Emergency
    function rescueAvax() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        if (!success) revert TransferFailed();
    }

    function rescueERC20(address tokenAddress) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        if (!token.transfer(owner(), token.balanceOf(address(this)))) {
            revert TransferFailed();
        }
    }

    receive() external payable {}
}
