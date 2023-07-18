
module abex_core::agg_price {
    use sui::math::pow;
    use sui::object::{Self, ID};
    use sui::coin::{Self, CoinMetadata};

    use pyth::pyth::get_price_unsafe;
    use pyth::i64::{Self as pyth_i64};
    use pyth::price::{Self as pyth_price};
    use pyth::price_info::{PriceInfoObject as PythFeeder};

    use abex_core::decimal::{Self, Decimal};

    friend abex_core::market;

    struct AggPrice has drop, store {
        price: Decimal,
        precision: u64,
    }

    struct AggPriceConfig has store {
        max_interval: u64,
        max_confidence: u64,
        precision: u64,
        feeder: ID,
    }

    const ERR_INVALID_PRICE_FEEDER: u64 = 1;
    const ERR_PRICE_STALED: u64 = 2;
    const ERR_EXCEED_PRICE_CONFIDENCE: u64 = 3;
    const ERR_INVALID_PRICE_VALUE: u64 = 4;

    public(friend) fun new_agg_price_config<T>(
        max_interval: u64,
        max_confidence: u64,
        coin_metadata: &CoinMetadata<T>,
        feeder: &PythFeeder,
    ): AggPriceConfig {
        AggPriceConfig {
            max_interval,
            max_confidence,
            precision: pow(10, coin::get_decimals(coin_metadata)),
            feeder: object::id(feeder),
        }
    }

    public fun from_price(config: &AggPriceConfig, price: Decimal): AggPrice {
        AggPrice { price, precision: config.precision }
    }

    public fun parse_pyth_feeder(
        config: &AggPriceConfig,
        feeder: &PythFeeder,
        timestamp: u64,
    ): AggPrice {
        assert!(object::id(feeder) == config.feeder, ERR_INVALID_PRICE_FEEDER);

        let price = get_price_unsafe(feeder);
        assert!(
            pyth_price::get_timestamp(&price) + config.max_interval >= timestamp,
            ERR_PRICE_STALED,
        );
        assert!(
            pyth_price::get_conf(&price) <= config.max_confidence,
            ERR_EXCEED_PRICE_CONFIDENCE,
        );

        let value = pyth_price::get_price(&price);
        // price can not be negative
        let value = pyth_i64::get_magnitude_if_positive(&value);
        // price can not be zero
        assert!(value > 0, ERR_INVALID_PRICE_VALUE);

        let exp = pyth_price::get_expo(&price);
        let price = if (pyth_i64::get_is_negative(&exp)) {
            let exp = pyth_i64::get_magnitude_if_negative(&exp);
            decimal::div_by_u64(decimal::from_u64(value), pow(10, (exp as u8)))
        } else {
            let exp = pyth_i64::get_magnitude_if_positive(&exp);
            decimal::mul_with_u64(decimal::from_u64(value), pow(10, (exp as u8)))
        };

        AggPrice { price, precision: config.precision}
    }

    public fun price_of(self: &AggPrice): Decimal {
        self.price
    }

    public fun precision_of(self: &AggPrice): u64 {
        self.precision
    }

    public fun coins_to_value(self: &AggPrice, amount: u64): Decimal {
        decimal::div_by_u64(
            decimal::mul_with_u64(self.price, amount),
            self.precision,
        )
    }

    public fun value_to_coins(self: &AggPrice, value: Decimal): Decimal {
        decimal::div(
            decimal::mul_with_u64(value, self.precision),
            self.price,
        )
    }
}