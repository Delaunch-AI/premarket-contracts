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

    // Errors
    error ExistingOrder();
    error InvalidMarket();
    error InvalidMarketParameters();
    error TokenDetailsNotSet();
    error TokenDetailsAlreadySet();
    error InvalidOrder();
    error InsufficientCollateral();
    error Unauthorized();
    error DeadlineNotReached();
    error DeadlinePassed();
    error TransferFailed();
}
