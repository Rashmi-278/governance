// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./interfaces/ISecurityCouncilUpgradeExectutor.sol";
import "./interfaces/IGnosisSafe.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract SecurityCouncilUpgradeExecutor is
    ISecurityCouncilUpgradeExectutor,
    Initializable,
    OwnableUpgradeable
{
    // gnosis safe stores owners as linked list; SENTINAL_OWNERS is the head
    address internal constant SENTINEL_OWNERS = address(0x1);

    IGnosisSafe public securityCouncil;

    // TODO: setter?
    uint256 public maxMembers = 12;

    constructor() {
        _disableInitializers();
    }

    function initialize(IGnosisSafe _securityCouncil, address _owner) public initializer {
        securityCouncil = _securityCouncil;
        _transferOwnership(_owner);
    }

    /// @notice update gnosis safe members. We use add and remove gnosis's swapOwners method for cleansliness of handling different sized _membersToAdd & _membersToRemove arrays
    function updateMembers(address[] memory _membersToAdd, address[] memory _membersToRemove)
        external
        onlyOwner
    {
        // All update-initiating methods in SecurityCouncilManager ensure _membersToAdd and _membersToRemove have no addresses in common.
        // TODO We could, additionally, run removeSharedAddresses for extra insurance

        // always preserve current threshold
        uint256 threshold = securityCouncil.getThreshold();

        // when adding and removing, we skip if the operation is redundant (instead of letting gnosis revert).
        // This is for race conditions of adding/removing a member and the result of an election; we want the election result to still
        // take effect if member is added/removeed before the results are finalized.
        for (uint256 i = 0; i < _membersToAdd.length; i++) {
            address member = _membersToAdd[i];
            // skip, don't revert, if it's already not a member
            if (!securityCouncil.isOwner(member)) {
                _addMember(_membersToAdd[i], threshold);
            }
        }

        for (uint256 i = 0; i < _membersToRemove.length; i++) {
            address member = _membersToRemove[i];
            // skip, don't revert, if it's already not a member
            if (securityCouncil.isOwner(member)) {
                _removeMember(member, threshold);
            }
        }
        // sanity check: ensure that after update, total member count is below max
        uint256 memberCount = securityCouncil.getOwners().length;
        require(memberCount <= maxMembers, "SecurityCouncilUpgradeExecutor: too many members");
    }

    /// @notice add member to multisig
    /// @param _member member to add
    /// @param _threshold signer theshold
    function _addMember(address _member, uint256 _threshold) internal {
        _execFromModule(
            abi.encodeWithSelector(IGnosisSafe.addOwnerWithThreshold.selector, _member, _threshold)
        );
    }

    /// @notice remove member from multisig. takes O(n) time. gnosis safe reverts if removal puts signer count below threshold
    /// @param _member member to remove
    /// @param _threshold signer theshold
    function _removeMember(address _member, uint256 _threshold) internal {
        // owners are stored as a linked list and removal requires the previous owner
        address[] memory owners = securityCouncil.getOwners();
        address previousOwner = SENTINEL_OWNERS;
        for (uint256 i = 0; i < owners.length; i++) {
            address currentOwner = owners[i];
            if (currentOwner == _member) {
                break;
            }
            previousOwner = currentOwner;
        }
        _execFromModule(
            abi.encodeWithSelector(
                IGnosisSafe.removeOwner.selector, previousOwner, _member, _threshold
            )
        );
    }

    /// @notice execute provided operation via gnosis safe's trusted  execTransactionFromModule entry point
    function _execFromModule(bytes memory data) internal {
        securityCouncil.execTransactionFromModule(
            address(securityCouncil), 0, data, Enum.Operation.Call
        );
    }
}