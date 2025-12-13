import fs from "fs";
import path from "path";
import { createWalletClient, http, parseAbi, createPublicClient } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { unichain } from "viem/chains";
import * as dotenv from "dotenv";

dotenv.config();

interface RefundEntry {
  amount: number;
  totalCost: string;
  cost: number;
  minter: string;
}

const REFUNDS_CONTRACT = "0x51b71c4791f1abe267308d49f27a897f851e6354";

const ABI = parseAbi([
  "function setRefunds(address[] calldata users, uint256[] calldata amounts) external",
  "function owner() external view returns (address)",
]);

async function setRefunds() {
  try {
    // Check for --execute flag
    const EXECUTE = process.argv.includes("--execute");
    
    if (!EXECUTE) {
      console.log("🔍 DRY RUN MODE - No transactions will be sent");
      console.log("   Add --execute flag to actually send transactions\n");
    } else {
      console.log("⚠️  EXECUTE MODE - Transactions will be sent!\n");
    }

    // Load refunds.json
    const refundsPath = path.join(__dirname, "..", "refunds.json");
    const refundsData: RefundEntry[] = JSON.parse(fs.readFileSync(refundsPath, "utf8"));

    console.log(`📄 Loaded ${refundsData.length} refund entries`);

    // Aggregate by address
    const refundsByAddress = new Map<string, bigint>();
    
    for (const entry of refundsData) {
      const address = entry.minter.toLowerCase();
      const amount = BigInt(entry.totalCost);
      
      const current = refundsByAddress.get(address) || 0n;
      refundsByAddress.set(address, current + amount);
    }

    console.log(`\n💰 Aggregated refunds for ${refundsByAddress.size} unique addresses`);

    // Convert to arrays
    const addresses: `0x${string}`[] = [];
    const amounts: bigint[] = [];
    let totalRefundAmount = 0n;

    for (const [address, amount] of refundsByAddress.entries()) {
      addresses.push(address as `0x${string}`);
      amounts.push(amount);
      totalRefundAmount += amount;
    }

    console.log(`\n📊 Total refund amount: ${totalRefundAmount} wei (${Number(totalRefundAmount) / 1e18} ETH)`);
    
    // Show sample of data
    console.log(`\n📋 Sample of aggregated data (first 10):`);
    for (let i = 0; i < Math.min(10, addresses.length); i++) {
      console.log(`   ${addresses[i]}: ${amounts[i]} wei (${Number(amounts[i]) / 1e18} ETH)`);
    }
    if (addresses.length > 10) {
      console.log(`   ... and ${addresses.length - 10} more addresses`);
    }

    if (!EXECUTE) {
      console.log(`\n✅ Dry run complete - no transactions sent`);
      console.log(`   Run with --execute to send transactions`);
      return;
    }

    // Setup wallet client
    if (!process.env.DEPLOYER_KEY) {
      throw new Error("DEPLOYER_KEY not found in .env");
    }

    const account = privateKeyToAccount(`0x${process.env.DEPLOYER_KEY}` as `0x${string}`);
    
    const publicClient = createPublicClient({
      chain: unichain,
      transport: http("https://mainnet.unichain.org"),
    });

    const walletClient = createWalletClient({
      account,
      chain: unichain,
      transport: http("https://mainnet.unichain.org"),
    });

    console.log(`\n🔑 Using account: ${account.address}`);

    // Verify owner
    const owner = await publicClient.readContract({
      address: REFUNDS_CONTRACT,
      abi: ABI,
      functionName: "owner",
    });

    console.log(`👤 Contract owner: ${owner}`);

    if (owner.toLowerCase() !== account.address.toLowerCase()) {
      throw new Error("Account is not the contract owner!");
    }

    // Batch size (to avoid gas limits)
    const BATCH_SIZE = 100;
    const batches = Math.ceil(addresses.length / BATCH_SIZE);

    console.log(`\n📦 Splitting into ${batches} batches of up to ${BATCH_SIZE} addresses each`);

    for (let i = 0; i < batches; i++) {
      const start = i * BATCH_SIZE;
      const end = Math.min(start + BATCH_SIZE, addresses.length);
      const batchAddresses = addresses.slice(start, end);
      const batchAmounts = amounts.slice(start, end);

      console.log(`\n🚀 Processing batch ${i + 1}/${batches} (${batchAddresses.length} addresses)...`);

      const { request } = await publicClient.simulateContract({
        account,
        address: REFUNDS_CONTRACT,
        abi: ABI,
        functionName: "setRefunds",
        args: [batchAddresses, batchAmounts],
      });

      const hash = await walletClient.writeContract(request);
      console.log(`📝 Transaction hash: ${hash}`);

      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      console.log(`✅ Batch ${i + 1} confirmed in block ${receipt.blockNumber}`);
    }

    console.log(`\n✨ All refunds set successfully!`);
    console.log(`📈 Summary:`);
    console.log(`   - Total addresses: ${addresses.length}`);
    console.log(`   - Total amount: ${Number(totalRefundAmount) / 1e18} ETH`);
    console.log(`   - Batches processed: ${batches}`);

  } catch (error) {
    console.error("❌ Error setting refunds:", error);
    process.exit(1);
  }
}

setRefunds();
