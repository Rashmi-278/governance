// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistryInterfaces.sol";
 
/// @notice Updates the delay of the core gov timelock to 8 days
///         and sets the new constitution hash
contract CoreGovTimelockUpdateDelayEightDayAction {
    IL2AddressRegistry public constant govAddressRegistry = IL2AddressRegistry(0x56C4E9Eb6c63aCDD19AeC2b1a00e4f0d7aBda9d3);
    uint256 public constant delay = 86400 * 8;
    bytes32 public constant newConstitutionHash =
        0x2498ca4a737c2d06c43799b5ddf5183b6e169359f68bea4b34775751528a2ee1;

    function perform() external {
        govAddressRegistry.coreGovTimelock().updateDelay(delay);
        require(
            govAddressRegistry.coreGovTimelock().getMinDelay() == delay,
            "CoreGovTimelockUpdateDelayAction: Timelock delay"
        );

        IArbitrumDAOConstitution arbitrumDaoConstitution =
            govAddressRegistry.arbitrumDAOConstitution();
        arbitrumDaoConstitution.setConstitutionHash(newConstitutionHash);
        require(
            arbitrumDaoConstitution.constitutionHash() == newConstitutionHash,
            "CoreGovTimelockUpdateDelayAction: new constitution hash not set"
        );
    }
}
