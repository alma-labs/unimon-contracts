// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {Hooks} from "../lib/v4-periphery/lib/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "../lib/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "../lib/v4-periphery/src/utils/HookMiner.sol";
import {UnimonHook} from "../contracts/UnimonHook.sol";

contract DeployHook is Script {
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
    IPoolManager constant POOL_MANAGER = IPoolManager(0x1F98400000000000000000000000000000000004);
    address constant OWNER = 0x12D0f29642Ebf73aB1b636222Fd3eB48eB9b4A03;

    function run() public {
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG |
                Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG
        );

        bytes memory constructorArgs = abi.encode(POOL_MANAGER, OWNER);
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(UnimonHook).creationCode,
            constructorArgs
        );

        vm.startBroadcast(vm.envUint("DEPLOYER_KEY"));
        UnimonHook hook = new UnimonHook{salt: salt}(POOL_MANAGER, OWNER);
        require(address(hook) == hookAddress, "DeployUnimonHook: hook address mismatch");
        vm.stopBroadcast();
    }
}
