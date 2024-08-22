// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import "../address-registries/interfaces.sol";

contract PauseRollupAction {
    IRollupGetter public immutable addressRegistry;

    constructor(IRollupGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform() external {
        IRollupAdmin(address(addressRegistry.rollup())).pause();
    }
}
