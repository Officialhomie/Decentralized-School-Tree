// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// Import the interface from the existing system
import "../../src/SchoolManagementBase.sol";

/**
 * @title MockRoleRegistry
 * @dev A mock implementation of IRoleRegistry interface for testing
 */
contract MockRoleRegistry is IRoleRegistry {
    // Role storage
    mapping(bytes32 => mapping(address => mapping(address => bool))) private _roles;
    mapping(bytes32 => mapping(address => bool)) private _globalRoles;
    
    // Events
    event SchoolRoleGranted(bytes32 indexed role, address indexed account, address indexed school);
    event SchoolRoleRevoked(bytes32 indexed role, address indexed account, address indexed school);
    
    function initialize(address masterAdmin) external {
        bytes32 masterAdminRole = keccak256("MASTER_ADMIN_ROLE");
        bytes32 defaultAdminRole = 0x00;
        _globalRoles[masterAdminRole][masterAdmin] = true;
        _globalRoles[defaultAdminRole][masterAdmin] = true;
    }
    
    function checkRole(bytes32 role, address account, address school) external view returns (bool) {
        return _roles[role][account][school] || _globalRoles[role][account];
    }
    
    function grantSchoolRole(bytes32 role, address account, address school) external {
        _roles[role][account][school] = true;
        emit SchoolRoleGranted(role, account, school);
    }
    
    function revokeSchoolRole(bytes32 role, address account, address school) external {
        _roles[role][account][school] = false;
        emit SchoolRoleRevoked(role, account, school);
    }
    
    function hasRole(bytes32 role, address account) external view returns (bool) {
        return _globalRoles[role][account];
    }
    
    function grantGlobalRole(bytes32 role, address account) external {
        _globalRoles[role][account] = true;
    }
} 