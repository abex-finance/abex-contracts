#!/bin/bash

read -p "Import the config path (default: "/root/.sui/sui_config/devnet-client.yaml"): " config

if [ -z "$config" ]; then
    config="/root/.sui/sui_config/devnet-client.yaml"
fi

all_gas=`sui client --client.config $config gas | awk 'NR > 2'`
if [ `echo "$all_gas" | wc -l` -gt 2 ]; then
    gas_budget=`echo "$all_gas" | awk '{if (NR==1) {print $3}}'`
    main_gas=`echo "$all_gas" | awk '{if (NR==2) {print $1}}'`
    aux_gas=""
    for gas in `echo "$all_gas" | awk '{if (NR > 2) {print $1}}'`; do
        if [ -z $aux_gas ]; then
            aux_gas="$gas"
        else
            aux_gas="$aux_gas,$gas"
        fi
    done

    sui client --client.config $config call --gas-budget $gas_budget \
                                            --package 0x0000000000000000000000000000000000000000000000000000000000000002 \
                                            --module pay \
                                            --function join_vec \
                                            --type-args 0x0000000000000000000000000000000000000000000000000000000000000002::sui::SUI \
                                            --args $main_gas "[$aux_gas]"
fi
