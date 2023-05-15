# Fetch the price of a given token from coingecko

import random
import subprocess
import time
import requests
import json
import os
import threading
import asyncio
import click

from pythclient.pythaccounts import PythPriceAccount
from pythclient.solana import SolanaClient, SolanaPublicKey, PYTHNET_HTTP_ENDPOINT, PYTHNET_WS_ENDPOINT

def parse_deployments(path, token):
    with open(path, 'r') as f:
        data = json.load(f)
        feeder = data['abex_feeder']
        return feeder["package"], feeder['feeder'][token]

def get_binance_price(token: str):
    if token == 'fsui':
        token = 'sui'
    url = f'https://api.binance.com/api/v3/avgPrice?symbol={token.upper()}USDT'
    response = requests.get(url)
    data = json.loads(response.text)
    return float(data['price'])

def get_stable_price(token):
    if token == 'usdt':
        # suppose USDT is always stabled as USD
        return random.random() * 0.0001 + 1
    else:
        raise Exception("Unknown token: {token}")

async def get_pyth_price(token):
    pyth_map = {
        'xau': '8y3WWjvmSmVGWVKH1rCA7VTRmuU7QbJ9axafSsBX5FcD',
        'xag': 'HMVfAm6uuwnPnHRzaqfMhLNyrYHxaczKTbzeDcjBvuDo',
    }
    account_key = SolanaPublicKey(pyth_map[token])
    solana_client = SolanaClient(endpoint=PYTHNET_HTTP_ENDPOINT, ws_endpoint=PYTHNET_WS_ENDPOINT)
    price: PythPriceAccount = PythPriceAccount(account_key, solana_client)

    await price.update()
    await solana_client.close()

    if price.aggregate_price is not None:
        return price.aggregate_price
    else:
        raise Exception("Price is not on trading")

def run_command_with_semaphore(max_threads, command):
    with threading.Semaphore(max_threads):
        process = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output = process.stdout.decode('utf-8')
        print(output)

@click.command()
@click.option('--env', type=str, default='testnet')
@click.option('--gas', type=str)
@click.option('--gas_budget', type=int, default=2000000)
@click.option('--interval', type=int, default=30)
@click.option('--max_threads', type=int, default=1)
@click.option('--token', type=str)
@click.option('--source', type=str, default='binance')
@click.option('--exp', type=int, default=12)
def execute_command(env, gas, gas_budget, interval, max_threads, token, source, exp):
    config = f'/root/.sui/sui_config/{env}-{token}-feeder.yaml'
    deployments = f'../../deployments-{env}.json'
    package, feeder = parse_deployments(deployments, token)

    while True:
        try:
            price = 0
            if source == 'binance':
                price = get_binance_price(token)
            elif source == 'stable':
                price = get_stable_price(token)
            elif source == 'pyth':
                price = asyncio.run(get_pyth_price(token))
            else:
                raise Exception("Unknown source: {source}")
        except Exception:
            pass

        command = f'sui client --client.config {config} call --package {package} --module native_feeder --function feed --args {feeder} 0x6 {exp} {int(price * (10 ** exp))} --gas {gas} --gas-budget {gas_budget}'
        if price > 0:
            print(command)
            command_thread = threading.Thread(target=run_command_with_semaphore, args=(max_threads,command,))
            command_thread.start()
        time.sleep(interval)

execute_command()
