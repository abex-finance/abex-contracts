#!/bin/bash

read -p "Import the env name (default: mainnet): " env_name
read -p "Import gas budget (default: 1000000000): " gas_budget
read -p "Import the rebate rate (default: 200000000000000000): " rebate_rate

if [ -z "$env_name" ]; then
       env_name="mainnet"
fi
if [ -z "$gas_budget" ]; then
       gas_budget=1000000000
fi
if [ -z "$rebate_rate" ]; then
       rebate_rate=200000000000000000
fi

deployments="../../deployments-$env_name.json"
config="/root/.sui/sui_config/$env_name-client.yaml"

package=`cat $deployments | jq -r ".abex_core.package"`
package_v1_1_3=`cat $deployments | jq -r ".abex_core.package_v1_1_3"`
admin_cap=`cat $deployments | jq -r ".abex_core.admin_cap"`
market=`cat $deployments | jq -r ".abex_core.market"`

# set rebate rate
log=`sui client --client.config $config \
       call --gas-budget ${gas_budget} \
              --package ${package_v1_1_3} \
              --module market \
              --function set_rebate_rate_v1_1 \
              --type-args $package::alp::ALP \
              --args ${admin_cap} \
                     ${market} \
                     ${rebate_rate}`
echo "$log"
