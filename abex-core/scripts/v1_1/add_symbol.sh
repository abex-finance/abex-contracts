#!/bin/bash

read -p "Import the env name (default: mainnet): " env_name
read -p "Import gas budget (default: 1000000000): " gas_budget
read -p "Import the index coin name: " coin
read -p "Import the symbol direction (default: LONG): " direction
read -p "Import max price interval in seconds (default: 20): " max_interval
read -p "Import max price confidence (default: 18446744073709551615): " max_price_confidence
read -p "Import param multiplier (default: 20000000000000000): " param_multiplier
read -p "Import param max (default: 7500000000000000): " param_max
read -p "Import max leverage (default: 10): " max_leverage
read -p "Import min holding duration seconds (default: 20): " min_duration
read -p "Import max reserved multiplier (default: 20): " max_reserved
read -p "Import min collateral value (default: 5000000000000000000): " min_collateral_value
read -p "Import open position fee bps (default 1000000000000000): " open_fee_bps
read -p "Import decrease position fee bps (default 1000000000000000): " decrease_fee_bps
read -p "Import liquidation threshold (default: 980000000000000000): " liq_threshold
read -p "Import liquidation bonus (default: 10000000000000000): " liq_bonus
read -p "Import the collateral coin name: " -a c_coins

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
if [ -z "${max_interval}" ]; then
       max_interval=20
fi
if [ -z "${max_price_confidence}" ]; then
       max_price_confidence=18446744073709551615
fi
if [ -z "${param_multiplier}" ]; then
    param_multiplier=20000000000000000
fi
if [ -z "${param_max}" ]; then
    param_max=7500000000000000
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
package_v1_1=`cat $deployments | jq -r ".abex_core.package_v1_1"`
admin_cap=`cat $deployments | jq -r ".abex_core.admin_cap"`
market=`cat $deployments | jq -r ".abex_core.market"`
coin_module=`cat $deployments | jq -r ".coins.$coin.module"`
coin_metadata=`cat $deployments | jq -r ".coins.$coin.metadata"`
pyth_feeder=`cat $deployments | jq -r ".pyth_feeder.feeder.$coin"`

# add new symbol
add_log=`sui client --client.config $config \
       call --gas-budget $gas_budget \
              --package ${package_v1_1} \
              --module market \
              --function add_new_symbol_v1_1 \
              --type-args $package::alp::ALP ${coin_module} $package::market::$direction \
              --args ${admin_cap} \
                     $market \
                     ${max_interval} \
                     ${max_price_confidence} \
                     ${coin_metadata} \
                     ${pyth_feeder} \
                     ${param_multiplier} \
                     ${param_max} \
                     ${max_leverage} \
                     ${min_duration} \
                     ${max_reserved} \
                     ${min_collateral_value} \
                     ${open_fee_bps} \
                     ${decrease_fee_bps} \
                     ${liq_threshold} \
                     ${liq_bonus}`
echo "${add_log}"

ok=`echo "${add_log}" | grep "Status : Success"`
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
else
       exit 1
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