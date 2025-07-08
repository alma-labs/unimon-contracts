// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {UnimonV2} from "../contracts/v2/UnimonV2.sol";
import {UnimonItems} from "../contracts/v2/UnimonItems.sol";
import {UnimonMinter} from "../contracts/v2/UnimonMinter.sol";
import {UnimonGacha} from "../contracts/v2/UnimonGacha.sol";

contract DeployV2 is Script {
    function run() public {
        address deployer = vm.addr(vm.envUint("DEPLOYER_KEY"));
        vm.startBroadcast(vm.envUint("DEPLOYER_KEY"));

        // 1. Deploy UnimonItems (ERC1155)
        UnimonItems items = new UnimonItems(deployer);

        // 2. Deploy UnimonV2 (ERC721 NFTs)
        UnimonV2 nfts = new UnimonV2(address(items));

        // 3. Deploy UnimonMinter
        UnimonMinter minter = new UnimonMinter(address(nfts), address(items), deployer);

        // 4. Set up permissions
        // Give minter permission to mint NFTs
        nfts.grantRole(nfts.MINTER_ROLE(), address(minter));

        // Give minter permission to mint items (energy, keys)
        items.grantMinterRole(address(minter));

        // Give minter permission to spend items (coupons)
        items.grantSpenderRole(address(minter));

        // Give NFT contract permission to spend items (for evolution)
        items.grantSpenderRole(address(nfts));

        vm.stopBroadcast();

        // Log deployed addresses
        console.log("UnimonItems deployed at:", address(items));
        console.log("UnimonV2 deployed at:", address(nfts));
        console.log("UnimonMinter deployed at:", address(minter));
    }
}
