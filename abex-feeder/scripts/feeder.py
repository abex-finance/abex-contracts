# Fetch the price of a given token from coingecko

import random
import subprocess
import time
import requests
import json
import os

# Get the token name from the environment variable
token = os.environ['TOKEN']

feeder_map = {
    'sui': '0xb37df8a461dbd7c5df963544320cf54a0ab96445',
    'usdt': '0x33134da8a9ef5010ec4222d2c4499bf604d7cbd4',
    'btc': '0x64aca68029bb832219611fcb9f85df64e4c9b6c3',
}

coingecko_map = {
    'sui': 'sui',
    'usdt': 'tether',
    'btc': 'bitcoin',
}

# Get the token price from coingecko
def get_price(token):
    if token == 'sui':
        return random.random() * 100 + 1000
    url = 'https://api.coingecko.com/api/v3/simple/price?ids=' + coingecko_map[token] + '&vs_currencies=usd'
    response = requests.get(url)
    data = json.loads(response.text)
    return data[coingecko_map[token]]['usd']

# Command:
# sui client --client.config ~/.sui/sui_config/sui-feeder.yaml call --package 0x24987ad6a88fc0812bdb569155128ddb62f359d1 --module native_feeder --function feed --gas-budget 10000 --args 0x0000 0x6429c5f5790f41fada2a86f24224d523bd0c71eb 10 100000000
# Run the command every 10 seconds

def run_command(command):
    process = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return process.stdout.decode('utf-8')

while True:
    price = 0
    try:
        price = get_price(token)
    except Exception:
        pass

    exp = 9
    command = f'sui client --client.config ~/.sui/sui_config/{token}-feeder.yaml call --package 0x07700da7e886a5e40042e155c847fbe400f1aa3e --module native_feeder --function feed --gas-budget 10000 --args {feeder_map[token]} 0x6429c5f5790f41fada2a86f24224d523bd0c71eb {exp} {int(price * (10 ** exp))}'
    print(command)
    if price:
        print(run_command(command))
    time.sleep(10)

