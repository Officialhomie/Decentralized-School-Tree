// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AttendanceTracking.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";


error RateLimitExceeded();
error StudentNotRegistered();
error ProgramInactive();
error AttendanceHistoryLimitReached();

contract MockStudentManagement {
    mapping(address => bool) public isRegistered;
    mapping(address => uint32) public currentTerms;
    mapping(address => uint32) public attendanceCounts;
    mapping(address => uint64) public lastAttendanceDates;
    mapping(address => bool) public hasFirstAttendance;
    mapping(address => uint32) public programIds;

    function setStudentData(
        address student,
        bool _isRegistered,
        uint32 _currentTerm,
        uint32 _attendanceCount,
        uint64 _lastAttendanceDate,
        bool _hasFirstAttendance,
        uint32 _programId
    ) external {
        isRegistered[student] = _isRegistered;
        currentTerms[student] = _currentTerm;
        attendanceCounts[student] = _attendanceCount;
        lastAttendanceDates[student] = _lastAttendanceDate;
        hasFirstAttendance[student] = _hasFirstAttendance;
        programIds[student] = _programId;
    }

    function getStudentDetails(address student) external view returns (
        string memory name,
        bool isRegistered_,
        uint32 currentTerm,
        uint32 attendanceCount,
        uint64 lastAttendanceDate,
        bool hasFirstAttendance_,
        uint32 programId,
        uint128 totalPayments
    ) {
        return (
            "Test Student",
            isRegistered[student],
            currentTerms[student],
            attendanceCounts[student],
            lastAttendanceDates[student],
            hasFirstAttendance[student],
            programIds[student],
            0
        );
    }

    function updateStudentAttendance(address student, bool increase) external {
        if (increase) {
            attendanceCounts[student]++;
        }
    }

    function updateStudentAttendanceDate(address student, uint64 timestamp) external {
        lastAttendanceDates[student] = timestamp;
    }

    function setFirstAttendance(address student) external {
        hasFirstAttendance[student] = true;
    }
}

contract MockProgramManagement {
    mapping(uint256 => bool) public programActive;
    mapping(uint256 => uint256) public attendanceRequirements;

    function setProgramActive(uint256 programId, bool active) external {
        programActive[programId] = active;
    }

    function setAttendanceRequirement(uint256 programId, uint256 requirement) external {
        attendanceRequirements[programId] = requirement;
    }

    function isProgramActive(uint256 programId) external view returns (bool) {
        return programActive[programId];
    }

    function getProgramAttendanceRequirement(uint256 programId) external view returns (uint256) {
        return attendanceRequirements[programId];
    }
}

contract MockStudentProfile {
    function updateReputation(
        address student,
        uint256 attendancePoints,
        uint256 behaviorPoints,
        uint256 academicPoints
    ) external {}
}

contract MockRevenueSystem {
    function programCreationFee() external pure returns (uint256) {
        return 0.1 ether;
    }
}

contract MockTuitionSystem {
    function checkTuitionStatus(
        address school,
        address student,
        uint256 term
    ) external view returns (bool isPaid, uint256 dueDate) {
        return (true, block.timestamp + 30 days);
    }
}

contract TestableSchoolManagementBase is SchoolManagementBase {
    function setupForTest(
        address _revenueSystem,
        address _studentProfile,
        address _tuitionSystem,
        address _masterAdmin,
        address _organizationAdmin
    ) external {
        initialize(
            _revenueSystem,
            _studentProfile,
            _tuitionSystem,
            _masterAdmin,
            _organizationAdmin
        );
    }
}

