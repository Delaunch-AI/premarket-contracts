// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import "../src/Premarket.sol";
import "../src/interfaces/IPremarket.sol";

contract DeployScript is Script {
    address public constant feeReceiver = 0x00;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Premarket premarket = new Premarket();

        premarket.setFeeReceiver(feeReceiver);

        console.log("Premarket: ", address(premarket));
    }
}
