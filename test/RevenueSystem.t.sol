// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/RevenueSystem.sol";

// Mock contracts for testing
contract MockSchoolManagement is ISchoolManagement {
    mapping(uint256 => bool) public programs;
    mapping(uint256 => ProgramInfo) public programDetails;
    mapping(address => uint256) public studentPrograms;
    uint256 public currentProgramFee;
    uint256 public currentCertificateFee;

    struct ProgramInfo {
        string name;
        uint256 termFee;
    }

    function setProgramActive(uint256 programId, bool active) external {
        programs[programId] = active;
    }

    function setProgram(uint256 programId, string memory name, uint256 fee) external {
        programDetails[programId] = ProgramInfo(name, fee);
        currentProgramFee = fee;
    }

    function setStudentProgram(address student, uint256 programId) external {
        studentPrograms[student] = programId;
    }

    function isProgramActive(uint256 programId) external view returns (bool) {
        return programs[programId];
    }

    function getProgramDetails(uint256 programId) external view returns (string memory name, uint256 termFee) {
        ProgramInfo memory info = programDetails[programId];
        return (info.name, currentProgramFee); // Return the updated fee
    }

    function getStudentProgram(address student) external view returns (uint256) {
        return studentPrograms[student];
    }

    function updateProgramFees(uint256 programFee, uint256 certificateFee) external {
        currentProgramFee = programFee;
        currentCertificateFee = certificateFee;
        // Update all existing programs with new fee
        // This is a simplified implementation for testing
    }
}

contract MockTuitionSystem is ITuitionSystem {
    mapping(bytes32 => bool) public tuitionStatus;

    function setTuitionStatus(address school, address student, uint256 term, bool status) external {
        bytes32 key = keccak256(abi.encodePacked(school, student, term));
        tuitionStatus[key] = status;
    }

    function checkTuitionStatus(address school, address student, uint256 term) external view returns (bool isPaid, uint256 dueDate) {
        bytes32 key = keccak256(abi.encodePacked(school, student, term));
        return (tuitionStatus[key], block.timestamp + 30 days);
    }
}

