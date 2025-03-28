// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


/**
 * @title IAttendanceTracking
 * @dev Interface for attendance tracking functionalities
 */
interface IAttendanceTracking {
    function recordAttendance(
        address student, 
        uint256 programId,
        bool present
    ) external;
    function updateStudentReputation(
        address student, 
        uint256 attendancePoints, 
        uint256 behaviorPoints,
        uint256 academicPoints
    ) external;
    function hasMetAttendanceRequirement(
        address student,
        uint256 programId
    ) external view returns (bool);
}