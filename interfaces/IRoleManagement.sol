// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IRoleManagement
 * @dev Interface for role management functionalities
 */
interface IRoleManagement {
    function addTeacher(address teacher) external;
    function removeTeacher(address teacher) external;
    function hasTeacherRole(address account) external view returns (bool);
    function hasAdminRole(address account) external view returns (bool);
    function hasMasterAdminRole(address account) external view returns (bool);
}