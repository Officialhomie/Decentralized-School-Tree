// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SchoolManagementBase.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Complete mock implementations of required interfaces
contract MockRevenueSystem is IRevenueSystem {
    uint256 private _certificateFee = 0.05 ether;
    uint256 private _programCreationFee = 0.1 ether;
    
    // Tracks custom fee structures set by schools
    mapping(address => uint256) public customProgramFees;
    mapping(address => uint256) public customSubscriptionFees;
    mapping(address => uint256) public customCertificateFees;
    mapping(address => uint256) public customRevenueShares;
    
    // Tracks certificate issuance
    mapping(address => mapping(uint256 => bool)) public certificatesIssued;
    
    // Tracks tuition payments
    mapping(address => uint256) public tuitionPayments;
    
    function certificateFee() external view returns (uint256) {
        return _certificateFee;
    }
    
    function programCreationFee() external view returns (uint256) {
        return _programCreationFee;
    }
    
    function issueCertificate(address studentAddress, uint256 batchId) external payable {
        require(msg.value >= _certificateFee, "Insufficient payment");
        certificatesIssued[studentAddress][batchId] = true;
    }
    
    function processTuitionPayment(address student, uint256 amount) external payable {
        require(msg.value >= amount, "Insufficient payment");
        tuitionPayments[student] += amount;
    }
    
    function setCustomFeeStructure(
        address school,
        uint256 programFee,
        uint256 subscriptionFee,
        uint256 certificateFee,
        uint256 revenueShare
    ) external {
        customProgramFees[school] = programFee;
        customSubscriptionFees[school] = subscriptionFee;
        customCertificateFees[school] = certificateFee;
        customRevenueShares[school] = revenueShare;
    }
}

contract MockStudentProfile is IStudentProfile {
    // Reputation data for students
    mapping(address => Reputation) private studentReputations;
    
    // Student to school mapping
    mapping(address => mapping(address => bool)) private studentSchools;
    
    // Student to program mapping
    mapping(address => uint256) private studentPrograms;
    
    // Program enrollment status
    mapping(address => mapping(uint256 => bool)) private programEnrollments;

    function getStudentReputation(address student) external view returns (Reputation memory) {
        return studentReputations[student];
    }
    
    function isStudentOfSchool(address student, address school) external view returns (bool) {
        return studentSchools[student][school];
    }
    
    function updateReputation(
        address student,
        uint256 attendancePoints,
        uint256 behaviorPoints,
        uint256 academicPoints
    ) external {
        Reputation storage rep = studentReputations[student];
        rep.attendancePoints = attendancePoints;
        rep.behaviorPoints = behaviorPoints;
        rep.academicPoints = academicPoints;
        rep.lastUpdateTime = block.timestamp;
    }
    
    function validateProgramEnrollment(address student, uint256 programId) external view returns (bool) {
        return programEnrollments[student][programId];
    }
    
    function getStudentProgram(address student) external view returns (uint256) {
        return studentPrograms[student];
    }
    
    // Helper functions for testing
    function setStudentSchool(address student, address school, bool isEnrolled) external {
        studentSchools[student][school] = isEnrolled;
    }
    
    function setStudentProgram(address student, uint256 programId) external {
        studentPrograms[student] = programId;
    }
    
    function setStudentProgramEnrollment(address student, uint256 programId, bool enrolled) external {
        programEnrollments[student][programId] = enrolled;
    }
}

contract MockTuitionSystem is ITuitionSystem {
    // Tracks tuition payment status
    mapping(address => mapping(address => mapping(uint256 => bool))) private tuitionPaid;
    mapping(address => mapping(address => mapping(uint256 => uint256))) private tuitionDueDates;
    
    function checkTuitionStatus(
        address organization,
        address student,
        uint256 term
    ) external view returns (bool isPaid, uint256 dueDate) {
        return (
            tuitionPaid[organization][student][term], 
            tuitionDueDates[organization][student][term]
        );
    }
    
    function recordTuitionPayment(address student, uint256 term) external {
        tuitionPaid[msg.sender][student][term] = true;
        tuitionDueDates[msg.sender][student][term] = block.timestamp + 90 days; // Example due date
    }
    
    // Helper function for setting test data
    function setTuitionStatus(
        address organization,
        address student,
        uint256 term,
        bool paid,
        uint256 dueDate
    ) external {
        tuitionPaid[organization][student][term] = paid;
        tuitionDueDates[organization][student][term] = dueDate;
    }
}