contract RevenueSystemTest is Test {
    RevenueSystem public revenueSystem;
    MockSchoolManagement public schoolManagement;
    MockTuitionSystem public tuitionSystem;

    address public masterAdmin;
    address public school;
    address public student;
    address public randomUser;

    uint256 public constant DEFAULT_PROGRAM_FEE = 1 ether;
    uint256 public constant DEFAULT_SUBSCRIPTION_FEE = 0.5 ether;
    uint256 public constant DEFAULT_CERTIFICATE_FEE = 0.1 ether;
    uint256 public constant DEFAULT_REVENUE_SHARE = 20; // 20%

    event TuitionProcessed(address school, address student, uint256 amount);
    event CertificateIssued(address school, address student, uint256 programId);
    event FeeStructureUpdated(address school, uint256 programFee, uint256 subscriptionFee, uint256 certificateFee, uint256 revenueShare);


    event SubscriptionRenewed(
        address indexed school,
        uint256 validUntil,
        uint256 amount
    );
    
    event RevenueReceived(
        address indexed school,
        uint256 indexed programId,
        uint256 amount,
        uint256 platformShare,
        uint256 schoolShare
    );
    event ProgramRevenueLocked(
        address indexed school,
        uint256 indexed programId,
        uint256 amount
    );

    event RevenueWithdrawn(
        address indexed school,
        uint256 amount,
        uint256 timestamp
    );

    function setUp() public {
        masterAdmin = address(1);
        school = address(2);
        student = address(3);
        randomUser = address(4);

        schoolManagement = new MockSchoolManagement();
        tuitionSystem = new MockTuitionSystem();

        revenueSystem = new RevenueSystem();
        revenueSystem.initialize(
            address(schoolManagement),
            address(tuitionSystem),
            masterAdmin,
            DEFAULT_PROGRAM_FEE,
            DEFAULT_SUBSCRIPTION_FEE,
            DEFAULT_CERTIFICATE_FEE,
            DEFAULT_REVENUE_SHARE
        );

        vm.startPrank(masterAdmin);
        revenueSystem.grantRole(revenueSystem.SCHOOL_ROLE(), school);
        vm.stopPrank();

        schoolManagement.setProgramActive(1, true);
        schoolManagement.setProgram(1, "Test Program", 1 ether);
        schoolManagement.setStudentProgram(student, 1);

        vm.deal(school, 100 ether);
        vm.deal(randomUser, 100 ether);
    }



    function test_RevertEarlyWithdrawal() public {
        vm.startPrank(school);
        revenueSystem.renewSubscription{value: DEFAULT_SUBSCRIPTION_FEE}();
        revenueSystem.processTuitionPayment{value: 1 ether}(student, 1 ether);
        
        // Try to withdraw immediately
        vm.expectRevert(TooSoonToWithdraw.selector);
        revenueSystem.withdrawSchoolRevenue();
        vm.stopPrank();
    }

    // Test zero balance withdrawal
    function test_RevertZeroBalanceWithdrawal() public {
        vm.startPrank(school);
        revenueSystem.renewSubscription{value: DEFAULT_SUBSCRIPTION_FEE}();
        
        vm.expectRevert(NoRevenueToWithdraw.selector);
        revenueSystem.withdrawSchoolRevenue();
        vm.stopPrank();
    }

    function test_RevertExpiredSubscription() public {
        vm.startPrank(school);
        
        vm.expectRevert(SubscriptionExpired.selector);
        revenueSystem.processTuitionPayment{value: 1 ether}(student, 1 ether);
        
        vm.stopPrank();
    }

    function test_RevertInvalidPaymentAmount() public {
        vm.startPrank(school);
        revenueSystem.renewSubscription{value: DEFAULT_SUBSCRIPTION_FEE}();
        
        vm.expectRevert(InvalidPaymentAmount.selector);
        revenueSystem.processTuitionPayment{value: 0.5 ether}(student, 1 ether);
        
        vm.stopPrank();
    }



    function testInitialization() public view {
        assertEq(revenueSystem.hasRole(revenueSystem.MASTER_ADMIN_ROLE(), masterAdmin), true);
        assertEq(address(revenueSystem.schoolManagement()), address(schoolManagement));
        assertEq(address(revenueSystem.tuitionSystem()), address(tuitionSystem));
    }

    function testSubscriptionRenewal() public {
        vm.startPrank(school);
        revenueSystem.renewSubscription{value: DEFAULT_SUBSCRIPTION_FEE}();
        
        uint256 expectedEndTime = block.timestamp + 30 days;
        assertEq(revenueSystem.subscriptionEndTimes(school), expectedEndTime);
        vm.stopPrank();
    }

    function testTuitionPayment() public {
        vm.startPrank(school);
        
        // Test subscription renewal with correct event parameters
        vm.expectEmit(true, false, false, true);
        emit SubscriptionRenewed(
            school,
            block.timestamp + 30 days,
            DEFAULT_SUBSCRIPTION_FEE
        );
        revenueSystem.renewSubscription{value: DEFAULT_SUBSCRIPTION_FEE}();

        // Calculate expected values
        uint256 paymentAmount = 1 ether;
        uint256 programId = schoolManagement.getStudentProgram(student);
        uint256 expectedPlatformShare = (paymentAmount * DEFAULT_REVENUE_SHARE) / 100;
        uint256 expectedSchoolShare = paymentAmount - expectedPlatformShare;

        // Test tuition payment event
        vm.expectEmit(true, true, false, true);
        emit RevenueReceived(
            school,
            programId,
            paymentAmount,
            expectedPlatformShare,
            expectedSchoolShare
        );

        revenueSystem.processTuitionPayment{value: paymentAmount}(student, paymentAmount);
        vm.stopPrank();

        // Verify the state changes
        (uint256 total, uint256 platformShare, uint256 schoolShare,) = revenueSystem.getRevenueDetails(school);
        assertEq(total, paymentAmount, "Total revenue mismatch");
        assertEq(platformShare, expectedPlatformShare, "Platform share mismatch");
        assertEq(schoolShare, expectedSchoolShare, "School share mismatch");
    }

    function test_RevertCertificateWithoutTuition() public {
        vm.startPrank(school);
        revenueSystem.renewSubscription{value: DEFAULT_SUBSCRIPTION_FEE}();
        
        // Explicitly ensure tuition is not paid
        tuitionSystem.setTuitionStatus(school, student, 0, false);
        
        // This should fail because tuition is not paid
        vm.expectRevert(TuitionNotPaid.selector);
        revenueSystem.issueCertificate{value: DEFAULT_CERTIFICATE_FEE}(student, 1);
        vm.stopPrank();
    }

    function test_RevertInsufficientCertificateFee() public {
        vm.startPrank(school);
        revenueSystem.renewSubscription{value: DEFAULT_SUBSCRIPTION_FEE}();
        tuitionSystem.setTuitionStatus(school, student, 0, true);

        // Try to issue certificate with insufficient fee
        vm.expectRevert(InsufficientFee.selector);
        revenueSystem.issueCertificate{value: DEFAULT_CERTIFICATE_FEE - 0.01 ether}(student, 1);
        vm.stopPrank();
    }

    function test_RevertInvalidCustomFeeStructure() public {
        vm.startPrank(masterAdmin);
        
        // Try to set invalid revenue share (100 or greater)
        vm.expectRevert(InvalidRevenueSharePercentage.selector);
        revenueSystem.setCustomFeeStructure(
            school,
            DEFAULT_PROGRAM_FEE,
            DEFAULT_SUBSCRIPTION_FEE,
            DEFAULT_CERTIFICATE_FEE,
            100 // This should fail as per the updated contract
        );
        vm.stopPrank();
    }

    function testFeeSynchronization() public {
        // First activate a program in SchoolManagement
        schoolManagement.setProgramActive(1, true);
        
        uint256 newProgramFee = 2 ether;
        
        // Set a custom fee structure for the school through the master admin
        vm.startPrank(masterAdmin);
        revenueSystem.setCustomFeeStructure(
            school,
            newProgramFee,    // Program fee
            1 ether,          // Subscription fee  
            0.2 ether,        // Certificate fee
            15               // Revenue share %
        );
        vm.stopPrank();

        // Have the school sync their new fee structure
        vm.startPrank(school);
        revenueSystem.syncFeeStructure(school);
        vm.stopPrank();
        
        // Verify the SchoolManagement contract was updated with the new program fee
        (, uint256 termFee) = schoolManagement.getProgramDetails(1);
        assertEq(termFee, newProgramFee, "Program fee was not properly synced");
    }



    function testCertificateIssuance() public {
        // Setup subscription and tuition status
        vm.startPrank(school);
        revenueSystem.renewSubscription{value: DEFAULT_SUBSCRIPTION_FEE}();
        tuitionSystem.setTuitionStatus(school, student, 0, true);

        // Issue certificate
        revenueSystem.issueCertificate{value: DEFAULT_CERTIFICATE_FEE}(student, 1);
        vm.stopPrank();
    }

    function testRevenueWithdrawal() public {
        // Setup and process payment
        vm.startPrank(school);
        revenueSystem.renewSubscription{value: DEFAULT_SUBSCRIPTION_FEE}();
        revenueSystem.processTuitionPayment{value: 1 ether}(student, 1 ether);

        // Wait 1 day
        vm.warp(block.timestamp + 1 days);

        // Record initial balance
        uint256 initialBalance = address(school).balance;

        // Withdraw revenue
        revenueSystem.withdrawSchoolRevenue();

        // Verify withdrawal
        uint256 expectedShare = 1 ether - (1 ether * DEFAULT_REVENUE_SHARE / 100);
        assertEq(address(school).balance - initialBalance, expectedShare);
        vm.stopPrank();
    }

    function testCustomFeeStructure() public {
        uint256 customProgramFee = 2 ether;
        uint256 customSubscriptionFee = 1 ether;
        uint256 customCertificateFee = 0.2 ether;
        uint256 customRevenueShare = 15;

        vm.startPrank(masterAdmin);
        revenueSystem.setCustomFeeStructure(
            school,
            customProgramFee,
            customSubscriptionFee,
            customCertificateFee,
            customRevenueShare
        );
        vm.stopPrank();

        // Process payment with custom fee structure
        vm.startPrank(school);
        revenueSystem.renewSubscription{value: customSubscriptionFee}();
        revenueSystem.processTuitionPayment{value: 1 ether}(student, 1 ether);
        vm.stopPrank();

        // Verify custom revenue share
        (,uint256 platformShare,,) = revenueSystem.getRevenueDetails(school);
        assertEq(platformShare, 1 ether * customRevenueShare / 100);
    }



    function testExpiredSubscriptionRevert() public {
        vm.startPrank(school);
        
        vm.expectRevert(SubscriptionExpired.selector);
        revenueSystem.processTuitionPayment{value: 1 ether}(student, 1 ether);
        
        vm.stopPrank();
    }




    function testPauseUnpause() public {
        // Setup initial state
        vm.startPrank(school);
        revenueSystem.renewSubscription{value: DEFAULT_SUBSCRIPTION_FEE}();
        vm.stopPrank();

        // Pause contract
        vm.startPrank(masterAdmin);
        revenueSystem.pause();

        // Try operation while paused
        vm.startPrank(school);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        revenueSystem.processTuitionPayment{value: 1 ether}(student, 1 ether);
        vm.stopPrank();

        // Unpause and verify operations work again
        vm.startPrank(masterAdmin);
        revenueSystem.unpause();
        vm.stopPrank();

        // Verify operations work after unpause
        vm.startPrank(school);
        revenueSystem.processTuitionPayment{value: 1 ether}(student, 1 ether);
        vm.stopPrank();
    }


    function testDirectTransferReverts() public {
        vm.startPrank(randomUser);
        
        // Convert string to bytes
        vm.expectRevert(DirectTransfersNotAllowed.selector);
        
        // Try to send ether directly
        payable(address(revenueSystem)).transfer(1 ether);
        
        vm.stopPrank();
    }

    function testInvalidPaymentAmountRevert() public {
        vm.startPrank(school);
        revenueSystem.renewSubscription{value: DEFAULT_SUBSCRIPTION_FEE}();
        
        vm.expectRevert(InvalidPaymentAmount.selector);
        revenueSystem.processTuitionPayment{value: 0.5 ether}(student, 1 ether);
        
        vm.stopPrank();
    }

    // Test pause/unpause with separate tests for better clarity
    function testPause() public {
        vm.startPrank(masterAdmin);
        revenueSystem.pause();
        assertTrue(revenueSystem.paused());
        vm.stopPrank();
    }

    function testUnpause() public {
        vm.startPrank(masterAdmin);
        revenueSystem.pause();
        revenueSystem.unpause();
        assertFalse(revenueSystem.paused());
        vm.stopPrank();
    }

    function testPausedOperationRevert() public {
        // Setup
        vm.startPrank(school);
        revenueSystem.renewSubscription{value: DEFAULT_SUBSCRIPTION_FEE}();
        vm.stopPrank();

        // Pause contract
        vm.prank(masterAdmin);
        revenueSystem.pause();

        // Test operation while paused
        vm.startPrank(school);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        revenueSystem.processTuitionPayment{value: 1 ether}(student, 1 ether);
        vm.stopPrank();
    }
    
    function testConsecutiveSubscriptionRenewals() public {
        vm.startPrank(school);
        
        // First renewal
        revenueSystem.renewSubscription{value: DEFAULT_SUBSCRIPTION_FEE}();
        uint256 firstEndTime = revenueSystem.subscriptionEndTimes(school);
        
        // Second renewal before expiration
        vm.warp(block.timestamp + 15 days);
        revenueSystem.renewSubscription{value: DEFAULT_SUBSCRIPTION_FEE}();
        
        // Should extend from previous end time
        assertEq(revenueSystem.subscriptionEndTimes(school), firstEndTime + 30 days);
        vm.stopPrank();
    }

    // Test withdrawal time restriction


    // Test certificate issuance without paid tuition


    // Test default fee structure update
    function testUpdateDefaultFeeStructure() public {
        vm.startPrank(masterAdmin);
        
        uint256 newProgramFee = 2 ether;
        uint256 newSubscriptionFee = 0.8 ether;
        uint256 newCertificateFee = 0.15 ether;
        uint256 newRevenueShare = 25;
        
        revenueSystem.updateDefaultFeeStructure(
            newProgramFee,
            newSubscriptionFee,
            newCertificateFee,
            newRevenueShare
        );
        
        // Test new school gets new default fees
        address newSchool = address(5);
        revenueSystem.grantRole(revenueSystem.SCHOOL_ROLE(), newSchool);
        vm.stopPrank();
        
        // Fund new school
        vm.deal(newSchool, 100 ether);
        
        // Test with new fees
        vm.startPrank(newSchool);
        revenueSystem.renewSubscription{value: newSubscriptionFee}();
        vm.stopPrank();
    }

    // Test program revenue tracking
    function testProgramRevenueTracking() public {
        vm.startPrank(school);
        revenueSystem.renewSubscription{value: DEFAULT_SUBSCRIPTION_FEE}();
        
        uint256 payment1 = 1 ether;
        uint256 payment2 = 0.5 ether;
        
        revenueSystem.processTuitionPayment{value: payment1}(student, payment1);
        revenueSystem.processTuitionPayment{value: payment2}(student, payment2);
        
        uint256 programRevenue = revenueSystem.getProgramRevenue(school, 1);
        assertEq(programRevenue, payment1 + payment2);
        vm.stopPrank();
    }

    // Test role management
    function testRoleManagement() public {
        address newAdmin = address(6);
        
        vm.startPrank(masterAdmin);
        revenueSystem.grantRole(revenueSystem.ADMIN_ROLE(), newAdmin);
        assertTrue(revenueSystem.hasRole(revenueSystem.ADMIN_ROLE(), newAdmin));
        
        revenueSystem.revokeRole(revenueSystem.ADMIN_ROLE(), newAdmin);
        assertFalse(revenueSystem.hasRole(revenueSystem.ADMIN_ROLE(), newAdmin));
        vm.stopPrank();
    }

    // Test unauthorized actions
    function testUnauthorizedActions() public {
        vm.startPrank(randomUser);
        
        vm.expectRevert();
        revenueSystem.pause();
        
        vm.expectRevert();
        revenueSystem.setCustomFeeStructure(school, 1 ether, 1 ether, 1 ether, 20);
        
        vm.expectRevert();
        revenueSystem.updateDefaultFeeStructure(1 ether, 1 ether, 1 ether, 20);
        
        vm.stopPrank();
    }

    // Test multiple revenue withdrawals
    function testMultipleWithdrawals() public {
        vm.startPrank(school);
        revenueSystem.renewSubscription{value: DEFAULT_SUBSCRIPTION_FEE}();
        
        // First payment and withdrawal
        revenueSystem.processTuitionPayment{value: 1 ether}(student, 1 ether);
        vm.warp(block.timestamp + 1 days);
        revenueSystem.withdrawSchoolRevenue();
        
        // Second payment and withdrawal
        revenueSystem.processTuitionPayment{value: 0.5 ether}(student, 0.5 ether);
        vm.warp(block.timestamp + 1 days);
        revenueSystem.withdrawSchoolRevenue();
        
        // Verify no remaining balance
        (,, uint256 schoolShare,) = revenueSystem.getRevenueDetails(school);
        assertEq(schoolShare, 0);
        vm.stopPrank();
    }
}