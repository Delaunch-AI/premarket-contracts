// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import "../src/Premarket.sol";
import "../src/interfaces/IPremarket.sol";

//     event TokenDetailsSet(
//         uint256 indexed marketId,
//         uint256 tokenAmount,
//         address tokenAddress
//     );
//     event MarketStarted(uint256 indexed marketId);
//     event MarketStopped(uint256 indexed marketId);
//     event MarketDeadlineSet(uint256 indexed marketId, uint256 deadline);
//     event MarketCreated(uint256 indexed marketId);
//     event OrderCreated(bytes32 indexed orderHash, uint256 indexed marketId);
//     event OrderMatched(bytes32 indexed orderHash, address indexed taker);
//     event OrderFulfilled(bytes32 indexed orderHash);
//     event OrderCancelled(bytes32 indexed orderHash);
//     event OrderDefaulted(bytes32 indexed orderHash);
//     event DefaultCollateralSettingUpdated(
//         uint256 indexed marketId,
//         bool defaultCollateralToBuyer
//     );
//     event DefaultFeeRateUpdated(
//         uint256 indexed marketId,
//         uint256 defaultFeeRate
//     );

contract OpsScript is Script {
    uint256 marketId = 5;
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        IPremarket premarket = IPremarket(
            0x9BaD54CAD50Da7059AaF8Bd8B00c3f20594d7841
        );

        // premarket.createMarket(
        //     10 minutes, // 24 hours
        //     500, // 5% platform fee
        //     3000, // 30% default fee
        //     "https://pyrdmmdqiqerkvwzvkha.supabase.co/storage/v1/object/public/premarket_static/markets/2.json",
        //     false // defaultCollateralToBuyer
        // );

        // premarket.createMarket(
        //     86400, // 24 hours
        //     500, // 5% platform fee
        //     3000, // 30% default fee
        //     "https://pyrdmmdqiqerkvwzvkha.supabase.co/storage/v1/object/public/premarket_static/markets/1.json",
        //     false // defaultCollateralToBuyer
        // );

        premarket.stopMarket(marketId);

        // premarket.overrideMarketTokenDetails(
        //     marketId,
        //     0x5Ae5f0b8cbCf6F1f3fD942B748e1b6E7b107F0ea,
        //     110 ether
        // );

        premarket.setMarketTokenDetails(
            marketId,
            110 ether,
            0x5Ae5f0b8cbCf6F1f3fD942B748e1b6E7b107F0ea
        );
        premarket.setMarketDeadline(marketId);

        // premarket.stopMarket(marketId);
        // premarket.startMarket(marketId);
    }
}
