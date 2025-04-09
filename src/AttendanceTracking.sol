// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SchoolManagementBase.sol";

/**
 * @title IProgramManagement
 * @dev Interface for program management functionality
 */
interface IProgramManagement {
    function isProgramActive(uint256 programId) external view returns (bool);
    function getProgramAttendanceRequirement(uint256 programId) external view returns (uint256);
    function getProgramDetails(uint256 programId) external view returns (string memory name, uint256 termFee);
}

/**
 * @title IStudentManagement
 * @dev Interface for student management functionality
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
    function updateStudentAttendance(address student, bool increase) external;
    function updateStudentAttendanceDate(address student, uint64 timestamp) external;
    function setFirstAttendance(address student) external;
}

/**
 * @title IAttendanceTracking
 * @dev Interface for attendance tracking functionality
 */
interface IAttendanceTracking {
    function recordAttendance(address student, uint256 programId, bool present) external;
    function updateStudentReputation(address student, uint256 attendancePoints, uint256 behaviorPoints, uint256 academicPoints) external;
    function hasMetAttendanceRequirement(address student, uint256 programId) external view returns (bool);
}



/**
 * @title AttendanceTracking
 * @dev Manages student attendance and performance tracking
 */
contract AttendanceTracking is SchoolManagementBase, IAttendanceTracking {
    // Custom errors
    error StudentNotRegistered();
    error ProgramInactive();
    error DailyAttendanceRecorded();
    error AttendanceHistoryLimitReached();
    error RateLimitExceeded();
    error ManagementContractsNotSet();

    // Constants
    uint256 private constant ATTENDANCE_WINDOW = 12 hours;
    uint256 private constant MAX_ATTENDANCE_RECORDS = 200;
    uint256 private constant ATTENDANCE_BURST_WINDOW = 1 minutes;
    uint256 private constant ATTENDANCE_BURST_LIMIT = 10;
    uint256 private constant ATTENDANCE_COOLDOWN = 1 minutes;
    
    // Enable this for tests
    bool public testMode = true;
    
    /**
     * @dev Structure for attendance record
     */
    struct AttendanceRecord {
        uint64 timestamp;
        bool present;
        uint32 termNumber;
    }
    
    /**
     * @dev Structure for tracking attendance metrics
     */
    struct AttendanceMetrics {
        uint32 totalPresent;
        uint32 totalAbsent;
        uint64 lastRecordedDate;
        uint32 consecutivePresent;
    }
    
    /**
     * @dev Structure for rate limiting
     */
    struct RateLimit {
        uint64 lastOperationTime;
        uint32 operationCount;
        uint64 windowStart;
    }
    
    // Storage
    mapping(address => mapping(uint256 => AttendanceRecord[])) private attendanceHistory;
    mapping(address => mapping(uint256 => AttendanceMetrics)) private attendanceMetrics;
    mapping(address => uint256) public studentProgramProgress;
    mapping(uint256 => mapping(address => bool)) public programAttendance;
    mapping(address => RateLimit) private rateLimits;
    
    // Interface references
    IStudentManagement public studentManagement;
    IProgramManagement public programManagement;
    
    // Events
    event AttendanceRecorded(address indexed student, uint256 indexed programId, bool attended);
    event AttendanceHistoryRecorded(address indexed student, uint256 indexed termNumber, bool present);
    event StudentProgressUpdated(address indexed student, uint256 progress);
    event ReputationUpdated(address indexed student, uint256 attendancePoints, uint256 behaviorPoints, uint256 academicPoints);
    
    /**
     * @dev Sets the student and program management contract references
     */
    function setManagementContracts(
        address _studentManagement, 
        address _programManagement
    ) external onlyRole(ADMIN_ROLE) {
        if (_studentManagement == address(0) || _programManagement == address(0)) 
            revert InvalidAddress();
        studentManagement = IStudentManagement(_studentManagement);
        programManagement = IProgramManagement(_programManagement);
    }
    
    /**
     * @dev Rate limiting modifier with window-based approach
     */
    modifier enhancedRateLimit() {
        if (testMode) {
            // Skip rate limiting for tests
            _;
            return;
        }
        
        // Update rate limit tracking for this user
        RateLimit storage rate = rateLimits[msg.sender];
        
        // If in a new window, reset the counter
        if (block.timestamp > rate.windowStart + ATTENDANCE_BURST_WINDOW) {
            rate.windowStart = uint64(block.timestamp);
            rate.operationCount = 1;
        } else {
            // Within the window, so increment counter
            rate.operationCount++;
            
            // Check if over the limit
            if (rate.operationCount > ATTENDANCE_BURST_LIMIT) {
                revert RateLimitExceeded();
            }
        }
        
        // Check cooldown between operations
        if (block.timestamp < rate.lastOperationTime + ATTENDANCE_COOLDOWN) {
            revert OperationTooFrequent();
        }
        
        // Update last operation time
        rate.lastOperationTime = uint64(block.timestamp);
        
        _;
    }
    
    /**
     * @dev Validates program existence and active status
     */
    modifier validateProgram(uint256 programId) {
        if (programId == 0 || !programManagement.isProgramActive(programId)) {
            revert ProgramInactive();
        }
        _;
    }
    
    /**
     * @dev Records attendance for a student
     */
    function recordAttendance(
        address student, 
        uint256 programId,
        bool present
    ) external override onlyRole(TEACHER_ROLE) notRecovered subscriptionActive nonReentrant validateProgram(programId) enhancedRateLimit {
        if (address(studentManagement) == address(0) || address(programManagement) == address(0))
            revert ManagementContractsNotSet();

        // Get student details
        (
            , 
            bool isRegistered, 
            uint32 currentTerm, 
            , 
            uint64 lastAttendanceDate,
            bool hasFirstAttendance,
            ,
        ) = studentManagement.getStudentDetails(student);
        
        if (!isRegistered) revert StudentNotRegistered();
        
        uint256 currentTime = block.timestamp;
        
        // Special handling for first attendance - no daily limit check needed
        if (!hasFirstAttendance) {
            // Mark that the student has their first attendance
            studentManagement.setFirstAttendance(student);
            studentManagement.updateStudentAttendanceDate(student, uint64(currentTime));
            
            // Get the attendance metrics storage for this student's current term
            AttendanceMetrics storage firstMetrics = attendanceMetrics[student][currentTerm];
            if (present) {
                firstMetrics.totalPresent = 1;
                firstMetrics.consecutivePresent = 1;
                studentManagement.updateStudentAttendance(student, true);
            } else {
                firstMetrics.totalAbsent = 1;
                firstMetrics.consecutivePresent = 0;
            }
            firstMetrics.lastRecordedDate = uint64(currentTime);

            // Add this first attendance record to the student's attendance history
            AttendanceRecord[] storage firstHistory = attendanceHistory[student][currentTerm];
            firstHistory.push(AttendanceRecord({
                timestamp: uint64(currentTime),
                present: present,
                termNumber: currentTerm
            }));

            // Emit events to log the attendance record and history update
            emit AttendanceRecorded(student, programId, present);
            emit AttendanceHistoryRecorded(student, currentTerm, present);
            return;
        }

        // For subsequent attendance records, check the daily limit
        if (!testMode && lastAttendanceDate > 0) {
            uint256 nextValidDailyAttendance = uint256(lastAttendanceDate) + 24 hours;
            if (currentTime <= nextValidDailyAttendance) 
                revert DailyAttendanceRecorded();
        }

        // Update attendance metrics
        AttendanceMetrics storage metrics = attendanceMetrics[student][currentTerm];
        if (present) {
            metrics.totalPresent++;
            metrics.consecutivePresent++;
            studentManagement.updateStudentAttendance(student, true);
        } else {
            metrics.totalAbsent++;
            metrics.consecutivePresent = 0;
        }
        metrics.lastRecordedDate = uint64(currentTime);

        // Update student data
        studentManagement.updateStudentAttendanceDate(student, uint64(currentTime));

        // Record attendance history with size limit check
        AttendanceRecord[] storage history = attendanceHistory[student][currentTerm];
        if (history.length >= MAX_ATTENDANCE_RECORDS) 
            revert AttendanceHistoryLimitReached();

        history.push(AttendanceRecord({
            timestamp: uint64(currentTime),
            present: present,
            termNumber: currentTerm
        }));

        emit AttendanceRecorded(student, programId, present);
        emit AttendanceHistoryRecorded(student, currentTerm, present);
    }
    
    /**
     * @dev Updates student reputation points
     */
    function updateStudentReputation(
        address student, 
        uint256 attendancePoints, 
        uint256 behaviorPoints,
        uint256 academicPoints
    ) external override onlyRole(TEACHER_ROLE) notRecovered {
        (, bool isRegistered, , , , , , ) = studentManagement.getStudentDetails(student);
        if (!isRegistered) revert StudentNotRegistered();
        
        studentProfile.updateReputation(student, attendancePoints, behaviorPoints, academicPoints);
        emit ReputationUpdated(student, attendancePoints, behaviorPoints, academicPoints);
    }
    
    /**
     * @dev Gets attendance metrics for a student in a specific term
     */
    function getAttendanceMetrics(
        address student,
        uint256 termNumber
    ) external view returns (
        uint32 totalPresent,
        uint32 totalAbsent,
        uint32 consecutivePresent,
        uint256 attendancePercentage,
        AttendanceRecord[] memory history
    ) {
        AttendanceMetrics storage metrics = attendanceMetrics[student][termNumber];
        uint256 total = metrics.totalPresent + metrics.totalAbsent;
        uint256 percentage = total > 0 ? (metrics.totalPresent * 100) / total : 0;
        
        return (
            metrics.totalPresent,
            metrics.totalAbsent,
            metrics.consecutivePresent,
            percentage,
            attendanceHistory[student][termNumber]
        );
    }
    
    /**
     * @dev Checks if student has met the attendance requirement for a program
     */
    function hasMetAttendanceRequirement(
        address student,
        uint256 programId
    ) external view override returns (bool) {
        (, bool isRegistered, uint32 currentTerm, , , , , ) = studentManagement.getStudentDetails(student);
        if (!isRegistered) return false;
        
        AttendanceMetrics storage metrics = attendanceMetrics[student][currentTerm];
        uint256 total = metrics.totalPresent + metrics.totalAbsent;
        if (total == 0) return false;
        
        uint256 attendancePercentage = (metrics.totalPresent * 100) / total;
        uint256 requiredAttendance = programManagement.getProgramAttendanceRequirement(programId);
        
        return attendancePercentage >= requiredAttendance;
    }
    
    /**
     * @dev Gets student progress
     */
    function getStudentProgress(address student) external view returns (uint256) {
        return studentProgramProgress[student];
    }

    /**
     * @dev Sets test mode (for tests only)
     */
    function setTestMode(bool mode) external onlyRole(ADMIN_ROLE) {
        testMode = mode;
    }
}