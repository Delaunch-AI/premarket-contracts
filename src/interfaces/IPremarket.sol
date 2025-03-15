// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IPremarket {
    // Order status
    enum OrderStatus {
        Invalid, // Default state
        Active, // Order is live and can be matched
        Matched, // Order has been matched but not fulfilled
        Fulfilled, // Deal completed successfully
        Cancelled, // Deal cancelled by maker before buyer
        Defaulted // Seller failed to deliver tokens
    }

    struct StoredOrder {
        address maker; // Address of the order creator (seller)
        uint256 marketId; // ID of the market this order belongs to
        uint256 price; // Selling price in native currency
        bytes32 salt; // Random value for uniqueness
        address taker; // Address of the order taker (buyer)
        uint256 collateral; // Collateral amount in native currency
        uint256 takerCollateral; // Collateral amount in native currency
        OrderStatus status; // Order status
    }

    // Order parameters stored off-chain
    struct Order {
        address maker; // Address of the order creator (seller)
        uint256 marketId; // ID of the market this order belongs to
        uint256 price; // Selling price in native currency
        bytes32 salt; // Random value for uniqueness
    }

    // Market parameters
    struct Market {
        string metadataURI; // Metadata URI for off-chain data
        uint256 tokenAmount; // Amount of tokens being sold
        address tokenAddress; // Token contract address (set after TGE)
        uint256 fulfillWindow; // Time window for fulfillment after match
        uint256 fulfillDeadline; // Time when token details were set
        uint256 platformFeeRate; // Platform fee in basis points (e.g. 1000 = 10%)
        uint256 defaultFeeRate; // Fee rate for defaults in basis points (e.g. 1000 = 10%)
        bool isActive; // Market status
        bool hasTokenDetails; // Whether token details is set
        bool hasDeadline; // Whether fulfill deadline is set
        bool defaultCollateralToBuyer; // If true, defaulted collateral goes to buyer instead of platform
        bool initialized;
    }

    // Events
    event TokenDetailsSet(
        uint256 indexed marketId,
        uint256 tokenAmount,
        address tokenAddress
    );
    event MarketStarted(uint256 indexed marketId);
    event MarketStopped(uint256 indexed marketId);
    event MarketDeadlineSet(uint256 indexed marketId, uint256 deadline);
    event MarketCreated(uint256 indexed marketId);
    event OrderCreated(bytes32 indexed orderHash, uint256 indexed marketId);
    event OrderMatched(bytes32 indexed orderHash, address indexed taker);
    event OrderFulfilled(bytes32 indexed orderHash);
    event OrderCancelled(bytes32 indexed orderHash);
    event OrderDefaulted(bytes32 indexed orderHash);
    event DefaultCollateralSettingUpdated(
        uint256 indexed marketId,
        bool defaultCollateralToBuyer
    );
    event DefaultFeeRateUpdated(
        uint256 indexed marketId,
        uint256 defaultFeeRate
    );

    // Errors
    error InvalidFeeReceiver();
    error MarketEnded();
    error ExistingOrder();
    error InvalidMarket();
    error InvalidMarketParameters();
    error TokenDetailsNotSet();
    error TokenDetailsAlreadySet();
    error InvalidOrder();
    error InsufficientCollateral();
    error Unauthorized();
    error DeadlineNotSet();
    error DeadlineNotReached();
    error DeadlinePassed();
    error TransferFailed();

    function createMarket(
        uint256 fulfillWindow,
        uint256 platformFeeRate,
        uint256 defaultFeeRate,
        string calldata metadataURI,
        bool defaultCollateralToBuyer
    ) external returns (uint256);

    function setDefaultFeeRate(
        uint256 marketId,
        uint256 defaultFeeRate
    ) external;

    function setDefaultCollateralRecipient(
        uint256 marketId,
        bool defaultCollateralToBuyer
    ) external;

    function setMarketTokenDetails(
        uint256 marketId,
        uint256 tokenAmount,
        address tokenAddress
    ) external;

    function overrideMarketTokenDetails(
        uint256 marketId,
        address tokenAddress,
        uint256 tokenAmount
    ) external;

    function setMarketDeadline(uint256 marketId) external;

    function getMarketDetails(
        uint256 marketId
    ) external view returns (Market memory);

    function validateOrder(Order calldata order) external view returns (bool);

    function getOrderHash(Order calldata order) external pure returns (bytes32);

    function createOrder(Order calldata order) external payable;

    function getUserOrderCount(address user) external view returns (uint256);

    function getUserOrderHashByIndex(
        address user,
        uint256 index
    ) external view returns (bytes32);

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
        );

    function matchOrder(Order calldata order) external payable;

    function fulfillOrder(Order calldata order) external;

    function cancelOrder(Order calldata order) external;

    function claimDefault(Order calldata order) external;

    function rescueAvax() external;

    function stopMarket(uint256 marketId) external;

    function startMarket(uint256 marketId) external;

    function rescueERC20(address tokenAddress) external;
}
