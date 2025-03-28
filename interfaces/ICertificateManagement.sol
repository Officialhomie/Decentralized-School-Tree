// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


/**
 * @title ICertificateManagement
 * @dev Interface for certificate management functionalities
 */
interface ICertificateManagement {
    function mintCertificate(address student, uint256 batchId) external payable;
    function getCurrentCertificateTokenId() external view returns (uint256);
}