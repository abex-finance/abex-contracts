#!/bin/bash

read -p "Import the env name (default: mainnet): " env_name
read -p "Import gas budget (default: 1000000000): " gas_budget
read -p "Import the upgrade version: " version

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
       new_package=`echo "${upgrade_log}" | grep '"type": String("published")' -A 1 | grep packageId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # update published-at to new id
       sed -i "s/\(published-at\s*=\s*\)\"0x[0-9a-fA-F]\+\"/\1\"${new_package}\"/" ../Move.toml
       # modify field ".abex_core.package_$version" in $deployments
       json_content=`jq ".abex_core.package_$version = \"${new_package}\"" $deployments`

       if [ -n "$json_content" ]; then
              echo "$json_content" | jq . > $deployments
              echo "Update $deployments finished!"
       else
              echo "Update $deployments failed!"
       fi
fi
