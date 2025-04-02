import { createPublicClient, createWalletClient, http, parseUnits, encodeAbiParameters, Hex, Address } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { unichain } from "viem/chains";
import { UniversalRouterAbi } from "../abi/UniversalRouterABI";
import { IV4RouterAbiExactInput } from "../abi/v4RouterABI";
import { IV4QuoterAbiExactInput } from "../abi/QuoterABI";

// Change these
const TOKEN_OUT = "0x7edc481366a345d7f9fcecb207408b5f2887ff99";
const HOOK_ADDRESS = "0x7f7d7e4a9d4da8997730997983c5ca64846868c0"; // Test Hook address
const AMOUNT_IN = parseUnits("0.0111", 18); // Current price for 1 NFT

// Don't change these, they are Unichain/Uniswap Variables
const TOKEN_IN = "0x0000000000000000000000000000000000000000"; // ETH on Unichain
const UNIVERSAL_ROUTER = "0xef740bf23acae26f6492b10de645d6b98dc8eaf3"; // Universal Router on Unichain
const V4_QUOTER = "0x333e3c607b141b18ff6de9f258db6e77fe7491e0"; // V4 Quoter on Unichain

// Command types for Universal Router
const URCommands = {
  V4_SWAP: "10",
  SWEEP: "04",
};

// V4 specific action types
const V4Actions = {
  SWAP_EXACT_IN: "07",
  SWAP_EXACT_OUT: "09",
  SETTLE_ALL: "0c",
  TAKE_ALL: "0f",
};

