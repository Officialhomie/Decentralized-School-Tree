// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


/**
 * @title IStudentManagement
 * @dev Interface for student management functionalities
 */
interface IStudentManagement {
    function getStudentDetails(address student) external view returns (
        string memory name,
        bool isRegistered,
        uint32 currentTerm,
        uint32 attendanceCount,
        uint64 lastAttendanceDate,
        bool hasFirstAttendance,
        uint32 programId,
        uint128 totalPayments
    );
    function getStudentProgram(address student) external view returns (uint256);
    function registerStudent(
        address student,
        string memory name,
        uint256 programId
    ) external;
    function advanceStudentTerm(address student) external;
    function removeStudent(address student) external;
    function updateStudentAttendance(address student, bool increase) external;
    function updateStudentAttendanceDate(address student, uint64 timestamp) external;
    function setFirstAttendance(address student) external;
}
