// Using built-in fetch (Node.js 18+)
import fs from "fs";
import path from "path";

interface Item {
  id: number;
  name: string;
  weight: number;
  itemType: string;
  maxSupply: number;
  attackImpact?: number;
  defenseImpact?: number;
  probabilityImpact?: number;
  equipable: boolean;
  consumable: boolean;
}

async function generateDeployConfig() {
  try {
    console.log("Fetching items from API...");
    const response = await fetch("https://v2.unimon.app/items/all");
    const items: Item[] = await response.json();

    let output = "";
    output += `// Generated on ${new Date().toISOString()}\n`;
    output += `// Total items found: ${items.length}\n\n`;

    // Generate gacha configuration (items with weight > 0)
    const gachaItems = items.filter((item) => item.weight > 0);
    const gachaIds = gachaItems.map((item) => item.id);
    const gachaWeights = gachaItems.map((item) => item.weight);

    output += "=== GACHA CONFIGURATION ===\n";
    output += `Found ${gachaItems.length} items for gacha:\n`;
    gachaItems.forEach((item) => {
      output += `  ID ${item.id}: ${item.name} (weight: ${item.weight})\n`;
    });

    output += "\n// Gacha configuration\n";
    output += `uint256[] public GACHA_ITEM_IDS = [${gachaIds.join(", ")}];\n`;
    output += `uint256[] public GACHA_WEIGHTS = [${gachaWeights.join(", ")}];\n`;

    // Generate max supply configuration (items with maxSupply > 0)
    const maxSupplyItems = items.filter((item) => item.maxSupply > 0);
    const maxSupplyIds = maxSupplyItems.map((item) => item.id);
    const maxSupplies = maxSupplyItems.map((item) => item.maxSupply);

    output += "\n=== MAX SUPPLY CONFIGURATION ===\n";
    output += `Found ${maxSupplyItems.length} items with max supply:\n`;
    maxSupplyItems.forEach((item) => {
      output += `  ID ${item.id}: ${item.name} (max: ${item.maxSupply})\n`;
    });

    output += "\n// Max supply configuration\n";
    output += `uint256[] public MAX_SUPPLY_ITEM_IDS = [${maxSupplyIds.join(", ")}];\n`;
    output += `uint256[] public MAX_SUPPLIES = [${maxSupplies.join(", ")}];\n`;

    // Generate equipment configuration (equipable items + consumables with impacts)
    const equipableItems = items.filter(
      (item) =>
        item.equipable &&
        (item.attackImpact !== undefined || item.defenseImpact !== undefined || item.probabilityImpact !== undefined)
    );

    const consumableAsEquipable = items.filter(
      (item) =>
        item.consumable &&
        !item.equipable &&
        (item.attackImpact !== undefined || item.defenseImpact !== undefined || item.probabilityImpact !== undefined)
    );

    // Combine both equipable items and consumables
    const allEquipment = [...equipableItems, ...consumableAsEquipable];

    const equipmentIds = allEquipment.map((item) => item.id);
    const attackMods = allEquipment.map((item) => item.attackImpact || 0);
    const defenseMods = allEquipment.map((item) => item.defenseImpact || 0);
    const overallMods = allEquipment.map((item) => item.probabilityImpact || 0);
    const isConsumables = allEquipment.map((item) => item.consumable && !item.equipable);

    output += "\n=== EQUIPMENT CONFIGURATION (EQUIPABLE + CONSUMABLES) ===\n";
    output += `Found ${equipableItems.length} equipable items + ${consumableAsEquipable.length} consumables = ${allEquipment.length} total:\n`;
    
    output += "\nEquipable items:\n";
    equipableItems.forEach((item) => {
      output += `  ID ${item.id}: ${item.name} (+${item.attackImpact || 0} atk, +${item.defenseImpact || 0} def, +${
        item.probabilityImpact || 0
      }% prob)\n`;
    });

    output += "\nConsumable items (configured as equipable):\n";
    consumableAsEquipable.forEach((item) => {
      output += `  ID ${item.id}: ${item.name} (+${item.attackImpact || 0} atk, +${item.defenseImpact || 0} def, +${
        item.probabilityImpact || 0
      }% prob)\n`;
    });

    output += "\n// Equipment configuration (includes both equipable items and consumables)\n";
    output += `uint256[] memory equipmentIds = new uint256[](${allEquipment.length});\n`;
    output += `int256[] memory attackMods = new int256[](${allEquipment.length});\n`;
    output += `int256[] memory defenseMods = new int256[](${allEquipment.length});\n`;
    output += `int256[] memory overallMods = new int256[](${allEquipment.length});\n`;
    output += `bool[] memory isConsumables = new bool[](${allEquipment.length});\n`;
    output += "\n";
    output += "// Equipment configuration based on API data\n";

    allEquipment.forEach((item, index) => {
      const comment = `// ${item.name} (${item.equipable ? 'equipable' : 'consumable'})`;
      output += `equipmentIds[${index}] = ${item.id};   attackMods[${index}] = ${
        item.attackImpact || 0
      };   defenseMods[${index}] = ${item.defenseImpact || 0};   overallMods[${index}] = ${
        item.probabilityImpact || 0
      };   isConsumables[${index}] = ${item.consumable && !item.equipable};     ${comment}\n`;
    });

    output += "\n// Call the bulk configuration function\n";
    output += `equipment.configureBulkEquipment(equipmentIds, attackMods, defenseMods, overallMods, isConsumables);\n`;

    output += "\n=== SUMMARY ===\n";
    output += `Total items: ${items.length}\n`;
    output += `Gacha items: ${gachaItems.length}\n`;
    output += `Max supply items: ${maxSupplyItems.length}\n`;
    output += `Equipable items: ${equipableItems.length}\n`;
    output += `Consumable items: ${consumableAsEquipable.length}\n`;
    output += `Total equipment configured: ${allEquipment.length}\n`;

    // Write to file
    const outputPath = path.join(__dirname, "deploy-config-output.txt");
    fs.writeFileSync(outputPath, output, "utf8");
    console.log(`✅ Configuration generated and saved to: ${outputPath}`);
    console.log(
      `📊 Summary: ${items.length} total items | ${gachaItems.length} gacha | ${allEquipment.length} total equipment (${equipableItems.length} equipable + ${consumableAsEquipable.length} consumables)`
    );
  } catch (error) {
    console.error("Error fetching or processing items:", error);
  }
}

// Run the script
generateDeployConfig();
