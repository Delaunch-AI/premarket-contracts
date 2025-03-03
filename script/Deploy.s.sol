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

        IPremarket.Lot[] memory lots = new IPremarket.Lot[](3);
        lots[0] = IPremarket.Lot("Small", 0.01 ether);
        lots[1] = IPremarket.Lot("Medium", 0.03 ether);
        lots[2] = IPremarket.Lot("Large", 0.05 ether);

        premarket.createMarket(
            lots,
            86400,
            500,
            "https://pyrdmmdqiqerkvwzvkha.supabase.co/storage/v1/object/public/premarket_static/markets/0.json",
            false
        );

        console.log("Premarket: ", address(premarket));
    }
}
