#!/bin/bash

read -p "Import the env name (default: mainnet): " env_name
read -p "Import gas budget (default: 1000000000): " gas_budget

if [ -z "$gas_budget" ]; then
       gas_budget=1000000000
fi
if [ -z "$env_name" ]; then
       env_name="mainnet"
fi
deployments="../../deployments-$env_name.json"
config="/root/.sui/sui_config/$env_name-client.yaml"

# update Move.toml
sed -i 's/\(abex_core\s*=\s*\)"0x[0-9a-fA-F]\+"/\1"0x0"/' ../Move.toml

upgrade_cap=`cat $deployments | jq -r ".abex_core.upgrade_cap"`

# upgrade
upgrade_log=`sui client --client.config $config upgrade --skip-dependency-verification --upgrade-capability $upgrade_cap --gas-budget $gas_budget ../`
echo "$upgrade_log"

ok=`echo "$upgrade_log" | grep "Status : Success"`
if [ -n "$ok" ]; then
       package=`cat $deployments | jq -r ".abex_core.package"`
       # update abex_core to origin id
       sed -i "s/\(abex_core\s*=\s*\)\"0x[0-9a-fA-F]\+\"/\1\"$package\"/" ../Move.toml
       # update published-at to new id
       published_at=`echo "${upgrade_log}" | grep '"type": String("published")' -A 1 | grep packageId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       sed -i "s/\(published-at\s*=\s*\)\"0x[0-9a-fA-F]\+\"/\1\"${published_at}\"/" ../Move.toml
fi
