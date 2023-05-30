
module abex_core::position {
    use sui::math;
    use sui::balance::{Self, Balance};
    
    use abex_core::rate::{Self, Rate};
    use abex_core::srate::{Self, SRate};
    use abex_core::decimal::{Self, Decimal};
    use abex_core::sdecimal::{Self, SDecimal};
    use abex_core::agg_price::{Self, AggPrice};

    friend abex_core::pool;
    friend abex_core::market;

    const ERR_INVALID_PLEDGE: u64 = 0;
    const ERR_INVALID_REDEEM_AMOUNT: u64 = 1;
    const ERR_INVALID_OPEN_AMOUNT: u64 = 2;
    const ERR_INVALID_DECREASE_AMOUNT: u64 = 3;
    const ERR_INSUFFICIENT_COLLATERAL: u64 = 4;
    const ERR_INSUFFICIENT_RESERVED: u64 = 5;
    const ERR_POSITION_SIZE_TOO_LESS: u64 = 6;
    const ERR_HOLDING_DURATION_TOO_SHORT: u64 = 7;
    const ERR_LEVERAGE_TOO_LARGE: u64 = 8;
    const ERR_LIQUIDATION_TRIGGERED: u64 = 9;
    const ERR_LIQUIDATION_NOT_TRIGGERED: u64 = 10;
    const ERR_EXCEED_MAX_RESERVED: u64 = 11;

    // === Storage ===

    struct PositionConfig has copy, drop, store {
        max_leverage: u64,
        min_holding_duration: u64,
        max_reserved_multiplier: u64,
        min_size: Decimal,
        open_fee_bps: Rate,
        decrease_fee_bps: Rate,
        // liquidation_threshold + liquidation_bonus < 100%
        liquidation_threshold: Rate,
        liquidation_bonus: Rate,
    }

    spec PositionConfig {
        pragma aborts_if_is_strict;
        ensures liquidation_threshold.value + liquidation_bonus.value
            < 1_000_000_000_000_000_000;
    }

    struct Position<phantom C> has store {
        config: PositionConfig,
        open_timestamp: u64,
        position_amount: u64,
        position_size: Decimal,
        reserving_fee_amount: Decimal,
        funding_fee_value: SDecimal,
        last_reserving_rate: Rate,
        last_funding_rate: SRate,
        reserved: Balance<C>,
        collateral: Balance<C>,
    }

    public(friend) fun new_position_config(
        max_leverage: u64,
        min_holding_duration: u64,
        max_reserved_multiplier: u64,
        min_size: u256,
        open_fee_bps: u128,
        decrease_fee_bps: u128,
        liquidation_threshold: u128,
        liquidation_bonus: u128,
    ): PositionConfig {
        PositionConfig {
            max_leverage,
            min_holding_duration,
            max_reserved_multiplier,
            min_size: decimal::from_raw(min_size),
            open_fee_bps: rate::from_raw(open_fee_bps),
            decrease_fee_bps: rate::from_raw(decrease_fee_bps),
            liquidation_threshold: rate::from_raw(liquidation_threshold),
            liquidation_bonus: rate::from_raw(liquidation_bonus),
        }
    }

    public(friend) fun open_position<C>(
        config: PositionConfig,
        collateral_price: &AggPrice,
        index_price: &AggPrice,
        reserved: Balance<C>,
        collateral: Balance<C>,
        open_amount: u64,
        reserving_rate: Rate,
        funding_rate: SRate,
        timestamp: u64,
    ): (Position<C>, Balance<C>, Decimal) {
        assert!(balance::value(&collateral) > 0, ERR_INVALID_PLEDGE);
        assert!(open_amount > 0, ERR_INVALID_OPEN_AMOUNT);
        assert!(
            balance::value(&collateral) * config.max_reserved_multiplier
                >= balance::value(&reserved),
            ERR_EXCEED_MAX_RESERVED,
        );
        // compute position size
        let open_size = agg_price::coins_to_value(index_price, open_amount);
        assert!(
            decimal::ge(&open_size, &config.min_size),
            ERR_POSITION_SIZE_TOO_LESS,
        );

        // compute open position fee
        let open_fee_value = decimal::mul_with_rate(open_size, config.open_fee_bps);
        let open_fee_amount = decimal::ceil_u64(
            agg_price::value_to_coins(collateral_price, open_fee_value)
        );
        assert!(
            open_fee_amount < balance::value(&collateral),
            ERR_INSUFFICIENT_COLLATERAL,
        );
        let open_fee = balance::split(&mut collateral, open_fee_amount);

        // create position
        let position = Position {
            config,
            open_timestamp: timestamp,
            position_amount: open_amount,
            position_size: open_size,
            reserving_fee_amount: decimal::zero(),
            funding_fee_value: sdecimal::zero(),
            last_reserving_rate: reserving_rate,
            last_funding_rate: funding_rate,
            reserved,
            collateral,
        };

        // validate leverage
        let ok = check_leverage(&position, collateral_price, index_price);
        assert!(ok, ERR_LEVERAGE_TOO_LARGE);

        (position, open_fee, open_fee_value)
    }

