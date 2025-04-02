// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title UnimonUserRegistry
 * @notice Human readable username registry for Unimon
 * @dev This contract manages the mapping between Unichain addresses and usernames for Unimon
 */
contract UnimonUserRegistry is Ownable {
    /// @notice Maximum length allowed for usernames
    uint8 public constant MAX_USERNAME_LENGTH = 14;

    /// @notice Mapping of addresses to usernames
    mapping(address => string) private addressToUsername;
    /// @notice Mapping of usernames to addresses
    mapping(string => address) private usernameToAddress;

    /// @notice Event emitted when a username is set or updated
    event UsernameSet(address indexed user, string username);

    /**
     * @notice Constructor for UnimonUserRegistry
     * @dev Sets the contract deployer as the owner
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @notice Get the username associated with a given address
     * @param _user The address to look up
     * @return The username associated with the given address
     */
    function getUsername(address _user) public view returns (string memory) {
        return addressToUsername[_user];
    }

    /**
     * @notice Get the address associated with a given username
     * @param _username The username to look up
     * @return The address associated with the given username
     */
    function getAddress(string memory _username) public view returns (address) {
        return usernameToAddress[_username];
    }

    /**
     * @notice Set or update the username for the caller's address
     * @param _username The new username to set
     * @dev Emits UsernameSet event
     * @dev Validates username format and uniqueness
     */
    function setUsername(string memory _username) public {
        require(bytes(_username).length > 0, "Username cannot be empty");
        require(bytes(_username).length <= MAX_USERNAME_LENGTH, "Username too long");
        require(usernameToAddress[_username] == address(0), "Username already taken");
        require(isValidUsername(_username), "Username must be lowercase letters and numbers only");

        string memory oldUsername = addressToUsername[msg.sender];

        if (bytes(oldUsername).length > 0) {
            delete usernameToAddress[oldUsername];
        }

        addressToUsername[msg.sender] = _username;
        usernameToAddress[_username] = msg.sender;
        emit UsernameSet(msg.sender, _username);
    }

    /**
     * @notice Set or update the username for a specific user address by the owner
     * @param _user The address of the user to set the username for
     * @param _username The new username to set
     * @dev Emits UsernameSet event
     * @dev Only callable by contract owner
     */
    function setUsernameByOwner(address _user, string memory _username) public onlyOwner {
        require(bytes(_username).length > 0, "Username cannot be empty");
        require(usernameToAddress[_username] == address(0), "Username already taken");

        string memory oldUsername = addressToUsername[_user];

        if (bytes(oldUsername).length > 0) {
            delete usernameToAddress[oldUsername];
        }

        addressToUsername[_user] = _username;
        usernameToAddress[_username] = _user;
        emit UsernameSet(_user, _username);
    }

    /**
     * @notice Check if a username contains only lowercase letters and numbers
     * @param _username The username to check
     * @return True if the username is valid, false otherwise
     */
    function isValidUsername(string memory _username) internal pure returns (bool) {
        bytes memory b = bytes(_username);
        for (uint i; i < b.length; i++) {
            bytes1 char = b[i];
            if (!(char >= 0x30 && char <= 0x39) && !(char >= 0x61 && char <= 0x7A)) {
                return false;
            }
        }
        return true;
    }
}