// A test implementation of SchoolManagementBase for testing
contract TestableSchoolManagementBase is SchoolManagementBase {
    // This function is just to expose the initialize function for testing
    // No additional implementation needed since we're testing the base contract
}

contract SchoolManagementBaseTest is Test {
    TestableSchoolManagementBase schoolManagement;
    MockRevenueSystem revenueSystem;
    MockStudentProfile studentProfile;
    MockTuitionSystem tuitionSystem;
    
    address masterAdmin;
    address organizationAdmin;
    address teacher;
    address student;
    address unauthorized;
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TEACHER_ROLE = keccak256("TEACHER_ROLE");
    bytes32 public constant MASTER_ADMIN_ROLE = keccak256("MASTER_ADMIN_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);
    
    event ContractRecoveredEvent(address indexed recoveredBy, uint256 timestamp);
    event SubscriptionRenewed(uint256 newEndTime);
    event SubscriptionEnded(uint256 timestamp);
    event ContractPaused(address indexed pauser);
    event ContractUnpaused(address indexed unpauser);
    event InitializationComplete(
        address indexed revenueSystem,
        address indexed studentProfile, 
        address indexed tuitionSystem,
        address masterAdmin,
        address organizationAdmin
    );
    event EthReceived(address indexed sender, uint256 amount);
    event FallbackCalled(address indexed sender, uint256 amount);
    event EmergencyWithdrawal(address indexed recipient, uint256 amount);
    event FeeStructureUpdated(
        uint256 programFee,
        uint256 certificateFee,
        uint256 subscriptionFee,
        uint256 revenueShare
    );
    
    function setUp() public {
        masterAdmin = makeAddr("masterAdmin");
        organizationAdmin = makeAddr("organizationAdmin");
        teacher = makeAddr("teacher");
        student = makeAddr("student");
        unauthorized = makeAddr("unauthorized");
        
        // Deploy mock contracts
        revenueSystem = new MockRevenueSystem();
        studentProfile = new MockStudentProfile();
        tuitionSystem = new MockTuitionSystem();
        
        // Deploy implementation
        TestableSchoolManagementBase implementation = new TestableSchoolManagementBase();
        
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
        
        // Get the proxied SchoolManagementBase
        schoolManagement = TestableSchoolManagementBase(payable(address(proxy)));
        
        // Set block timestamp to 1 to ensure consistent testing
        vm.warp(1);
        
        // Fund accounts for testing
        vm.deal(masterAdmin, 10 ether);
        vm.deal(organizationAdmin, 10 ether);
        vm.deal(teacher, 1 ether);
        vm.deal(address(schoolManagement), 1 ether);
    }
    
    function test_Initialization() public {
        // Verify that roles were set up correctly
        assertTrue(schoolManagement.hasRole(MASTER_ADMIN_ROLE, masterAdmin));
        assertTrue(schoolManagement.hasRole(ADMIN_ROLE, organizationAdmin));
        assertTrue(schoolManagement.hasRole(DEFAULT_ADMIN_ROLE, organizationAdmin));
        
        // Verify that the subscription was set
        assertTrue(schoolManagement.subscriptionEndTime() > block.timestamp);
        
        // Verify interfaces are correctly set
        assertEq(address(schoolManagement.revenueSystem()), address(revenueSystem));
        assertEq(address(schoolManagement.studentProfile()), address(studentProfile));
        assertEq(address(schoolManagement.tuitionSystem()), address(tuitionSystem));
    }
    
    function test_RenewSubscription() public {
        uint64 oldEndTime = schoolManagement.subscriptionEndTime();
        
        // Skip forward in time to approach end of subscription
        vm.warp(block.timestamp + 25 days);
        
        // Calculate the expected new end time
        uint64 expectedNewEndTime = uint64(block.timestamp + 30 days);
        
        // Renew the subscription
        vm.prank(organizationAdmin);
        vm.expectEmit(false, false, false, true);
        emit SubscriptionRenewed(expectedNewEndTime);
        schoolManagement.renewSubscription{value: 0.1 ether}();
        
        // Verify that subscription was extended
        uint64 newEndTime = schoolManagement.subscriptionEndTime();
        assertTrue(newEndTime > oldEndTime);
        assertEq(newEndTime, expectedNewEndTime);
    }
    
    function test_HandleSubscriptionExpiration() public {
        // Skip forward in time beyond subscription end
        vm.warp(schoolManagement.subscriptionEndTime() + 1);
        
        // Handle expiration
        vm.prank(organizationAdmin);
        vm.expectEmit(false, false, false, true);
        emit SubscriptionEnded(block.timestamp);
        schoolManagement.handleSubscriptionExpiration();
        
        // Contract should now be paused
        assertTrue(schoolManagement.paused());
    }
    
    function test_RevertWhen_HandleSubscriptionBeforeExpiration() public {
        // First make sure we have the right role
        vm.startPrank(organizationAdmin);
        schoolManagement.grantRole(ADMIN_ROLE, address(this));
        vm.stopPrank();
        
        // Try to handle expiration while still active
        vm.expectRevert(abi.encodeWithSelector(SubscriptionExpiredError.selector, schoolManagement.subscriptionEndTime()));
        schoolManagement.handleSubscriptionExpiration();
    }
    
    function test_RecoverContract() public {
        // Recover the contract
        vm.prank(masterAdmin);
        vm.expectEmit(true, false, false, true);
        emit ContractRecoveredEvent(masterAdmin, block.timestamp);
        schoolManagement.recoverContract();
        
        // Verify contract state
        assertTrue(schoolManagement.isRecovered());
        assertTrue(schoolManagement.paused());
    }
    
    function test_RevertWhen_RecoverAlreadyRecovered() public {
        // First recovery
        vm.prank(masterAdmin);
        schoolManagement.recoverContract();
        
        // Try to recover again
        vm.prank(masterAdmin);
        vm.expectRevert(abi.encodeWithSelector(ContractRecovered.selector, masterAdmin, block.timestamp));
        schoolManagement.recoverContract();
    }
    
    function test_RevertWhen_UnauthorizedRecovery() public {
        // Try to recover without proper role
        vm.prank(unauthorized);
        vm.expectRevert();
        schoolManagement.recoverContract();
    }
    
    function test_EmergencyWithdraw() public {
        // Send some ETH to the contract
        vm.deal(address(schoolManagement), 5 ether);
        
        // Initial master admin balance
        uint256 initialBalance = masterAdmin.balance;
        
        // Perform emergency withdrawal
        vm.prank(masterAdmin);
        vm.expectEmit(true, false, false, true);
        emit EmergencyWithdrawal(masterAdmin, 5 ether);
        schoolManagement.emergencyWithdraw();
        
        // Verify balances
        assertEq(address(schoolManagement).balance, 0);
        assertEq(masterAdmin.balance, initialBalance + 5 ether);
    }
    
    function test_RevertWhen_EmergencyWithdrawEmpty() public {
        // Ensure contract has no balance
        vm.deal(address(schoolManagement), 0);
        
        // Try to withdraw
        vm.prank(masterAdmin);
        vm.expectRevert(InsufficientPayment.selector);
        schoolManagement.emergencyWithdraw();
    }
    
    function test_UpdateProgramFees() public {
        uint256 programFee = 0.2 ether;
        uint256 certificateFee = 0.05 ether;
        uint256 subscriptionFee = 0.3 ether;
        uint256 revenueShare = 15; // 15%
        
        // Update fees
        vm.prank(organizationAdmin);
        vm.expectEmit(false, false, false, true);
        emit FeeStructureUpdated(programFee, certificateFee, subscriptionFee, revenueShare);
        schoolManagement.updateProgramFees(programFee, certificateFee, subscriptionFee, revenueShare);
        
        // Verify the fee structure was updated in the revenue system
        assertEq(revenueSystem.customProgramFees(address(schoolManagement)), programFee);
        assertEq(revenueSystem.customSubscriptionFees(address(schoolManagement)), subscriptionFee);
        assertEq(revenueSystem.customCertificateFees(address(schoolManagement)), certificateFee);
        assertEq(revenueSystem.customRevenueShares(address(schoolManagement)), revenueShare);
    }
    
    function test_RevertWhen_InvalidFeeUpdate() public {
        // Test with zero fees
        vm.prank(organizationAdmin);
        vm.expectRevert(InvalidInput.selector);
        schoolManagement.updateProgramFees(0, 0.05 ether, 0.3 ether, 15);
        
        // Test with invalid revenue share
        vm.prank(organizationAdmin);
        vm.expectRevert(InvalidInput.selector);
        schoolManagement.updateProgramFees(0.2 ether, 0.05 ether, 0.3 ether, 101); // Over 100%
    }
    
    function test_PauseAndUnpause() public {
        // Pause the contract
        vm.prank(masterAdmin);
        vm.expectEmit(true, false, false, false);
        emit ContractPaused(masterAdmin);
        schoolManagement.pause();
        
        // Verify contract is paused
        assertTrue(schoolManagement.paused());
        
        // Unpause the contract
        vm.prank(masterAdmin);
        vm.expectEmit(true, false, false, false);
        emit ContractUnpaused(masterAdmin);
        schoolManagement.unpause();
        
        // Verify contract is not paused
        assertFalse(schoolManagement.paused());
    }
    
    function test_ReceiveFunction() public {
        // Test receive function
        vm.prank(organizationAdmin);
        vm.expectEmit(true, false, false, true);
        emit EthReceived(organizationAdmin, 0.5 ether);
        (bool success, ) = address(schoolManagement).call{value: 0.5 ether}("");
        assertTrue(success);
    }
    
    function test_FallbackFunction() public {
        // Test fallback function by calling a non-existent function
        vm.prank(organizationAdmin);
        vm.expectEmit(true, false, false, true);
        emit FallbackCalled(organizationAdmin, 0.5 ether);
        (bool success, ) = address(schoolManagement).call{value: 0.5 ether}(abi.encodeWithSignature("nonExistentFunction()"));
        assertTrue(success);
    }
    
    function test_SubscriptionActiveModifier() public {
        // First make sure we have the right role
        vm.startPrank(organizationAdmin);
        schoolManagement.grantRole(ADMIN_ROLE, address(this));
        vm.stopPrank();
        
        // Skip past subscription end
        vm.warp(schoolManagement.subscriptionEndTime() + 1);
        
        // Create a function that uses the subscriptionActive modifier (renewSubscription does)
        // This should fail when subscription has expired
        vm.expectRevert(abi.encodeWithSelector(SubscriptionExpiredError.selector, schoolManagement.subscriptionEndTime()));
        schoolManagement.updateProgramFees(0.2 ether, 0.05 ether, 0.3 ether, 15);
    }
    
    function test_NotRecoveredModifier() public {
        // First recover the contract
        vm.prank(masterAdmin);
        schoolManagement.recoverContract();
        
        // Try an operation that requires notRecovered modifier
        // We'll use updateProgramFees which we know has the notRecovered modifier
        
        // Grant our test contract the ADMIN_ROLE
        vm.startPrank(organizationAdmin);
        schoolManagement.grantRole(ADMIN_ROLE, address(this));
        vm.stopPrank();
        
        // This should revert because the contract is recovered
        vm.expectRevert(abi.encodeWithSelector(ContractRecovered.selector, masterAdmin, block.timestamp));
        schoolManagement.updateProgramFees(0.2 ether, 0.05 ether, 0.3 ether, 15);
    }
    
    function test_GeneralRateLimited() public {
        // Use a custom test function that we know has the generalRateLimited modifier
        // First check if updateProgramFees has the generalRateLimited modifier
        
        // Grant our test contract the ADMIN_ROLE
        vm.startPrank(organizationAdmin);
        schoolManagement.grantRole(ADMIN_ROLE, address(this));
        vm.stopPrank();
        
        // First call
        schoolManagement.updateProgramFees(0.2 ether, 0.05 ether, 0.3 ether, 15);
        
        // Try again immediately - should be rate limited
        vm.expectRevert(OperationTooFrequent.selector);
        schoolManagement.updateProgramFees(0.3 ether, 0.06 ether, 0.4 ether, 20);
        
        // Skip forward past the cooldown period
        vm.warp(block.timestamp + schoolManagement.GENERAL_COOLDOWN() + 1);
        
        // Should work now
        schoolManagement.updateProgramFees(0.3 ether, 0.06 ether, 0.4 ether, 20);
    }
    
    function test_InvalidAddressInitialization() public {
        // Deploy a new implementation
        TestableSchoolManagementBase newImplementation = new TestableSchoolManagementBase();
        
        // Try to initialize with invalid addresses
        vm.expectRevert(InvalidAddress.selector);
        new ERC1967Proxy(
            address(newImplementation),
            abi.encodeWithSelector(
                SchoolManagementBase.initialize.selector,
                address(0), // Invalid revenue system address
                address(studentProfile),
                address(tuitionSystem),
                masterAdmin,
                organizationAdmin
            )
        );
    }
}