// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title UnimonEnergy
 * @notice ERC20 token used as energy currency in the Unimon game
 * @dev Extends ERC20 and ERC20Burnable with game manager functionality
 */
contract TestEnergy is ERC20, ERC20Burnable, Ownable {
    /// @notice Mapping of addresses to game manager status
    mapping(address => bool) public gameManagers;

    /**
     * @notice Constructor for UnimonEnergy
     * @dev Sets the contract deployer as the owner and mints initial supply
     */
    constructor() ERC20("Test Energy", "TE") Ownable(msg.sender) {
        _mint(msg.sender, 42069 * 10 ** decimals());
    }

    /**
     * @notice Set or update the game manager status of an address
     * @param manager The address to set as game manager
     * @param status The new status to set
     * @dev Only callable by contract owner
     */
    function setGameManager(address manager, bool status) external onlyOwner {
        gameManagers[manager] = status;
    }

    /**
     * @notice Burn tokens from a specified address
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     * @dev Only callable by game managers
     */
    function burn(address from, uint256 amount) external {
        require(gameManagers[msg.sender], "Not a game manager");
        _burn(from, amount);
    }
}
