// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {UnimonRefunds} from "../contracts/v2/UnimonRefunds.sol";

contract DeployRefunds is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");

        vm.startBroadcast(deployerKey);

        UnimonRefunds refunds = new UnimonRefunds();
        console2.log("UnimonRefunds deployed at:", address(refunds));

        vm.stopBroadcast();

        console2.log("\n=== Deployment Summary ===");
        console2.log("UnimonRefunds:", address(refunds));
    }
}
