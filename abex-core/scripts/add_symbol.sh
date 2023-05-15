#!/bin/bash

read -p "Import the env name (default: testnet): " env_name
read -p "Import gas budget (default: 1000000000): " gas_budget
read -p "Import the index coin name: " coin
read -p "Import the symbol direction (default: LONG): " direction
read -p "Import max price interval in seconds (default: 90): " max_interval
read -p "Import param multiplier (default: 25000000000000000): " param_multiplier
read -p "Import param max (default: 5000000000000000): " param_max
read -p "Import max laverage (default: 100): " max_laverage
read -p "Import min holding duration seconds (default: 30): " min_duration
read -p "Import max reserved multiplier (default: 10): " max_reserved
read -p "Import min position size (default: 10000000000000000000): " min_size
read -p "Import open position fee bps (default 1000000000000000): " open_fee_bps
read -p "Import decrease position fee bps (default 1000000000000000): " decrease_fee_bps
read -p "Import liquidation threshold (default: 980000000000000000): " liq_threshold
read -p "Import liquidation bonus (default: 10000000000000000): " liq_bonus
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
if [ -z "${max_interval}" ]; then
       max_interval=90
fi
if [ -z "${param_multiplier}" ]; then
    param_multiplier=25000000000000000
fi
if [ -z "${param_max}" ]; then
    param_max=5000000000000000
fi
if [ -z "${max_laverage}" ]; then
       max_laverage=100
fi
if [ -z "${min_duration}" ]; then
       min_duration=30
fi
if [ -z "${max_reserved}" ]; then
       max_reserved=10
fi
if [ -z "${min_size}" ]; then
       min_size=10000000000000000000
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
admin_cap=`cat $deployments | jq -r ".abex_core.admin_cap"`
market=`cat $deployments | jq -r ".abex_core.market"`
coin_module=`cat $deployments | jq -r ".coins.$coin.module"`
coin_metadata=`cat $deployments | jq -r ".coins.$coin.metadata"`
native_feeder=`cat $deployments | jq -r ".abex_feeder.feeder.$coin"`

# add new symbol
add_log=`sui client --client.config $config \
       call --gas-budget $gas_budget \
              --package $package \
              --module market \
              --function add_new_symbol \
              --type-args $package::alp::ALP ${coin_module} $package::market::$direction \
              --args ${admin_cap} \
                     $market \
                     ${max_interval} \
                     ${coin_metadata} \
                     ${native_feeder} \
                     ${param_multiplier} \
                     ${param_max} \
                     ${max_laverage} \
                     ${min_duration} \
                     ${max_reserved} \
                     ${min_size} \
                     ${open_fee_bps} \
                     ${decrease_fee_bps} \
                     ${liq_threshold} \
                     ${liq_bonus}`
echo "$add_log"

ok=`echo "$add_log" | grep "Status : Success"`
if [ -n "$ok" ]; then
       fee_model=`echo "${add_log}" | grep "$package::model::FundingFeeModel" -A 1 | grep objectId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`
       position_config=`echo "${add_log}" | grep "$package::market::WrappedPositionConfig" -A 1 | grep objectId | awk -F 'String\\("' '{print $2}' | awk -F '"\\)' '{print $1}'`

       symbol="${direction}_${coin}"
       declare -l symbol=$symbol
       json_content=`jq ".abex_core.symbols.$symbol = {}" $deployments`
       json_content=`echo "$json_content" | jq ".abex_core.symbols.$symbol.supported_collaterals = []"`
       json_content=`echo "$json_content" | jq ".abex_core.symbols.$symbol.funding_fee_model = \"$fee_model\""`
       json_content=`echo "$json_content" | jq ".abex_core.symbols.$symbol.position_config = \"${position_config}\""`

       if [ -n "$json_content" ]; then
              echo "$json_content" | jq . > $deployments
              echo "Update $deployments finished!"
       else
              echo "Update $deployments failed!"
       fi
fi

for c_coin in ${c_coins[*]}; do
       c_coin_module=`cat $deployments | jq -r ".coins.${c_coin}.module"`
       # add collateral to symbol
       add_log=`sui client --client.config $config \
              call --gas-budget $gas_budget \
                     --package $package \
                     --module market \
                     --function add_collateral_to_symbol \
                     --type-args $package::alp::ALP ${c_coin_module} ${coin_module} $package::market::$direction \
                     --args ${admin_cap} $market`
       echo "$add_log"

       ok=`echo "$add_log" | grep "Status : Success"`
       if [ -n "$ok" ]; then
              symbol="${direction}_${coin}"
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
