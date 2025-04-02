// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {UnimonEnergy} from "../contracts/UnimonEnergy.sol";

contract DeployEnergy is Script {
    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_KEY"));
        new UnimonEnergy();
        vm.stopBroadcast();
    }
}
