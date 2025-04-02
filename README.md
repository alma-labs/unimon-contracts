# 🦄 Unimon - The First Game in a V4 Hook!

This is a foundry repository containing the hook & auxillary contracts needed to launch Unimon, a novel game baked into a Uniswap V4 Hook. We utilize OpenZeppelin's BaseHooks & implement our own custom logic where needed.

![Unimon Banner](public/banner.png)

## 🔑 Key Contracts

- `UnimonEnergy.sol` - An illiquid ERC20 Token (UMN) acquired through a v4 LP position, needed to play the game.
- `UnimonHook.sol` - An blended ERC721 & Hook contract, designed to mint ERC721 upon swaps.
- `UnimonBattles.sol` - The core battle logic for "Phase 3: The War".
- `UnimonUserRegistry.sol` - Username list for tracking in the game

## 🚗 Getting Started

1. Run `npm i`.
2. Copy `.env.example` as `.env`.
3. Run `forge install foundry-rs/forge-std`

## 🤝 Helpful Repo Commands

- `forge test` run Foundry tests
- `forge build` compile Foundry contracts
- `npm run deploy:<hook || energy || registry>`

## Deployed Contracts

- [UnimonEnergy](https://uniscan.xyz/address/0xdaabe932b36bbabd9017cc9e03e8633c42fe7a12)
- [UnimonHook](https://uniscan.xyz/address/0x2daf085ad7e6b7b1e3dc7415923e7c1cad5ee8c0)
- [UserRegistry](https://uniscan.xyz/address/0xb11749d5392f1a3ed18f42dd2e438348d9e5c0d4)

## 📝 Important Notes

- Make sure Energy is a GameManager & The Hook has the configured energy contract!
