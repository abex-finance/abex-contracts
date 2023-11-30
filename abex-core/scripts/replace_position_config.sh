#!/bin/bash

read -p "Import the env name (default: mainnet): " env_name
read -p "Import gas budget (default: 1000000000): " gas_budget
read -p "Import the index coin name: " coin
read -p "Import the symbol direction (default: LONG): " direction
read -p "Import max leverage (default: 10): " max_leverage
read -p "Import min holding duration seconds (default: 20): " min_duration
read -p "Import max reserved multiplier (default: 20): " max_reserved
read -p "Import min collateral value (default: 5000000000000000000): " min_collateral_value
read -p "Import open position fee bps (default 1000000000000000): " open_fee_bps
read -p "Import decrease position fee bps (default 1000000000000000): " decrease_fee_bps
read -p "Import liquidation threshold (default: 980000000000000000): " liq_threshold
read -p "Import liquidation bonus (default: 10000000000000000): " liq_bonus

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
if [ -z "${max_leverage}" ]; then
       max_leverage=10
fi
if [ -z "${min_duration}" ]; then
       min_duration=20
fi
if [ -z "${max_reserved}" ]; then
       max_reserved=20
fi
if [ -z "${min_collateral_value}" ]; then
       min_collateral_value=5000000000000000000
fi
if [ -z "${open_fee_bps}" ]; then
       open_fee_bps=1000000000000000
fi
if [ -z "${decrease_fee_bps}" ]; then
       decrease_fee_bps=1000000000000000
fi
if [ -z "${liq_threshold}" ]; then
       liq_threshold=980000000000000000
fi
if [ -z "${liq_bonus}" ]; then
       liq_bonus=10000000000000000
fi

package=`cat $deployments | jq -r ".abex_core.package"`
package_v1_1_1=`cat $deployments | jq -r ".abex_core.package_v1_1_1"`
admin_cap=`cat $deployments | jq -r ".abex_core.admin_cap"`
coin_module=`cat $deployments | jq -r ".coins.$coin.module"`
declare -l symbol=${direction}_${coin}
position_config=`cat $deployments | jq -r ".abex_core.symbols.$symbol.position_config"`

# replace position config
log=`sui client --client.config $config \
       call --gas-budget ${gas_budget} \
              --package ${package_v1_1_1} \
              --module market \
              --function replace_position_config \
              --type-args ${coin_module} $package::market::$direction \
              --args ${admin_cap} \
                     ${position_config} \
                     ${max_leverage} \
                     ${min_duration} \
                     ${max_reserved} \
                     ${min_collateral_value} \
                     ${open_fee_bps} \
                     ${decrease_fee_bps} \
                     ${liq_threshold} \
                     ${liq_bonus}`
echo "$log"
