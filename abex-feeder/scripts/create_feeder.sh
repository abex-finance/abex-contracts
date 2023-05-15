#!/bin/bash

read -p "Import the env name (default: testnet): " env_name
read -p "Import gas budget (default: 1000000000): " gas_budget
read -p "Import the coin name: " coin

if [ -z "$gas_budget" ]; then
       gas_budget="1000000000"
fi
if [ -z "$env_name" ]; then
       env_name="testnet"
fi
deployments="../../deployments-$env_name.json"
config="/root/.sui/sui_config/$env_name-$coin-feeder.yaml"

package=`cat $deployments | jq -r ".abex_feeder.package"`

# add new feeder
create_log=`sui client --client.config $config \
    call --gas-budget $gas_budget \
         --package $package \
         --module native_feeder \
         --function create_native_feeder`
echo "$create_log"

ok=`echo "$create_log" | grep "Status : Success"`
if [ -n "$ok" ]; then
       feeder=`echo "$create_log" | grep "$package::native_feeder::NativeFeeder" -A 1 | grep objectId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".abex_feeder.upgrade_cap" in $deployments
       json_content=`jq ".abex_feeder.feeder.$coin = \"$feeder\"" $deployments`

       if [ -n "$json_content" ]; then
              echo "$json_content" | jq . > $deployments
              echo "Update $deployments finished!"
       else
              echo "Update $deployments failed!"
       fi
fi
