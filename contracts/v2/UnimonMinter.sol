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

    uint256 public constant MINT_PRICE = 0.0111 ether;
    uint256 public constant MAX_MINT_PER_TX = 100;

    // Prize functionality
    mapping(address => uint256) public prizesForAddress;
    mapping(address => bool) public hasClaimed;
    bool public claimsEnabled;

    event Minted(address indexed minter, uint256 amount, uint256 totalCost);
    event MintedWithCoupons(address indexed minter, uint256 amount, uint256 totalCost, uint256 couponsUsed);
    event PrizeClaimed(address indexed claimant, uint256 amount);

    error AlreadyClaimed();
    error NoPrize();
    error InsufficientContractBalance();
    error ClaimsDisabled();

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

    function claimPrize() external nonReentrant {
        if (!claimsEnabled) revert ClaimsDisabled();
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();

        uint256 prizeAmount = prizesForAddress[msg.sender];
        if (prizeAmount == 0) revert NoPrize();
        if (address(this).balance < prizeAmount) revert InsufficientContractBalance();

        hasClaimed[msg.sender] = true;

        (bool success, ) = payable(msg.sender).call{value: prizeAmount}("");
        require(success, "Transfer failed");

        emit PrizeClaimed(msg.sender, prizeAmount);
    }

    /*
        VIEW FUNCTIONS
    */

    function getClaimStatus(address user) external view returns (bool canClaim, uint256 amount, string memory reason) {
        if (!claimsEnabled) {
            return (false, 0, "Claims are disabled");
        }
        if (hasClaimed[user]) {
            return (false, 0, "Already claimed");
        }
        uint256 prizeAmount = prizesForAddress[user];
        if (prizeAmount == 0) {
            return (false, 0, "No prize available");
        }
        if (address(this).balance < prizeAmount) {
            return (false, prizeAmount, "Insufficient contract balance");
        }
        return (true, prizeAmount, "Ready to claim");
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

    function toggleClaims(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        claimsEnabled = enabled;
    }

    function setPrizes(address[] calldata users, uint256[] calldata amounts) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(users.length == amounts.length, "Length mismatch");
        for (uint256 i = 0; i < users.length; i++) {
            prizesForAddress[users[i]] = amounts[i];
        }
    }

    function withdrawPrizePool(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount <= address(this).balance, "Insufficient contract balance");
        require(to != address(0), "Invalid recipient");

        payable(to).transfer(amount);
    }

    receive() external payable {}
}
