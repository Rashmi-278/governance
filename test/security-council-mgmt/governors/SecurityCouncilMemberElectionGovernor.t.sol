// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../util/TestUtil.sol";

import "../../../src/security-council-mgmt/governors/SecurityCouncilMemberElectionGovernor.sol";

contract SecurityCouncilMemberElectionGovernorTest is Test {
    struct InitParams {
        SecurityCouncilNomineeElectionGovernor nomineeElectionGovernor;
        ISecurityCouncilManager securityCouncilManager;
        IVotesUpgradeable token;
        address owner;
        uint256 votingPeriod;
        uint256 maxNominees;
        uint256 fullWeightDurationNumerator;
        uint256 durationDenominator;
    }

    SecurityCouncilMemberElectionGovernor governor;
    address proxyAdmin = address(10_000);

    InitParams initParams = InitParams({
        nomineeElectionGovernor: SecurityCouncilNomineeElectionGovernor(payable(address(0x0A))),
        securityCouncilManager: ISecurityCouncilManager(address(0x0B)),
        token: IVotesUpgradeable(address(0x0C)),
        owner: address(0x0D),
        votingPeriod: 2 ** 8,
        maxNominees: 6,
        fullWeightDurationNumerator: 3,
        durationDenominator: 4
    });

    function setUp() public {
        governor = _deployGovernor();

        governor.initialize({
            _nomineeElectionGovernor: initParams.nomineeElectionGovernor,
            _securityCouncilManager: initParams.securityCouncilManager,
            _token: initParams.token,
            _owner: initParams.owner,
            _votingPeriod: initParams.votingPeriod,
            _maxNominees: initParams.maxNominees,
            _fullWeightDurationNumerator: initParams.fullWeightDurationNumerator,
            _durationDenominator: initParams.durationDenominator
        });

        vm.roll(10);
    }

    function testProperInitialization() public {
        assertEq(
            address(governor.nomineeElectionGovernor()), address(initParams.nomineeElectionGovernor)
        );
        assertEq(
            address(governor.securityCouncilManager()), address(initParams.securityCouncilManager)
        );
        assertEq(address(governor.token()), address(initParams.token));
        assertEq(governor.owner(), initParams.owner);
        assertEq(governor.votingPeriod(), initParams.votingPeriod);
        assertEq(governor.maxNominees(), initParams.maxNominees);
        assertEq(governor.fullWeightDurationNumerator(), initParams.fullWeightDurationNumerator);
        assertEq(governor.durationDenominator(), initParams.durationDenominator);
    }

    function testProposeReverts() public {
        vm.expectRevert(
            "SecurityCouncilMemberElectionGovernor: Proposing is not allowed, call proposeFromNomineeElectionGovernor instead"
        );
        governor.propose(new address[](0), new uint256[](0), new bytes[](0), "");

        // should also fail if called by the nominee election governor
        vm.prank(address(initParams.nomineeElectionGovernor));
        vm.expectRevert(
            "SecurityCouncilMemberElectionGovernor: Proposing is not allowed, call proposeFromNomineeElectionGovernor instead"
        );
        governor.propose(new address[](0), new uint256[](0), new bytes[](0), "");
    }

    function testOnlyNomineeElectionGovernorCanPropose() public {
        vm.expectRevert(
            "SecurityCouncilMemberElectionGovernor: Only the nominee election governor can call this function"
        );
        governor.proposeFromNomineeElectionGovernor();

        _propose(0);
    }

    function testVotesToWeight() public {
        _propose(0);

        uint256 proposalId = governor.nomineeElectionIndexToProposalId(0);
        uint256 startBlock = governor.proposalSnapshot(proposalId);

        // test weight before voting starts (block <= startBlock)
        assertEq(governor.votesToWeight(proposalId, startBlock, 100), 0);

        // test weight right after voting starts (block == startBlock + 1)
        assertEq(governor.votesToWeight(proposalId, startBlock + 1, 100), 100);

        // test weight right before full weight voting ends
        // (block == startBlock + votingPeriod * fullWeightDurationNumerator / durationDenominator)
        assertEq(
            governor.votesToWeight(proposalId, governor.fullWeightVotingDeadline(proposalId), 100),
            100
        );

        // test weight right after full weight voting ends
        assertLe(
            governor.votesToWeight(
                proposalId, governor.fullWeightVotingDeadline(proposalId) + 1, 100
            ),
            100
        );

        // test weight halfway through decreasing weight voting
        uint256 halfwayPoint = (
            governor.fullWeightVotingDeadline(proposalId) + governor.proposalDeadline(proposalId)
        ) / 2;
        assertEq(governor.votesToWeight(proposalId, halfwayPoint, 100), 50);

        // test weight at proposal deadline
        assertEq(governor.votesToWeight(proposalId, governor.proposalDeadline(proposalId), 100), 0);

        // test governor with no decreasing weight voting
        vm.prank(address(governor));
        governor.setFullWeightDurationNumeratorAndDurationDenominator(1, 1);
        assertEq(
            governor.votesToWeight(proposalId, governor.proposalDeadline(proposalId), 100), 100
        );
    }

    function testNoVoteForNonCompliantNominee() public {
        uint256 proposalId = _propose(0);
        address voter = address(100);
        address nominee = address(200);

        // make sure the nomineeElectionGovernor says the nominee is not compliant
        _setCompliantNominee(nominee, false);

        // make sure the voter has enough votes
        _mockGetPastVotes({
            account: voter,
            blockNumber: governor.proposalSnapshot(proposalId),
            votes: 100
        });

        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(voter);
        vm.expectRevert(
            "SecurityCouncilMemberElectionGovernorCountingUpgradeable: Nominee is not compliant"
        );
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 0,
            reason: "",
            params: abi.encode(nominee, 100)
        });
    }

    function testCannotUseMoreVotesThanAvailable() public {
        uint256 proposalId = _propose(0);
        address voter = address(100);
        address nominee = address(200);

        // make sure the nomineeElectionGovernor says the nominee is compliant
        _setCompliantNominee(nominee, true);

        // make sure the voter has some votes
        _mockGetPastVotes({
            account: voter,
            blockNumber: governor.proposalSnapshot(proposalId),
            votes: 100
        });

        // roll to the start of voting
        vm.roll(governor.proposalSnapshot(proposalId) + 1);

        // try to use more votes than available
        vm.prank(voter);
        vm.expectRevert(
            "SecurityCouncilMemberElectionGovernorCountingUpgradeable: Cannot use more votes than available"
        );
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 0,
            reason: "",
            params: abi.encode(nominee, 101)
        });

        // use some amount of votes that is less than available
        vm.prank(voter);
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 0,
            reason: "",
            params: abi.encode(nominee, 50)
        });

        // now try to use more votes than available
        vm.prank(voter);
        vm.expectRevert(
            "SecurityCouncilMemberElectionGovernorCountingUpgradeable: Cannot use more votes than available"
        );
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 0,
            reason: "",
            params: abi.encode(nominee, 51)
        });
    }

    function testHasVotedAndVotesUsed() public {
        uint256 proposalId = _propose(0);
        address voter = address(100);
        address nominee = address(200);

        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        _mockGetPastVotes({
            account: voter,
            blockNumber: governor.proposalSnapshot(proposalId),
            votes: 100
        });
        _castVoteForCompliantNominee({
            proposalId: proposalId,
            voter: voter,
            nominee: nominee,
            votes: 100
        });

        assertEq(governor.hasVoted(proposalId, voter), true);
        assertEq(governor.votesUsed(proposalId, voter), 100);
    }

    function _mockGetPastVotes(address account, uint256 votes, uint256 blockNumber) internal {
        vm.mockCall(
            address(initParams.token),
            abi.encodeWithSelector(initParams.token.getPastVotes.selector, account, blockNumber),
            abi.encode(votes)
        );
    }

    function _mockGetPastVotes(address account, uint256 votes) internal {
        vm.mockCall(
            address(initParams.token),
            abi.encodeWithSelector(initParams.token.getPastVotes.selector, account),
            abi.encode(votes)
        );
    }

    function _setCompliantNominee(address account, bool ans) internal {
        vm.mockCall(
            address(initParams.nomineeElectionGovernor),
            abi.encodeWithSelector(
                initParams.nomineeElectionGovernor.isCompliantNomineeForMostRecentElection.selector,
                account
            ),
            abi.encode(ans)
        );
    }

    function _castVoteForCompliantNominee(
        uint256 proposalId,
        address voter,
        address nominee,
        uint256 votes
    ) internal {
        // make sure the nomineeElectionGovernor says the nominee is compliant
        _setCompliantNominee(nominee, true);

        vm.prank(voter);
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 0,
            reason: "",
            params: abi.encode(nominee, votes)
        });

        vm.clearMockedCalls();
    }

    function _propose(uint256 nomineeElectionIndex) internal returns (uint256) {
        // we need to mock call to the nominee election governor
        // electionCount() returns 1
        vm.mockCall(
            address(initParams.nomineeElectionGovernor),
            abi.encodeWithSelector(initParams.nomineeElectionGovernor.electionCount.selector),
            abi.encode(nomineeElectionIndex + 1)
        );

        // we need to mock getPastVotes for the nominee election governor
        _mockGetPastVotes({
            account: address(initParams.nomineeElectionGovernor),
            votes: 0
        });

        vm.prank(address(initParams.nomineeElectionGovernor));
        governor.proposeFromNomineeElectionGovernor();

        vm.clearMockedCalls();

        return governor.nomineeElectionIndexToProposalId(nomineeElectionIndex);
    }

    function _deployGovernor() internal returns (SecurityCouncilMemberElectionGovernor) {
        return SecurityCouncilMemberElectionGovernor(
            payable(
                new TransparentUpgradeableProxy(
                    address(new SecurityCouncilMemberElectionGovernor()),
                    proxyAdmin,
                    bytes("")
                )
            )
        );
    }
}