    public(friend) fun decrease_reserved_from_position<C>(
        position: &mut Position<C>,
        decrease_amount: u64,
        reserving_rate: Rate,
    ): Balance<C> {
        assert!(
            decrease_amount < balance::value(&position.reserved),
            ERR_INSUFFICIENT_RESERVED,
        );

        // update dynamic fee
        position.reserving_fee_amount = reserving_fee_amount(position, reserving_rate);
        position.last_reserving_rate = reserving_rate;        

        balance::split(&mut position.reserved, decrease_amount)
    }

    public(friend) fun pledge_in_position<C>(
        position: &mut Position<C>,
        pledge: Balance<C>,
    ) {
        // handle pledge
        assert!(balance::value(&pledge) > 0, ERR_INVALID_PLEDGE);
        let _ = balance::join(&mut position.collateral, pledge);
    }

    public(friend) fun redeem_from_position<C>(
        position: &mut Position<C>,
        collateral_price: &AggPrice,
        index_price: &AggPrice,
        long: bool,
        redeem_amount: u64,
        reserving_rate: Rate,
        funding_rate: SRate,
        timestamp: u64,
    ): Balance<C> {
        assert!(
            redeem_amount > 0
                && redeem_amount < balance::value(&position.collateral),
            ERR_INVALID_REDEEM_AMOUNT,
        );

        // compute delta size
        let delta_size = compute_delta_size(position, index_price, long);

        // check holding duration
        let ok = check_holding_duration(position, &delta_size, timestamp);
        assert!(ok, ERR_HOLDING_DURATION_TOO_SHORT);

        // update dynamic fee
        position.reserving_fee_amount = reserving_fee_amount(position, reserving_rate);
        position.last_reserving_rate = reserving_rate;
        position.funding_fee_value = funding_fee_value(position, funding_rate);
        position.last_funding_rate = funding_rate;

        // redeem
        let redeem = balance::split(&mut position.collateral, redeem_amount);

        // validate leverage
        ok = check_leverage(position, collateral_price, index_price);
        assert!(ok, ERR_LEVERAGE_TOO_LARGE);

        // validate liquidation
        ok = check_liquidation(position, &delta_size, collateral_price);
        assert!(!ok, ERR_LIQUIDATION_TRIGGERED);

        redeem
    }

