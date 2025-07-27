// Simple Node.js script to simulate evolution results
// Run with: node test_evolution.js

function calculateEvolutionStats(energyAmount, tokenId) {
    // Simulate the Solidity logic
    const seed = Math.floor(Math.random() * 2**32);
    const hash = seed;
    
    // Choose total stats between energyAmount and 2x energy amount
    const minStats = energyAmount;
    const maxStats = energyAmount * 2;
    let totalStats = minStats + (hash % (maxStats - minStats + 1));
    
    // Cap totalStats at 18 (max possible with 9+9)
    if (totalStats > 18) {
        totalStats = 18;
    }
    
    // Randomly distribute between attack and defense
    const attackSeed = Math.floor(Math.random() * 2**32);
    let attackBonus = attackSeed % (totalStats + 1); // 0 to totalStats
    let defenseBonus = totalStats - attackBonus;
    
    // Cap each skill at 9 bonus (since base is 1, total will be 10)
    // Redistribute excess to ensure no stats are lost
    if (attackBonus > 9) {
        const excess = attackBonus - 9;
        attackBonus = 9;
        defenseBonus = defenseBonus + excess;
    }
    if (defenseBonus > 9) {
        const excess = defenseBonus - 9;
        defenseBonus = 9;
        attackBonus = attackBonus + excess > 9 ? 9 : attackBonus + excess;
    }
    
    return { attackBonus, defenseBonus, totalStats };
}

console.log("=== Evolution Distribution Simulation ===\n");

for (let energy = 1; energy <= 10; energy++) {
    console.log(`Energy Amount: ${energy}`);
    console.log("Results:");
    
    for (let i = 0; i < 5; i++) {
        const result = calculateEvolutionStats(energy, i);
        const finalAttack = 1 + result.attackBonus; // Base 1 + bonus
        const finalDefense = 1 + result.defenseBonus; // Base 1 + bonus
        const totalGain = result.attackBonus + result.defenseBonus;
        
        console.log(`  ${i+1}. Attack: ${finalAttack}, Defense: ${finalDefense}, Total Gain: ${totalGain}, Total Stats: ${result.totalStats}`);
    }
    console.log("");
}