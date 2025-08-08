// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {GM} from "../contracts/v2/GM.sol";
import {UnimonSlayer} from "../contracts/v2/UnimonSlayer.sol";

contract DeployGMAndSlayer is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        // Hardcoded addresses provided by user
        address unimonV2 = 0x8161169579cfC3C6AaE09E182EB06CeFcD2F68C7;
        address unimonEquipment = 0x44afb9e951718FC7d9344cAdE16f5a6781E96190;

        vm.startBroadcast(deployerKey);

        GM gm = new GM(unimonV2);
        // Example: set to 1 hour (already default), keep here for clarity
        gm.setPeriodSeconds(1 hours);
        console2.log("GM deployed at:", address(gm));

        UnimonSlayer slayer = new UnimonSlayer(unimonEquipment);
        console2.log("UnimonSlayer deployed at:", address(slayer));

        vm.stopBroadcast();

        console2.log("\n=== Deployment Summary ===");
        console2.log("GM:", address(gm));
        console2.log("UnimonSlayer:", address(slayer));
        console2.log("UNIMON_V2:", unimonV2);
        console2.log("UNIMON_EQUIPMENT:", unimonEquipment);
    }
}


