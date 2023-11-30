#!/bin/bash

read -p "Import the env name (default: testnet): " env_name
read -p "Import gas budget (default: 1000000000): " gas_budget
read -p "Import the coin name: " coin

declare -l coin=$coin
declare -u coin_upper=$coin

if [ -z "$gas_budget" ]; then
       gas_budget="1000000000"
fi
if [ -z "$env_name" ]; then
       env_name="testnet"
fi
deployments="../../deployments-$env_name.json"
config="/root/.sui/sui_config/$env_name-client.yaml"

# set field "abex_$coin" to 0x0 in Move.toml, which is required by publishing
sed -i "s/\(abex_$coin\s*=\s*\)\"0x[0-9a-fA-F]\+\"/\1\"0x0\"/" ../$coin/Move.toml

# deploy
log=`sui client --client.config $config publish ../$coin --skip-dependency-verification --gas-budget $gas_budget`
echo "$log"

ok=`echo "$log" | grep "Status : Success"`
if [ -n "$ok" ]; then
       package=`echo "$log" | grep '"type": String("published")' -A 1 | grep packageId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field "abex_$coin" to $package in Move.toml
       sed -i "s/\(abex_$coin\s*=\s*\)\"0x[0-9a-fA-F]\+\"/\1\"$package\"/" ../$coin/Move.toml
       # modify field "published-at" to $package in Move.toml
       sed -i "s/\(published-at\s*=\s*\)\"0x[0-9a-fA-F]\+\"/\1\"$package\"/" ../$coin/Move.toml
       # modify field ".coins.$coin.module" in $deployments
       json_content=`jq ".coins.$coin.module = \"$package::$coin::${coin_upper}\"" $deployments`

       metadata=`echo "$log" | grep "0x2::coin::CoinMetadata<$package::$coin::${coin_upper}>" -A 1 | grep objectId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".coins.$coin.metadata" in $deployments
       json_content=`echo "$json_content" | jq ".coins.$coin.metadata = \"$metadata\""`

       treasury=`echo "$log" | grep "0x2::coin::TreasuryCap<$package::$coin::${coin_upper}>" -A 1 | grep objectId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       # modify field ".coins.$coin.treasury" in $deployments
       json_content=`echo "$json_content" | jq ".coins.$coin.treasury = \"$treasury\""`

       if [ -n "$json_content" ]; then
              echo "$json_content" | jq . > $deployments
              echo "Update $deployments finished!"
       else
              echo "Update $deployments failed!"
       fi
fi
