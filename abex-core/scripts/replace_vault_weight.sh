#!/bin/bash

read -p "Import the env name (default: mainnet): " env_name
read -p "Import gas budget (default: 1000000000): " gas_budget
read -p "Import vault coin name: " coin
read -p "Import weight: " weight

if [ -z "$gas_budget" ]; then
       gas_budget=1000000000
fi
if [ -z "$env_name" ]; then
       env_name="mainnet"
fi
if [ -z "$weight" ]; then
       weight=100000000000000000
fi
deployments="../../deployments-$env_name.json"

package=`cat $deployments | jq -r ".abex_core.package"`
package_v1_1_7=`cat $deployments | jq -r ".abex_core.package_v1_1_7"`
admin_cap=`cat $deployments | jq -r ".abex_core.admin_cap"`
market=`cat $deployments | jq -r ".abex_core.market"`
coin_module=`cat $deployments | jq -r ".coins.$coin.module"`

# replace vault feeder
replace_log=`sui client call --gas-budget ${gas_budget} \
              --package ${package_v1_1_7} \
              --module market \
              --function replace_vault_weight \
              --type-args $package::alp::ALP ${coin_module} \
              --args ${admin_cap} $market ${weight}`
echo "${replace_log}"
