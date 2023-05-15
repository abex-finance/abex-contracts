# ABEx Core

## Admin Interaction

### Deployment

```bash
sui client --client.config ~/.sui/sui_config/client.yaml publish --gas-budget 100000 --skip-dependency-verification
```

### Add Vault

```bash
cd scripts
chmod a+x add_vault.sh
./add_vault.sh
```

### Add Symbol

```bash
cd scripts
chmod a+x add_symbol.sh
./add_symbol.sh
```

## ALP Holder Interaction

### Generate market evaluation

Both deposit and withdraw must evaluate the market value first.

- **Step 1**: Create market evaluation

|item|discription|
|-|-|
|package|`package_object`|
|module|"market"|
|function|"create_market_valuation"|
|type arg|"`package_object`::alp::ALP"|
|arg|`market_object`|

returned value is `market_eval`.

- **Step 2**: Create vault evaluation for the first vault, suppose the vault token is TA, type is 0x123::ta::TA.

|item|discription|
|-|-|
|package|`package_object`|
|module|"market"|
|function|"create_vault_valuation"|
|type arg|`package_object`::alp::ALP <br> 0x123::ta::TA|
|arg|`market_object` <br> 0x6 <br> `ta_feeder_object`|

returned value is `vault_eval`.

- **Step 3**: Valuate the first symbol in the vault, suppost the symbol is long TB/USD, type is 0x234::tb::TB.

|item|discription|
|-|-|
|package|`package_object`|
|module|"market"|
|function|"valuate_vault"|
|type arg|`package_object`::alp::ALP <br> 0x123::ta::TA <br> 0x234::tb::TB <br> `package_object`::direction::LONG (long=LONG, short=SHORT)|
|arg|`market_object` <br> `vault_eval` <br> 0x6 <br> `tb_feeder_object`|

- **Step 4**: Repeat **Step 3** and valuate other symbols in the vault.

- **Step 5**: Valuate market.

|item|discription|
|-|-|
|package|`package_object`|
|module|"market"|
|function|"valuate_market"|
|type arg|0x123::ta::TA|
|arg|`market_eval` <br> `vault_eval`|

- **Step 6**: Repeat **Step 2-5** and finish other vaults evaluation in the market.

- **Step 7**: End of evaluation, output `market_eval`

### Deposit

Suppost the deposit token is TA, type is 0x123::ta::TA. Must generate market evaluation before.

|item|discription|
|-|-|
|package|`package_object`|
|module|"market"|
|function|"deposit"|
|type arg|`package_object`::alp::ALP <br> 0x123::ta::TA|
|arg|`market_object` <br> 0x6 <br> `ta_feeder_object` <br> `user_ta_coin_object` <br> `deposit_amount` <br> `market_eval`|

### Withdraw

Suppost the withdraw token is TA, type is 0x123::ta::TA. Must generate market evaluation before.

|item|discription|
|-|-|
|package|`package_object`|
|module|"market"|
|function|"withdraw"|
|type arg|`package_object`::alp::ALP <br> 0x123::ta::TA|
|arg|`market_object` <br> 0x6 <br> `TA_feeder_object` <br> `user_alp_coin_object` <br> `burn_alp_amount` <br> `market_eval`|

## Trader Interaction

### Open Position

Suppost both the vault token and index token is TA, type is 0x123::ta::TA. Must generate market evaluation before.

|item|discription|
|-|-|
|package|`package_object`|
|module|"market"|
|function|"open_position_1"|
|type arg|`package_object`::alp::ALP <br> 0x123::ta::TA <br> `package_object`::direction::LONG|
|arg|`market_object` <br> 0x6 <br> `TA_feeder_object` <br> `trader_coin_object` <br> `entry_amount` <br> `pledge_amount` |
