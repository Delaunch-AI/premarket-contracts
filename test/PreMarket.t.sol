// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Test, console2} from "forge-std/Test.sol";
import "../src/Premarket.sol";
import "../src/interfaces/IPremarket.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1000000 * (10 ** 18));
    }
}

contract PremarketTest is Test {
    Premarket public market;
    MockToken public token;

    address owner = makeAddr("owner");
    address seller = makeAddr("seller");
    address buyer = makeAddr("buyer");
    uint256 sellerPrivateKey = 0x1;
    uint256 buyerPrivateKey = 0x2;

    uint256 constant PLATFORM_FEE = 1000; // 10%
    uint256 constant DEFAULT_FEE = 1000; // 10%

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
            DEFAULT_FEE,
            "MOCK URI",
            false // defaultCollateralToBuyer
        );

        assertEq(marketId, 1);

        IPremarket.Market memory _market = market.getMarketDetails(marketId);

        address tokenAddress = _market.tokenAddress;

        bool isActive = _market.isActive;
        bool hasToken = _market.hasTokenDetails;

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
            DEFAULT_FEE,
            "MOCK URI",
            false // defaultCollateralToBuyer
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
            DEFAULT_FEE,
            "MOCK URI",
            false // defaultCollateralToBuyer
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

        bytes32 orderHash = market.getOrderHash(order);

        // Seller creates order
        vm.prank(seller);
        market.createOrder{value: order.price}(order);

        // Buyer matches order
        vm.prank(buyer);
        market.matchOrder{value: order.price}(order);

        vm.prank(owner);
        market.setMarketDeadline(marketId);

        // Record balances before fulfillment
        uint256 sellerBalanceBefore = seller.balance;
        uint256 ownerBalanceBefore = owner.balance;
        uint256 buyerTokensBefore = token.balanceOf(buyer);
        uint256 ownerTokensBefore = token.balanceOf(owner);

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

    function test_StopStartMarket() public {
        // Setup market
        vm.startPrank(owner);
        uint256 marketId = market.createMarket(
            24 hours, // fulfillWindow
            PLATFORM_FEE,
            DEFAULT_FEE,
            "MOCK URI",
            false // defaultCollateralToBuyer
        );

        market.stopMarket(marketId);
        vm.stopPrank();
        IPremarket.Market memory _market = market.getMarketDetails(marketId);

        // Verify market is stopped
        assertFalse(_market.isActive);

        // Create order parameters
        IPremarket.Order memory order = IPremarket.Order({
            maker: seller,
            marketId: marketId,
            price: 10 ether,
            salt: bytes32(uint256(1))
        });

        vm.expectRevert();
        vm.prank(seller);
        market.createOrder{value: order.price}(order);

        vm.prank(owner);
        market.startMarket(marketId);

        vm.prank(seller);
        market.createOrder{value: order.price}(order);

        (, , , , IPremarket.OrderStatus orderStatus) = market.getOrderByHash(
            market.getOrderHash(order)
        );

        assertEq(uint256(orderStatus), uint256(IPremarket.OrderStatus.Active));
    }

    function test_CancelOrder() public {
        // Setup market
        vm.startPrank(owner);
        uint256 marketId = market.createMarket(
            24 hours, // fulfillWindow
            PLATFORM_FEE,
            DEFAULT_FEE,
            "MOCK URI",
            false // defaultCollateralToBuyer
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

    function test_SetDefaultFeeRate() public {
        // Setup market
        vm.startPrank(owner);
        uint256 marketId = market.createMarket(
            24 hours,
            PLATFORM_FEE,
            DEFAULT_FEE,
            "MOCK URI",
            false
        );

        // Update default fee rate
        uint256 newDefaultFee = 500; // 5%
        market.setDefaultFeeRate(marketId, newDefaultFee);

        // Verify update
        IPremarket.Market memory _market = market.getMarketDetails(marketId);
        assertEq(_market.defaultFeeRate, newDefaultFee);

        vm.stopPrank();
    }

    function test_SetDefaultFeeRate_RevertIfTooHigh() public {
        vm.startPrank(owner);
        uint256 marketId = market.createMarket(
            24 hours,
            PLATFORM_FEE,
            DEFAULT_FEE,
            "MOCK URI",
            false
        );

        // Try to set fee higher than 10%
        vm.expectRevert(IPremarket.InvalidMarketParameters.selector);
        market.setDefaultFeeRate(marketId, 1001);

        vm.stopPrank();
    }

    function test_ClaimDefault_ToOwner() public {
        // Setup market
        vm.startPrank(owner);
        uint256 marketId = market.createMarket(
            24 hours, // fulfillWindow
            PLATFORM_FEE,
            DEFAULT_FEE,
            "MOCK URI",
            false // defaultCollateralToBuyer
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
        vm.stopPrank();

        // Buyer matches order
        vm.prank(buyer);
        market.matchOrder{value: order.price}(order);

        vm.prank(owner);
        market.setMarketDeadline(marketId);

        // Record balances before default
        uint256 buyerBalanceBefore = buyer.balance;
        uint256 ownerBalanceBefore = owner.balance;

        // Fast forward past deadline
        vm.warp(block.timestamp + 25 hours);

        // Buyer claims default
        vm.prank(buyer);
        market.claimDefault(order);

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

    function test_ClaimDefault_ToBuyer() public {
        // Setup market with defaultCollateralToBuyer = true
        vm.startPrank(owner);
        uint256 marketId = market.createMarket(
            24 hours,
            PLATFORM_FEE,
            DEFAULT_FEE,
            "MOCK URI",
            true // defaultCollateralToBuyer
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
        vm.stopPrank();

        // Buyer matches order
        vm.prank(buyer);
        market.matchOrder{value: order.price}(order);

        vm.prank(owner);
        market.setMarketDeadline(marketId);

        // Record balances before default
        uint256 buyerBalanceBefore = buyer.balance;
        uint256 ownerBalanceBefore = owner.balance;

        // Calculate expected amounts
        uint256 defaultFee = (order.price * DEFAULT_FEE) / 10000; // 10% of seller's collateral
        uint256 buyerShare = order.price - defaultFee; // 90% of seller's collateral

        // Fast forward past deadline
        vm.warp(block.timestamp + 25 hours);

        // Buyer claims default
        vm.prank(buyer);
        market.claimDefault(order);

        (, , , , IPremarket.OrderStatus orderStatus) = market.getOrderByHash(
            orderHash
        );

        // Verify order defaulted
        assertEq(
            uint256(orderStatus),
            uint256(IPremarket.OrderStatus.Defaulted)
        );

        // Verify balances:
        // - Buyer gets their payment back + 90% of seller's collateral
        // - Platform gets 10% of seller's collateral
        assertEq(buyer.balance, buyerBalanceBefore + order.price + buyerShare);
        assertEq(owner.balance, ownerBalanceBefore + defaultFee);
    }

    function testRescueAvax() public {
        vm.deal(address(market), 10 ether); // Fund contract with AVAX

        uint256 ownerBalanceBefore = owner.balance;
        uint256 contractBalanceBefore = address(market).balance;
        vm.prank(owner);
        market.rescueAvax();

        uint256 ownerBalanceAfter = owner.balance;
        uint256 contractBalanceAfter = address(market).balance;

        assertEq(ownerBalanceAfter, ownerBalanceBefore + contractBalanceBefore);
        assertEq(contractBalanceAfter, 0);
    }

    function testRescueAvax_RevertIfNotOwner() public {
        vm.prank(seller);
        vm.expectRevert();
        market.rescueAvax();
    }

    function testRescueERC20() public {
        vm.startPrank(owner);
        token.transfer(address(market), 100 ether);

        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 contractBalanceBefore = token.balanceOf(address(market));

        market.rescueERC20(address(token));

        uint256 ownerBalanceAfter = token.balanceOf(owner);
        uint256 contractBalanceAfter = token.balanceOf(address(market));

        assertEq(ownerBalanceAfter, ownerBalanceBefore + contractBalanceBefore);
        assertEq(contractBalanceAfter, 0);
    }

    function testRescueERC20_RevertIfNotOwner() public {
        vm.prank(seller);
        vm.expectRevert();
        market.rescueERC20(address(token));
    }
}
