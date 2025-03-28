// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IProgramManagement
 * @dev Interface for program management functionalities
 */
interface IProgramManagement {
    function isProgramActive(uint256 programId) external view returns (bool);
    function getProgramDetails(uint256 programId) external view returns (string memory name, uint256 termFee);
    function getProgramAttendanceRequirement(uint256 programId) external view returns (uint256);
    function getProgramEnrollmentCount(uint256 programId) external view returns (uint32);
    function getProgramMaxEnrollment(uint256 programId) external view returns (uint32);
    function getCurrentProgramId() external view returns (uint256);
    function createProgram(
        string memory name,
        uint128 termFee,
        uint16 requiredAttendance,
        uint32 maxEnrollment
    ) external payable;
    function updateProgramFee(uint256 programId, uint256 newFee) external;
    function deactivateProgram(uint256 programId) external;
    function incrementEnrollment(uint256 programId) external returns (bool);
}
