// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @title RoleRegistry
 * @dev Centralized role management for the entire school system
 */
contract RoleRegistry is AccessControl, Initializable {
    // Role definitions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TEACHER_ROLE = keccak256("TEACHER_ROLE");
    bytes32 public constant MASTER_ADMIN_ROLE = keccak256("MASTER_ADMIN_ROLE");
    bytes32 public constant STUDENT_ROLE = keccak256("STUDENT_ROLE");
    bytes32 public constant SCHOOL_ROLE = keccak256("SCHOOL_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    
    // School-specific role assignments
    mapping(address => mapping(bytes32 => mapping(address => bool))) private schoolRoles;
    
    // Events
    event SchoolRoleGranted(bytes32 indexed role, address indexed account, address indexed school);
    event SchoolRoleRevoked(bytes32 indexed role, address indexed account, address indexed school);
    event GlobalRoleAssigned(bytes32 indexed role, address indexed account);
    
    /**
     * @dev Initialize the role registry with a master admin
     */
    function initialize(address masterAdmin) public initializer {
        require(masterAdmin != address(0), "Invalid master admin address");
        
        _grantRole(DEFAULT_ADMIN_ROLE, masterAdmin);
        _grantRole(MASTER_ADMIN_ROLE, masterAdmin);
        
        emit GlobalRoleAssigned(DEFAULT_ADMIN_ROLE, masterAdmin);
        emit GlobalRoleAssigned(MASTER_ADMIN_ROLE, masterAdmin);
    }
    
    /**
     * @dev Grant a role within a specific school context
     */
    function grantSchoolRole(bytes32 role, address account, address school) external {
        require(
            hasRole(ADMIN_ROLE, msg.sender) || 
            hasRole(MASTER_ADMIN_ROLE, msg.sender) ||
            (schoolRoles[school][ADMIN_ROLE][msg.sender] && msg.sender == school),
            "Not authorized to grant roles"
        );
        require(account != address(0), "Invalid account address");
        require(school != address(0), "Invalid school address");
        
        schoolRoles[school][role][account] = true;
        emit SchoolRoleGranted(role, account, school);
    }
    
    /**
     * @dev Grant global role (system-wide)
     */
    function grantGlobalRole(bytes32 role, address account) external onlyRole(MASTER_ADMIN_ROLE) {
        require(account != address(0), "Invalid account address");
        _grantRole(role, account);
        emit GlobalRoleAssigned(role, account);
    }
    
    /**
     * @dev Revoke a role from an account in a school context
     */
    function revokeSchoolRole(bytes32 role, address account, address school) external {
        require(
            hasRole(ADMIN_ROLE, msg.sender) || 
            hasRole(MASTER_ADMIN_ROLE, msg.sender) ||
            (schoolRoles[school][ADMIN_ROLE][msg.sender] && msg.sender == school),
            "Not authorized to revoke roles"
        );
        
        schoolRoles[school][role][account] = false;
        emit SchoolRoleRevoked(role, account, school);
    }
    
    /**
     * @dev Check if an account has a role in a school context
     */
    function hasSchoolRole(bytes32 role, address account, address school) public view returns (bool) {
        return schoolRoles[school][role][account];
    }
    
    /**
     * @dev Check if an account has a role (globally or in a school context)
     */
    function checkRole(bytes32 role, address account, address school) public view returns (bool) {
        return hasRole(role, account) || hasSchoolRole(role, account, school);
    }
    
    /**
     * @dev Get all global roles of an account
     */
    function getGlobalRoles(address account) external view returns (bool isAdmin, bool isTeacher, bool isMasterAdmin, bool isSchool) {
        return (
            hasRole(ADMIN_ROLE, account),
            hasRole(TEACHER_ROLE, account),
            hasRole(MASTER_ADMIN_ROLE, account),
            hasRole(SCHOOL_ROLE, account)
        );
    }
    
    /**
     * @dev Get all school-specific roles of an account
     */
    function getSchoolRoles(address account, address school) external view returns (bool isAdmin, bool isTeacher, bool isStudent) {
        return (
            hasSchoolRole(ADMIN_ROLE, account, school),
            hasSchoolRole(TEACHER_ROLE, account, school),
            hasSchoolRole(STUDENT_ROLE, account, school)
        );
    }
}