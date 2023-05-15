# Fetch the price of a given token from coingecko

import random
import subprocess
import time
import requests
import json
import os
import threading

# Get the token name from the environment variable
token = os.environ['TOKEN']
env= os.environ['ENV']
gas = os.environ['GAS']
gas_budget = os.environ['GAS_BUDGET']

binance_map = {
    'btc': 'BTCUSDT',
    'eth': 'ETHUSDT',
    'usdc': 'USDCUSDT',
}

def parse_deployments(path, token):
    with open(path, 'r') as f:
        data = json.load(f)
        feeder = data['abex_feeder']
        return feeder["package"], feeder['feeder'][token]

# Get the token price from coingecko
def get_price(token):
    if token == 'sui':
        return random.random() * 10 + 1000
    elif token == "usdt":
        return random.random() * 0.0001 + 1

    url = f'https://api.binance.com/api/v3/avgPrice?symbol={binance_map[token]}'
    response = requests.get(url)
    data = json.loads(response.text)
    return float(data['price'])

# Command:
# sui client --client.config ~/.sui/sui_config/sui-feeder.yaml call --package 0x24987ad6a88fc0812bdb569155128ddb62f359d1 --module native_feeder --function feed --gas-budget 10000 --args 0x0000 0x6429c5f5790f41fada2a86f24224d523bd0c71eb 10 100000000
# Run the command every 1 seconds

def run_command(command):
    process = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output = process.stdout.decode('utf-8')
    print(output)

max_threads = 20  # Adjust this value according to your system's capacity
semaphore = threading.Semaphore(max_threads)

def run_command_with_semaphore(command):
    with semaphore:
        run_command(command)

def execute_command():
    config = f'/root/.sui/sui_config/{env}-{token}-feeder.yaml'
    deployments = f'../../deployments-{env}.json'
    package, feeder = parse_deployments(deployments, token)

    while True:
        price = 0
        try:
            price = get_price(token)
        except Exception:
            pass

        exp = 9
        command = f'sui client --client.config {config} call --package {package} --module native_feeder --function feed --args {feeder} 0x6 {exp} {int(price * (10 ** exp))} --gas {gas} --gas-budget {gas_budget}'
        if price > 0:
            print(command)
            command_thread = threading.Thread(target=run_command_with_semaphore, args=(command,))
            command_thread.start()
        time.sleep(15)

execute_command()