    public(friend) fun decrease_position<C>(
        position: &mut Position<C>,
        collateral_price: &AggPrice,
        index_price: &AggPrice,
        long: bool,
        decrease_amount: u64,
        reserving_rate: Rate,
        funding_rate: SRate,
        timestamp: u64,
    ): (
        bool,
        u64,
        u64,
        Decimal,
        Decimal,
        Decimal,
        Decimal,
        SDecimal,
        Balance<C>,
        Balance<C>,
    ) {
        assert!(
            decrease_amount > 0 && decrease_amount < position.position_amount,
            ERR_INVALID_DECREASE_AMOUNT,
        );
        let decrease_size = decimal::div_by_u64(
            decimal::mul_with_u64(position.position_size, decrease_amount),
            position.position_amount,
        );

        // compute delta size
        let delta_size = compute_delta_size(position, index_price, long);
        let settled_delta_size = sdecimal::div_by_u64(
            sdecimal::mul_with_u64(delta_size, decrease_amount),
            position.position_amount,
        );
        delta_size = sdecimal::sub(delta_size, settled_delta_size);

        // check holding duration
        let ok = check_holding_duration(position, &delta_size, timestamp);
        assert!(ok, ERR_HOLDING_DURATION_TOO_SHORT);

        // update dynamic fee
        position.reserving_fee_amount = reserving_fee_amount(position, reserving_rate);
        position.last_reserving_rate = reserving_rate;
        position.funding_fee_value = funding_fee_value(position, funding_rate);
        position.last_funding_rate = funding_rate;

       // compute fee
        let reserving_fee_amount = position.reserving_fee_amount;
        let funding_fee_value = position.funding_fee_value;
        let decrease_fee_value = decimal::mul_with_rate(
            decrease_size,
            position.config.decrease_fee_bps,
        );
        let reserving_fee_value = agg_price::coins_to_value(
            collateral_price,
            decimal::ceil_u64(reserving_fee_amount),
        );
        // impact fee on settled delta size
        settled_delta_size = sdecimal::sub(
            settled_delta_size,
            sdecimal::add_with_decimal(
                funding_fee_value,
                decimal::add(decrease_fee_value, reserving_fee_value),
            ),
        );

        // settlement
        let has_profit = sdecimal::is_positive(&settled_delta_size);
        let settled_amount = agg_price::value_to_coins(
            collateral_price,
            sdecimal::value(&settled_delta_size),
        );
        let (
            settled_amount,
            decreased_reserved_amount,
            to_vault,
            to_trader,
        ) = if (has_profit) {
            let profit_amount = decimal::floor_u64(settled_amount);
            assert!(
                profit_amount < balance::value(&position.reserved),
                ERR_INSUFFICIENT_RESERVED,
            );
            (
                profit_amount,
                profit_amount,
                balance::zero(),
                balance::split(&mut position.reserved, profit_amount),
            )
        } else {
            let loss_amount = decimal::ceil_u64(settled_amount);
            assert!(
                loss_amount < balance::value(&position.collateral),
                ERR_INSUFFICIENT_COLLATERAL,    
            );
            (
                loss_amount,
                0,
                balance::split(&mut position.collateral, loss_amount),
                balance::zero(),
            )
        };

        // update position
        position.position_amount = position.position_amount - decrease_amount;
        position.position_size = decimal::sub(position.position_size, decrease_size);
        assert!(
            decimal::ge(&position.position_size, &position.config.min_size),
            ERR_POSITION_SIZE_TOO_LESS,
        );
        position.reserving_fee_amount = decimal::zero();
        position.funding_fee_value = sdecimal::zero();

        // validate leverage
        ok = check_leverage(position, collateral_price, index_price);
        assert!(ok, ERR_LEVERAGE_TOO_LARGE);

        // check liquidation
        ok = check_liquidation(position, &delta_size, collateral_price);
        assert!(!ok, ERR_LIQUIDATION_TRIGGERED);

        (
            has_profit,
            settled_amount,
            decreased_reserved_amount,
            decrease_size,
            reserving_fee_amount,
            decrease_fee_value,
            reserving_fee_value,
            funding_fee_value,
            to_vault,
            to_trader,
        )
    }

