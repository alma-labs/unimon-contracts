// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./UnimonV2.sol";
import "./UnimonItems.sol";

/**
 * @title UnimonMinter
 * @author Unimon Team
 * @notice Contract for minting UnimonV2 NFTs and managing prize distributions
 * @dev This contract handles the primary minting functionality for Unimon NFTs
 *
 * Key features:
 * - ETH-based minting with configurable price
 * - Mint coupon support (50% discount)
 * - Automatic item distribution (energy + gacha keys)
 * - Prize claiming system
 * - Bulk minting with supply limits
 * - Global mint toggle functionality
 *
 * @custom:security This contract uses OpenZeppelin's AccessControl and ReentrancyGuard
 */
contract UnimonMinter is AccessControl, ReentrancyGuard {
    /// @notice Reference to the UnimonV2 NFT contract
    UnimonV2 public immutable unimonNFT;

    /// @notice Reference to the UnimonItems contract
    UnimonItems public immutable unimonItems;

    /// @notice Total number of NFTs minted through this contract
    uint256 public totalMinted;

    /// @notice Price per NFT mint in ETH (0.0111 ETH)
    uint256 public constant MINT_PRICE = 0.0111 ether;

    /// @notice Maximum number of NFTs that can be minted per transaction
    uint256 public constant MAX_MINT_PER_TX = 100;

    /// @notice Whether minting is globally enabled
    bool public mintingEnabled = true;

    // Prize functionality
    /// @notice Mapping of addresses to their prize amounts
    mapping(address => uint256) public prizesForAddress;

    /// @notice Mapping of addresses to whether they have claimed their prize
    mapping(address => bool) public hasClaimed;

    /// @notice Whether prize claims are currently enabled
    bool public claimsEnabled;

    /// @notice Emitted when NFTs are minted with ETH
    /// @param minter Address of the minter
    /// @param amount Number of NFTs minted
    /// @param totalCost Total ETH cost
    event Minted(address indexed minter, uint256 amount, uint256 totalCost);

    /// @notice Emitted when NFTs are minted with coupons
    /// @param minter Address of the minter
    /// @param amount Number of NFTs minted
    /// @param totalCost Total ETH cost (reduced by coupons)
    /// @param couponsUsed Number of coupons used
    event MintedWithCoupons(address indexed minter, uint256 amount, uint256 totalCost, uint256 couponsUsed);

    /// @notice Emitted when a prize is claimed
    /// @param claimant Address of the prize claimant
    /// @param amount Amount of ETH claimed
    event PrizeClaimed(address indexed claimant, uint256 amount);

    /// @notice Emitted when minting is toggled
    /// @param enabled Whether minting is now enabled or disabled
    event MintingToggled(bool enabled);

    /// @notice Error thrown when trying to claim a prize that was already claimed
    error AlreadyClaimed();

    /// @notice Error thrown when trying to claim but no prize is available
    error NoPrize();

    /// @notice Error thrown when contract has insufficient balance for prize payout
    error InsufficientContractBalance();

    /// @notice Error thrown when prize claims are disabled
    error ClaimsDisabled();

    /// @notice Error thrown when minting is disabled
    error MintingDisabled();

    /**
     * @notice Constructor for UnimonMinter contract
     * @param _unimonNFT Address of the UnimonV2 NFT contract
     * @param _unimonItems Address of the UnimonItems contract
     * @param _admin Address that will receive admin role
     */
    constructor(address _unimonNFT, address _unimonItems, address _admin) {
        unimonNFT = UnimonV2(_unimonNFT);
        unimonItems = UnimonItems(_unimonItems);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /*
        USER WRITE FUNCTIONS
    */

    /**
     * @notice Mint Unimon NFTs with ETH
     * @param amount Number of NFTs to mint (1 to MAX_MINT_PER_TX)
     * @dev This function:
     * - Validates the mint amount
     * - Calculates total cost based on MINT_PRICE
     * - Mints NFTs and distributes items (energy + gacha keys)
     * - Emits Minted event
     */
    function mint(uint256 amount) external payable nonReentrant {
        if (!mintingEnabled) revert MintingDisabled();
        require(amount > 0 && amount <= MAX_MINT_PER_TX, "Invalid mint amount");

        uint256 totalCost = amount * MINT_PRICE;
        require(msg.value >= totalCost, "Insufficient ETH");

        _processMint(msg.sender, amount);

        emit Minted(msg.sender, amount, totalCost);
    }

    /**
     * @notice Mint Unimon NFTs with ETH and mint coupons (50% discount)
     * @param amount Number of NFTs to mint (1 to MAX_MINT_PER_TX)
     * @dev This function:
     * - Validates the mint amount and coupon balance
     * - Calculates discounted cost (50% off)
     * - Spends mint coupons
     * - Mints NFTs and distributes items
     * - Emits MintedWithCoupons event
     */
    function mintWithCoupons(uint256 amount) external payable nonReentrant {
        if (!mintingEnabled) revert MintingDisabled();
        require(amount > 0 && amount <= MAX_MINT_PER_TX, "Invalid mint amount");

        uint256 couponBalance = unimonItems.balanceOf(msg.sender, unimonItems.MINT_COUPON_ID());
        require(couponBalance >= amount, "Insufficient coupons");

        uint256 totalCost = (amount * MINT_PRICE) / 2;
        require(msg.value >= totalCost, "Insufficient ETH");

        unimonItems.spendItem(msg.sender, unimonItems.MINT_COUPON_ID(), amount);

        _processMint(msg.sender, amount);

        emit MintedWithCoupons(msg.sender, amount, totalCost, amount);
    }

    /**
     * @notice Claim ETH prize if available
     * @dev This function:
     * - Checks if claims are enabled
     * - Verifies user hasn't already claimed
     * - Validates prize amount and contract balance
     * - Transfers ETH to claimant
     * - Marks user as claimed
     * - Emits PrizeClaimed event
     */
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

    /**
     * @notice Get the claim status for a user
     * @param user Address to check claim status for
     * @return canClaim Whether the user can claim a prize
     * @return amount Amount of prize available
     * @return reason Reason why user cannot claim (if applicable)
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

    /**
     * @notice Internal function to process minting and item distribution
     * @param to Address to mint NFTs to
     * @param amount Number of NFTs to mint
     * @dev This function:
     * - Increments total minted counter
     * - Mints NFTs via UnimonV2 contract
     * - Distributes energy (4 per NFT) and gacha keys (1 per NFT)
     */
    function _processMint(address to, uint256 amount) internal {
        totalMinted += amount;

        for (uint256 i = 0; i < amount; i++) {
            unimonNFT.safeMint(to);
        }

        uint256[] memory itemIds = new uint256[](2);
        uint256[] memory itemAmounts = new uint256[](2);

        itemIds[0] = unimonItems.ENERGY_ID();
        itemIds[1] = unimonItems.UNIKEY_ID();

        itemAmounts[0] = amount * 4;
        itemAmounts[1] = amount * 1;

        unimonItems.mintBatch(to, itemIds, itemAmounts);
    }

    /*
        ADMIN FUNCTIONS
    */

    /**
     * @notice Toggle whether minting is globally enabled
     * @param enabled Whether to enable or disable minting
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function toggleMinting(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        mintingEnabled = enabled;
        emit MintingToggled(enabled);
    }

    /**
     * @notice Toggle whether prize claims are enabled
     * @param enabled Whether to enable or disable claims
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function toggleClaims(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        claimsEnabled = enabled;
    }

    /**
     * @notice Set prize amounts for multiple addresses
     * @param users Array of user addresses
     * @param amounts Array of prize amounts for each user
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     * @dev Arrays must have the same length
     */
    function setPrizes(address[] calldata users, uint256[] calldata amounts) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(users.length == amounts.length, "Length mismatch");
        for (uint256 i = 0; i < users.length; i++) {
            prizesForAddress[users[i]] = amounts[i];
        }
    }

    /**
     * @notice Withdraw ETH from the prize pool
     * @param to Address to withdraw to
     * @param amount Amount of ETH to withdraw
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function withdrawPrizePool(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount <= address(this).balance, "Insufficient contract balance");
        require(to != address(0), "Invalid recipient");

        payable(to).transfer(amount);
    }

    /**
     * @notice Receive function to accept ETH
     * @dev Allows the contract to receive ETH for prize pool
     */
    receive() external payable {}
}
