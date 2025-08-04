// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {UnimonV2} from "../contracts/v2/UnimonV2.sol";
import {UnimonItems} from "../contracts/v2/UnimonItems.sol";
import {UnimonMinter} from "../contracts/v2/UnimonMinter.sol";
import {UnimonGacha} from "../contracts/v2/UnimonGacha.sol";
import {UnimonEquipment} from "../contracts/v2/UnimonEquipment.sol";
import {UnimonGeneralStore} from "../contracts/v2/UnimonGeneralStore.sol";

contract DeployV2 is Script {
    uint256[] public GACHA_ITEM_IDS = [
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
        17,
        18,
        19,
        20,
        21,
        22,
        23,
        24,
        25,
        26,
        27,
        28,
        29,
        30,
        31,
        32,
        33,
        34,
        35,
        36,
        37,
        38,
        39,
        40,
        41,
        42,
        43,
        44,
        45,
        46,
        47,
        48,
        49,
        50,
        51,
        52,
        53,
        54,
        55,
        56,
        57,
        58
    ];
    uint256[] public GACHA_WEIGHTS = [
        50,
        20,
        20,
        20,
        10,
        5,
        500,
        500,
        400,
        300,
        300,
        250,
        50,
        50,
        40,
        100,
        100,
        100,
        25,
        100,
        300,
        300,
        100,
        300,
        300,
        100,
        300,
        30,
        100,
        50,
        100,
        500,
        300,
        100,
        75,
        25,
        10,
        5,
        100,
        100,
        4,
        10,
        50,
        50,
        3,
        100,
        500,
        500,
        250,
        250,
        250,
        250,
        50,
        25,
        25,
        50
    ];

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

        // 4. Deploy UnimonGacha
        UnimonGacha gacha = new UnimonGacha(address(items));

        // 5. Deploy UnimonEquipment
        UnimonEquipment equipment = new UnimonEquipment(address(nfts), address(items));

        // 6. Deploy UnimonGeneralStore
        UnimonGeneralStore generalStore = new UnimonGeneralStore(address(items));

        // 7. Set up permissions
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

        // Give general store permission to spend items (for redemptions)
        items.grantSpenderRole(address(generalStore));

        // Grant RANDOMNESS_HANDLER role to randomness suppliers
        gacha.grantRole(gacha.RANDOMNESS_HANDLER(), 0xa205537dc7096852AF727026dCEAA2087dAAdbfe);
        gacha.grantRole(gacha.RANDOMNESS_HANDLER(), 0xBd9a4B7100d4c7EDB66DB16B24E6bfcddB32e59D);
        gacha.grantRole(gacha.RANDOMNESS_HANDLER(), 0x46c00cA330BDB5F2622E65d2f7770e2583F7B9B5);
        gacha.grantRole(gacha.RANDOMNESS_HANDLER(), 0xf9Ac5Df2702dB617A7Dc9758fe74181E3b201343);
        gacha.grantRole(gacha.RANDOMNESS_HANDLER(), 0x7633de105FB581Be42fa9d35281188c0f5756a1C);

        // 8. Configure gacha with item IDs and weights
        gacha.updateGacha(GACHA_ITEM_IDS, GACHA_WEIGHTS);

        // 9. Configure max supplies for items
        gacha.setMaxSupply(MAX_SUPPLY_ITEM_IDS, MAX_SUPPLIES);

        // 10. Configure equipment items and consumables with their attack, defense, and probability impacts
        // Equipment configuration (includes both equipable items and consumables)
        uint256[] memory equipmentIds = new uint256[](50);
        int256[] memory attackMods = new int256[](50);
        int256[] memory defenseMods = new int256[](50);
        int256[] memory overallMods = new int256[](50);
        bool[] memory isConsumables = new bool[](50);

        equipmentIds[0] = 9;
        attackMods[0] = 1;
        defenseMods[0] = 0;
        overallMods[0] = 0;
        isConsumables[0] = false; // Swapium Short Sword (equipable)
        equipmentIds[1] = 10;
        attackMods[1] = 0;
        defenseMods[1] = 1;
        overallMods[1] = 0;
        isConsumables[1] = false; // Swapium Buckler (equipable)
        equipmentIds[2] = 11;
        attackMods[2] = 1;
        defenseMods[2] = 1;
        overallMods[2] = 0;
        isConsumables[2] = false; // Swapium Helm (equipable)
        equipmentIds[3] = 12;
        attackMods[3] = 2;
        defenseMods[3] = 0;
        overallMods[3] = 0;
        isConsumables[3] = false; // L2 Longsword (equipable)
        equipmentIds[4] = 13;
        attackMods[4] = 0;
        defenseMods[4] = 2;
        overallMods[4] = 0;
        isConsumables[4] = false; // L2 Shield (equipable)
        equipmentIds[5] = 14;
        attackMods[5] = 1;
        defenseMods[5] = 2;
        overallMods[5] = 0;
        isConsumables[5] = false; // L2 Medium Helm (equipable)
        equipmentIds[6] = 15;
        attackMods[6] = 3;
        defenseMods[6] = -1;
        overallMods[6] = 0;
        isConsumables[6] = false; // Uni Scimmy (equipable)
        equipmentIds[7] = 16;
        attackMods[7] = -1;
        defenseMods[7] = 3;
        overallMods[7] = 0;
        isConsumables[7] = false; // Uni Godshield (equipable)
        equipmentIds[8] = 17;
        attackMods[8] = 1;
        defenseMods[8] = 3;
        overallMods[8] = 0;
        isConsumables[8] = false; // Uni Full Helm (equipable)
        equipmentIds[9] = 18;
        attackMods[9] = 5;
        defenseMods[9] = 0;
        overallMods[9] = -10;
        isConsumables[9] = false; // Leveraged Blade (equipable)
        equipmentIds[10] = 19;
        attackMods[10] = 0;
        defenseMods[10] = 5;
        overallMods[10] = -10;
        isConsumables[10] = false; // Leveraged Defender (equipable)
        equipmentIds[11] = 20;
        attackMods[11] = 3;
        defenseMods[11] = 3;
        overallMods[11] = -10;
        isConsumables[11] = false; // Leveraged Guard (equipable)
        equipmentIds[12] = 21;
        attackMods[12] = 1;
        defenseMods[12] = 1;
        overallMods[12] = 0;
        isConsumables[12] = false; // Catex Ears (equipable)
        equipmentIds[13] = 22;
        attackMods[13] = 1;
        defenseMods[13] = 2;
        overallMods[13] = -5;
        isConsumables[13] = false; // Trimmed Rune Helmet (equipable)
        equipmentIds[14] = 23;
        attackMods[14] = 0;
        defenseMods[14] = 1;
        overallMods[14] = 0;
        isConsumables[14] = false; // Straw Hat (equipable)
        equipmentIds[15] = 24;
        attackMods[15] = 1;
        defenseMods[15] = 1;
        overallMods[15] = 3;
        isConsumables[15] = false; // Mog Glasses (equipable)
        equipmentIds[16] = 25;
        attackMods[16] = 0;
        defenseMods[16] = 0;
        overallMods[16] = -100;
        isConsumables[16] = false; // Permenant Loss (equipable)
        equipmentIds[17] = 26;
        attackMods[17] = 0;
        defenseMods[17] = 1;
        overallMods[17] = 0;
        isConsumables[17] = false; // Uni Saddle (equipable)
        equipmentIds[18] = 27;
        attackMods[18] = 1;
        defenseMods[18] = 0;
        overallMods[18] = 1;
        isConsumables[18] = false; // Fedora (equipable)
        equipmentIds[19] = 28;
        attackMods[19] = 0;
        defenseMods[19] = 2;
        overallMods[19] = 5;
        isConsumables[19] = false; // Pink Chain (equipable)
        equipmentIds[20] = 29;
        attackMods[20] = 0;
        defenseMods[20] = 0;
        overallMods[20] = 3;
        isConsumables[20] = false; // Horse Head (equipable)
        equipmentIds[21] = 30;
        attackMods[21] = 2;
        defenseMods[21] = 2;
        overallMods[21] = 2;
        isConsumables[21] = false; // Unicloak (equipable)
        equipmentIds[22] = 31;
        attackMods[22] = 1;
        defenseMods[22] = 1;
        overallMods[22] = 11;
        isConsumables[22] = true; // Green Candle (consumable)
        equipmentIds[23] = 32;
        attackMods[23] = 2;
        defenseMods[23] = 2;
        overallMods[23] = 22;
        isConsumables[23] = true; // Uni Energy Drink (consumable)
        equipmentIds[24] = 33;
        attackMods[24] = 0;
        defenseMods[24] = 0;
        overallMods[24] = -5;
        isConsumables[24] = true; // Broken Horn (consumable)
        equipmentIds[25] = 34;
        attackMods[25] = 0;
        defenseMods[25] = 0;
        overallMods[25] = 1;
        isConsumables[25] = true; // Common Horn (consumable)
        equipmentIds[26] = 35;
        attackMods[26] = 0;
        defenseMods[26] = 0;
        overallMods[26] = 5;
        isConsumables[26] = true; // Uncommon Horn (consumable)
        equipmentIds[27] = 36;
        attackMods[27] = 0;
        defenseMods[27] = 0;
        overallMods[27] = 10;
        isConsumables[27] = true; // Epic Horn (consumable)
        equipmentIds[28] = 37;
        attackMods[28] = 0;
        defenseMods[28] = 0;
        overallMods[28] = 15;
        isConsumables[28] = true; // Mythic Horn (consumable)
        equipmentIds[29] = 38;
        attackMods[29] = 0;
        defenseMods[29] = 0;
        overallMods[29] = 20;
        isConsumables[29] = true; // Divine Horn (consumable)
        equipmentIds[30] = 39;
        attackMods[30] = 0;
        defenseMods[30] = 0;
        overallMods[30] = 25;
        isConsumables[30] = true; // Ultimate Horn (consumable)
        equipmentIds[31] = 40;
        attackMods[31] = 0;
        defenseMods[31] = 0;
        overallMods[31] = 50;
        isConsumables[31] = true; // Ginny Horn (consumable)
        equipmentIds[32] = 41;
        attackMods[32] = 0;
        defenseMods[32] = 0;
        overallMods[32] = -5;
        isConsumables[32] = true; // Broken Horseshoe (consumable)
        equipmentIds[33] = 42;
        attackMods[33] = 0;
        defenseMods[33] = 0;
        overallMods[33] = 11;
        isConsumables[33] = true; // Lucky Horseshoe (consumable)
        equipmentIds[34] = 43;
        attackMods[34] = 0;
        defenseMods[34] = 0;
        overallMods[34] = 44;
        isConsumables[34] = true; // Uni v4 Hook (consumable)
        equipmentIds[35] = 44;
        attackMods[35] = 0;
        defenseMods[35] = 0;
        overallMods[35] = 33;
        isConsumables[35] = true; // Rainbow Horseshoe (consumable)
        equipmentIds[36] = 45;
        attackMods[36] = 4;
        defenseMods[36] = 0;
        overallMods[36] = -25;
        isConsumables[36] = true; // Strange Pink Powder (consumable)
        equipmentIds[37] = 46;
        attackMods[37] = 0;
        defenseMods[37] = 4;
        overallMods[37] = -25;
        isConsumables[37] = true; // Unicorn Tranquilizer (consumable)
        equipmentIds[38] = 47;
        attackMods[38] = 10;
        defenseMods[38] = 10;
        overallMods[38] = 100;
        isConsumables[38] = true; // Cerulean City Cig (consumable)
        equipmentIds[39] = 48;
        attackMods[39] = 3;
        defenseMods[39] = 3;
        overallMods[39] = 3;
        isConsumables[39] = true; // Unicig (consumable)
        equipmentIds[40] = 49;
        attackMods[40] = 1;
        defenseMods[40] = 1;
        overallMods[40] = 1;
        isConsumables[40] = true; // Uninana (consumable)
        equipmentIds[41] = 50;
        attackMods[41] = 2;
        defenseMods[41] = 2;
        overallMods[41] = 2;
        isConsumables[41] = true; // Uniberry (consumable)
        equipmentIds[42] = 51;
        attackMods[42] = 1;
        defenseMods[42] = 1;
        overallMods[42] = 10;
        isConsumables[42] = true; // Uniswap Growth Potion (consumable)
        equipmentIds[43] = 52;
        attackMods[43] = 1;
        defenseMods[43] = 0;
        overallMods[43] = 10;
        isConsumables[43] = true; // Uniswap Labs Elixir (consumable)
        equipmentIds[44] = 53;
        attackMods[44] = 0;
        defenseMods[44] = 1;
        overallMods[44] = 10;
        isConsumables[44] = true; // Uni Foundation Flask (consumable)
        equipmentIds[45] = 54;
        attackMods[45] = 1;
        defenseMods[45] = 1;
        overallMods[45] = 5;
        isConsumables[45] = true; // UNI Delegate Brew (consumable)
        equipmentIds[46] = 55;
        attackMods[46] = -4;
        defenseMods[46] = -4;
        overallMods[46] = 69;
        isConsumables[46] = true; // Pink Pill (consumable)
        equipmentIds[47] = 56;
        attackMods[47] = 5;
        defenseMods[47] = -5;
        overallMods[47] = 0;
        isConsumables[47] = true; // Liquidity Potion (consumable)
        equipmentIds[48] = 57;
        attackMods[48] = -5;
        defenseMods[48] = 5;
        overallMods[48] = 0;
        isConsumables[48] = true; // Hayden Adams' Glasses (consumable)
        equipmentIds[49] = 58;
        attackMods[49] = 10;
        defenseMods[49] = 10;
        overallMods[49] = -100;
        isConsumables[49] = true; // Honeypot (consumable)

        // Call the bulk configuration function
        equipment.configureBulkEquipment(equipmentIds, attackMods, defenseMods, overallMods, isConsumables);

        vm.stopBroadcast();

        // Log deployed addresses
        console.log("UnimonItems deployed at:", address(items));
        console.log("UnimonV2 deployed at:", address(nfts));
        console.log("UnimonMinter deployed at:", address(minter));
        console.log("UnimonGacha deployed at:", address(gacha));
        console.log("UnimonEquipment deployed at:", address(equipment));
        console.log("UnimonGeneralStore deployed at:", address(generalStore));
        console.log("Gacha configured with", GACHA_ITEM_IDS.length, "equipment and consumable items");
        console.log("Max supplies configured for", MAX_SUPPLY_ITEM_IDS.length, "non-equipment items");
        console.log("General store configured with spender role for item redemptions");
    }
}
