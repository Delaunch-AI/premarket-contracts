// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import "../src/Premarket.sol";

contract DeployScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Premarket premarket = new Premarket();

        uint256[] memory lotSizes = new uint256[](2);
        lotSizes[0] = 0.01 ether;
        lotSizes[1] = 0.02 ether;

        premarket.createMarket(
            lotSizes,
            86400,
            500,
            "https://pyrdmmdqiqerkvwzvkha.supabase.co/storage/v1/object/public/premarket_static/markets/0.json",
            false
        );

        console.log("Premarket: ", address(premarket));
    }
}
