// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {UnimonBattlesTest as UnimonBattles} from "../contracts/UnimonBattlesTest.sol"; // TODO: Change to UnimonBattles
import {UnimonEnergy} from "../contracts/UnimonEnergy.sol";

contract DeployBattlesTest is Script {
    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_KEY"));

        //address unimonHook = 0x7F7d7E4a9D4DA8997730997983C5Ca64846868C0; // Real Hook
        address unimonHook = 0x32DC0294Ef0Bc29dd76d49D2A3Cdd6B99354d849; // Test Hook
        address unimonEnergy = 0xB75Ef5F073d2D40BF22D0328360a002F458E07d2; // Test UnimonEnergy
        uint256 startTimestamp = 1745935200;

        UnimonBattles battles = new UnimonBattles(unimonHook, unimonEnergy, startTimestamp);

        //Basic Setup
        UnimonEnergy(unimonEnergy).setGameManager(address(battles), true);
        battles.toggleBattles(true);
        battles.killUnhatched(0, 200);

        // Assign randomness roles
        battles.grantRole(battles.RANDOMNESS_ROLE(), 0xa205537dc7096852AF727026dCEAA2087dAAdbfe);
        battles.grantRole(battles.RANDOMNESS_ROLE(), 0xBd9a4B7100d4c7EDB66DB16B24E6bfcddB32e59D);
        battles.grantRole(battles.RANDOMNESS_ROLE(), 0x46c00cA330BDB5F2622E65d2f7770e2583F7B9B5);

        vm.stopBroadcast();
    }
}