contract AttendanceTrackingTest is Test {
    AttendanceTracking attendanceTracking;
    MockStudentManagement studentManagement;
    MockProgramManagement programManagement;
    MockStudentProfile studentProfile;
    MockRevenueSystem revenueSystem;
    MockTuitionSystem tuitionSystem;

    address masterAdmin;
    address organizationAdmin;
    address teacher;
    address student;
    address unauthorized;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TEACHER_ROLE = keccak256("TEACHER_ROLE");
    bytes32 public constant MASTER_ADMIN_ROLE = keccak256("MASTER_ADMIN_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00; // Add this line

    uint256 programId = 1;

    event AttendanceRecorded(address indexed student, uint256 indexed programId, bool attended);
    event AttendanceHistoryRecorded(address indexed student, uint256 indexed termNumber, bool present);
    event ReputationUpdated(address indexed student, uint256 attendancePoints, uint256 behaviorPoints, uint256 academicPoints);

    function setUp() public {
        console.log("1. Starting setup");
        masterAdmin = makeAddr("masterAdmin");
        organizationAdmin = makeAddr("organizationAdmin");
        teacher = makeAddr("teacher");
        student = makeAddr("student");
        unauthorized = makeAddr("unauthorized");

        console.log("2. Deploying mock contracts");
        // Deploy mock contracts
        studentManagement = new MockStudentManagement();
        programManagement = new MockProgramManagement();
        studentProfile = new MockStudentProfile();
        revenueSystem = new MockRevenueSystem();
        tuitionSystem = new MockTuitionSystem();

        console.log("3. Deploying implementation");
        // Deploy implementation
        AttendanceTracking implementation = new AttendanceTracking();

        console.log("4. Preparing proxy initialization");
        // Deploy proxy with implementation
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                SchoolManagementBase.initialize.selector,
                address(revenueSystem),
                address(studentProfile),
                address(tuitionSystem),
                masterAdmin,
                organizationAdmin
            )
        );

        console.log("5. Getting proxied contract");
        // Get the proxied AttendanceTracking
        attendanceTracking = AttendanceTracking(payable(address(proxy)));

        console.log("6. Checking roles");
        // Check roles
        console.log("masterAdmin has MASTER_ADMIN_ROLE:", attendanceTracking.hasRole(MASTER_ADMIN_ROLE, masterAdmin));
        console.log("organizationAdmin has ADMIN_ROLE:", attendanceTracking.hasRole(ADMIN_ROLE, organizationAdmin));
        console.log("organizationAdmin has DEFAULT_ADMIN_ROLE:", attendanceTracking.hasRole(DEFAULT_ADMIN_ROLE, organizationAdmin));

        console.log("7. Granting teacher role");
        // Grant teacher role
        vm.prank(organizationAdmin);
        attendanceTracking.grantRole(TEACHER_ROLE, teacher);
        vm.stopPrank();


        console.log("8. Setting management contracts");
        // Set management contracts
        vm.prank(organizationAdmin);
        attendanceTracking.setManagementContracts(
            address(studentManagement),
            address(programManagement)
        );

        console.log("9. Funding accounts");
        // Fund accounts
        vm.deal(organizationAdmin, 10 ether);
        vm.deal(teacher, 10 ether);

        console.log("10. Renewing subscription");
        // Set the subscription to active for tests
        vm.prank(organizationAdmin);
        attendanceTracking.renewSubscription{value: 0.1 ether}();

        console.log("11. Setting up student and program");
        // Setup student and program
        studentManagement.setStudentData(
            student,
            true, // registered
            1,    // term 1
            0,    // attendance count
            0,    // last attendance date
            false, // first attendance not recorded
            uint32(programId)
        );

        programManagement.setProgramActive(programId, true);
        programManagement.setAttendanceRequirement(programId, 80);
        
        console.log("12. Setup complete");
    }

    function test_RecordAttendance() public {
        vm.startPrank(teacher);

        // Test event emission
        vm.expectEmit(true, true, false, true);
        emit AttendanceRecorded(student, programId, true);

        vm.expectEmit(true, true, false, true);
        emit AttendanceHistoryRecorded(student, 1, true);

        // Record first attendance
        attendanceTracking.recordAttendance(student, programId, true);

        // Verify student management calls were made
        assertTrue(studentManagement.hasFirstAttendance(student));

        vm.stopPrank();
    }

    function test_RecordConsecutiveAttendance() public {
        vm.startPrank(teacher);

        // Record first attendance
        attendanceTracking.recordAttendance(student, programId, true);

        // Advance time for daily limit
        vm.warp(block.timestamp + 25 hours);

        // Record second attendance
        attendanceTracking.recordAttendance(student, programId, true);

        // Get attendance metrics
        (
            uint32 totalPresent,
            uint32 totalAbsent,
            uint32 consecutivePresent,
            uint256 attendancePercentage,
            AttendanceTracking.AttendanceRecord[] memory history
        ) = attendanceTracking.getAttendanceMetrics(student, 1);

        // Verify metrics
        assertEq(totalPresent, 2);
        assertEq(totalAbsent, 0);
        assertEq(consecutivePresent, 2);
        assertEq(attendancePercentage, 100);
        assertEq(history.length, 2);
        
        vm.stopPrank();
    }
    
    function test_RecordAbsence() public {
        vm.startPrank(teacher);
        
        // Record absence
        attendanceTracking.recordAttendance(student, programId, false);
        
        // Get attendance metrics
        (
            uint32 totalPresent,
            uint32 totalAbsent,
            uint32 consecutivePresent,
            uint256 attendancePercentage,
            AttendanceTracking.AttendanceRecord[] memory history
        ) = attendanceTracking.getAttendanceMetrics(student, 1);
        
        // Verify metrics
        assertEq(totalPresent, 0);
        assertEq(totalAbsent, 1);
        assertEq(consecutivePresent, 0);
        assertEq(attendancePercentage, 0);
        assertEq(history.length, 1);
        assertEq(history[0].present, false);
        
        vm.stopPrank();
    }
    
    function test_AttendancePattern() public {
        vm.startPrank(teacher);
        
        // Create a pattern of attendance: Present, Absent, Present
        attendanceTracking.recordAttendance(student, programId, true);
        
        vm.warp(block.timestamp + 25 hours);
        attendanceTracking.recordAttendance(student, programId, false);
        
        vm.warp(block.timestamp + 25 hours);
        attendanceTracking.recordAttendance(student, programId, true);
        
        // Get attendance metrics
        (
            uint32 totalPresent,
            uint32 totalAbsent,
            uint32 consecutivePresent,
            uint256 attendancePercentage,
            AttendanceTracking.AttendanceRecord[] memory history
        ) = attendanceTracking.getAttendanceMetrics(student, 1);
        
        // Verify metrics
        assertEq(totalPresent, 2);
        assertEq(totalAbsent, 1);
        assertEq(consecutivePresent, 1); // Reset after absence
        assertEq(attendancePercentage, 66); // 2/3 = 66%
        assertEq(history.length, 3);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_StudentNotRegistered() public {
        // Setup unregistered student
        address unregisteredStudent = makeAddr("unregisteredStudent");
        studentManagement.setStudentData(
            unregisteredStudent,
            false, // not registered
            1,
            0,
            0,
            false,
            uint32(programId)
        );
        
        vm.startPrank(teacher);
        vm.expectRevert(StudentNotRegistered.selector);
        attendanceTracking.recordAttendance(unregisteredStudent, programId, true);
        vm.stopPrank();
    }
    
    function test_RevertWhen_ProgramInactive() public {
        // Setup inactive program
        uint256 inactiveProgramId = 2;
        programManagement.setProgramActive(inactiveProgramId, false);
        
        vm.startPrank(teacher);
        vm.expectRevert(ProgramInactive.selector);
        attendanceTracking.recordAttendance(student, inactiveProgramId, true);
        vm.stopPrank();
    }
    
    function test_RevertWhen_DailyAttendanceLimit() public {
        vm.startPrank(teacher);
        
        // Record first attendance
        attendanceTracking.recordAttendance(student, programId, true);
        
        // Try to record again within 24 hours
        vm.expectRevert(OperationTooFrequent.selector);
        attendanceTracking.recordAttendance(student, programId, true);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_UnauthorizedAccess() public {
        vm.prank(unauthorized);
        
        vm.expectRevert();
        attendanceTracking.recordAttendance(student, programId, true);
    }
    
    function test_UpdateStudentReputation() public {
        vm.startPrank(teacher);
        
        vm.expectEmit(true, false, false, true);
        emit ReputationUpdated(student, 90, 85, 95);
        
        attendanceTracking.updateStudentReputation(student, 90, 85, 95);
        
        vm.stopPrank();
    }
    
    function test_HasMetAttendanceRequirement() public {
        vm.startPrank(teacher);
        
        // Record sufficient attendance (90% with 80% requirement)
        for (uint i = 0; i < 9; i++) {
            attendanceTracking.recordAttendance(student, programId, true);
            vm.warp(block.timestamp + 25 hours);
        }
        attendanceTracking.recordAttendance(student, programId, false);
        
        // Check if requirement is met
        bool hasMetRequirement = attendanceTracking.hasMetAttendanceRequirement(student, programId);
        assertTrue(hasMetRequirement);
        
        vm.stopPrank();
    }
    
    function test_HasNotMetAttendanceRequirement() public {
        vm.startPrank(teacher);
        
        // Record insufficient attendance (70% with 80% requirement)
        for (uint i = 0; i < 7; i++) {
            attendanceTracking.recordAttendance(student, programId, true);
            vm.warp(block.timestamp + 25 hours);
        }
        for (uint i = 0; i < 3; i++) {
            attendanceTracking.recordAttendance(student, programId, false);
            vm.warp(block.timestamp + 25 hours);
        }
        
        // Check if requirement is met
        bool hasMetRequirement = attendanceTracking.hasMetAttendanceRequirement(student, programId);
        assertFalse(hasMetRequirement);
        
        vm.stopPrank();
    }
    
    function test_AttendanceHistoryLimit() public {
        vm.startPrank(teacher);
        
        // Record in batches with periodic subscription renewal to avoid expiration
        for (uint batch = 0; batch < 10; batch++) { // 10 batches of 20 = 200 records
            // Pause to renew subscription
            vm.stopPrank();
            vm.prank(organizationAdmin);
            attendanceTracking.renewSubscription{value: 0.1 ether}();
            vm.startPrank(teacher);
            
            // Record 20 attendance records per batch
            for (uint i = 0; i < 20; i++) {
                attendanceTracking.recordAttendance(student, programId, true);
                vm.warp(block.timestamp + 25 hours);
            }
        }
        
        // At this point, we've recorded 200 records (the limit in the contract)
        // Try to record one more, which should trigger the limit
        vm.expectRevert(AttendanceHistoryLimitReached.selector);
        attendanceTracking.recordAttendance(student, programId, true);
        
        vm.stopPrank();
    }
    
    function test_EnhancedRateLimit() public {
        vm.startPrank(teacher);
        
        // Create a second student for testing rate limits
        address student2 = makeAddr("student2");
        studentManagement.setStudentData(
            student2,
            true,
            1,
            0,
            0,
            false,
            uint32(programId)
        );
        
        // Record attendance for first student
        attendanceTracking.recordAttendance(student, programId, true);
        
        // Try to immediately record for second student (should trigger cooldown)
        vm.expectRevert(OperationTooFrequent.selector);
        attendanceTracking.recordAttendance(student2, programId, true);
        
        // Wait for cooldown and try again
        vm.warp(block.timestamp + 2); // REGISTRATION_COOLDOWN is 1 second in the contract
        attendanceTracking.recordAttendance(student2, programId, true);
        
        vm.stopPrank();
    }
    
    function test_RateLimitBurstWindow() public {
        vm.startPrank(teacher);
        
        // Create multiple students for testing rate limits
        address[] memory students = new address[](52); // More than REGISTRATION_BURST_LIMIT
        
        for (uint i = 0; i < students.length; i++) {
            students[i] = makeAddr(string.concat("student", vm.toString(i)));
            studentManagement.setStudentData(
                students[i],
                true,
                1,
                0,
                0,
                false,
                uint32(programId)
            );
        }
        
        // Record attendance for REGISTRATION_BURST_LIMIT students
        for (uint i = 0; i < 50; i++) { // REGISTRATION_BURST_LIMIT is 50
            attendanceTracking.recordAttendance(students[i], programId, true);
            vm.warp(block.timestamp + 2); // Wait for cooldown between each
        }
        
        // Try to record one more within the burst window
        vm.expectRevert(RateLimitExceeded.selector);
        attendanceTracking.recordAttendance(students[50], programId, true);
        
        // Wait for burst window reset
        vm.warp(block.timestamp + 1 hours + 1); // BURST_WINDOW is 1 hour
        
        // Should be able to record again
        attendanceTracking.recordAttendance(students[50], programId, true);
        
        vm.stopPrank();
    }
    
    function test_PauseAndUnpause() public {
        // Pause the contract
        vm.prank(masterAdmin);
        attendanceTracking.pause();
        
        // Verify contract is paused
        assertTrue(attendanceTracking.paused());
        
        // Record attendance while paused - this should actually work
        // since recordAttendance doesn't have the whenNotPaused modifier
        vm.prank(teacher);
        attendanceTracking.recordAttendance(student, programId, true);
        
        // Unpause the contract
        vm.prank(masterAdmin);
        attendanceTracking.unpause();
        
        // Verify contract is unpaused
        assertFalse(attendanceTracking.paused());
        
        // Should still work after unpausing (need to wait 24 hours due to daily limit)
        vm.warp(block.timestamp + 25 hours);
        vm.prank(teacher);
        attendanceTracking.recordAttendance(student, programId, true);
    }
    
    function testFuzz_AttendancePattern(bool[] calldata attendancePattern) public {
        vm.assume(attendancePattern.length > 0 && attendancePattern.length <= 10);
        
        vm.startPrank(teacher);
        
        uint32 expectedPresent = 0;
        uint32 expectedAbsent = 0;
        uint32 expectedConsecutive = 0;
        
        for (uint i = 0; i < attendancePattern.length; i++) {
            // Record attendance based on pattern
            attendanceTracking.recordAttendance(student, programId, attendancePattern[i]);
            
            // Update expected metrics
            if (attendancePattern[i]) {
                expectedPresent++;
                expectedConsecutive++;
            } else {
                expectedAbsent++;
                expectedConsecutive = 0;
            }
            
            // Wait for daily limit
            vm.warp(block.timestamp + 25 hours);
        }
        
        // Get actual metrics
        (
            uint32 totalPresent,
            uint32 totalAbsent,
            uint32 consecutivePresent,
            ,
            AttendanceTracking.AttendanceRecord[] memory history
        ) = attendanceTracking.getAttendanceMetrics(student, 1);
        
        // Verify metrics
        assertEq(totalPresent, expectedPresent);
        assertEq(totalAbsent, expectedAbsent);
        assertEq(consecutivePresent, expectedConsecutive);
        assertEq(history.length, attendancePattern.length);
        
        vm.stopPrank();
    }
    
    function test_GetStudentProgress() public {
        // Set student progress
        vm.startPrank(teacher);
        attendanceTracking.recordAttendance(student, programId, true);
        vm.stopPrank();
        
        // Check progress
        uint256 progress = attendanceTracking.getStudentProgress(student);
        assertEq(progress, 0); // Default is 0 until updated
    }
}