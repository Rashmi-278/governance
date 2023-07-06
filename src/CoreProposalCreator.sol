// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";

import "./UpgradeExecutor.sol";
import "./L1ArbitrumTimelock.sol";

interface DefaultGovAction {
    function perform() external;
}

/// @notice Contract that packages "round trip" proposals to be sent to the L1 timelock
contract CoreProposalCreator is Initializable, AccessControlUpgradeable {
    bytes32 public constant PROPOSAL_CREATOR_ROLE = keccak256("PROPOSAL_CREATOR_ROLE");

    address public l1ArbitrumTimelock;

    struct Chain {
        uint256 chainID;
        address inbox;
        address upgradeExecutor;
        bool exists;
        SecurityCouncil emergencySecurityCouncil;
    }

    struct SecurityCouncil {
        /// @notice Address of the Security Council
        address securityCouncilAddress;
        /// @notice Address of the update action contract that contains the logic for
        ///         updating council membership. Will be delegate called by the upgrade executor
        address updateAction;
        uint256 chainID;
    }

    mapping(uint256 => Chain) chainIDToChainData;

    SecurityCouncil[] nonEmergencySecurityCouncils;

    uint256[] registeredChainIDs;

    // The minimum L1 timelock delay that can be used for a proposal. Should be kept in sync with min delay on the L1 timelock.
    uint256 minL1TimelockDelay;

    // Used as a magic value to indicate that a retryable ticket should be created by the L1 timelock
    address public constant RETRYABLE_TICKET_MAGIC = 0xa723C008e76E379c55599D2E4d93879BeaFDa79C;

    event ChainAdded(Chain chain);
    event ChainRemoved(Chain chain);
    event NonEmergencySecurityCouncilAdded(SecurityCouncil securityCouncil);
    event NonEmergencySecurityCouncilRemoved(SecurityCouncil securityCouncil);

    event MinL1TimelockDelaySet(uint256 indexed newMinTimelockDelay);

    event ProposalCreated(
        uint256 targetChainID,
        address govActionContract,
        bytes govActionContractCalldata,
        uint256 values,
        bytes32 l1TimelockPrececessor,
        bytes32 l1TimelockSalt,
        uint256 l1TimelockDelay
    );
    event ProposalBatchCreated(
        uint256[] targetChainIDs,
        address[] govActionContracts,
        bytes[] govActionContractCalldatas,
        uint256[] values,
        bytes32 l1TimelockPrececessor,
        bytes32 l1TimelockSalt,
        uint256 l1TimelockDelay
    );

    // Default args for creating a proposal, used by createProposalWithDefaulArgs and createProposalBatchWithDefaultArgs
    bytes public constant DEFAULT_GOV_ACTION_CALLDATA =
        abi.encodeWithSelector(DefaultGovAction.perform.selector);
    uint256 public constant DEFAULT_VALUE = 0;
    bytes32 public constant DEFAULT_PREDECESSOR = bytes32(0);

    constructor() {
        _disableInitializers();
    }

    modifier sufficientTimelockDelay(uint256 _l1TimelockDelay) {
        require(
            _l1TimelockDelay >= minL1TimelockDelay, "CoreProposalCreator: l1 timelock delay too low"
        );
        _;
    }

    function requireRegisteredChainID(uint256 _chainID) internal view {
        require(chainIDToChainData[_chainID].exists, "CoreProposalCreator: unregisterded chain ID");
    }

    /// @param _l1ArbitrumTimelock address of the core gov L1 timelock
    /// @param _chains todo
    /// @param _admin address of the admin role
    /// @param _proposalCreator address of the proposal creator role (l2 gov timelock)
    /// @param _minL1TimelockDelay minimum delay for L1 timelock
    function initialize(
        address _l1ArbitrumTimelock,
        Chain[] memory _chains,
        SecurityCouncil[] memory _nonEmergencySecurityCouncils,
        address _admin,
        address _proposalCreator,
        uint256 _minL1TimelockDelay
    ) external initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PROPOSAL_CREATOR_ROLE, _proposalCreator);

        l1ArbitrumTimelock = _l1ArbitrumTimelock;
        for (uint256 i = 0; i < _chains.length; i++) {
            _addChain(_chains[i]);
        }

        for (uint256 i = 0; i < _nonEmergencySecurityCouncils.length; i++) {
            _addNonEmergencySecurityCouncil(_nonEmergencySecurityCouncils[i]);
        }
        _setMinL1TimelockDelay(_minL1TimelockDelay);
    }

    function allSecurityCouncils()
        public
        view
        returns (SecurityCouncil[] memory allSecurityCouncils)
    {
        SecurityCouncil[] memory allSecurityCouncils =
            new SecurityCouncil[](registeredChainIDs.length + nonEmergencySecurityCouncils.length);
        uint256 i;
        for (i = 0; i < registeredChainIDs.length; i++) {
            allSecurityCouncils[i] =
                chainIDToChainData[registeredChainIDs[i]].emergencySecurityCouncil;
        }
        for (uint256 j = 0; j < nonEmergencySecurityCouncils.length; j++) {
            allSecurityCouncils[i + j] = nonEmergencySecurityCouncils[j];
        }
    }
    /// @notice Sets the minimum L1 timelock delay that can be used for a proposal; value should be kept in sync with value in L1 timelock

    function setMinL1TimelockDelay(uint256 _minL1TimelockDelay)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setMinL1TimelockDelay(_minL1TimelockDelay);
    }

    function _setMinL1TimelockDelay(uint256 _minL1TimelockDelay) internal {
        minL1TimelockDelay = _minL1TimelockDelay;
        emit MinL1TimelockDelaySet(minL1TimelockDelay);
    }

    function _addChain(Chain memory _chain) internal {
        require(
            !chainIDToChainData[_chain.chainID].exists,
            "CoreProposalCreator: chain already included"
        );
        _chain.exists = true;
        chainIDToChainData[_chain.chainID] = _chain;
        registeredChainIDs.push(_chain.chainID);
        emit ChainAdded(_chain);
    }

    /// @notice Add a new chain to be used for governance actions
    function addChain(Chain memory _chain) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addChain(_chain);
    }

    /// @notice Remove a chain to be used for governance actions
    function removeChain(uint256 _chainID) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        Chain storage chain = chainIDToChainData[_chainID];
        delete chainIDToChainData[_chainID];
        for (uint256 i = 0; i < registeredChainIDs.length; i++) {
            if (registeredChainIDs[i] == _chainID) {
                registeredChainIDs[i] = registeredChainIDs[registeredChainIDs.length - 1];
                registeredChainIDs.pop();
                emit ChainRemoved(chain);
                return true;
            }
        }
        revert("CoreProposalCreator: chain not found");
    }

    function addNonEmergencySecurityCouncil(SecurityCouncil memory _securityCouncil)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _addNonEmergencySecurityCouncil(_securityCouncil);
    }

    function _addNonEmergencySecurityCouncil(SecurityCouncil memory _securityCouncil) internal {
        nonEmergencySecurityCouncils.push(_securityCouncil);
        emit NonEmergencySecurityCouncilAdded(_securityCouncil);
    }

    function removeNonEmergencySecurityCouncil(uint256 _index)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        SecurityCouncil memory lastNESecurityCouncil =
            nonEmergencySecurityCouncils[nonEmergencySecurityCouncils.length - 1];
        SecurityCouncil storage NESecurityCouncilToRemove = nonEmergencySecurityCouncils[_index];
        nonEmergencySecurityCouncils[_index] = lastNESecurityCouncil;
        nonEmergencySecurityCouncils.pop();
        emit NonEmergencySecurityCouncilRemoved(NESecurityCouncilToRemove);
    }

    function createProposalBatch(
        uint256[] memory _targetChainIDs,
        address[] memory _govActionContracts,
        bytes[] memory _govActionContractCalldatas,
        uint256[] memory _values,
        bytes32 _l1TimelockPrececessor,
        bytes32 _l1TimelockSalt,
        uint256 _l1TimelockDelay
    ) external onlyRole(PROPOSAL_CREATOR_ROLE) {
        _createProposalBatch(
            _targetChainIDs,
            _govActionContracts,
            _govActionContractCalldatas,
            _values,
            _l1TimelockPrececessor,
            _l1TimelockSalt,
            _l1TimelockDelay
        );
    }

    /// @notice Create a proposal batch; callable by the core gov timelock. Uses common values as default args:
    /// calldatas are all for an action with a perform() method (no arguments)
    /// values are all 0
    /// predecessor is bytes(0)
    /// salt is generated from block.timestamp and block.number
    /// delay is the default delay (the minimum)
    function createProposalBatch__UseDefaultArgs(
        uint256[] memory _targetChainIDs,
        address[] memory _govActionContracts
    ) external onlyRole(PROPOSAL_CREATOR_ROLE) {
        bytes[] memory _defaultGovActionContractCalldatas;
        uint256[] memory _defaultValues;
        for (uint256 i = 0; i < _targetChainIDs.length; i++) {
            _defaultGovActionContractCalldatas[i] = DEFAULT_GOV_ACTION_CALLDATA;
            _defaultValues[i] = DEFAULT_VALUE;
        }
        _createProposalBatch(
            _targetChainIDs,
            _govActionContracts,
            _defaultGovActionContractCalldatas,
            _defaultValues,
            DEFAULT_PREDECESSOR,
            generateSalt(),
            defaultL1TimelockDelay()
        );
    }

    function _createProposalBatch(
        uint256[] memory _targetChainIDs,
        address[] memory _govActionContracts,
        bytes[] memory _govActionContractCalldatas,
        uint256[] memory _values,
        bytes32 _l1TimelockPrececessor,
        bytes32 _l1TimelockSalt,
        uint256 _l1TimelockDelay
    ) internal sufficientTimelockDelay(_l1TimelockDelay) {
        require(
            _targetChainIDs.length == _govActionContracts.length,
            "CoreProposalCreator: length mismatch"
        );
        require(
            _govActionContracts.length == _govActionContractCalldatas.length,
            "CoreProposalCreator: length mismatch"
        );
        require(
            _govActionContractCalldatas.length == _values.length,
            "CoreProposalCreator: length mismatch"
        );

        address[] memory targets;
        uint256[] memory values;
        bytes[] memory payloads;
        for (uint256 i = 0; i < _targetChainIDs.length; i++) {
            requireRegisteredChainID(_targetChainIDs[i]);
            (address target, uint256 value, bytes memory payload) = _getScheduleParams(
                _targetChainIDs[i],
                _govActionContracts[i],
                _govActionContractCalldatas[i],
                _values[i]
            );
            targets[i] = target;
            values[i] = value;
            payloads[i] = payload;
        }
        bytes memory l1TimelockCallData = abi.encodeWithSelector(
            L1ArbitrumTimelock.scheduleBatch.selector,
            targets,
            values,
            payloads,
            _l1TimelockPrececessor,
            _l1TimelockSalt,
            _l1TimelockDelay
        );
        sendTxToL1Timelock(l1TimelockCallData);
        emit ProposalBatchCreated(
            _targetChainIDs,
            _govActionContracts,
            _govActionContractCalldatas,
            _values,
            _l1TimelockPrececessor,
            _l1TimelockSalt,
            _l1TimelockDelay
        );
    }

    /// @notice Get the target, value, and payload for a proposal to be sent to the L1 timelock
    function _getScheduleParams(
        uint256 _targetChainID,
        address _govActionContract,
        bytes memory govActionContractCalldata,
        uint256 _value
    ) public view returns (address target, uint256 value, bytes memory payload) {
        Chain storage chain = chainIDToChainData[_targetChainID];

        bytes memory upgradeExecutorCallData = abi.encodeWithSelector(
            UpgradeExecutor.execute.selector, _govActionContract, govActionContractCalldata
        );

        address target;
        uint256 value;
        bytes memory payload;
        if (chain.inbox == address(0)) {
            // target and value are encoded top level for L1 actions
            target = chain.upgradeExecutor;
            value = _value;
            payload = upgradeExecutorCallData;
        } else {
            // For L2 actions, magic is top level target, and value and calldata are encoded in payload
            target = RETRYABLE_TICKET_MAGIC;
            value = 0;
            payload = abi.encode(
                chain.inbox, chain.upgradeExecutor, _value, 0, 0, upgradeExecutorCallData
            );
        }
    }

    function sendTxToL1Timelock(bytes memory _l1TimelockCallData) internal {
        ArbSys(address(100)).sendTxToL1(l1ArbitrumTimelock, _l1TimelockCallData);
    }

    function generateSalt() public view returns (bytes32) {
        return keccak256(abi.encodePacked(block.timestamp, block.number));
    }

    function defaultL1TimelockDelay() public view returns (uint256) {
        return minL1TimelockDelay;
    }
}