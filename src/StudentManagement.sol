// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SchoolManagementBase.sol";

/**
 * @title IProgramManagement
 * @dev Interface for program management functionality used by student management
 */
interface IProgramManagement {
    function incrementEnrollment(uint256 programId) external returns (bool);
    function isProgramActive(uint256 programId) external view returns (bool);
    function getProgramDetails(uint256 programId) external view returns (string memory name, uint256 termFee);
}

/**
 * @title IStudentManagement
 * @dev Interface for student management functionality
 */
interface IStudentManagement {
    function registerStudent(address student, string memory name, uint256 programId) external;
    function removeStudent(address student) external;
    function advanceStudentTerm(address student) external;
    function updateStudentAttendance(address student, bool increase) external;
    function updateStudentAttendanceDate(address student, uint64 timestamp) external;
    function setFirstAttendance(address student) external;
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
}

/**
 * @title StudentManagement
 * @dev Manages student registration, enrollment, and progression
 */
contract StudentManagement is SchoolManagementBase, IStudentManagement {
    // Custom errors
    error StudentAlreadyRegistered();
    error StudentNotRegistered();
    error ProgramInactive();
    error ArrayLengthMismatch();
    error BatchSizeTooLarge();
    error RateLimitExceeded();
    error TuitionAlreadyPaid();
    error InvalidString();

    /**
     * @dev Student structure with enrollment and academic information
     */
    struct Student {
        string name;
        bool isRegistered;
        uint32 currentTerm;
        uint32 attendanceCount;
        uint64 lastAttendanceDate;
        bool hasFirstAttendance;
        uint32 programId;
        uint128 totalPayments;
    }
    
    // Storage variables
    mapping(address => Student) public students;
    mapping(address => mapping(uint256 => bool)) public tuitionPayments;
    mapping(address => uint256) public studentPrograms;
    
    // Rate limiting variables
    mapping(address => uint256) private lastRegistrationTime;
    mapping(address => uint256) private registrationCount;
    mapping(address => uint256) private lastBurstWindowStart;
    
    // Program management interface
    IProgramManagement public programManagement;
    
    // Events
    event StudentRegistered(address indexed student, string name, uint256 term);
    event StudentRemoved(address indexed student);
    event StudentTermAdvanced(address indexed student, uint256 newTerm);
    event StudentProgramUpdated(address indexed student, uint256 indexed programId);
    event TuitionPaid(address indexed student, uint256 indexed term, uint256 amount);
    event BatchStudentsRegistered(uint256 count);
    
    /**
     * @dev Sets the program management contract reference
     */
    function setProgramManagement(address _programManagement) external onlyRole(ADMIN_ROLE) {
        if (_programManagement == address(0)) revert InvalidAddress();
        programManagement = IProgramManagement(_programManagement);
    }
    
    /**
     * @dev Modifier to limit registration frequency with burst allowance
     */
    modifier registrationRateLimited() {
        // Reset burst window if needed
        if (block.timestamp >= lastBurstWindowStart[msg.sender] + BURST_WINDOW) {
            lastBurstWindowStart[msg.sender] = block.timestamp;
            registrationCount[msg.sender] = 0;
        }
        
        // Check burst limit
        if (registrationCount[msg.sender] >= REGISTRATION_BURST_LIMIT)
            revert RateLimitExceeded();
        
        // Check cooldown only if not first in burst
        if (registrationCount[msg.sender] > 0) {
            if (block.timestamp < lastRegistrationTime[msg.sender] + REGISTRATION_COOLDOWN)
                revert OperationTooFrequent();
        }
        
        lastRegistrationTime[msg.sender] = block.timestamp;
        registrationCount[msg.sender]++;
        _;
    }
    
    /**
     * @dev Registers a new student
     */
    function registerStudent(
        address student,
        string memory name,
        uint256 programId
    ) external override onlyRole(TEACHER_ROLE) registrationRateLimited notRecovered subscriptionActive {
        _registerStudent(student, name, programId);
    }
    
    /**
     * @dev Internal function to register a student
     */
    function _registerStudent(
        address student,
        string memory name,
        uint256 programId
    ) internal notRecovered subscriptionActive validString(name) nonReentrant {
        if (student == address(0)) revert InvalidAddress();
        if (students[student].isRegistered) revert StudentAlreadyRegistered();
        
        // Check that program is active and has space
        bool success = programManagement.incrementEnrollment(programId);
        if (!success) revert ProgramInactive();
        
        students[student] = Student({
            name: name,
            isRegistered: true,
            currentTerm: 1,
            attendanceCount: 0,
            lastAttendanceDate: 0,
            hasFirstAttendance: false,
            programId: uint32(programId),
            totalPayments: 0
        });
        
        studentPrograms[student] = programId;
        
        // Grant student role through role registry
        roleRegistry.grantSchoolRole(STUDENT_ROLE, student, address(this));
        
        emit StudentRegistered(student, name, 1);
        emit StudentProgramUpdated(student, programId);
    }
    
    /**
     * @dev Batch registers multiple students at once
     */
    function batchRegisterStudents(
        address[] calldata studentAddresses,
        string[] calldata names,
        uint256[] calldata programIds
    ) external onlyRole(TEACHER_ROLE) notRecovered subscriptionActive {
        if (studentAddresses.length != names.length || 
            names.length != programIds.length)
            revert ArrayLengthMismatch();
        
        // Check burst window reset
        if (block.timestamp >= lastBurstWindowStart[msg.sender] + BURST_WINDOW) {
            lastBurstWindowStart[msg.sender] = block.timestamp;
            registrationCount[msg.sender] = 0;
        }
        
        // Check if batch would exceed burst limit
        if (registrationCount[msg.sender] + studentAddresses.length > REGISTRATION_BURST_LIMIT)
            revert BatchSizeTooLarge();
        
        for(uint i = 0; i < studentAddresses.length; i++) {
            _registerStudent(studentAddresses[i], names[i], programIds[i]);
        }
        
        registrationCount[msg.sender] += studentAddresses.length;
        lastRegistrationTime[msg.sender] = block.timestamp;
        
        emit BatchStudentsRegistered(studentAddresses.length);
    }
    
    /**
     * @dev Removes a student's registration
     */
    function removeStudent(address student) external override onlyRole(ADMIN_ROLE) notRecovered {
        if (!students[student].isRegistered) revert StudentNotRegistered();
        delete students[student];
        
        // Revoke student role through role registry
        roleRegistry.revokeSchoolRole(STUDENT_ROLE, student, address(this));
        
        emit StudentRemoved(student);
    }
    
    /**
     * @dev Advances a student to the next term
     */
    function advanceStudentTerm(address student) external override onlyRole(TEACHER_ROLE) notRecovered subscriptionActive {
        if (!students[student].isRegistered) revert StudentNotRegistered();
        students[student].currentTerm++;
        students[student].attendanceCount = 0; // Reset attendance for new term
        
        emit StudentTermAdvanced(student, students[student].currentTerm);
    }
    
    /**
     * @dev Processes tuition payment for a term
     */
    function payTuition(uint256 term) external payable notRecovered {
        if (!students[msg.sender].isRegistered) revert StudentNotRegistered();
        if (tuitionPayments[msg.sender][term]) revert TuitionAlreadyPaid();
        
        uint256 programId = studentPrograms[msg.sender];
        (, uint256 termFee) = programManagement.getProgramDetails(programId);
        if (msg.value < termFee) revert InsufficientPayment();
        
        tuitionPayments[msg.sender][term] = true;
        revenueSystem.processTuitionPayment{value: msg.value}(msg.sender, msg.value);
        tuitionSystem.recordTuitionPayment(msg.sender, term);
        
        emit TuitionPaid(msg.sender, term, msg.value);
    }
    
    /**
     * @dev Updates a student's attendance count
     */
    function updateStudentAttendance(address student, bool increase) external override onlyRole(TEACHER_ROLE) {
        if (!students[student].isRegistered) revert StudentNotRegistered();
        
        if (increase) {
            students[student].attendanceCount++;
        }
    }
    
    /**
     * @dev Updates a student's last attendance date
     */
    function updateStudentAttendanceDate(address student, uint64 timestamp) external override onlyRole(TEACHER_ROLE) {
        if (!students[student].isRegistered) revert StudentNotRegistered();
        students[student].lastAttendanceDate = timestamp;
    }
    
    /**
     * @dev Marks student's first attendance
     */
    function setFirstAttendance(address student) external override onlyRole(TEACHER_ROLE) {
        if (!students[student].isRegistered) revert StudentNotRegistered();
        students[student].hasFirstAttendance = true;
    }
    
    /**
     * @dev Gets details about a student
     */
    function getStudentDetails(address student) external view override returns (
        string memory name,
        bool isRegistered,
        uint32 currentTerm,
        uint32 attendanceCount,
        uint64 lastAttendanceDate,
        bool hasFirstAttendance,
        uint32 programId,
        uint128 totalPayments
    ) {
        Student storage studentData = students[student];
        return (
            studentData.name,
            studentData.isRegistered,
            studentData.currentTerm,
            studentData.attendanceCount,
            studentData.lastAttendanceDate,
            studentData.hasFirstAttendance,
            studentData.programId,
            studentData.totalPayments
        );
    }
    
    /**
     * @dev Gets the program a student is enrolled in
     */
    function getStudentProgram(address student) external view override returns (uint256) {
        return studentPrograms[student];
    }
    
    /**
     * @dev Checks if tuition has been paid for a term
     */
    function getTuitionPaymentStatus(address student, uint256 term) external view returns (bool) {
        return tuitionPayments[student][term];
    }
    
    /**
     * @dev Gets remaining registration quota for current window
     */
    function getRemainingRegistrations() external view returns (
        uint256 remaining,
        uint256 windowReset
    ) {
        if (block.timestamp >= lastBurstWindowStart[msg.sender] + BURST_WINDOW) {
            return (REGISTRATION_BURST_LIMIT, 0);
        }
        
        uint256 used = registrationCount[msg.sender];
        uint256 resetTime = lastBurstWindowStart[msg.sender] + BURST_WINDOW;
        
        return (
            used >= REGISTRATION_BURST_LIMIT ? 0 : REGISTRATION_BURST_LIMIT - used,
            resetTime
        );
    }
}