#!/bin/bash

read -p "Import the env name (default: testnet): " env_name
read -p "Import gas budget (default: 1000000000): " gas_budget
read -p "Import the coin name: " coin
read -p "Import mint amount: " amount
read -p "Import recipient address: " recipient

if [ -z "$gas_budget" ]; then
       gas_budget="1000000000"
fi
if [ -z "$env_name" ]; then
       env_name="testnet"
fi
deployments="../../deployments-$env_name.json"
config="/root/.sui/sui_config/$env_name-client.yaml"

coin_module=`cat $deployments | jq -r ".coins.$coin.module"`
treasury=`cat $deployments | jq -r ".coins.$coin.treasury"`

sui client --client.config $config \
       call --gas-budget $gas_budget \
              --package 0x2 \
              --module coin \
              --function mint_and_transfer \
              --type-args $coin_module \
              --args $treasury $amount $recipient
