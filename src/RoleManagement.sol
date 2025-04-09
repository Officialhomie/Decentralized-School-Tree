// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SchoolManagementBase.sol";

/**
 * @title IRoleManagement
 * @dev Interface for role management functionality
 */
interface IRoleManagement {
    function addTeacher(address teacher) external;
    function removeTeacher(address teacher) external;
    function hasTeacherRole(address account) external view returns (bool);
    function hasAdminRole(address account) external view returns (bool);
    function hasMasterAdminRole(address account) external view returns (bool);
}

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
    event AdminRoleGranted(address indexed admin);
    event AdminRoleRevoked(address indexed admin);
    event StudentRoleGranted(address indexed student);
    event StudentRoleRevoked(address indexed student);
    
    /**
     * @dev Adds a teacher role to an address
     */
    function addTeacher(address teacher) external override onlyRole(ADMIN_ROLE) notRecovered {
        if (teacher == address(0)) revert InvalidAddress();
        
        // Using role registry instead of direct AccessControl
        if (roleRegistry.checkRole(TEACHER_ROLE, teacher, address(this))) 
            revert RoleAlreadyAssigned();
            
        roleRegistry.grantSchoolRole(TEACHER_ROLE, teacher, address(this));
        emit TeacherRoleGranted(teacher);
    }
    
    /**
     * @dev Removes a teacher role from an address
     */
    function removeTeacher(address teacher) external override onlyRole(ADMIN_ROLE) notRecovered {
        if (teacher == address(0)) revert InvalidAddress();
        
        if (!roleRegistry.checkRole(TEACHER_ROLE, teacher, address(this))) 
            revert RoleNotAssigned();
        
        roleRegistry.revokeSchoolRole(TEACHER_ROLE, teacher, address(this));
        emit TeacherRoleRevoked(teacher);
    }
    
    /**
     * @dev Adds an admin role to an address
     */
    function addAdmin(address admin) external onlyRole(ADMIN_ROLE) notRecovered {
        if (admin == address(0)) revert InvalidAddress();
        
        if (roleRegistry.checkRole(ADMIN_ROLE, admin, address(this))) 
            revert RoleAlreadyAssigned();
            
        roleRegistry.grantSchoolRole(ADMIN_ROLE, admin, address(this));
        emit AdminRoleGranted(admin);
    }
    
    /**
     * @dev Removes an admin role from an address
     */
    function removeAdmin(address admin) external onlyRole(ADMIN_ROLE) notRecovered {
        if (admin == address(0)) revert InvalidAddress();
        
        if (!roleRegistry.checkRole(ADMIN_ROLE, admin, address(this))) 
            revert RoleNotAssigned();
        
        roleRegistry.revokeSchoolRole(ADMIN_ROLE, admin, address(this));
        emit AdminRoleRevoked(admin);
    }
    
    /**
     * @dev Adds a student role to an address
     */
    function addStudent(address student) external onlyRole(TEACHER_ROLE) notRecovered {
        if (student == address(0)) revert InvalidAddress();
        
        if (roleRegistry.checkRole(STUDENT_ROLE, student, address(this))) 
            revert RoleAlreadyAssigned();
            
        roleRegistry.grantSchoolRole(STUDENT_ROLE, student, address(this));
        emit StudentRoleGranted(student);
    }
    
    /**
     * @dev Removes a student role from an address
     */
    function removeStudent(address student) external onlyRole(TEACHER_ROLE) notRecovered {
        if (student == address(0)) revert InvalidAddress();
        
        if (!roleRegistry.checkRole(STUDENT_ROLE, student, address(this))) 
            revert RoleNotAssigned();
        
        roleRegistry.revokeSchoolRole(STUDENT_ROLE, student, address(this));
        emit StudentRoleRevoked(student);
    }
    
    /**
     * @dev Checks if an address has teacher role
     */
    function hasTeacherRole(address account) external view override returns (bool) {
        if (account == address(0)) revert InvalidAddress();
        return roleRegistry.checkRole(TEACHER_ROLE, account, address(this));
    }
    
    /**
     * @dev Checks if an address has admin role
     */
    function hasAdminRole(address account) external view override returns (bool) {
        if (account == address(0)) revert InvalidAddress();
        return roleRegistry.checkRole(ADMIN_ROLE, account, address(this));
    }
    
    /**
     * @dev Checks if an address has master admin role
     */
    function hasMasterAdminRole(address account) external view override returns (bool) {
        if (account == address(0)) revert InvalidAddress();
        return roleRegistry.checkRole(MASTER_ADMIN_ROLE, account, address(this));
    }
    
    /**
     * @dev Checks if an address has student role
     */
    function hasStudentRole(address account) external view returns (bool) {
        if (account == address(0)) revert InvalidAddress();
        return roleRegistry.checkRole(STUDENT_ROLE, account, address(this));
    }
}