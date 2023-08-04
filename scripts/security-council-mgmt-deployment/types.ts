import { DeployedContracts } from "../../src-ts/types";
import { DeployParamsStruct } from "../../typechain-types/src/security-council-mgmt/factories/L2SecurityCouncilMgmtFactory";
import { Signer } from "ethers";

export interface SecurityCouncilAndChainID {
  securityCouncilAddress: string;
  chainID: number;
}

export interface ChainIDs {
  govChainID: number,
  l1ChainID: number,
}

export type ChainConfig = {
  chainID: number;
  rpcUrl: string;
  privateKey: string;
}

export type GovernedChainConfig = ChainConfig & {
  upExecLocation: string;
}

export type DeploymentConfig =
  DeployedContracts &
  Pick<
    DeployParamsStruct,
    'removalGovVotingDelay' |
    'removalGovVotingPeriod' |
    'removalGovQuorumNumerator' |
    'removalGovProposalThreshold' |
    'removalGovVoteSuccessNumerator' |
    'removalGovMinPeriodAfterQuorum' |
    'removalProposalExpirationBlocks' |
    'firstNominationStartDate' |
    'nomineeVettingDuration' |
    'nomineeVetter' |
    'nomineeQuorumNumerator' |
    'nomineeVotingPeriod' |
    'memberVotingPeriod' |
    'fullWeightDuration' |
    'firstCohort' |
    'secondCohort'
  > & {
    emergencySignerThreshold: number;
    nonEmergencySignerThreshold: number;
    govChain: ChainConfig;
    hostChain: ChainConfig;
    governedChains: GovernedChainConfig[];
    gnosisSafeL2Singleton: string;
    gnosisSafeL1Singleton: string;
    gnosisSafeFallbackHandler: string;
    gnosisSafeFactory: string;
  };

export interface ChainIDToConnectedSigner {
  [key: number]: Signer;
}

export type SecurityCouncilManagementDeploymentResult = {
  keyValueStores: {[key: number]: string};
  securityCouncilMemberSyncActions: {[key: number]: string};

  emergencyGnosisSafes: {[key: number]: string};
  nonEmergencyGnosisSafe: string;

  nomineeElectionGovernor: string;
  nomineeElectionGovernorLogic: string;
  memberElectionGovernor: string;
  memberElectionGovernorLogic: string;
  securityCouncilManager: string;
  securityCouncilManagerLogic: string;
  securityCouncilMemberRemoverGov: string;
  securityCouncilMemberRemoverGovLogic: string;

  upgradeExecRouteBuilder: string;
};