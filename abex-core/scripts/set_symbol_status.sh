#!/bin/bash

read -p "Import the env name (default: mainnet): " env_name
read -p "Import gas budget (default: 1000000000): " gas_budget
read -p "Import the index coin name: " coin
read -p "Import the symbol direction (default: LONG): " direction
read -p "Import the open position flag (default: true): " open_flag
read -p "Import the decrease position flag (default: true): " decrease_flag
read -p "Import the liquidate position flag (default: true): " liquidate_flag

if [ -z "$gas_budget" ]; then
       gas_budget=1000000000
fi
if [ -z "$env_name" ]; then
       env_name="mainnet"
fi
deployments="../../deployments-$env_name.json"
config="/root/.sui/sui_config/$env_name-client.yaml"

if [ -z "$direction" ]; then
       direction="LONG"
fi
if [ -z "${open_flag}" ]; then
       open_flag=true
fi
if [ -z "${decrease_flag}" ]; then
       decrease_flag=true
fi
if [ -z "${liquidate_flag}" ]; then
       liquidate_flag=true
fi

package=`cat $deployments | jq -r ".abex_core.package"`
package_v1_1_1=`cat $deployments | jq -r ".abex_core.package_v1_1_1"`
admin_cap=`cat $deployments | jq -r ".abex_core.admin_cap"`
market=`cat $deployments | jq -r ".abex_core.market"`
coin_module=`cat $deployments | jq -r ".coins.$coin.module"`

# set symbol status
log=`sui client --client.config $config \
       call --gas-budget ${gas_budget} \
              --package ${package_v1_1_1} \
              --module market \
              --function set_symbol_status \
              --type-args $package::alp::ALP ${coin_module} $package::market::$direction \
              --args ${admin_cap} \
                     ${market} \
                     ${open_flag} \
                     ${decrease_flag} \
                     ${liquidate_flag}`
echo "$log"

