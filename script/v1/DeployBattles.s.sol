// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {UnimonBattles} from "../../contracts/v1/UnimonBattles.sol";
import {UnimonEnergy} from "../../contracts/v1/UnimonEnergy.sol";

contract DeployBattles is Script {
    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_KEY"));

        address unimonHook = 0x7F7d7E4a9D4DA8997730997983C5Ca64846868C0;
        address unimonEnergy = 0x7eDc481366A345D7F9fCEcB207408b5f2887fF99;
        uint256 startTimestamp = 1746576000;

        UnimonBattles battles = new UnimonBattles(unimonHook, unimonEnergy, startTimestamp);

        // Basic Setup
        UnimonEnergy(unimonEnergy).setGameManager(address(battles), true);
        battles.toggleBattles(true);
        // battles.killUnhatched(0, 999);
        // battles.killUnhatched(1000, 1999);
        // battles.killUnhatched(2000, 2999);
        // battles.killUnhatched(3000, 3999);
        // battles.killUnhatched(4000, 5003);

        // Assign randomness roles
        address[] memory randomnessProviders = new address[](10);
        randomnessProviders[0] = 0xa205537dc7096852AF727026dCEAA2087dAAdbfe;
        randomnessProviders[1] = 0xBd9a4B7100d4c7EDB66DB16B24E6bfcddB32e59D;
        randomnessProviders[2] = 0x46c00cA330BDB5F2622E65d2f7770e2583F7B9B5;
        randomnessProviders[3] = 0xf9Ac5Df2702dB617A7Dc9758fe74181E3b201343;
        randomnessProviders[4] = 0x7633de105FB581Be42fa9d35281188c0f5756a1C;
        randomnessProviders[5] = 0x7ef5d74252B52870Fc46e4F5bE31C4c3D2452456;
        randomnessProviders[6] = 0x2aCffD8C6B21735DBB7555ee5b3D9B5c7Ef1851f;
        randomnessProviders[7] = 0xB56fdE7dEb308d3dCCED244D5E53a04257ff4C14;
        randomnessProviders[8] = 0xa98A36F2d2d73e05C10FEb8fDBdEff5215DaE89B;
        randomnessProviders[9] = 0x7a5D1B7B6529cFc59fD11f985233CdC09aA1C9c1;
        battles.bulkGrantRandomness(randomnessProviders);

        vm.stopBroadcast();
    }
}
