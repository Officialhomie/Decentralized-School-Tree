// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SchoolManagementFactory.sol";

// This is a fake contract that pretends to be a school management system
// It has empty functions that simulate what a real school system would do
contract MockSchoolManagement {
    // This function pretends to set up a new school with basic info like who runs it
    function initialize(
        address revenueSystem,
        address studentProfile,
        address factory,
        address masterAdmin,
        address organizationAdmin
    ) external {}
    
    // This function pretends to give special permissions to someone
    function grantRole(bytes32 role, address account) external {}
}

// This is a fake contract that pretends to handle money stuff
contract MockRevenueSystem {
    // This function pretends to set up fees for a specific school
    function setCustomFeeStructure(
        address school,
        uint256 programFee,
        uint256 subscriptionFee,
        uint256 certificateFee,
        uint256 revenueShare
    ) external {}
}

// This is a fake contract that pretends to manage student information
contract MockStudentProfile {
    // This function pretends to turn on a school in the student system
    function activateSchool(address school) external {}
}

// This is the main testing contract that checks if our school factory works correctly
contract SchoolManagementFactoryTest is Test {
    // These are variables we'll use throughout our tests
    SchoolManagementFactory factory;
    MockSchoolManagement implementation;
    MockRevenueSystem revenueSystem;
    MockStudentProfile studentProfile;
    
    address masterAdmin;
    address organizationAdmin;
    uint256 constant SUBSCRIPTION_FEE = 1 ether;
    
    // This event gets triggered when a new school is created
    event ContractDeployed(
        address indexed newContract, 
        address indexed organization,
        uint256 deploymentTime,
        uint256 subscriptionEnd,
        uint256 subscriptionDuration
    );
    
    // This event gets triggered when a school renews their subscription
    event SubscriptionRenewed(
        address indexed organization, 
        uint256 newEndTime,
        uint256 amountPaid
    );

    // This function runs before each test to set everything up fresh
    function setUp() public {
        // Create fake addresses for our admins
        masterAdmin = makeAddr("masterAdmin");
        organizationAdmin = makeAddr("organizationAdmin");
        
        // Give some test money to accounts
        vm.deal(address(this), 100 ether);
        vm.deal(masterAdmin, 100 ether);
        
        // Create our fake contracts
        implementation = new MockSchoolManagement();
        revenueSystem = new MockRevenueSystem();
        studentProfile = new MockStudentProfile();
        
        // Create the main factory we're testing
        factory = new SchoolManagementFactory(address(implementation));
        
        // Set up default settings for new schools
        SchoolManagementFactory.DeploymentConfig memory defaultConfig = SchoolManagementFactory.DeploymentConfig({
            programFee: 0.1 ether,
            subscriptionFee: SUBSCRIPTION_FEE,
            certificateFee: 0.05 ether,
            revenueShare: 10,
            subscriptionDuration: 30 days
        });
        
        // Start up the factory with these settings
        vm.prank(masterAdmin);
        factory.initialize(
            address(implementation),
            address(revenueSystem),
            address(studentProfile),
            masterAdmin,
            defaultConfig
        );
    }

    // This test makes sure the factory was set up correctly
    function test_Initialize() public view {
        // Check if all the addresses and permissions are set right
        assert(address(factory.revenueSystem()) == address(revenueSystem));
        assert(address(factory.studentProfile()) == address(studentProfile));
        assert(factory.hasRole(factory.MASTER_ADMIN_ROLE(), masterAdmin));
        assert(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), masterAdmin));
    }

    // This test checks if we can create a new school successfully
    function test_DeploySchoolManagement() public {
        // Set up the school's configuration
        SchoolManagementFactory.DeploymentConfig memory config = SchoolManagementFactory.DeploymentConfig({
            programFee: 0.1 ether,
            subscriptionFee: SUBSCRIPTION_FEE,
            certificateFee: 0.05 ether,
            revenueShare: 10,
            subscriptionDuration: 30 days
        });

        // Create the new school
        vm.prank(masterAdmin);
        address newContract = factory.deploySchoolManagement{value: SUBSCRIPTION_FEE}(
            organizationAdmin,
            config
        );
        
        // Make sure the school was created
        assertTrue(newContract != address(0));
        
        // Get the school's information
        (
            address contractAddress,
            bool isActive,
            ,
            uint256 subscriptionDuration,
            bool isInGracePeriod
        ) = factory.getOrganizationDetails(organizationAdmin);
        
        // Check if everything is set up right
        assertEq(contractAddress, newContract);
        assertTrue(isActive);
        assertEq(subscriptionDuration, 30 days);
        assertFalse(isInGracePeriod);
    }

    // This test makes sure you can't create a school without paying enough
    function test_RevertWhen_DeployWithInsufficientFee() public {
        // Set up school configuration
        SchoolManagementFactory.DeploymentConfig memory config = SchoolManagementFactory.DeploymentConfig({
            programFee: 0.1 ether,
            subscriptionFee: SUBSCRIPTION_FEE,
            certificateFee: 0.05 ether,
            revenueShare: 10,
            subscriptionDuration: 30 days
        });

        // Try to create school with not enough money
        vm.prank(masterAdmin);
        vm.expectRevert(InsufficientSubscriptionFee.selector);
        factory.deploySchoolManagement{value: 0.5 ether}(
            organizationAdmin,
            config
        );
    }

    // This test checks if the system catches invalid school settings
    function test_RevertWhen_DeployWithInvalidConfig() public {
        // Set up bad configuration (revenue share too high)
        SchoolManagementFactory.DeploymentConfig memory invalidConfig = SchoolManagementFactory.DeploymentConfig({
            programFee: 0.1 ether,
            subscriptionFee: SUBSCRIPTION_FEE,
            certificateFee: 0.05 ether,
            revenueShare: 101, // This is too high
            subscriptionDuration: 30 days
        });

        // Try to create school with bad settings
        vm.prank(masterAdmin);
        vm.expectRevert(InvalidRevenueShare.selector);
        factory.deploySchoolManagement{value: SUBSCRIPTION_FEE}(
            organizationAdmin,
            invalidConfig
        );
    }

    // This test checks if schools can renew their subscription
    function test_RenewSubscription() public {
        // First create a school
        SchoolManagementFactory.DeploymentConfig memory config = SchoolManagementFactory.DeploymentConfig({
            programFee: 0.1 ether,
            subscriptionFee: SUBSCRIPTION_FEE,
            certificateFee: 0.05 ether,
            revenueShare: 10,
            subscriptionDuration: 30 days
        });

        // Create the school
        vm.startPrank(masterAdmin);
        factory.deploySchoolManagement{value: SUBSCRIPTION_FEE}(
            organizationAdmin,
            config
        );
        vm.stopPrank();

        // Fast forward 15 days
        vm.warp(block.timestamp + 15 days);

        // Give the school admin some money
        vm.deal(organizationAdmin, SUBSCRIPTION_FEE);

        // Renew the subscription
        vm.startPrank(organizationAdmin);
        factory.renewSubscription{value: SUBSCRIPTION_FEE}(organizationAdmin);
        vm.stopPrank();

        // Check if renewal worked right
        (,, uint256 subscriptionEnd,,) = factory.getOrganizationDetails(organizationAdmin);
        assertEq(subscriptionEnd, block.timestamp + 45 days);
    }

    // This test checks if we can turn off a school's access
    function test_DeactivateOrganization() public {
        // First create a school
        SchoolManagementFactory.DeploymentConfig memory config = SchoolManagementFactory.DeploymentConfig({
            programFee: 0.1 ether,
            subscriptionFee: SUBSCRIPTION_FEE,
            certificateFee: 0.05 ether,
            revenueShare: 10,
            subscriptionDuration: 30 days
        });

        // Create the school
        vm.prank(masterAdmin);
        factory.deploySchoolManagement{value: SUBSCRIPTION_FEE}(
            organizationAdmin,
            config
        );

        // Turn off the school
        vm.prank(masterAdmin);
        factory.deactivateOrganization(organizationAdmin);

        // Check if it's really turned off
        (,bool isActive,,,) = factory.getOrganizationDetails(organizationAdmin);
        assertFalse(isActive);
    }

    // This test checks if we can withdraw collected fees
    function test_WithdrawFees() public {
        // First create a school to collect some fees
        SchoolManagementFactory.DeploymentConfig memory config = SchoolManagementFactory.DeploymentConfig({
            programFee: 0.1 ether,
            subscriptionFee: SUBSCRIPTION_FEE,
            certificateFee: 0.05 ether,
            revenueShare: 10,
            subscriptionDuration: 30 days
        });

        // Create the school
        vm.prank(masterAdmin);
        factory.deploySchoolManagement{value: SUBSCRIPTION_FEE}(
            organizationAdmin,
            config
        );

        // Create someone to receive the fees
        address payable recipient = payable(makeAddr("recipient"));
        uint256 initialBalance = recipient.balance;

        // Withdraw the fees
        vm.prank(masterAdmin);
        factory.withdrawFees(recipient, SUBSCRIPTION_FEE);

        // Check if the money was sent correctly
        assertEq(recipient.balance - initialBalance, SUBSCRIPTION_FEE);
        assertEq(factory.totalFeesCollected(), 0);
    }

    // This test checks if we can pause and unpause the system
    function test_PauseAndUnpause() public {
        vm.startPrank(masterAdmin);
        
        // Stop the system
        factory.pause();
        assertTrue(factory.paused());
        
        // Try to create a school while system is stopped
        SchoolManagementFactory.DeploymentConfig memory config = SchoolManagementFactory.DeploymentConfig({
            programFee: 0.1 ether,
            subscriptionFee: SUBSCRIPTION_FEE,
            certificateFee: 0.05 ether,
            revenueShare: 10,
            subscriptionDuration: 30 days
        });

        // This should fail because system is paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        factory.deploySchoolManagement{value: SUBSCRIPTION_FEE}(
            organizationAdmin,
            config
        );

        // Start the system again
        factory.unpause();
        assertFalse(factory.paused());
        
        vm.stopPrank();
    }

    // This test makes sure random people can't use admin functions
    function test_RevertWhen_UnauthorizedAccess() public {
        // Create a random person
        address unauthorized = makeAddr("unauthorized");
        vm.deal(unauthorized, SUBSCRIPTION_FEE);
        
        vm.startPrank(unauthorized);
        
        // Set up school configuration
        SchoolManagementFactory.DeploymentConfig memory config = SchoolManagementFactory.DeploymentConfig({
            programFee: 0.1 ether,
            subscriptionFee: SUBSCRIPTION_FEE,
            certificateFee: 0.05 ether,
            revenueShare: 10,
            subscriptionDuration: 30 days
        });

        // Try to create a school as unauthorized person
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                factory.MASTER_ADMIN_ROLE()
            )
        );

        factory.deploySchoolManagement{value: SUBSCRIPTION_FEE}(
            organizationAdmin,
            config
        );
        
        vm.stopPrank();
    }

    // This test checks if we can update the default school settings
    function test_UpdateDefaultConfig() public {
        SchoolManagementFactory.DeploymentConfig memory newConfig = SchoolManagementFactory.DeploymentConfig({
            programFee: 0.2 ether,
            subscriptionFee: 2 ether,
            certificateFee: 0.1 ether,
            revenueShare: 20,
            subscriptionDuration: 60 days
        });
        
        vm.prank(masterAdmin);
        factory.updateDefaultConfig(newConfig);
        
        SchoolManagementFactory.DeploymentConfig memory retrievedConfig = factory.getDefaultConfig();
        
        assertEq(retrievedConfig.programFee, newConfig.programFee);
        assertEq(retrievedConfig.subscriptionFee, newConfig.subscriptionFee);
        assertEq(retrievedConfig.certificateFee, newConfig.certificateFee);
        assertEq(retrievedConfig.revenueShare, newConfig.revenueShare);
        assertEq(retrievedConfig.subscriptionDuration, newConfig.subscriptionDuration);
    }

    // This test makes sure we can't set invalid default settings
    function test_RevertWhen_UpdateDefaultConfigInvalid() public {
        SchoolManagementFactory.DeploymentConfig memory invalidConfig = SchoolManagementFactory.DeploymentConfig({
            programFee: 0.2 ether,
            subscriptionFee: 0.005 ether, // Too low!
            certificateFee: 0.1 ether,
            revenueShare: 20,
            subscriptionDuration: 60 days
        });
        
        vm.prank(masterAdmin);
        vm.expectRevert(InvalidSubscriptionFee.selector);
        factory.updateDefaultConfig(invalidConfig);
    }

    // This test checks if we catch invalid addresses when updating the system
    function test_RevertWhen_UpdateImplementationInvalid() public {
        vm.startPrank(masterAdmin);
        
        // Try to use zero address
        vm.expectRevert(InvalidImplementation.selector);
        factory.updateImplementation(address(0));
        
        // Try to use same address
        vm.expectRevert(SameImplementation.selector);
        factory.updateImplementation(address(implementation));
        
        // Try to use a regular address instead of a contract
        address nonContract = makeAddr("nonContract");
        vm.expectRevert(NotContractAddress.selector);
        factory.updateImplementation(nonContract);
        
        vm.stopPrank();
    }

    // This test makes sure people can't just send money to the contract
    function test_RevertWhen_DirectPayment() public {
        // Try to send money directly
        vm.deal(address(this), 1 ether);
        
        vm.expectRevert(DirectPaymentsNotAllowed.selector);
        payable(address(factory)).transfer(1 ether);
    }

    // This test checks if we can get lists of schools in chunks
    function test_GetDeployedContracts() public {
        // Create several schools
        SchoolManagementFactory.DeploymentConfig memory config = SchoolManagementFactory.DeploymentConfig({
            programFee: 0.1 ether,
            subscriptionFee: SUBSCRIPTION_FEE,
            certificateFee: 0.05 ether,
            revenueShare: 10,
            subscriptionDuration: 30 days
        });
        
        address[] memory admins = new address[](3);
        for(uint i = 0; i < 3; i++) {
            admins[i] = makeAddr(string.concat("org", vm.toString(i)));
            vm.prank(masterAdmin);
            factory.deploySchoolManagement{value: SUBSCRIPTION_FEE}(admins[i], config);
        }
        
        // Get schools in different sized chunks
        address[] memory batch1 = factory.getDeployedContracts(0, 2);
        assertEq(batch1.length, 2);
        
        address[] memory batch2 = factory.getDeployedContracts(2, 2);
        assertEq(batch2.length, 1);
        
        // Get all schools at once
        address[] memory allContracts = factory.getDeployedContracts(0, 10);
        assertEq(allContracts.length, 3);
    }

    // This test makes sure we can't create a school using a contract address
    function test_RevertWhen_DeployToContractAddress() public {
        SchoolManagementFactory.DeploymentConfig memory config = SchoolManagementFactory.DeploymentConfig({
            programFee: 0.1 ether,
            subscriptionFee: SUBSCRIPTION_FEE,
            certificateFee: 0.05 ether,
            revenueShare: 10,
            subscriptionDuration: 30 days
        });
        
        // Try to use a contract address as school admin
        vm.prank(masterAdmin);
        vm.expectRevert(OrganizationCannotBeContract.selector);
        factory.deploySchoolManagement{value: SUBSCRIPTION_FEE}(
            address(implementation),  // This is a contract address
            config
        );
    }

    // This test checks if schools can renew even if slightly late
    function test_RenewSubscriptionInGracePeriod() public {
        // First create a school
        SchoolManagementFactory.DeploymentConfig memory config = SchoolManagementFactory.DeploymentConfig({
            programFee: 0.1 ether,
            subscriptionFee: SUBSCRIPTION_FEE,
            certificateFee: 0.05 ether,
            revenueShare: 10,
            subscriptionDuration: 30 days
        });

        vm.prank(masterAdmin);
        factory.deploySchoolManagement{value: SUBSCRIPTION_FEE}(organizationAdmin, config);
        
        // Fast forward past due date but still in grace period
        vm.warp(block.timestamp + 31 days);
        
        // Try to renew
        vm.deal(organizationAdmin, SUBSCRIPTION_FEE);
        vm.prank(organizationAdmin);
        factory.renewSubscription{value: SUBSCRIPTION_FEE}(organizationAdmin);
        
        // Check if renewal worked
        (,, uint256 subscriptionEnd,,) = factory.getOrganizationDetails(organizationAdmin);
        assertEq(subscriptionEnd, block.timestamp + 30 days);
    }

    // This function lets the contract receive money
    receive() external payable {}
}