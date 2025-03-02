// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console2} from "forge-std/Test.sol";
import "../src/PreMarketV2.sol";
import "../src/interfaces/IPremarketV2.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1000000 * (10 ** decimals()));
    }
}

contract PreMarketV2Test is Test {
    PremarketV2 public market;
    MockToken public token;

    address owner = makeAddr("owner");
    address seller = makeAddr("seller");
    address buyer = makeAddr("buyer");
    uint256 sellerPrivateKey = 0x1;
    uint256 buyerPrivateKey = 0x2;

    uint256 constant PLATFORM_FEE = 1000; // 10%
    uint256[] lotSizes = [10 ether]; // 10 AVAX lot

    function setUp() public {
        vm.startPrank(owner);
        market = new PremarketV2();
        token = new MockToken();
        vm.stopPrank();

        // Set seller and buyer addresses based on private keys
        seller = vm.addr(sellerPrivateKey);
        buyer = vm.addr(buyerPrivateKey);

        // Give tokens to seller
        vm.startPrank(owner);
        token.transfer(seller, 10000 * (10 ** token.decimals()));
        vm.stopPrank();

        // Fund accounts with ETH
        vm.deal(seller, 1000 ether);
        vm.deal(buyer, 1000 ether);
    }

    function test_CreateMarket() public {
        vm.startPrank(owner);

        uint256 marketId = market.createMarket(
            lotSizes,
            24 hours, // fulfillWindow
            PLATFORM_FEE,
            "MOCK URI"
        );

        assertEq(marketId, 1);

        (
            ,
            address tokenAddress,
            uint256[] memory marketLotSizes,
            ,
            ,
            bool isActive,
            bool hasToken,

        ) = market.getMarketDetails(marketId);

        assertEq(tokenAddress, address(0));
        assertEq(marketLotSizes[0], lotSizes[0]);
        assertTrue(isActive);
        assertFalse(hasToken);

        vm.stopPrank();
    }

    function test_CreateAndMatchOrder() public {
        // Setup market
        vm.startPrank(owner);
        uint256 marketId = market.createMarket(
            lotSizes,
            24 hours,
            PLATFORM_FEE,
            "MOCK URI"
        );
        market.setMarketTokenAddress(marketId, address(token));
        market.setMarketTokenAmount(marketId, 100 * (10 ** token.decimals())); // 100 tokens
        vm.stopPrank();

        // Create order parameters
        IPremarketV2.Order memory order = IPremarketV2.Order({
            maker: seller,
            marketId: marketId,
            lotSize: 10 ether, // 10 AVAX
            expiration: block.timestamp + 7 days,
            salt: bytes32(uint256(1))
        });

        // Get order hash and sign it
        bytes32 orderHash = market.getOrderHash(order);
        bytes memory signature = signOrder(orderHash, sellerPrivateKey);

        // Seller creates order
        vm.startPrank(seller);
        market.createOrder{value: order.lotSize}(order, signature);
        vm.stopPrank();

        // Verify order status
        assertEq(
            uint256(market.orderStatus(orderHash)),
            uint256(IPremarketV2.OrderStatus.Active)
        );

        // Buyer matches order
        vm.startPrank(buyer);
        market.matchOrder{value: order.lotSize}(order, signature);
        vm.stopPrank();

        // Verify order was matched
        assertEq(
            uint256(market.orderStatus(orderHash)),
            uint256(IPremarketV2.OrderStatus.Matched)
        );
    }

    function test_FulfillOrder() public {
        // Setup market
        vm.startPrank(owner);
        uint256 marketId = market.createMarket(
            lotSizes,
            24 hours,
            PLATFORM_FEE,
            "MOCK URI"
        );
        market.setMarketTokenAddress(marketId, address(token));
        market.setMarketTokenAmount(marketId, 100 * (10 ** token.decimals())); // 100 tokens
        vm.stopPrank();

        // Create order parameters
        IPremarketV2.Order memory order = IPremarketV2.Order({
            maker: seller,
            marketId: marketId,
            lotSize: 10 ether, // 10 AVAX
            expiration: block.timestamp + 7 days,
            salt: bytes32(uint256(1))
        });

        bytes32 orderHash = market.getOrderHash(order);
        bytes memory signature = signOrder(orderHash, sellerPrivateKey);

        // Seller creates order
        vm.startPrank(seller);
        market.createOrder{value: order.lotSize}(order, signature);
        vm.stopPrank();

        // Buyer matches order
        vm.startPrank(buyer);
        market.matchOrder{value: order.lotSize}(order, signature);
        vm.stopPrank();

        // Record balances before fulfillment
        uint256 sellerBalanceBefore = seller.balance;
        uint256 ownerBalanceBefore = owner.balance;
        uint256 buyerTokensBefore = token.balanceOf(buyer);
        uint256 ownerTokensBefore = token.balanceOf(owner);

        (uint256 tokenAmount, , , , , , , ) = market.getMarketDetails(marketId);

        // Calculate expected amounts
        uint256 platformFeeAvax = (order.lotSize * PLATFORM_FEE) / 10000; // 10% of 10 AVAX = 1 AVAX
        uint256 platformFeeTokens = (tokenAmount * PLATFORM_FEE) / 10000; // 10% of 100 tokens = 10 tokens
        uint256 expectedSellerAmount = order.lotSize +
            (order.lotSize - platformFeeAvax); // Collateral + (Payment - Fee)
        uint256 expectedBuyerTokens = tokenAmount - platformFeeTokens; // 90 tokens

        // Seller fulfills order
        vm.startPrank(seller);
        token.approve(address(market), tokenAmount);
        market.fulfillOrder(order, signature);
        vm.stopPrank();

        // Verify order fulfilled
        assertEq(
            uint256(market.orderStatus(orderHash)),
            uint256(IPremarketV2.OrderStatus.Fulfilled)
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
            lotSizes,
            24 hours,
            PLATFORM_FEE,
            "MOCK URI"
        );
        market.setMarketTokenAddress(marketId, address(token));
        market.setMarketTokenAmount(marketId, 100 * (10 ** token.decimals())); // 100 tokens
        vm.stopPrank();

        // Create order parameters
        IPremarketV2.Order memory order = IPremarketV2.Order({
            maker: seller,
            marketId: marketId,
            lotSize: 10 ether,
            expiration: block.timestamp + 7 days,
            salt: bytes32(uint256(1))
        });

        bytes32 orderHash = market.getOrderHash(order);
        bytes memory signature = signOrder(orderHash, sellerPrivateKey);

        // Seller creates order
        vm.startPrank(seller);
        market.createOrder{value: order.lotSize}(order, signature);

        // Record balance before cancellation
        uint256 sellerBalanceBefore = seller.balance;

        // Seller cancels order
        market.cancelOrder(order, signature);
        vm.stopPrank();

        // Verify order cancelled and collateral returned
        assertEq(
            uint256(market.orderStatus(orderHash)),
            uint256(IPremarketV2.OrderStatus.Cancelled)
        );
        assertEq(seller.balance, sellerBalanceBefore + order.lotSize);
    }

    function test_ClaimDefault() public {
        // Setup market
        vm.startPrank(owner);
        uint256 marketId = market.createMarket(
            lotSizes,
            24 hours,
            PLATFORM_FEE,
            "MOCK URI"
        );
        market.setMarketTokenAddress(marketId, address(token));
        market.setMarketTokenAmount(marketId, 100 * (10 ** token.decimals())); // 100 tokens
        vm.stopPrank();

        // Create order parameters
        IPremarketV2.Order memory order = IPremarketV2.Order({
            maker: seller,
            marketId: marketId,
            lotSize: 10 ether,
            expiration: block.timestamp + 7 days,
            salt: bytes32(uint256(1))
        });

        bytes32 orderHash = market.getOrderHash(order);
        bytes memory signature = signOrder(orderHash, sellerPrivateKey);

        // Seller creates order
        vm.startPrank(seller);
        market.createOrder{value: order.lotSize}(order, signature);
        vm.stopPrank();

        // Buyer matches order
        vm.startPrank(buyer);
        market.matchOrder{value: order.lotSize}(order, signature);

        // Record balances before default
        uint256 buyerBalanceBefore = buyer.balance;
        uint256 ownerBalanceBefore = owner.balance;

        // Fast forward past deadline
        vm.warp(block.timestamp + 25 hours);

        // Buyer claims default
        market.claimDefault(order, signature);
        vm.stopPrank();

        // Verify order defaulted
        assertEq(
            uint256(market.orderStatus(orderHash)),
            uint256(IPremarketV2.OrderStatus.Defaulted)
        );

        // Verify balances - buyer gets their payment back, platform gets seller's collateral
        assertEq(buyer.balance, buyerBalanceBefore + order.lotSize);
        assertEq(owner.balance, ownerBalanceBefore + order.lotSize);
    }

    function signOrder(
        bytes32 orderHash,
        uint256 privateKey
    ) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, orderHash);
        return abi.encodePacked(r, s, v);
    }
}
