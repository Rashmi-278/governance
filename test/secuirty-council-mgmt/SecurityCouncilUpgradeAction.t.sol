// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";
import "../util/TestUtil.sol";
import "../util/DeployGnosisWithModule.sol";
import "../../src/UpgradeExecutor.sol";

import "../../src/security-council-mgmt/SecurityCouncilUpgradeAction.sol";
import "../../src/security-council-mgmt/interfaces/IGnosisSafe.sol";
import "../util/TestUtil.sol";

contract SecurityCouncilUpgradeActionTest is Test, DeployGnosisWithModule {
    address admin = address(1111);
    address executor = address(2222);

    address[] owners = [
        address(3333),
        address(4444),
        address(5555),
        address(6666),
        address(7777),
        address(8888),
        address(9999),
        address(10_111),
        address(110_111),
        address(121_111),
        address(131_111),
        address(141_111)
    ];

    function updateMembersTest(
        address[] memory initialMembers,
        address[] memory newMembers,
        uint256 threshold
    ) internal {
        UpgradeExecutor upgradeExecutor =
            UpgradeExecutor(TestUtil.deployProxy(address(new UpgradeExecutor())));
        address[] memory executors = new address[](1);
        executors[0] = executor;
        upgradeExecutor.initialize(admin, executors);

        address safe = deploySafe(initialMembers, threshold, address(upgradeExecutor));

        address action = address(new SecurityCouncilUpgradeAction());

        bytes memory upgradeCallData =
            abi.encodeWithSelector(SecurityCouncilUpgradeAction.perform.selector, safe, newMembers);
        vm.prank(executor);
        upgradeExecutor.execute(action, upgradeCallData);
        assertTrue(
            TestUtil.areAddressArraysEqual(newMembers, IGnosisSafe(safe).getOwners()),
            "updated sucessfully"
        );
        assertEq(IGnosisSafe(safe).getThreshold(), threshold, "threshold preserved");
    }

    function testNoopUpdate() public {
        address[] memory newMembers = owners;
        address[] memory prevMembers = owners;

        updateMembersTest(prevMembers, newMembers, 9);
    }

    function testRemoveOne() public {
        address[] memory newMembers = new address[](11);

        for (uint256 i = 0; i < 11; i++) {
            newMembers[i] = owners[i];
        }
        address[] memory prevMembers = owners;
        updateMembersTest(prevMembers, newMembers, 9);
    }

    function testAddOne() public {
        address[] memory prevMembers = new address[](11);

        for (uint256 i = 0; i < 11; i++) {
            prevMembers[i] = owners[i];
        }
        address[] memory newMembers = owners;
        updateMembersTest(prevMembers, newMembers, 9);
    }

    function testUpdateCohort() public {
        address[] memory prevMembers = owners;
        address[] memory newMembers = new address[](12);

        address[6] memory newCohort = [
            address(16_111),
            address(18_111),
            address(19_111),
            address(200_111),
            address(210_111),
            address(220_111)
        ];

        for (uint256 i = 0; i < 6; i++) {
            newMembers[i] = newCohort[i];
        }
        for (uint256 i = 6; i < owners.length; i++) {
            newMembers[i] = owners[i];
        }
        updateMembersTest(prevMembers, newMembers, 9);
    }

    function testCantDropBelowThreshhold() public {
        address[] memory prevMembers = owners;
        address[] memory newMembers = new address[](8);
        for (uint256 i = 0; i < 8; i++) {
            newMembers[i] = owners[i];
        }
        UpgradeExecutor upgradeExecutor =
            UpgradeExecutor(TestUtil.deployProxy(address(new UpgradeExecutor())));
        address[] memory executors = new address[](1);
        executors[0] = executor;
        upgradeExecutor.initialize(admin, executors);

        address safe = deploySafe(prevMembers, 9, address(upgradeExecutor));

        address action = address(new SecurityCouncilUpgradeAction());

        bytes memory upgradeCallData =
            abi.encodeWithSelector(SecurityCouncilUpgradeAction.perform.selector, safe, newMembers);
        vm.prank(executor);
        vm.expectRevert("SecurityCouncilUpgradeAction: execTransactionFromModule failed");
        upgradeExecutor.execute(action, upgradeCallData);
    }
}