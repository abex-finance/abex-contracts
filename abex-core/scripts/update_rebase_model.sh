#!/bin/bash

read -p "Import the env name (default: mainnet): " env_name
read -p "Import gas budget (default: 1000000000): " gas_budget
read -p "Import param base rate: (default: 100000000000000): " param_base
read -p "Import param multiplier (default: 100000000000000000): " param_multiplier

if [ -z "$gas_budget" ]; then
       gas_budget=1000000000
fi
if [ -z "$env_name" ]; then
       env_name="mainnet"
fi
deployments="../../deployments-$env_name.json"
config="/root/.sui/sui_config/$env_name-client.yaml"

if [ -z "${param_base}" ]; then
       param_base=100000000000000
fi
if [ -z "${param_multiplier}" ]; then
       param_multiplier=100000000000000000
fi

package=`cat $deployments | jq -r ".abex_core.package"`
admin_cap=`cat $deployments | jq -r ".abex_core.admin_cap"`
rebase_fee_model=`cat $deployments | jq -r ".abex_core.rebase_fee_model"`

# update rebase model
update_log=`sui client --client.config $config \
       call --gas-budget $gas_budget \
              --package $package \
              --module model \
              --function update_rebase_fee_model \
              --args ${admin_cap} \
                     ${rebase_fee_model} \
                     ${param_base} \
                     ${param_multiplier}`
echo "$update_log"
