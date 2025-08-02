// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

/**
 * @title UnimonItems
 * @author Unimon Team
 * @notice ERC1155 token contract for Unimon game items including energy, keys, and mint coupons
 * @dev This contract manages all fungible items in the Unimon ecosystem
 *
 * Key features:
 * - ERC1155 multi-token standard for efficient item management
 * - Role-based access control for minting and spending
 * - Supply tracking for all tokens
 * - Airdrop functionality for v1 users
 * - Equipment transfer whitelisting
 *
 * @custom:security This contract uses OpenZeppelin's AccessControl, ERC1155Burnable, and ERC1155Supply
 */
contract UnimonItems is ERC1155, AccessControl, ERC1155Burnable, ERC1155Supply {
    /// @notice Role for entities that can mint new items
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Role for entities that can spend/burn items from users
    bytes32 public constant SPENDER_ROLE = keccak256("SPENDER_ROLE");

    /// @notice Role for equipment contracts that can transfer items
    bytes32 public constant EQUIPMENT_ROLE = keccak256("EQUIPMENT_ROLE");

    /// @notice Token ID for energy items (used for evolution)
    uint256 public constant ENERGY_ID = 0;

    /// @notice Token ID for UNIKEY items (used for gacha pulls)
    uint256 public constant UNIKEY_ID = 1;

    /// @notice Token ID for mint coupons (reduces mint cost by 50%)
    uint256 public constant MINT_COUPON_ID = 2;

    /// @notice Whether the v1 airdrop has been executed
    bool public airdropExecuted;

    /// @notice Emitted when items are minted
    /// @param to Address receiving the items
    /// @param id Token ID of the minted item
    /// @param amount Amount minted
    event ItemMinted(address indexed to, uint256 indexed id, uint256 amount);

    /// @notice Emitted when items are burned/spent
    /// @param from Address losing the items
    /// @param id Token ID of the burned item
    /// @param amount Amount burned
    event ItemBurned(address indexed from, uint256 indexed id, uint256 amount);

    /**
     * @notice Constructor for UnimonItems contract
     * @param _admin Address that will receive admin and minter roles
     */
    constructor(address _admin) ERC1155("https://v2.unimon.app/items/{id}") {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MINTER_ROLE, _admin);
        _grantRole(SPENDER_ROLE, _admin);
    }

    /*
        VIEW FUNCTIONS
    */

    /**
     * @notice Get balances for multiple token IDs for a specific account
     * @param account Address to check balances for
     * @param ids Array of token IDs to check
     * @return Array of balances corresponding to the token IDs
     */
    function getBalances(address account, uint256[] memory ids) external view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            balances[i] = balanceOf(account, ids[i]);
        }
        return balances;
    }

    /*
        PERMISSIONED FUNCTIONS
    */

    /**
     * @notice Mint a single item to an address
     * @param to Address to mint to
     * @param id Token ID to mint
     * @param amount Amount to mint
     * @dev Only callable by MINTER_ROLE
     */
    function mint(address to, uint256 id, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, id, amount, "");
        emit ItemMinted(to, id, amount);
    }

    /**
     * @notice Mint multiple items to an address in a single transaction
     * @param to Address to mint to
     * @param ids Array of token IDs to mint
     * @param amounts Array of amounts to mint for each token ID
     * @dev Only callable by MINTER_ROLE
     * @dev Arrays must have the same length
     */
    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts) external onlyRole(MINTER_ROLE) {
        _mintBatch(to, ids, amounts, "");

        for (uint256 i = 0; i < ids.length; i++) {
            emit ItemMinted(to, ids[i], amounts[i]);
        }
    }

    /**
     * @notice Spend/burn a single item from an address
     * @param from Address to burn from
     * @param id Token ID to burn
     * @param amount Amount to burn
     * @dev Only callable by SPENDER_ROLE
     */
    function spendItem(address from, uint256 id, uint256 amount) external onlyRole(SPENDER_ROLE) {
        _burn(from, id, amount);
        emit ItemBurned(from, id, amount);
    }

    /**
     * @notice Burn/spend multiple items from an address
     * @param from Address to burn from
     * @param ids Array of token IDs to burn
     * @param amounts Array of amounts to burn for each token ID
     * @dev Only callable by SPENDER_ROLE
     * @dev Arrays must have the same length
     */
    function spendItemBatch(
        address from,
        uint256[] memory ids,
        uint256[] memory amounts
    ) external onlyRole(SPENDER_ROLE) {
        _burnBatch(from, ids, amounts);

        for (uint256 i = 0; i < ids.length; i++) {
            emit ItemBurned(from, ids[i], amounts[i]);
        }
    }

    /*
        ADMIN FUNCTIONS
    */

    /**
     * @notice Admin transfer of a single item between addresses
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param id Token ID to transfer
     * @param amount Amount to transfer
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function adminTransfer(address from, address to, uint256 id, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _safeTransferFrom(from, to, id, amount, "");
    }

    /**
     * @notice Admin transfer of multiple items between addresses
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param ids Array of token IDs to transfer
     * @param amounts Array of amounts to transfer for each token ID
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     * @dev Arrays must have the same length
     */
    function adminTransferBatch(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _safeBatchTransferFrom(from, to, ids, amounts, "");
    }

    /**
     * @notice Bulk airdrop function for v1 users - mints unikeys and mint coupons to multiple addresses
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts (both unikeys and coupons) for each recipient
     * @dev Only callable by MINTER_ROLE
     * @dev Can only be executed once
     * @dev Arrays must have the same length
     */
    function v1Airdrop(address[] memory recipients, uint256[] memory amounts) external onlyRole(MINTER_ROLE) {
        require(!airdropExecuted, "Airdrop already executed");
        require(recipients.length == amounts.length, "Arrays length mismatch");

        airdropExecuted = true;

        for (uint256 i = 0; i < recipients.length; i++) {
            if (amounts[i] > 0) {
                // Mint unikeys
                _mint(recipients[i], UNIKEY_ID, amounts[i], "");
                emit ItemMinted(recipients[i], UNIKEY_ID, amounts[i]);

                // Mint coupons
                _mint(recipients[i], MINT_COUPON_ID, amounts[i], "");
                emit ItemMinted(recipients[i], MINT_COUPON_ID, amounts[i]);
            }
        }
    }

    /**
     * @notice Set the base URI for token metadata
     * @param newuri New base URI
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function setURI(string memory newuri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newuri);
    }

    /**
     * @notice Grant minter role to an address
     * @param minter Address to grant minter role to
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function grantMinterRole(address minter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINTER_ROLE, minter);
    }

    /**
     * @notice Grant spender role to an address
     * @param spender Address to grant spender role to
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function grantSpenderRole(address spender) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(SPENDER_ROLE, spender);
    }

    /**
     * @notice Whitelisted transfer of a single item (for equipment contracts)
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param id Token ID to transfer
     * @param amount Amount to transfer
     * @dev Only callable by EQUIPMENT_ROLE
     */
    function whitelistTransfer(address from, address to, uint256 id, uint256 amount) external onlyRole(EQUIPMENT_ROLE) {
        _safeTransferFrom(from, to, id, amount, "");
    }

    /**
     * @notice Whitelisted transfer of multiple items (for equipment contracts)
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param ids Array of token IDs to transfer
     * @param amounts Array of amounts to transfer for each token ID
     * @dev Only callable by EQUIPMENT_ROLE
     * @dev Arrays must have the same length
     */
    function whitelistBatchTransfer(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts
    ) external onlyRole(EQUIPMENT_ROLE) {
        _safeBatchTransferFrom(from, to, ids, amounts, "");
    }

    /*
        Overrides
    */

    /**
     * @dev Override to track supply changes
     */
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155, ERC1155Supply) {
        super._update(from, to, ids, values);
    }

    /**
     * @dev Override to support both ERC1155 and AccessControl interfaces
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
