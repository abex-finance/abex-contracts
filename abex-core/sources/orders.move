
module abex_core::orders {
    use std::option::Option;

    use sui::balance::{Self, Balance};
    
    use abex_core::rate::Rate;
    use abex_core::decimal::{Self, Decimal};
    use abex_core::agg_price::{Self, AggPrice};
    use abex_core::position::{Position, PositionConfig};
    use abex_core::model::{ReservingFeeModel, FundingFeeModel};
    use abex_core::pool::{
        Self, Vault, Symbol,
        OpenPositionResult, DecreasePositionResult,
        OpenPositionFailedEvent, DecreasePositionFailedEvent,
    };

    friend abex_core::market;

    const ERR_MISMATCHED_DECREASE_INTENTION: u64 = 1;
    const ERR_ORDER_ALREADY_EXECUTED: u64 = 2;
    const ERR_INDEX_PRICE_NOT_TRIGGERED: u64 = 3;
    const ERR_INVALID_DECREASE_AMOUNT: u64 = 4;

    struct OpenPositionOrder<phantom C, phantom F> has store {
        executed: bool,
        open_amount: u64,
        reserve_amount: u64,
        limited_index_price: AggPrice,
        collateral_price_threshold: Decimal,
        position_config: PositionConfig,
        collateral: Balance<C>,
        fee: Balance<F>,
    }

    struct DecreasePositionOrder<phantom F> has store {
        executed: bool,
        take_profit: bool,
        decrease_amount: u64,
        limited_index_price: AggPrice,
        collateral_price_threshold: Decimal,
        fee: Balance<F>,
    }

    public(friend) fun new_open_position_order<C, F>(
        open_amount: u64,
        reserve_amount: u64,
        limited_index_price: AggPrice,
        collateral_price_threshold: Decimal,
        position_config: PositionConfig,
        collateral: Balance<C>,
        fee: Balance<F>,
    ): OpenPositionOrder<C, F> {
        OpenPositionOrder {
            executed: false,
            open_amount,
            reserve_amount,
            limited_index_price,
            collateral_price_threshold,
            position_config,
            collateral,
            fee,
        }
    }

    public(friend) fun new_decrease_position_order<F>(
        take_profit: bool,
        decrease_amount: u64,
        limited_index_price: AggPrice,
        collateral_price_threshold: Decimal,
        fee: Balance<F>,
    ): DecreasePositionOrder<F> {
        DecreasePositionOrder {
            executed: false,
            take_profit,
            decrease_amount,
            limited_index_price,
            collateral_price_threshold,
            fee,
        }
    }

    public(friend) fun execute_open_position_order<C, F>(
        order: &mut OpenPositionOrder<C, F>,
        vault: &mut Vault<C>,
        symbol: &mut Symbol,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        collateral_price: &AggPrice,
        index_price: &AggPrice,
        rebate_rate: Rate,
        long: bool,
        lp_supply_amount: Decimal,
        timestamp: u64,
    ): (u64, Option<OpenPositionResult<C>>, Option<OpenPositionFailedEvent>, Balance<F>) {
        assert!(!order.executed, ERR_ORDER_ALREADY_EXECUTED);
        if (long) {
            assert!(
                decimal::le(
                    &agg_price::price_of(index_price),
                    &agg_price::price_of(&order.limited_index_price),
                ),
                ERR_INDEX_PRICE_NOT_TRIGGERED,
            );
        } else {
            assert!(
                decimal::ge(
                    &agg_price::price_of(index_price),
                    &agg_price::price_of(&order.limited_index_price),
                ),
                ERR_INDEX_PRICE_NOT_TRIGGERED,
            );
        };
        
        // update order status
        order.executed = true;
        // withdraw fee
        let fee = balance::withdraw_all(&mut order.fee);

        // open position in pool
        let (code, result, failure) = pool::open_position(
            vault,
            symbol,
            reserving_fee_model,
            funding_fee_model,
            &order.position_config,
            collateral_price,
            &order.limited_index_price,
            &mut order.collateral,
            order.collateral_price_threshold,
            rebate_rate,
            long,
            order.open_amount,
            order.reserve_amount,
            lp_supply_amount,
            timestamp,
        );

        (code, result, failure, fee)
    }

    public(friend) fun destroy_open_position_order<C, F>(
        order: OpenPositionOrder<C, F>,
    ): (Balance<C>, Balance<F>) {
        let OpenPositionOrder {
            executed: _,
            open_amount: _,
            reserve_amount: _,
            limited_index_price: _,
            collateral_price_threshold: _,
            position_config: _,
            collateral,
            fee,
        } = order;

        (collateral, fee)
    }

    public(friend) fun execute_decrease_position_order<C, F>(
        order: &mut DecreasePositionOrder<F>,
        vault: &mut Vault<C>,
        symbol: &mut Symbol,
        position: &mut Position<C>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        collateral_price: &AggPrice,
        index_price: &AggPrice,
        rebate_rate: Rate,
        long: bool,
        lp_supply_amount: Decimal,
        timestamp: u64,
    ): (u64, Option<DecreasePositionResult<C>>, Option<DecreasePositionFailedEvent>, Balance<F>) {
        assert!(!order.executed, ERR_ORDER_ALREADY_EXECUTED);
        if ((long && order.take_profit) || (!long && !order.take_profit)) {
            assert!(
                decimal::ge(
                    &agg_price::price_of(index_price),
                    &agg_price::price_of(&order.limited_index_price),
                ),
                ERR_INDEX_PRICE_NOT_TRIGGERED,
            );
        } else {
            assert!(
                decimal::le(
                    &agg_price::price_of(index_price),
                    &agg_price::price_of(&order.limited_index_price),
                ),
                ERR_INDEX_PRICE_NOT_TRIGGERED,
            );
        };

        // update order status
        order.executed = true;
        // withdraw fee
        let fee = balance::withdraw_all(&mut order.fee);
        // decrease position in pool
        let (code, result, failure) = pool::decrease_position(
            vault,
            symbol,
            position,
            reserving_fee_model,
            funding_fee_model,
            collateral_price,
            &order.limited_index_price,
            order.collateral_price_threshold,
            rebate_rate,
            long,
            order.decrease_amount,
            lp_supply_amount,
            timestamp,
        );

        (code, result, failure, fee)
    }
    
    public(friend) fun destroy_decrease_position_order<F>(
        order: DecreasePositionOrder<F>,
    ): Balance<F> {
        let DecreasePositionOrder {
            executed: _,
            take_profit: _,
            decrease_amount: _,
            limited_index_price: _,
            collateral_price_threshold: _,
            fee,
        } = order;

        fee
    }
}