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

pyth=`cat $deployments | jq -r ".pyth_feeder.package"`
wormhole=`cat $deployments | jq -r ".pyth_feeder.wormhole.package"`

# update Move.toml
sed -i "s/\(published-at\s*=\s*\)\"0x[0-9a-fA-F]\+\"/\1\"$wormhole\"/" ../../vendor/wormhole/Move.toml
sed -i "s/\(wormhole\s*=\s*\)\"0x[0-9a-fA-F]\+\"/\1\"$wormhole\"/" ../../vendor/wormhole/Move.toml
sed -i "s/\(wormhole\s*=\s*\)\"0x[0-9a-fA-F]\+\"/\1\"$wormhole\"/" ../../vendor/pyth/Move.toml
sed -i "s/\(published-at\s*=\s*\)\"0x[0-9a-fA-F]\+\"/\1\"$pyth\"/" ../../vendor/pyth/Move.toml
sed -i "s/\(pyth\s*=\s*\)\"0x[0-9a-fA-F]\+\"/\1\"$pyth\"/" ../../vendor/pyth/Move.toml
sed -i "s/\(pyth\s*=\s*\)\"0x[0-9a-fA-F]\+\"/\1\"$pyth\"/" ../Move.toml
sed -i 's/\(published-at\s*=\s*\)"0x[0-9a-fA-F]\+"/\1"0x0"/' ../Move.toml
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

       upgrade_cap=`echo "$deploy_log" | grep "0x2::package::UpgradeCap" -A 1 | grep objectId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".abex_core.upgrade_cap" in $deployments
       json_content=`echo "$json_content" | jq ".abex_core.upgrade_cap = \"$upgrade_cap\""`
       
       admin_cap=`echo "$deploy_log" | grep "$package::admin::AdminCap" -A 1 | grep objectId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".abex_core.upgrade_cap" in $deployments
       json_content=`echo "$json_content" | jq ".abex_core.admin_cap = \"$admin_cap\""`
       
       market_id=`echo "$deploy_log" | grep "$package::market::Market<$package::alp::ALP>" -A 1 | grep objectId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".abex_core.market.id" in $deployments
       json_content=`echo "$json_content" | jq ".abex_core.market = \"${market_id}\""`

       alp_metadata_id=`echo "$deploy_log" | grep "0x2::coin::CoinMetadata<$package::alp::ALP>" -A 1 | grep objectId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".abex_core.alp_metadata.id" in $deployments
       json_content=`echo "$json_content" | jq ".abex_core.alp_metadata = \"${alp_metadata_id}\""`

       fee_model_id=`echo "$deploy_log" | grep "$package::model::RebaseFeeModel" -A 1 | grep objectId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".abex_core.rebase_fee_model.id" in $deployments
       json_content=`echo "$json_content" | jq ".abex_core.rebase_fee_model = \"${fee_model_id}\""`

       ### grep from events

       referrals_parent=`echo "$deploy_log" | grep "referrals_parent" | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".abex_core.referrals_parent" in $deployments
       json_content=`echo "$json_content" | jq ".abex_core.referrals_parent = \"$referrals_parent\""`

       vaults_parent=`echo "$deploy_log" | grep "vaults_parent" | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".abex_core.vaults_parent" in $deployments
       json_content=`echo "$json_content" | jq ".abex_core.vaults_parent = \"$vaults_parent\""`

       symbols_parent=`echo "$deploy_log" | grep "symbols_parent" | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".abex_core.symbols_parent" in $deployments
       json_content=`echo "$json_content" | jq ".abex_core.symbols_parent = \"$symbols_parent\""`

       positions_parent=`echo "$deploy_log" | grep "positions_parent" | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".abex_core.positions_parent" in $deployments
       json_content=`echo "$json_content" | jq ".abex_core.positions_parent = \"$positions_parent\""`

       orders_parent=`echo "$deploy_log" | grep "orders_parent" | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".abex_core.orders_parent" in $deployments
       json_content=`echo "$json_content" | jq ".abex_core.orders_parent = \"$orders_parent\""`

       json_content=`echo "$json_content" | jq ".abex_core.upgraded_packages = []"`
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
