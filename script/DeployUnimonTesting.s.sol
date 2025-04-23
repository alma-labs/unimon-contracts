// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {UnimonTesting} from "../contracts/UnimonTesting.sol";

contract DeployUnimonTesting is Script {
    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_KEY"));
        new UnimonTesting(msg.sender);
        vm.stopBroadcast();
    }
}