async function main() {
  const publicClient = createPublicClient({
    chain: unichain,
    transport: http(),
  });

  const account = privateKeyToAccount(process.env.DEPLOYER_KEY as `0x${string}`);
  const walletClient = createWalletClient({
    account,
    chain: unichain,
    transport: http(),
  });

  // Min output amount - will be set after getting quote
  let amountOutMin = 0n;

  console.log("Swap details:");
  console.log("- Token IN:", TOKEN_IN, "(USDC)");
  console.log("- Token OUT:", TOKEN_OUT, "(CRAZY)");
  console.log("- Min Amount OUT:", amountOutMin.toString());

  const path = [
    {
      intermediateCurrency: TOKEN_OUT as `0x${string}`, // CRAZY token
      fee: 100, // 0.01% fee as seen in screenshot
      tickSpacing: 1, // From the UI
      hooks: HOOK_ADDRESS as `0x${string}`,
      hookData: "0x" as Hex, // Empty hook data
    },
  ];

  console.log("Pool params:");
  console.log("- Currency A:", TOKEN_IN);
  console.log("- Currency B:", TOKEN_OUT);
  console.log("- Fee:", 100);
  console.log("- TickSpacing:", 1);

  // Simple ExactInput swap parameters - similar to what's in the UI
  // V4 needs to initialize the pool on first swap, so we'll just use a small minimum amount
  const v4ExactInputParams = encodeAbiParameters(IV4RouterAbiExactInput, [
    {
      currencyIn: TOKEN_IN as `0x${string}`,
      path: path,
      amountIn: AMOUNT_IN,
      amountOutMinimum: 1n, // Set to 1 token as minimum, we're willing to accept any output for pool creation
    },
  ]);

  console.log("V4 exact input params encoded");

  // Standard V4Actions sequence for basic swap
  const v4Actions = ("0x" + V4Actions.SWAP_EXACT_IN + V4Actions.SETTLE_ALL + V4Actions.TAKE_ALL) as Hex;

  console.log("V4 actions:", v4Actions);

  // Standard Settle params
  const settleParams = encodeAbiParameters(
    [
      { type: "address", name: "currency" },
      { type: "uint256", name: "maxAmount" },
    ],
    [TOKEN_IN as `0x${string}`, AMOUNT_IN]
  );

  // Standard Take params
  const takeParams = encodeAbiParameters(
    [
      { type: "address", name: "currency" },
      { type: "uint256", name: "minAmount" },
    ],
    [TOKEN_OUT as `0x${string}`, 1n] // Match our min amount
  );

  // Standard V4 router data structure
  const v4RouterData = encodeAbiParameters(
    [
      { type: "bytes", name: "actions" },
      { type: "bytes[]", name: "params" },
    ],
    [v4Actions, [v4ExactInputParams, settleParams, takeParams]]
  );

  console.log("V4 router data encoded");

  // Add SWEEP command like Flaunch
  const urCommands = ("0x" + URCommands.V4_SWAP + URCommands.SWEEP) as Hex;
  const sweepInput = encodeAbiParameters(
    [
      { type: "address", name: "token" },
      { type: "address", name: "recipient" },
      { type: "uint160", name: "amountMin" },
    ],
    [TOKEN_IN as `0x${string}`, account.address, 0n]
  );

  const inputs = [v4RouterData, sweepInput];

  console.log("Universal Router commands:", urCommands);
  console.log("Inputs count:", inputs.length);

  // Use the proper V4 quoter
  console.log("Getting swap estimate from V4 quoter...");
  try {
    const v4QuoterContract = {
      address: V4_QUOTER as Address, // V4 Quoter on Unichain
      abi: IV4QuoterAbiExactInput,
    };

    // Use the exact same path structure as the swap
    const quote = (await publicClient.readContract({
      ...v4QuoterContract,
      functionName: "quoteExactInput",
      args: [
        {
          exactCurrency: TOKEN_IN,
          path: [
            {
              intermediateCurrency: TOKEN_OUT,
              fee: 100,
              tickSpacing: 1,
              hooks: HOOK_ADDRESS,
              hookData: "0x",
            },
          ],
          exactAmount: AMOUNT_IN,
        },
      ],
    })) as readonly [bigint, bigint];

    const [amountOut] = quote;

    console.log("Quote received from V4 quoter:");
    console.log("- Amount out:", amountOut.toString());

    // Set minimum output with 30% slippage
    amountOutMin = (amountOut * 70n) / 100n;
    console.log("- Minimum output (30% slippage):", amountOutMin.toString());

    // Update the params with our new minimum amount
    const updatedExactInputParams = encodeAbiParameters(IV4RouterAbiExactInput, [
      {
        currencyIn: TOKEN_IN as `0x${string}`,
        path: path,
        amountIn: AMOUNT_IN,
        amountOutMinimum: amountOutMin,
      },
    ]);

    // Update the swap params
    const updatedTakeParams = encodeAbiParameters(
      [
        { type: "address", name: "currency" },
        { type: "uint256", name: "minAmount" },
      ],
      [TOKEN_OUT as `0x${string}`, amountOutMin]
    );

    // Update the router data
    const updatedRouterData = encodeAbiParameters(
      [
        { type: "bytes", name: "actions" },
        { type: "bytes[]", name: "params" },
      ],
      [v4Actions, [updatedExactInputParams, settleParams, updatedTakeParams]]
    );

    // Update the inputs
    inputs[0] = updatedRouterData;

    console.log("Updated Universal Router calldata with quote-based minimum amount");
  } catch (error) {
    console.error("Failed to get quote:", error);
    console.log("Proceeding with minimum output set to 1 token");
  }

  // Execute swap - using a standard directly-to-UniversalRouter swap
  console.log("Executing swap...");

  try {
    console.log({
      address: UNIVERSAL_ROUTER,
      abi: UniversalRouterAbi,
      functionName: "execute",
      args: [urCommands, inputs],
      value: AMOUNT_IN,
      gas: 4_000_000n,
    });
    const hash = await walletClient.writeContract({
      address: UNIVERSAL_ROUTER,
      abi: UniversalRouterAbi,
      functionName: "execute",
      args: [urCommands, inputs],
      value: AMOUNT_IN,
      gas: 4_000_000n,
    });

    console.log("Transaction hash:", hash);

    console.log("Waiting for transaction receipt...");
    const receipt = await publicClient.waitForTransactionReceipt({ hash });

    if (receipt.status === "success") {
      console.log("✅ Swap executed successfully!");
    } else if (receipt.status === "reverted") {
      console.log("❌ Transaction reverted!");
      console.log("Gas used:", receipt.gasUsed.toString());
    }

    console.log("Gas used:", receipt.gasUsed.toString());
    console.log("Block number:", receipt.blockNumber);
  } catch (error) {
    console.error("ERROR DURING TRANSACTION:", error);
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error("Error executing swap:", error);
  process.exitCode = 1;
});
