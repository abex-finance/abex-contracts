#!/bin/bash

read -p "Import the env name (default: testnet): " env_name
read -p "Import gas budget (default: 1000000000): " gas_budget
read -p "Import the index coin name: " i_coin
read -p "Import the symbol direction (default: LONG): " direction
read -p "Import the collateral coin name: " -a c_coins

if [ -z "$gas_budget" ]; then
       gas_budget=1000000000
fi
if [ -z "$env_name" ]; then
       env_name="testnet"
fi
deployments="../../deployments-$env_name.json"
config="/root/.sui/sui_config/$env_name-client.yaml"

if [ -z "$direction" ]; then
       direction="LONG"
fi

package=`cat $deployments | jq -r ".abex_core.package"`
admin_cap=`cat $deployments | jq -r ".abex_core.admin_cap"`
market=`cat $deployments | jq -r ".abex_core.market"`
i_coin_module=`cat $deployments | jq -r ".coins.$i_coin.module"`

for c_coin in ${c_coins[*]}; do
       c_coin_module=`cat $deployments | jq -r ".coins.$c_coin.module"`
       # add collateral to symbol
       add_log=`sui client --client.config $config \
              call --gas-budget $gas_budget \
                     --package $package \
                     --module market \
                     --function add_collateral_to_symbol \
                     --type-args $package::alp::ALP ${c_coin_module} ${i_coin_module} $package::market::$direction \
                     --args ${admin_cap} $market`
       echo "$add_log"

       ok=`echo "$add_log" | grep "Status : Success"`
       if [ -n "$ok" ]; then
              symbol="${direction}_${i_coin}"
              declare -l symbol=$symbol
              json_content=`jq ".abex_core.symbols.$symbol.supported_collaterals += [\"${c_coin}\"]" $deployments`

              if [ -n "$json_content" ]; then
                     echo "$json_content" | jq . > $deployments
                     echo "Update $deployments finished!"
              else
                     echo "Update $deployments failed!"
              fi
       fi
done
