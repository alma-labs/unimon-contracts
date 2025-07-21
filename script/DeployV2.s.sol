// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {UnimonV2} from "../contracts/v2/UnimonV2.sol";
import {UnimonItems} from "../contracts/v2/UnimonItems.sol";
import {UnimonMinter} from "../contracts/v2/UnimonMinter.sol";
import {UnimonGachaSimple} from "../contracts/v2/UnimonGachaSimple.sol";
import {UnimonEquipment} from "../contracts/v2/UnimonEquipment.sol";

contract DeployV2 is Script {
    // Updated gacha configuration for equipment items 9-26 and consumable items 31-34
    uint256[] public GACHA_ITEM_IDS = [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 31, 32, 33, 34];
    uint256[] public GACHA_WEIGHTS = [1000, 1000, 1000, 500, 500, 500, 50, 50, 50, 100, 100, 100, 250, 100, 1000, 500, 100, 1000, 100, 50, 100, 1750];
    
    uint256[] public MAX_SUPPLY_ITEM_IDS = [3, 4, 5, 6, 7, 8];
    uint256[] public MAX_SUPPLIES = [69, 11, 11, 11, 11, 3];

    function run() public {
        address deployer = vm.addr(vm.envUint("DEPLOYER_KEY"));
        vm.startBroadcast(vm.envUint("DEPLOYER_KEY"));

        // 1. Deploy UnimonItems (ERC1155)
        UnimonItems items = new UnimonItems(deployer);

        // 2. Deploy UnimonV2 (ERC721 NFTs)
        UnimonV2 nfts = new UnimonV2(address(items));

        // 3. Deploy UnimonMinter
        UnimonMinter minter = new UnimonMinter(address(nfts), address(items), deployer);

        // 4. Deploy UnimonGachaSimple
        UnimonGachaSimple gacha = new UnimonGachaSimple(address(items));

        // 5. Deploy UnimonEquipment
        UnimonEquipment equipment = new UnimonEquipment(address(nfts), address(items));

        // 6. Set up permissions
        // Give minter permission to mint NFTs
        nfts.grantRole(nfts.MINTER_ROLE(), address(minter));

        // Give minter permission to mint items (energy, keys)
        items.grantMinterRole(address(minter));

        // Give minter permission to spend items (coupons)
        items.grantSpenderRole(address(minter));

        // Give NFT contract permission to spend items (for evolution)
        items.grantSpenderRole(address(nfts));

        // Give gacha permission to mint items (rewards)
        items.grantMinterRole(address(gacha));

        // Give gacha permission to spend items (keys)
        items.grantSpenderRole(address(gacha));

        // Grant equipment role for seamless transfers
        items.grantRole(items.EQUIPMENT_ROLE(), address(equipment));

        // 7. Configure gacha with item IDs and weights
        gacha.updateGacha(GACHA_ITEM_IDS, GACHA_WEIGHTS);

        // 8. Configure max supplies for items
        gacha.setMaxSupply(MAX_SUPPLY_ITEM_IDS, MAX_SUPPLIES);

        // 9. Configure equipment items with their attack, defense, and probability impacts
        uint256[] memory equipmentIds = new uint256[](22);
        int256[] memory attackMods = new int256[](22);
        int256[] memory defenseMods = new int256[](22);
        int256[] memory overallMods = new int256[](22);
        
        // Equipment configuration based on provided data
        equipmentIds[0] = 9;   attackMods[0] = 1;   defenseMods[0] = 0;   overallMods[0] = 0;     // Swapium Short Sword
        equipmentIds[1] = 10;  attackMods[1] = 0;   defenseMods[1] = 1;   overallMods[1] = 0;     // Swapium Buckler
        equipmentIds[2] = 11;  attackMods[2] = 1;   defenseMods[2] = 1;   overallMods[2] = 0;     // Swapium Helm
        equipmentIds[3] = 12;  attackMods[3] = 2;   defenseMods[3] = 0;   overallMods[3] = 0;     // L2 Longsword
        equipmentIds[4] = 13;  attackMods[4] = 0;   defenseMods[4] = 2;   overallMods[4] = 0;     // L2 Shield
        equipmentIds[5] = 14;  attackMods[5] = 1;   defenseMods[5] = 2;   overallMods[5] = 0;     // L2 Medium Helm
        equipmentIds[6] = 15;  attackMods[6] = 3;   defenseMods[6] = -1;  overallMods[6] = 0;     // Uni Scimmy
        equipmentIds[7] = 16;  attackMods[7] = -1;  defenseMods[7] = 3;   overallMods[7] = 0;     // Uni Godshield
        equipmentIds[8] = 17;  attackMods[8] = 1;   defenseMods[8] = 3;   overallMods[8] = 0;     // Uni Full Helm
        equipmentIds[9] = 18;  attackMods[9] = 5;   defenseMods[9] = 0;   overallMods[9] = -10;   // Leveraged Blade
        equipmentIds[10] = 19; attackMods[10] = 0;  defenseMods[10] = 5;  overallMods[10] = -10;  // Leveraged Defender
        equipmentIds[11] = 20; attackMods[11] = 3;  defenseMods[11] = 3;  overallMods[11] = -10;  // Leveraged Guard
        equipmentIds[12] = 21; attackMods[12] = 1;  defenseMods[12] = 1;  overallMods[12] = 0;    // Catex Ears
        equipmentIds[13] = 22; attackMods[13] = 1;  defenseMods[13] = 2;  overallMods[13] = -5;   // Trimmed Rune Helmet
        equipmentIds[14] = 23; attackMods[14] = 0;  defenseMods[14] = 1;  overallMods[14] = 0;    // Straw Hat
        equipmentIds[15] = 24; attackMods[15] = 1;  defenseMods[15] = 1;  overallMods[15] = 3;    // Mog Glasses
        equipmentIds[16] = 25; attackMods[16] = 0;  defenseMods[16] = 0;  overallMods[16] = -100; // Permenant Loss
        equipmentIds[17] = 26; attackMods[17] = 0;  defenseMods[17] = 1;  overallMods[17] = 0;    // Uni Saddle
        
        // Consumable items configured as equipables
        equipmentIds[18] = 31; attackMods[18] = 1;  defenseMods[18] = 1;  overallMods[18] = 11;   // Green Candle
        equipmentIds[19] = 32; attackMods[19] = 2;  defenseMods[19] = 2;  overallMods[19] = 22;   // Uni Energy Drink
        equipmentIds[20] = 33; attackMods[20] = 0;  defenseMods[20] = 0;  overallMods[20] = -5;   // Broken Horn
        equipmentIds[21] = 34; attackMods[21] = 0;  defenseMods[21] = 0;  overallMods[21] = 1;    // Common Horn
        
        equipment.configureBulkEquipment(equipmentIds, attackMods, defenseMods, overallMods);

        vm.stopBroadcast();

        // Log deployed addresses
        console.log("UnimonItems deployed at:", address(items));
        console.log("UnimonV2 deployed at:", address(nfts));
        console.log("UnimonMinter deployed at:", address(minter));
        console.log("UnimonGachaSimple deployed at:", address(gacha));
        console.log("UnimonEquipment deployed at:", address(equipment));
        console.log("Gacha configured with", GACHA_ITEM_IDS.length, "equipment and consumable items");
        console.log("Max supplies configured for", MAX_SUPPLY_ITEM_IDS.length, "non-equipment items");
        console.log("Equipment configured with 22 items (IDs 9-26, 31-34)");
    }
}
