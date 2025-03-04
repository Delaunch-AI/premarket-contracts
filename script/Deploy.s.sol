// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import "../src/Premarket.sol";
import "../src/interfaces/IPremarket.sol";

contract DeployScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Premarket premarket = new Premarket();

        premarket.createMarket(
            10 minutes, // 24 hours
            500, // 5% platform fee
            3000, // 30% default fee
            "https://pyrdmmdqiqerkvwzvkha.supabase.co/storage/v1/object/public/premarket_static/markets/0.json",
            false // defaultCollateralToBuyer
        );

        premarket.createMarket(
            24 hours, // 24 hours
            500, // 5% platform fee
            3000, // 30% default fee
            "https://pyrdmmdqiqerkvwzvkha.supabase.co/storage/v1/object/public/premarket_static/markets/1.json",
            false // defaultCollateralToBuyer
        );

        console.log("Premarket: ", address(premarket));
    }
}