    public(friend) fun close_position<C>(
        position: Position<C>,
        collateral_price: &AggPrice,
        index_price: &AggPrice,
        long: bool,
        reserving_rate: Rate,
        funding_rate: SRate,
        timestamp: u64,
    ): (
        bool,
        u64,
        u64,
        u64,
        Decimal,
        Decimal,
        Decimal,
        Decimal,
        SDecimal,
        Balance<C>,
        Balance<C>,
    ) {
        // compute delta size
        let delta_size = compute_delta_size(&position, index_price, long);

        // check holding duration
        let ok = check_holding_duration(&position, &delta_size, timestamp);
        assert!(ok, ERR_HOLDING_DURATION_TOO_SHORT);

        // update dynamic fee
        position.reserving_fee_amount = reserving_fee_amount(&position, reserving_rate);
        position.last_reserving_rate = reserving_rate;
        position.funding_fee_value = funding_fee_value(&position, funding_rate);
        position.last_funding_rate = funding_rate;

        // unwrap position
        let Position {
            config,
            open_timestamp: _,
            position_amount,
            position_size,
            reserving_fee_amount,
            funding_fee_value,
            last_reserving_rate: _,
            last_funding_rate: _,
            reserved: to_vault,
            collateral: to_trader,
        } = position;
        let reserved_amount = balance::value(&to_vault);

        // compute fee
        let close_fee_value = decimal::mul_with_rate(
            position_size,
            config.decrease_fee_bps,
        );
        let reserving_fee_value = agg_price::coins_to_value(
            collateral_price,
            decimal::ceil_u64(reserving_fee_amount),
        );
        // impact fee on delta size
        delta_size = sdecimal::sub(
            delta_size,
            sdecimal::add_with_decimal(
                funding_fee_value,
                decimal::add(close_fee_value, reserving_fee_value),
            ),
        );

        // settlement
        let has_profit = sdecimal::is_positive(&delta_size);
        let settled_amount = agg_price::value_to_coins(
            collateral_price,
            sdecimal::value(&delta_size),
        );
        let settled_amount = if (has_profit) {
            let profit_amount = math::min(
                decimal::floor_u64(settled_amount),
                balance::value(&to_vault),
            );
            balance::join(
                &mut to_trader,
                balance::split(&mut to_vault, profit_amount),
            )
        } else {
            let loss_amount = math::min(
                decimal::ceil_u64(settled_amount),
                balance::value(&to_trader),
            );
            balance::join(
                &mut to_vault,
                balance::split(&mut to_trader, loss_amount),
            )
        };

        (
            has_profit,
            settled_amount,
            position_amount,
            reserved_amount,
            position_size,
            reserving_fee_amount,
            close_fee_value,
            reserving_fee_value,
            funding_fee_value,
            to_vault,
            to_trader,
        )
    }

    public(friend) fun liquidate_position<C>(
        position: Position<C>,
        collateral_price: &AggPrice,
        index_price: &AggPrice,
        long: bool,
        reserving_rate: Rate,
        funding_rate: SRate,
    ): (
        u64,
        u64,
        u64,
        u64,
        Decimal,
        Decimal,
        Decimal,
        SDecimal,
        Balance<C>,
        Balance<C>,
    ) {
        // compute delta size
        let delta_size = compute_delta_size(&position, index_price, long);

        // update dynamic fee
        position.reserving_fee_amount = reserving_fee_amount(&position, reserving_rate);
        position.last_reserving_rate = reserving_rate;
        position.funding_fee_value = funding_fee_value(&position, funding_rate);
        position.last_funding_rate = funding_rate;

        // compute fee
        let reserving_fee_value = agg_price::coins_to_value(
            collateral_price,
            decimal::ceil_u64(position.reserving_fee_amount),
        );
        // impact fee on delta size
        delta_size = sdecimal::sub(
            delta_size,
            sdecimal::add_with_decimal(
                position.funding_fee_value,
                reserving_fee_value,  
            ),
        );

        // liquidation check
        let ok = check_liquidation(&position, &delta_size, collateral_price);
        assert!(ok, ERR_LIQUIDATION_NOT_TRIGGERED);

        // unwrap position
        let Position {
            config,
            open_timestamp: _,
            position_amount,
            position_size,
            reserving_fee_amount,
            funding_fee_value,
            last_reserving_rate: _,
            last_funding_rate: _,
            reserved: to_vault,
            collateral,
        } = position;
        let reserved_amount = balance::value(&to_vault);

        // liquidation bonus
        let bonus_amount = decimal::floor_u64(
            decimal::mul_with_rate(
                decimal::from_u64(balance::value(&collateral)),
                config.liquidation_bonus,
            )
        );
        let to_liquidator = balance::split(&mut collateral, bonus_amount);
        let loss_amount = balance::join(&mut to_vault, collateral);
    
        (
            bonus_amount,
            loss_amount,
            position_amount,
            reserved_amount,
            position_size,
            reserving_fee_amount,
            reserving_fee_value,
            funding_fee_value,
            to_vault,
            to_liquidator,
        )
    }

    // TODO: finish this
    // public(friend) fun emergency_close_position<C>(
    //     position: Position<C>,
    //     reserving_rate: Rate,
    // ): (Balance<C>, Balance<C>) {
    //     // update dynamic fee
    //     position.reserving_fee_amount = reserving_fee_amount(&position, reserving_rate);
    //     position.last_reserving_rate = reserving_rate;

    // }

    //////////////////////////// public read functions ////////////////////////////

