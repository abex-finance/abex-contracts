
module abex_core::agg_price {
    use sui::math::pow;
    use sui::object::{Self, ID};
    use sui::coin::{Self, CoinMetadata};

    // use switchboard_std::math::Self as switchboard_math;
    // use switchboard_std::aggregator::{
    //     Self as switchboard_feeder, Aggregator as SwitchboardFeeder,
    // };

    use abex_feeder::native_feeder::{Self, NativeFeeder};

    use abex_core::decimal::{Self, Decimal};

    friend abex_core::market;

    struct AggPrice has drop {
        price: Decimal,
        precision: u64,
    }

    struct AggPriceConfig has store {
        max_interval: u64,
        precision: u64,
        feeder: ID,
    }

    const ERR_INVALID_FEEDER_ADDRESS: u64 = 0;
    const ERR_FEEDER_INACTIVE: u64 = 1;
    const ERR_PRICE_EXPIRED: u64 = 2;
    const ERR_NEGATIVE_PRICE: u64 = 3;

    public(friend) fun new_agg_price_config<T>(
        max_interval: u64,
        coin_metadata: &CoinMetadata<T>,
        feeder: &NativeFeeder,
    ): AggPriceConfig {
        AggPriceConfig {
            max_interval,
            precision: pow(10, coin::get_decimals(coin_metadata)),
            feeder: object::id(feeder),
        }
    }

    public fun parse_native_feeder(
        config: &AggPriceConfig,
        feeder: &NativeFeeder,
        timestamp: u64,
    ): AggPrice {
        assert!(
            config.feeder == object::id(feeder),
            ERR_INVALID_FEEDER_ADDRESS,
        );
        assert!(native_feeder::enabled(feeder), ERR_FEEDER_INACTIVE);

        let last_timestamp = native_feeder::last_update(feeder);
        assert!(
            last_timestamp + config.max_interval >= timestamp,
            ERR_PRICE_EXPIRED,
        );

        let (exp, value) = native_feeder::value(feeder);

        AggPrice {
            price: decimal::div_by_u64(decimal::from_u128(value), pow(10, exp)),
            precision: config.precision,
        }
    }

    // public fun parse_switchboard_feeder(
    //     config: &AggPriceConfig,
    //     feeder: &SwitchboardFeeder,
    //     timestamp: u64,
    // ): AggPrice {
    //     assert!(
    //         config.feeder == object::id(feeder),
    //         ERR_INVALID_FEEDER_ADDRESS,
    //     );

    //     let (value, last_timestamp) = switchboard_feeder::latest_value(feeder);
    //     assert!(
    //         last_timestamp + config.max_interval >= timestamp,
    //         ERR_PRICE_EXPIRED,
    //     );
    //     let (val, exp, neg) = switchboard_math::unpack(value);
    //     assert!(!neg, ERR_NEGATIVE_PRICE);

    //     AggPrice {
    //         price: decimal::div_by_u64(decimal::from_u128(val), pow(10, exp)),
    //         precision: config.precision,
    //     }
    // }

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