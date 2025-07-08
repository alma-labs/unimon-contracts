// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./UnimonV2.sol";
import "./UnimonItems.sol";

contract UnimonMinter is AccessControl, ReentrancyGuard {
    UnimonV2 public immutable unimonNFT;
    UnimonItems public immutable unimonItems;
    uint256 public totalMinted;

    uint256 public constant MINT_PRICE = 0.0000111 ether;
    uint256 public constant MAX_MINT_PER_TX = 100;

    event Minted(address indexed minter, uint256 amount, uint256 totalCost);
    event MintedWithCoupons(address indexed minter, uint256 amount, uint256 totalCost, uint256 couponsUsed);

    constructor(address _unimonNFT, address _unimonItems, address _admin) {
        unimonNFT = UnimonV2(_unimonNFT);
        unimonItems = UnimonItems(_unimonItems);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /*
        USER WRITE FUNCTIONS
    */

    function mint(uint256 amount) external payable nonReentrant {
        require(amount > 0 && amount <= MAX_MINT_PER_TX, "Invalid mint amount");

        uint256 totalCost = amount * MINT_PRICE;
        require(msg.value >= totalCost, "Insufficient ETH");

        _processMint(msg.sender, amount);

        emit Minted(msg.sender, amount, totalCost);
    }

    function mintWithCoupons(uint256 amount) external payable nonReentrant {
        require(amount > 0 && amount <= MAX_MINT_PER_TX, "Invalid mint amount");

        uint256 couponBalance = unimonItems.balanceOf(msg.sender, unimonItems.MINT_COUPON_ID());
        require(couponBalance >= amount, "Insufficient coupons");

        uint256 totalCost = (amount * MINT_PRICE) / 2;
        require(msg.value >= totalCost, "Insufficient ETH");

        unimonItems.spendItem(msg.sender, unimonItems.MINT_COUPON_ID(), amount);

        _processMint(msg.sender, amount);

        emit MintedWithCoupons(msg.sender, amount, totalCost, amount);
    }

    /*
        INTERNAL FUNCTIONS
    */

    function _processMint(address to, uint256 amount) internal {
        totalMinted += amount;

        for (uint256 i = 0; i < amount; i++) {
            unimonNFT.safeMint(to);
        }

        uint256[] memory itemIds = new uint256[](2);
        uint256[] memory itemAmounts = new uint256[](2);

        itemIds[0] = unimonItems.ENERGY_ID(); // Energy
        itemIds[1] = unimonItems.UNIKEY_ID(); // Gacha key

        itemAmounts[0] = amount * 4; // 4 energy per Unimon
        itemAmounts[1] = amount * 1; // 1 gacha key per Unimon

        unimonItems.mintBatch(to, itemIds, itemAmounts);
    }

    /*
        ADMIN FUNCTIONS
    */

    function withdrawPrizePool(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount <= address(this).balance, "Insufficient contract balance");
        require(to != address(0), "Invalid recipient");

        payable(to).transfer(amount);
    }

    receive() external payable {}
}
