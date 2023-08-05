#!/bin/bash

read -p "Import the env name (default: testnet): " env_name
read -p "Import gas budget (default: 1000000000): " gas_budget
read -p "Import vault coin name: " coin
read -p "Import vault weight: (default: 100000000000000000): " weight
read -p "Import max price interval in seconds (default: 15): " max_interval
read -p "Import max price confidence (default: 18446744073709551615): " max_price_confidence
read -p "Import param multiplier (default: 800000000000000): " param_multiplier

if [ -z "$gas_budget" ]; then
       gas_budget=1000000000
fi
if [ -z "$env_name" ]; then
       env_name="testnet"
fi
deployments="../../deployments-$env_name.json"
config="/root/.sui/sui_config/$env_name-client.yaml"

if [ -z "$weight" ]; then
       weight=100000000000000000
fi
if [ -z "${max_interval}" ]; then
       max_interval=15
fi
if [ -z "${max_price_confidence}" ]; then
       max_price_confidence=18446744073709551615
fi
if [ -z "${param_multiplier}" ]; then
    param_multiplier=800000000000000
fi

package=`cat $deployments | jq -r ".abex_core.package"`
admin_cap=`cat $deployments | jq -r ".abex_core.admin_cap"`
market=`cat $deployments | jq -r ".abex_core.market"`
coin_module=`cat $deployments | jq -r ".coins.$coin.module"`
coin_metadata=`cat $deployments | jq -r ".coins.$coin.metadata"`
pyth_feeder=`cat $deployments | jq -r ".pyth_feeder.feeder.$coin"`

# add new vault
add_log=`sui client --client.config $config \
       call --gas-budget $gas_budget \
              --package $package \
              --module market \
              --function add_new_vault \
              --type-args $package::alp::ALP ${coin_module} \
              --args ${admin_cap} \
                     $market \
                     $weight \
                     ${max_interval} \
                     ${max_price_confidence} \
                     ${coin_metadata} \
                     ${pyth_feeder} \
                     ${param_multiplier}`
echo "$add_log"

ok=`echo "$add_log" | grep "Status : Success"`
if [ -n "$ok" ]; then
       fee_model=`echo "${add_log}" | grep "$package::model::ReservingFeeModel" -A 1 | grep objectId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`

       json_content=`jq ".abex_core.vaults.$coin.weight = \"$weight\"" $deployments`
       json_content=`echo "$json_content" | jq ".abex_core.vaults.$coin.reserving_fee_model = \"${fee_model}\""`

       if [ -n "$json_content" ]; then
              echo "$json_content" | jq . > $deployments
              echo "Update $deployments finished!"
       else
              echo "Update $deployments failed!"
       fi
fi
