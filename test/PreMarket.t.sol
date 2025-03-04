// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Test, console2} from "forge-std/Test.sol";
import "../src/PreMarket.sol";
import "../src/interfaces/IPremarket.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1000000 * (10 ** 18));
    }
}

contract PreMarketTest is Test {
    Premarket public market;
    MockToken public token;

    address owner = makeAddr("owner");
    address seller = makeAddr("seller");
    address buyer = makeAddr("buyer");
    uint256 sellerPrivateKey = 0x1;
    uint256 buyerPrivateKey = 0x2;

    uint256 constant PLATFORM_FEE = 1000; // 10%

    function setUp() public {
        vm.startPrank(owner);
        market = new Premarket();
        token = new MockToken();
        vm.stopPrank();

        // Set seller and buyer addresses based on private keys
        seller = vm.addr(sellerPrivateKey);
        buyer = vm.addr(buyerPrivateKey);

        // Give tokens to seller
        vm.startPrank(owner);
        token.transfer(seller, 10000 ether);
        vm.stopPrank();

        // Fund accounts with ETH
        vm.deal(seller, 1000 ether);
        vm.deal(buyer, 1000 ether);
    }

    function test_CreateMarket() public {
        vm.startPrank(owner);

        uint256 marketId = market.createMarket(
            24 hours, // fulfillWindow
            PLATFORM_FEE,
            "MOCK URI",
            false
        );

        assertEq(marketId, 1);

        IPremarket.Market memory _market = market.getMarketDetails(marketId);

        address tokenAddress = _market.tokenAddress;

        bool isActive = _market.isActive;
        bool hasToken = _market.hasTokenDetails;

        // (
        //     ,
        //     address tokenAddress,
        //     ,
        //     ,
        //     ,
        //     ,
        //     bool isActive,
        //     bool hasToken,
        //     ,

        // ) = market.getMarketDetails(marketId);

        assertEq(tokenAddress, address(0));
        assertTrue(isActive);
        assertFalse(hasToken);

        vm.stopPrank();
    }

    function test_CreateAndMatchOrder() public {
        // Setup market
        vm.startPrank(owner);
        uint256 marketId = market.createMarket(
            24 hours, // fulfillWindow
            PLATFORM_FEE,
            "MOCK URI",
            false
        );
        market.setMarketTokenDetails(marketId, 100 ether, address(token));

        vm.stopPrank();

        // Create order parameters
        IPremarket.Order memory order = IPremarket.Order({
            maker: seller,
            marketId: marketId,
            price: 10 ether, // 10 AVAX
            salt: bytes32(uint256(1))
        });

        // Get order hash and sign it
        bytes32 orderHash = market.getOrderHash(order);

        // Seller creates order
        vm.startPrank(seller);
        market.createOrder{value: order.price}(order);
        vm.stopPrank();

        assertEq(market.getUserOrderCount(seller), 1);
        assertEq(market.getUserOrderHashByIndex(seller, 0), orderHash);

        (, , , , IPremarket.OrderStatus orderStatus) = market.getOrderByHash(
            orderHash
        );

        // Verify order status
        assertEq(uint256(orderStatus), uint256(IPremarket.OrderStatus.Active));

        // Buyer matches order
        vm.startPrank(buyer);
        market.matchOrder{value: order.price}(order);
        vm.stopPrank();

        (, , , , IPremarket.OrderStatus orderStatusAfterMatched) = market
            .getOrderByHash(orderHash);

        // Verify order was matched
        assertEq(
            uint256(orderStatusAfterMatched),
            uint256(IPremarket.OrderStatus.Matched)
        );
    }

    function test_FulfillOrder() public {
        // Setup market
        vm.startPrank(owner);
        uint256 marketId = market.createMarket(
            24 hours,
            PLATFORM_FEE,
            "MOCK URI",
            false
        );

        market.setMarketTokenDetails(marketId, 100 ether, address(token));
        market.setMarketDeadline(marketId);
        vm.stopPrank();

        // Create order parameters
        IPremarket.Order memory order = IPremarket.Order({
            maker: seller,
            marketId: marketId,
            price: 10 ether, // 10 AVAX
            salt: bytes32(uint256(1))
        });

        bytes32 orderHash = market.getOrderHash(order);

        // Seller creates order
        vm.startPrank(seller);
        market.createOrder{value: order.price}(order);
        vm.stopPrank();

        // Buyer matches order
        vm.startPrank(buyer);
        market.matchOrder{value: order.price}(order);
        vm.stopPrank();

        // Record balances before fulfillment
        uint256 sellerBalanceBefore = seller.balance;
        uint256 ownerBalanceBefore = owner.balance;
        uint256 buyerTokensBefore = token.balanceOf(buyer);
        uint256 ownerTokensBefore = token.balanceOf(owner);

        // (uint256 tokenAmount, , , , , , , , , ) = market.getMarketDetails(
        //     marketId
        // );

        IPremarket.Market memory _market = market.getMarketDetails(marketId);
        uint256 tokenAmount = _market.tokenAmount;

        // Calculate expected amounts
        uint256 platformFeeAvax = (order.price * PLATFORM_FEE) / 10000; // 10% of 10 AVAX = 1 AVAX
        uint256 platformFeeTokens = (tokenAmount * PLATFORM_FEE) / 10000; // 10% of 100 tokens = 10 tokens
        uint256 expectedSellerAmount = order.price +
            (order.price - platformFeeAvax); // Collateral + (Payment - Fee)
        uint256 expectedBuyerTokens = tokenAmount - platformFeeTokens; // 90 tokens

        // Seller fulfills order
        vm.startPrank(seller);
        token.approve(address(market), tokenAmount);
        market.fulfillOrder(order);
        vm.stopPrank();

        (, , , , IPremarket.OrderStatus orderStatus) = market.getOrderByHash(
            orderHash
        );

        // Verify order fulfilled
        assertEq(
            uint256(orderStatus),
            uint256(IPremarket.OrderStatus.Fulfilled)
        );

        // Verify balances
        assertEq(seller.balance, sellerBalanceBefore + expectedSellerAmount);
        assertEq(owner.balance, ownerBalanceBefore + platformFeeAvax);
        assertEq(
            token.balanceOf(buyer),
            buyerTokensBefore + expectedBuyerTokens
        );
        assertEq(token.balanceOf(owner), ownerTokensBefore + platformFeeTokens);
    }

    function test_CancelOrder() public {
        // Setup market
        vm.startPrank(owner);
        uint256 marketId = market.createMarket(
            24 hours, // fulfillWindow
            PLATFORM_FEE,
            "MOCK URI",
            false
        );
        market.setMarketTokenDetails(marketId, 100 ether, address(token));
        vm.stopPrank();

        // Create order parameters
        IPremarket.Order memory order = IPremarket.Order({
            maker: seller,
            marketId: marketId,
            price: 10 ether,
            salt: bytes32(uint256(1))
        });

        bytes32 orderHash = market.getOrderHash(order);

        // Seller creates order
        vm.startPrank(seller);
        market.createOrder{value: order.price}(order);

        // Record balance before cancellation
        uint256 sellerBalanceBefore = seller.balance;

        // Seller cancels order
        market.cancelOrder(order);
        vm.stopPrank();

        (, , , , IPremarket.OrderStatus orderStatus) = market.getOrderByHash(
            orderHash
        );

        // Verify order cancelled and collateral returned
        assertEq(
            uint256(orderStatus),
            uint256(IPremarket.OrderStatus.Cancelled)
        );
        assertEq(seller.balance, sellerBalanceBefore + order.price);
    }

    function test_ClaimDefault() public {
        // Setup market
        vm.startPrank(owner);
        uint256 marketId = market.createMarket(
            24 hours, // fulfillWindow
            PLATFORM_FEE,
            "MOCK URI",
            false
        );

        market.setMarketTokenDetails(marketId, 100 ether, address(token));
        market.setMarketDeadline(marketId);
        vm.stopPrank();

        // Create order parameters
        IPremarket.Order memory order = IPremarket.Order({
            maker: seller,
            marketId: marketId,
            price: 10 ether,
            salt: bytes32(uint256(1))
        });

        bytes32 orderHash = market.getOrderHash(order);

        // Seller creates order
        vm.startPrank(seller);
        market.createOrder{value: order.price}(order);
        vm.stopPrank();

        // Buyer matches order
        vm.startPrank(buyer);
        market.matchOrder{value: order.price}(order);

        // Record balances before default
        uint256 buyerBalanceBefore = buyer.balance;
        uint256 ownerBalanceBefore = owner.balance;

        // Fast forward past deadline
        vm.warp(block.timestamp + 25 hours);

        // Buyer claims default
        market.claimDefault(order);
        vm.stopPrank();

        (, , , , IPremarket.OrderStatus orderStatus) = market.getOrderByHash(
            orderHash
        );

        // Verify order defaulted
        assertEq(
            uint256(orderStatus),
            uint256(IPremarket.OrderStatus.Defaulted)
        );

        // Verify balances - buyer gets their payment back, platform gets seller's collateral
        assertEq(buyer.balance, buyerBalanceBefore + order.price);
        assertEq(owner.balance, ownerBalanceBefore + order.price);
    }
}