    public fun position_config<C>(position: &Position<C>): &PositionConfig {
        &position.config
    }

    public fun open_timestamp<C>(position: &Position<C>): u64 {
        position.open_timestamp
    }

    public fun position_amount<C>(position: &Position<C>): u64 {
        position.position_amount
    }

    public fun position_size<C>(position: &Position<C>): Decimal {
        position.position_size
    }

    public fun collateral_amount<C>(position: &Position<C>): u64 {
        balance::value(&position.collateral)
    }

    public fun reserved_amount<C>(position: &Position<C>): u64 {
        balance::value(&position.reserved)
    }

    public fun reserving_fee_amount<C>(
        position: &Position<C>,
        reserving_rate: Rate,
    ): Decimal {
        let delta_fee = decimal::mul_with_rate(
            decimal::from_u64(balance::value(&position.reserved)),
            rate::sub(reserving_rate, position.last_reserving_rate),
        );
        decimal::add(position.reserving_fee_amount, delta_fee)
    }

    public fun funding_fee_value<C>(
        position: &Position<C>,
        funding_rate: SRate,
    ): SDecimal {
        let delta_rate = srate::sub(
            funding_rate,
            position.last_funding_rate,
        );
        let delta_fee = sdecimal::from_decimal(
            srate::is_positive(&delta_rate),
            decimal::mul_with_rate(
                position.position_size,
                srate::value(&delta_rate),
            ),
        );
        sdecimal::add(position.funding_fee_value, delta_fee)
    }

    // delta_size = |amount * new_price - size|
    public fun compute_delta_size<C>(
        position: &Position<C>,
        index_price: &AggPrice,
        long: bool,
    ): SDecimal {
        let latest_size = agg_price::coins_to_value(
            index_price,
            position.position_amount,
        );
        let cmp = decimal::gt(&latest_size, &position.position_size);
        let (has_profit, delta) = if (cmp) {
            (long, decimal::sub(latest_size, position.position_size))
        } else {
            (!long, decimal::sub(position.position_size, latest_size))
        };

        sdecimal::from_decimal(has_profit, delta)
    }

    public fun check_holding_duration<C>(
        position: &Position<C>,
        delta_size: &SDecimal,
        timestamp: u64,
    ): bool {
        !sdecimal::is_positive(delta_size)
            || position.open_timestamp
                + position.config.min_holding_duration <= timestamp
    }

    public fun check_leverage<C>(
        position: &Position<C>,
        collateral_price: &AggPrice,
        index_price: &AggPrice,
    ): bool {
        let max_size = decimal::mul_with_u64(
            agg_price::coins_to_value(
                collateral_price,
                balance::value(&position.collateral),
            ),
            position.config.max_leverage,
        );
        let latest_size = agg_price::coins_to_value(
            index_price,
            position.position_amount,
        );

        decimal::ge(&max_size, &latest_size)
    }

    public fun check_liquidation<C>(
        position: &Position<C>,
        delta_size: &SDecimal,
        collateral_price: &AggPrice,
    ): bool {
        if (sdecimal::is_positive(delta_size)) {
            false
        } else {
            let collateral_value = agg_price::coins_to_value(
                collateral_price,
                balance::value(&position.collateral),
            );
            decimal::le(
                &decimal::mul_with_rate(
                    collateral_value,
                    position.config.liquidation_threshold,
                ),
                &sdecimal::value(delta_size),
            )
        }
    }

    #[test_only]
    fun default_position_config(): PositionConfig {
        PositionConfig {
            max_leverage: 100,
            min_holding_duration: 30, // 30 seconds
            max_reserved_multiplier: 10, // 10
            min_size: decimal::from_u64(10), // 10 USD
            open_fee_bps: rate::from_raw(1_000_000_000_000_000), // 0.1%
            decrease_fee_bps: rate::from_raw(1_000_000_000_000_000), // 0.01%
            liquidation_threshold: rate::from_percent(95), // 95%,
            liquidation_bonus: rate::from_percent(3), // 3%
        }
    }

    // #[test]
    // fun test_update_dynamic_fee() {
    //     let position = Position {
    //         config: default_position_config(),
    //         last_update: 0,
    //         position_amount: 1_000_000,
    //         position_size: decimal::zero(), // not used here


    //     }
    // }
}
