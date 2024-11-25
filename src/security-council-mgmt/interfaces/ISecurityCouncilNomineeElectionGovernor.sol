// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./IElectionGovernor.sol";
import {Cohort} from "../Common.sol";
import "./ISecurityCouncilMemberElectionGovernor.sol";
import "./ISecurityCouncilManager.sol";

interface ISecurityCouncilNomineeElectionGovernorCountingUpgradeable {
    /// @notice Whether the contender has enough votes to be a nominee
    function isNominee(uint256 proposalId, address contender) external view returns (bool);
}

/// @notice Minimal interface of nominee election governor required by other contracts
interface ISecurityCouncilNomineeElectionGovernor is
    IElectionGovernor,
    ISecurityCouncilNomineeElectionGovernorCountingUpgradeable
{
    /// @notice Whether the account a compliant nominee for a given proposal
    ///         A compliant nominee is one who is a nominee, and has not been excluded
    /// @param  proposalId The id of the proposal
    /// @param  account The account to check
    function isCompliantNominee(uint256 proposalId, address account) external view returns (bool);
    /// @notice All compliant nominees of a given proposal
    ///         A compliant nominee is one who is a nominee, and has not been excluded
    function compliantNominees(uint256 proposalId) external view returns (address[] memory);
    /// @notice Number of elections created
    function electionCount() external returns (uint256);
    /// @notice Whether the account is a contender for the proposal
    function isContender(uint256 proposalId, address possibleContender)
        external
        view
        returns (bool);
    function otherCohort() external view returns (Cohort);
    /// @notice Security council manager contract
    /// @dev    Used to execute the election result immediately if <= 6 compliant nominees are chosen
    function securityCouncilManager() external view returns (ISecurityCouncilManager);
    /// @notice Security council member election governor contract
    function securityCouncilMemberElectionGovernor()
        external
        view
        returns (ISecurityCouncilMemberElectionGovernor);
}
