// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../arb-precompiles/ArbPrecompilesLib.sol";
import "../util/ActionCanExecute.sol";

interface IArbGasInfo {
    function getMinimumGasPrice() external view returns (uint256);
    function getL1RewardRate() external view returns (uint64);
}

contract ArbOneSetAtlasFeesAction {
    uint64 public constant NEW_MIN_BASE_FEE = 0.01 gwei;
    uint64 public constant NEW_L1_REWARD_RATE = 0;

    address public actionCanExecuteAddr = address(0); // TODO

    function perform() external {
        if (ActionCanExecute(actionCanExecuteAddr).canExecute()) {
            ArbPrecompilesLib.arbOwner.setMinimumL2BaseFee(NEW_MIN_BASE_FEE);
            ArbPrecompilesLib.arbOwner.setL1PricingRewardRate(NEW_L1_REWARD_RATE);

            // verify:
            IArbGasInfo arbGasInfo = IArbGasInfo(0x000000000000000000000000000000000000006C);
            require(
                arbGasInfo.getMinimumGasPrice() == NEW_MIN_BASE_FEE,
                "ArbOneSetAtlasFeesAction: min L2 gas price"
            );
            require(
                arbGasInfo.getL1RewardRate() == NEW_L1_REWARD_RATE,
                "ArbOneSetAtlasFeesAction: L1 reward rate"
            );
        }
    }
}
