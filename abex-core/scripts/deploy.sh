#!/bin/bash

read -p "Import the env name (default: testnet): " env_name
read -p "Import gas budget (default: 1000000000): " gas_budget

if [ -z "$gas_budget" ]; then
       gas_budget=1000000000
fi
if [ -z "$env_name" ]; then
       env_name="testnet"
fi
deployments="../../deployments-$env_name.json"
config="/root/.sui/sui_config/$env_name-client.yaml"

# update Move.toml
feeder=`sed -n 's/abex_feeder\s*=\s*\("0x[0-9a-fA-F]\+"\)/\1/p' ../../abex-feeder/Move.toml`
sed -i "s/\(abex_feeder\s*=\s*\)\"0x[0-9a-fA-F]\+\"/\1$feeder/" ../Move.toml
sed -i 's/\(abex_core\s*=\s*\)"0x[0-9a-fA-F]\+"/\1"0x0"/' ../Move.toml

# deploy
deploy_log=`sui client --client.config $config publish --skip-dependency-verification --gas-budget $gas_budget ../`
echo "$deploy_log"

ok=`echo "$deploy_log" | grep "Status : Success"`
if [ -n "$ok" ]; then
       ### grep from object changes

       package=`echo "$deploy_log" | grep '"type": String("published")' -A 1 | grep packageId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field "abex_core" to $package in Move.toml
       sed -i "s/\(abex_core\s*=\s*\)\"0x[0-9a-fA-F]\+\"/\1\"$package\"/" ../Move.toml
       # modify field "published-at" to $package in Move.toml
       sed -i "s/\(published-at\s*=\s*\)\"0x[0-9a-fA-F]\+\"/\1\"$package\"/" ../Move.toml
       # modify field ".abex_core.package" in $deployments
       json_content=`jq ".abex_core.package = \"$package\"" $deployments`

       upgrade_cap=`echo "$deploy_log" | grep "0x0000000000000000000000000000000000000000000000000000000000000002::package::UpgradeCap" -A 1 | grep objectId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".abex_core.upgrade_cap" in $deployments
       json_content=`echo "$json_content" | jq ".abex_core.upgrade_cap = \"$upgrade_cap\""`
       
       admin_cap=`echo "$deploy_log" | grep "$package::admin::AdminCap" -A 1 | grep objectId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".abex_core.upgrade_cap" in $deployments
       json_content=`echo "$json_content" | jq ".abex_core.admin_cap = \"$admin_cap\""`
       
       market=`echo "$deploy_log" | grep "$package::market::Market<$package::alp::ALP>" -A 1 | grep objectId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".abex_core.market" in $deployments
       json_content=`echo "$json_content" | jq ".abex_core.market = \"$market\""`

       alp_metadata=`echo "$deploy_log" | grep "0x0000000000000000000000000000000000000000000000000000000000000002::coin::CoinMetadata<$package::alp::ALP>" -A 1 | grep objectId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".abex_core.alp_metadata" in $deployments
       json_content=`echo "$json_content" | jq ".abex_core.alp_metadata = \"$alp_metadata\""`

       fee_model=`echo "$deploy_log" | grep "$package::model::RebaseFeeModel" -A 1 | grep objectId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".abex_core.rebase_fee_model" in $deployments
       json_content=`echo "$json_content" | jq ".abex_core.rebase_fee_model = \"$fee_model\""`

       ### grep from events

       vaults_parent=`echo "$deploy_log" | grep "vaults_parent_id" | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".abex_core.vaults_parent" in $deployments
       json_content=`echo "$json_content" | jq ".abex_core.vaults_parent = \"$vaults_parent\""`

       symbols_parent=`echo "$deploy_log" | grep "symbols_parent_id" | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".abex_core.symbols_parent" in $deployments
       json_content=`echo "$json_content" | jq ".abex_core.symbols_parent = \"$symbols_parent\""`

       positions_parent=`echo "$deploy_log" | grep "positions_parent_id" | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".abex_core.positions_parent" in $deployments
       json_content=`echo "$json_content" | jq ".abex_core.positions_parent = \"$positions_parent\""`

       # clear vaults
       json_content=`echo "$json_content" | jq ".abex_core.vaults = {}"`
       # clear symbols
       json_content=`echo "$json_content" | jq ".abex_core.symbols = {}"`

       if [ -n "$json_content" ]; then
              echo "$json_content" | jq . > $deployments
              echo "Update $deployments finished!"
       else
              echo "Update $deployments failed!"
       fi
fi
