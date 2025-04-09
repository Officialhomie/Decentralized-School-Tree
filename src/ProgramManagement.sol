// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "node_modules/@thirdweb-dev/contracts/node_modules/@openzeppelin/contracts/utils/Counters.sol";
import "./SchoolManagementBase.sol";

/**
 * @title IProgramManagement
 * @dev Interface for program management functionality
 */
interface IProgramManagement {
    function createProgram(string memory name, uint128 termFee, uint16 requiredAttendance, uint32 maxEnrollment) external payable;
    function deactivateProgram(uint256 programId) external;
    function updateProgramFee(uint256 programId, uint256 newFee) external;
    function incrementEnrollment(uint256 programId) external returns (bool);
    function getProgramDetails(uint256 programId) external view returns (string memory name, uint256 termFee);
    function isProgramActive(uint256 programId) external view returns (bool);
    function getProgramAttendanceRequirement(uint256 programId) external view returns (uint256);
    function getProgramEnrollmentCount(uint256 programId) external view returns (uint32);
    function getProgramMaxEnrollment(uint256 programId) external view returns (uint32);
    function getCurrentProgramId() external view returns (uint256);
}

/**
 * @title ProgramManagement
 * @dev Manages educational programs within the school system
 */
contract ProgramManagement is SchoolManagementBase, IProgramManagement {
    using Counters for Counters.Counter;

    // Custom errors
    error ProgramAlreadyExists();
    error ProgramInactive();
    error InvalidFeeRange();
    error InvalidAttendanceRequirement(); 
    error InvalidEnrollmentLimit();
    error EnrollmentLimitReached();
    error SubscriptionExpired();

    /**
     * @dev Program structure with details about each educational program
     */
    struct Program {
        string name;
        bool isActive;
        uint128 termFee;
        uint16 minimumAttendance;
        uint16 requiredAttendance;
        uint32 enrolledCount;
        uint32 maxEnrollment;
    }
    
    // Storage
    mapping(uint256 => Program) public programs;
    Counters.Counter private _programIds;
    
    // Events
    event ProgramCreated(uint256 indexed programId, string name, uint256 termFee, uint256 requiredAttendance);
    event ProgramDeactivated(uint256 indexed programId);
    event ProgramFeesUpdated(uint256 indexed programId, uint256 newFee);
    event ProgramDetailsRetrieved(uint256 indexed programId, string name, uint256 termFee);
    event ProgramAttendanceRequirementUpdated(uint256 indexed programId, uint256 requirement);
    event ProgramEnrollmentUpdated(uint256 indexed programId, uint32 maxEnrollment);
    
    /**
     * @dev Creates a new educational program
     */
    function createProgram(
        string memory name,
        uint128 termFee,
        uint16 requiredAttendance,
        uint32 maxEnrollment
    ) external payable override onlyRole(ADMIN_ROLE) notRecovered subscriptionActive validString(name) nonReentrant {
        if (msg.value < revenueSystem.programCreationFee()) 
            revert InsufficientPayment();
        if (termFee < MIN_TERM_FEE || termFee > MAX_TERM_FEE) 
            revert InvalidFeeRange();
        if (requiredAttendance == 0 || requiredAttendance > 100) 
            revert InvalidAttendanceRequirement();
        if (maxEnrollment == 0 || maxEnrollment > 1000) 
            revert InvalidEnrollmentLimit();
        
        // Check for duplicate program names
        uint256 currentId = _programIds.current();
        for(uint256 i = 1; i <= currentId; i++) {
            if (keccak256(bytes(programs[i].name)) == keccak256(bytes(name))) {
                revert ProgramAlreadyExists();
            }
        }
        
        _programIds.increment();
        uint256 newProgramId = _programIds.current();
        
        programs[newProgramId] = Program({
            name: name,
            isActive: true,
            termFee: termFee,
            minimumAttendance: 0,
            requiredAttendance: requiredAttendance,
            enrolledCount: 0,
            maxEnrollment: maxEnrollment
        });
        
        emit ProgramCreated(newProgramId, name, termFee, requiredAttendance);
    }
    
    /**
     * @dev Deactivates an existing program
     */
    function deactivateProgram(uint256 programId) external override onlyRole(ADMIN_ROLE) notRecovered {
        if (!programs[programId].isActive) 
            revert ProgramInactive();
        programs[programId].isActive = false;
        emit ProgramDeactivated(programId);
    }
    
    /**
     * @dev Updates the fee for a program
     */
    function updateProgramFee(uint256 programId, uint256 newFee) external override onlyRole(ADMIN_ROLE) generalRateLimited notRecovered {
        if (!programs[programId].isActive) 
            revert ProgramInactive();
        programs[programId].termFee = uint128(newFee);
        emit ProgramFeesUpdated(programId, newFee);
    }
    
    /**
     * @dev Increments the enrollment count for a program
     * Called by StudentManagement when registering a student
     */
    function incrementEnrollment(uint256 programId) external override onlyRole(SCHOOL_ROLE) returns (bool) {
        if (!programs[programId].isActive) 
            revert ProgramInactive();
        if (programs[programId].enrolledCount >= programs[programId].maxEnrollment) 
            revert EnrollmentLimitReached();
            
        programs[programId].enrolledCount++;
        return true;
    }
    
    /**
     * @dev Gets details about a program
     */
    function getProgramDetails(uint256 programId) external view override returns (string memory name, uint256 termFee) {
        Program storage program = programs[programId];
        return (program.name, program.termFee);
    }
    
    /**
     * @dev Checks if a program is active
     */
    function isProgramActive(uint256 programId) external view override returns (bool) {
        return programs[programId].isActive;
    }
    
    /**
     * @dev Gets the attendance requirement for a program
     */
    function getProgramAttendanceRequirement(uint256 programId) external view override returns (uint256) {
        return programs[programId].requiredAttendance;
    }
    
    /**
     * @dev Gets the current enrollment count for a program
     */
    function getProgramEnrollmentCount(uint256 programId) external view override returns (uint32) {
        return programs[programId].enrolledCount;
    }
    
    /**
     * @dev Gets the maximum enrollment capacity for a program
     */
    function getProgramMaxEnrollment(uint256 programId) external view override returns (uint32) {
        return programs[programId].maxEnrollment;
    }
    
    /**
     * @dev Gets the current program ID counter
     */
    function getCurrentProgramId() external view override returns (uint256) {
        return _programIds.current();
    }
}