// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SchoolManagementBase.sol";
import "interfaces/IRoleManagement.sol";

/**
 * @title RoleManagement
 * @dev Manages roles and permissions within the school system
 */
contract RoleManagement is SchoolManagementBase, IRoleManagement {
    // Custom errors
    error RoleAlreadyAssigned();
    error RoleNotAssigned();
    error InvalidRoleOperation();

    // Events
    event TeacherRoleGranted(address indexed teacher);
    event TeacherRoleRevoked(address indexed teacher);
    
    /**
     * @dev Adds a teacher role to an address
     */
    function addTeacher(address teacher) external override onlyRole(ADMIN_ROLE) notRecovered {
        if (teacher == address(0)) revert InvalidAddress();
        if (hasRole(TEACHER_ROLE, teacher)) revert RoleAlreadyAssigned();
        _grantRole(TEACHER_ROLE, teacher);
        emit TeacherRoleGranted(teacher);
    }
    
    /**
     * @dev Removes a teacher role from an address
     */
    function removeTeacher(address teacher) external override onlyRole(ADMIN_ROLE) notRecovered {
        if (teacher == address(0)) revert InvalidAddress();
        if (!hasRole(TEACHER_ROLE, teacher)) revert RoleNotAssigned();
        _revokeRole(TEACHER_ROLE, teacher);
        emit TeacherRoleRevoked(teacher);
    }
    
    /**
     * @dev Checks if an address has teacher role
     */
    function hasTeacherRole(address account) external view override returns (bool) {
        if (account == address(0)) revert InvalidAddress();
        return hasRole(TEACHER_ROLE, account);
    }
    
    /**
     * @dev Checks if an address has admin role
     */
    function hasAdminRole(address account) external view override returns (bool) {
        if (account == address(0)) revert InvalidAddress();
        return hasRole(ADMIN_ROLE, account);
    }
    
    /**
     * @dev Checks if an address has master admin role
     */
    function hasMasterAdminRole(address account) external view override returns (bool) {
        if (account == address(0)) revert InvalidAddress();
        return hasRole(MASTER_ADMIN_ROLE, account);
    }
}