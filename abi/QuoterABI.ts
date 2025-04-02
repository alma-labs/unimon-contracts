export const IV4QuoterAbiExactInput = [
  {
    inputs: [
      {
        components: [
          { name: "exactCurrency", type: "address" },
          {
            components: [
              { name: "intermediateCurrency", type: "address" },
              { name: "fee", type: "uint24" },
              { name: "tickSpacing", type: "int24" },
              { name: "hooks", type: "address" },
              { name: "hookData", type: "bytes" },
            ],
            name: "path",
            type: "tuple[]",
          },
          { name: "exactAmount", type: "uint128" },
        ],
        name: "params",
        type: "tuple",
      },
    ],
    name: "quoteExactInput",
    outputs: [
      { name: "amountOut", type: "uint256" },
      { name: "gasEstimate", type: "uint256" },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;
