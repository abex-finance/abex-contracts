#!/bin/bash

read -p "Import the env name (default: mainnet): " env_name
read -p "Import gas budget (default: 1000000000): " gas_budget
read -p "Import the fee rate percent (default: 10%): " fee_rate_percent
read -p "Import the fee collector: " fee_collector

if [ -z "$env_name" ]; then
       env_name="mainnet"
fi
if [ -z "$gas_budget" ]; then
       gas_budget=1000000000
fi
if [ -z "$fee_rate_percent" ]; then
       fee_rate_percent=10
fi
if [ -z "$fee_collector" ]; then
       fee_collector="0x5d18e6f886f43e48375f6d8beab6c740b9f6f1e7382eda22ea82990a12df497b"

deployments="../../deployments-$env_name.json"
config="/root/.sui/sui_config/$env_name-client.yaml"

package=`cat $deployments | jq -r ".abex_core.package"`
package_v1_1_3=`cat $deployments | jq -r ".abex_core.package_v1_1_3"`
admin_cap=`cat $deployments | jq -r ".abex_core.admin_cap"`
market=`cat $deployments | jq -r ".abex_core.market"`


# set fee config
log=`sui client --client.config $config \
       call --gas-budget ${gas_budget} \
              --package ${package_v1_1_3} \
              --module market \
              --function set_fee_config \
              --type-args $package::alp::ALP \
              --args ${admin_cap} \
                     ${market} \
                     ${fee_rate_percent} \
                     ${fee_collector}`
echo "$log"
