// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {UnimonBattlesV2} from "../contracts/v2/UnimonBattlesV2.sol";
import {UnimonV2} from "../contracts/v2/UnimonV2.sol";
import {UnimonEquipment} from "../contracts/v2/UnimonEquipment.sol";
import {UnimonItems} from "../contracts/v2/UnimonItems.sol";

contract DeployBattlesV2 is Script {
    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_KEY"));

        /*
        // DUMMY CONTRACTS
            UnimonItems deployed at: 0xC15C026418Dd0D419E51D7B8ABA1FC136A99a28a
            UnimonV2 deployed at: 0xD292945e0Aa30346A416c583d9Fd2616C712Ee4d
            UnimonMinter deployed at: 0xB010C345B0B99eDB84ad2d4E500D6E2329aE163a
            UnimonGacha deployed at: 0xFBcDa1915bbD51B586Ad669f6764165119914475
            UnimonEquipment deployed at: 0xC24b527301Eb836202dEBfe9E73Ea04e60766083
        */

        /*
        // ACTUAL CONTRACTS
            UnimonItems deployed at: 0x94b7A1768C4aFE63652Da69A2fF8425C49bB09f9
            UnimonV2 deployed at: 0x8161169579cfC3C6AaE09E182EB06CeFcD2F68C7
            UnimonMinter deployed at: 0x47dB8d81C68327C473eEF8067385FBb57b943193
            UnimonGacha deployed at: 0xC582b698D1EedD604BB0792b4611c3C3C15b35f2
            UnimonEquipment deployed at: 0x44afb9e951718FC7d9344cAdE16f5a6781E96190
            UnimonGeneralStore deployed at: 0xac03737f308a53bc9E1DdB78A25DC3c0A1d8995D
        */

        // DUMMY ADDRESSES FOR NOW
        address unimonV2Address = 0xD292945e0Aa30346A416c583d9Fd2616C712Ee4d;
        address unimonEquipmentAddress = 0xC24b527301Eb836202dEBfe9E73Ea04e60766083;
        address unimonItemsAddress = 0xC15C026418Dd0D419E51D7B8ABA1FC136A99a28a;

        // Start timestamp - set to future date
        uint256 startTimestamp = block.timestamp + 3 hours; // 3 hours from now

        // Deploy UnimonBattlesV2
        UnimonBattlesV2 battles = new UnimonBattlesV2(
            unimonV2Address,
            unimonEquipmentAddress,
            unimonItemsAddress,
            startTimestamp
        );

        console2.log("UnimonBattlesV2 deployed at:", address(battles));

        // Get contract instances for granting roles
        UnimonItems unimonItems = UnimonItems(unimonItemsAddress);
        UnimonEquipment unimonEquipment = UnimonEquipment(unimonEquipmentAddress);

        // Grant necessary roles to battles contract
        // SPENDER_ROLE on UnimonItems (needed for spending energy during revives)
        unimonItems.grantSpenderRole(address(battles));
        console2.log("Granted SPENDER_ROLE to battles contract on UnimonItems");

        // EQUIPMENT_MANAGER_ROLE on UnimonEquipment (needed for consuming equipment after battles)
        unimonEquipment.grantRole(unimonEquipment.EQUIPMENT_MANAGER_ROLE(), address(battles));
        console2.log("Granted EQUIPMENT_MANAGER_ROLE to battles contract on UnimonEquipment");

        // SPENDER_ROLE on UnimonItems for UnimonEquipment (needed for burning consumable equipment)
        unimonItems.grantSpenderRole(address(unimonEquipment));
        console2.log("Granted SPENDER_ROLE to equipment contract on UnimonItems");

        // Enable battles
        battles.toggleBattles(true);
        console2.log("Battles enabled");

        // Assign randomness roles - using temporary addresses
        address[] memory randomnessProviders = new address[](10);
        randomnessProviders[0] = 0xa205537dc7096852AF727026dCEAA2087dAAdbfe;
        randomnessProviders[1] = 0xBd9a4B7100d4c7EDB66DB16B24E6bfcddB32e59D;
        randomnessProviders[2] = 0x46c00cA330BDB5F2622E65d2f7770e2583F7B9B5;
        randomnessProviders[3] = 0xf9Ac5Df2702dB617A7Dc9758fe74181E3b201343;
        randomnessProviders[4] = 0x7633de105FB581Be42fa9d35281188c0f5756a1C;

        battles.bulkGrantRandomness(randomnessProviders);
        console2.log("Granted RANDOMNESS_ROLE to", randomnessProviders.length, "addresses");

        vm.stopBroadcast();

        console2.log("\n=== Deployment Summary ===");
        console2.log("UnimonBattlesV2:", address(battles));
        console2.log("Start Timestamp:", startTimestamp);
        console2.log("Battles Enabled:", true);
        console2.log("Randomness Providers:", randomnessProviders.length);
    }
}
