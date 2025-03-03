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

    // Lot definition for whitelist tiers
    struct Lot {
        string name;    // Human readable name (e.g. "Small", "Medium", "Large")
        uint256 size;   // Allocation size in native currency (e.g. 10 AVAX worth)
    }

    // Order parameters stored off-chain
    struct Order {
        address maker; // Address of the order creator (seller)
        uint256 marketId; // ID of the market this order belongs to
        uint256 lotIndex; // Index of the lot being sold
        uint256 price; // Selling price in native currency
        uint256 expiration; // Order expiration timestamp
        bytes32 salt; // Random value for uniqueness
    }

    // Market parameters
    struct Market {
        string metadataURI; // Metadata URI for off-chain data
        uint256 tokenAmount; // Amount of tokens being sold
        address tokenAddress; // Token contract address (set after TGE)
        Lot[] lots; // Available whitelist tiers
        uint256 fulfillWindow; // Time window for fulfillment after match
        uint256 platformFeeRate; // Platform fee in basis points (e.g. 1000 = 10%)
        bool isActive; // Market status
        bool hasToken; // Whether token is set
        bool hasTokenAmount; // Whether token amount is set
        bool defaultCollateralToBuyer; // If true, defaulted collateral goes to buyer instead of platform
    }

    // Events
    event TokenAmountSet(uint256 indexed marketId, uint256 tokenAmount);
    event MarketCreated(uint256 indexed marketId);
    event TokenSet(uint256 indexed marketId, address tokenAddress);
    event OrderCreated(bytes32 indexed orderHash, uint256 indexed marketId);
    event OrderMatched(bytes32 indexed orderHash, address indexed taker);
    event OrderFulfilled(bytes32 indexed orderHash);
    event OrderCancelled(bytes32 indexed orderHash);
    event OrderDefaulted(bytes32 indexed orderHash);
    event DefaultCollateralSettingUpdated(uint256 indexed marketId, bool defaultCollateralToBuyer);

    // Errors
    error InvalidMarketParameters();
    error MarketNotActive();
    error TokenNotSet();
    error TokenAlreadySet();
    error TokenAmountAlreadySet();
    error InvalidLotSize();
    error InvalidOrder();
    error OrderNotActive();
    error InsufficientCollateral();
    error Unauthorized();
    error InvalidSignature();
    error DeadlineNotReached();
    error DeadlinePassed();
    error TransferFailed();
}
