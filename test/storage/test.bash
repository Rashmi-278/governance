#!/bin/bash
output_dir="./test/storage"
for CONTRACTNAME in SecurityCouncilManager L1ArbitrumTimelock ArbitrumTimelock L2ArbitrumGovernor L2ArbitrumToken L1ArbitrumToken FixedDelegateErc20Wallet UpgradeExecutor SecurityCouncilMemberElectionGovernor SecurityCouncilMemberRemovalGovernor SecurityCouncilNomineeElectionGovernor
do
    echo "Checking storage change of $CONTRACTNAME"
    [ -f "$output_dir/$CONTRACTNAME" ] && mv "$output_dir/$CONTRACTNAME" "$output_dir/$CONTRACTNAME-old"
    forge inspect "$CONTRACTNAME" --pretty storage > "$output_dir/$CONTRACTNAME"
    diff "$output_dir/$CONTRACTNAME-old" "$output_dir/$CONTRACTNAME"
    if [[ $? != "0" ]]
    then
        CHANGED=1
    fi
done
if [[ $CHANGED == 1 ]]
then
    exit 1
fi