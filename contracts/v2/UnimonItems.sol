// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

contract UnimonItems is ERC1155, AccessControl, ERC1155Burnable, ERC1155Supply {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant SPENDER_ROLE = keccak256("SPENDER_ROLE");
    bytes32 public constant EQUIPMENT_ROLE = keccak256("EQUIPMENT_ROLE");

    uint256 public constant ENERGY_ID = 0;
    uint256 public constant UNIKEY_ID = 1;
    uint256 public constant MINT_COUPON_ID = 2;

    event ItemMinted(address indexed to, uint256 indexed id, uint256 amount);
    event ItemBurned(address indexed from, uint256 indexed id, uint256 amount);

    constructor(address _admin) ERC1155("https://v2.unimon.app/items/{id}") {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MINTER_ROLE, _admin);
        _grantRole(SPENDER_ROLE, _admin);
    }

    /*
        VIEW FUNCTIONS
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

    function mint(address to, uint256 id, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, id, amount, "");
        emit ItemMinted(to, id, amount);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts) external onlyRole(MINTER_ROLE) {
        _mintBatch(to, ids, amounts, "");

        for (uint256 i = 0; i < ids.length; i++) {
            emit ItemMinted(to, ids[i], amounts[i]);
        }
    }

    function spendItem(address from, uint256 id, uint256 amount) external onlyRole(SPENDER_ROLE) {
        _burn(from, id, amount);
        emit ItemBurned(from, id, amount);
    }

    /**
     * @dev Burn/spend multiple items (used by other contracts)
     * @param from Address to burn from
     * @param ids Array of item IDs
     * @param amounts Array of amounts to burn
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

    function adminTransfer(address from, address to, uint256 id, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _safeTransferFrom(from, to, id, amount, "");
    }

    function adminTransferBatch(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _safeBatchTransferFrom(from, to, ids, amounts, "");
    }

    function airdropMintCoupons(address[] memory recipients, uint256[] memory amounts) external onlyRole(MINTER_ROLE) {
        require(recipients.length == amounts.length, "Arrays length mismatch");

        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], MINT_COUPON_ID, amounts[i], "");
            emit ItemMinted(recipients[i], MINT_COUPON_ID, amounts[i]);
        }
    }

    function setURI(string memory newuri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newuri);
    }

    function grantMinterRole(address minter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINTER_ROLE, minter);
    }

    function grantSpenderRole(address spender) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(SPENDER_ROLE, spender);
    }

    function whitelistTransfer(address from, address to, uint256 id, uint256 amount) external onlyRole(EQUIPMENT_ROLE) {
        _safeTransferFrom(from, to, id, amount, "");
    }

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

    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155, ERC1155Supply) {
        super._update(from, to, ids, values);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
