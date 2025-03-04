// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

contract VerifyScript is Script {
    function run() public pure {
        console.log(
            string.concat(
                "forge verify-contract 0xfcaf1F9952038AD3896CcB29f5ec0e192C098100 src/token/DelaunchTokenV2.sol:DelaunchTokenV2",
                " --etherscan-api-key 11UZMNW8DVI3ZZJZJ8UDS722Y5TYSTX49",
                " --compiler-version 0.8.20",
                " --optimizer",
                " --optimizer-runs 200",
                " --via-ir",
                " --chain avalanche",
                " --watch"
            )
        );
    }
}
