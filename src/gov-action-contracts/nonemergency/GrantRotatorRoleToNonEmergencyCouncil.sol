// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../security-council-mgmt/SecurityCouncilManager.sol";

/// @notice Grant the non emergency council the MEMBER_ROTATOR_ROLE and MEMBER_REPLACER_ROLE on the SecurityCouncilManager.
///         Revoke those same roles from the emergency council.
contract GrantRotatorRoleToNonEmergencyCouncil {
    SecurityCouncilManager public constant securityCouncilManager =
        SecurityCouncilManager(address(0xD509E5f5aEe2A205F554f36E8a7d56094494eDFC));

    address public constant nonEmergencyCouncil =
        address(0xADd68bCb0f66878aB9D37a447C7b9067C5dfa941);
    address public constant emergencyCouncil = address(0x423552c0F05baCCac5Bfa91C6dCF1dc53a0A1641);

    bytes32 public immutable MEMBER_ROTATOR_ROLE = securityCouncilManager.MEMBER_ROTATOR_ROLE();
    bytes32 public immutable MEMBER_REPLACER_ROLE = securityCouncilManager.MEMBER_REPLACER_ROLE();

    function perform() public {
        // grant roles to non emergency council
        securityCouncilManager.grantRole(MEMBER_ROTATOR_ROLE, nonEmergencyCouncil);
        securityCouncilManager.grantRole(MEMBER_REPLACER_ROLE, nonEmergencyCouncil);

        // revoke roles from emergency council
        securityCouncilManager.revokeRole(MEMBER_ROTATOR_ROLE, emergencyCouncil);
        securityCouncilManager.revokeRole(MEMBER_REPLACER_ROLE, emergencyCouncil);
    }
}
