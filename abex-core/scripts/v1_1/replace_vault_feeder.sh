#!/bin/bash

read -p "Import the env name (default: mainnet): " env_name
read -p "Import gas budget (default: 1000000000): " gas_budget
read -p "Import vault coin name: " coin

if [ -z "$gas_budget" ]; then
       gas_budget=1000000000
fi
if [ -z "$env_name" ]; then
       env_name="mainnet"
fi
deployments="../../deployments-$env_name.json"
config="/root/.sui/sui_config/$env_name-client.yaml"

package=`cat $deployments | jq -r ".abex_core.package"`
package_v1_1=`cat $deployments | jq -r ".abex_core.package_v1_1"`
admin_cap=`cat $deployments | jq -r ".abex_core.admin_cap"`
market=`cat $deployments | jq -r ".abex_core.market"`
coin_module=`cat $deployments | jq -r ".coins.$coin.module"`
pyth_feeder=`cat $deployments | jq -r ".pyth_feeder.feeder.$coin"`

# replace vault feeder
replace_log=`sui client --client.config $config \
       call --gas-budget ${gas_budget} \
              --package ${package_v1_1} \
              --module market \
              --function replace_vault_feeder \
              --type-args $package::alp::ALP ${coin_module} \
              --args ${admin_cap} $market ${pyth_feeder}`
echo "${replace_log}"
