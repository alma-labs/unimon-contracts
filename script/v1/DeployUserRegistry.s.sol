// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {UnimonUserRegistry} from "../../contracts/v1/UnimonUserRegistry.sol";

contract DeployUserRegistry is Script {
    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_KEY"));
        new UnimonUserRegistry();
        vm.stopBroadcast();
    }
}
