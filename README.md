# ABEx Finance Contracts on Sui Blockchain

## Building Dependencies

Clone the repository

```shell
git clone https://github.com/abex-finance/abex-contracts -b develop
cd abex-contracts
```

Install Sui

```
wget https://github.com/MystenLabs/sui/releases/download/sui-v1.0.0/sui
chmod a+x sui
mv sui ~/.cargo/bin
```

## Deployments

Deployment configuration is a json file as following:

- [ ] Mainnet
- [x] [Testnet](./deployments-testnet.json)  

## Local Deployment

```shell
cd test-coins/scripts
```

### Generate test coins

> **Warning**
> Never deploy on Sui Mainnet.

Deploy Contract

```shell
./deploy.sh
```

Mint coins to recipient

```shell
./mint.sh
```

### Deploy ABEx Feeder

```shell
cd test-coins/scripts
```

Deploy Contract

```shell
./deploy.sh
```

Create Feeder

```shell
./create_feeder.sh
```

Run a Feeder Bot

```shell
python3 feeder3.py --gas=<YOUR_GAS_OBJECT> --token=<COIN_NAME> --source=<DATA_SOURCE> 
```

### Deploy ABEx Core

```shell
cd abex-contracts/abex-core/scripts
```

Deploy Contract

```bash
./deploy.sh
```

Add a new Vault

```bash
./add_vault.sh
```

Add a new Symbol

```bash
./add_symbol.sh
```
