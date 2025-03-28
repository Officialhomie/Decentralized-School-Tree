// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;



/**
 * @title ISchoolManagementBase
 * @dev Interface for school management base functionalities
 */
interface ISchoolManagementBase {
    function renewSubscription() external payable;
    function handleSubscriptionExpiration() external;
    function recoverContract() external;
    function pause() external;
    function unpause() external;
    function emergencyWithdraw() external;
}