
module abex_core::model {
    use sui::transfer;
    use sui::object::{Self, ID, UID};
    use sui::tx_context::TxContext;

    use abex_core::rate::{Self, Rate};
    use abex_core::srate::{Self, SRate};
    use abex_core::decimal::{Self, Decimal};
    use abex_core::sdecimal::{Self, SDecimal};

    friend abex_core::market;

    struct RebaseFeeModel has key {
        id: UID,

        base: Rate,
        multiplier: Decimal,
    }

    struct ReservingFeeModel has key {
        id: UID,

        multiplier: Decimal,
    }

    struct FundingFeeModel has key {
        id: UID,

        multiplier: Decimal,
        max: Rate,
    }

    const SECONDS_PER_EIGHT_HOUR: u64 = 28800;

    public(friend) fun create_rebase_fee_model(
        base: Rate,
        multiplier: Decimal,
        ctx: &mut TxContext,
    ): ID {
        let id = object::new(ctx);
        let model_id = object::uid_to_inner(&id);
        transfer::share_object(RebaseFeeModel { id, base, multiplier });
        model_id
    }

    public(friend) fun create_reserving_fee_model(
        multiplier: Decimal,
        ctx: &mut TxContext,
    ): ID {
        let id = object::new(ctx);
        let model_id = object::uid_to_inner(&id);
        transfer::share_object(ReservingFeeModel { id, multiplier });
        model_id
    }

    public(friend) fun create_funding_fee_model(
        multiplier: Decimal,
        max: Rate,
        ctx: &mut TxContext,
    ): ID {
        let id = object::new(ctx);
        let model_id = object::uid_to_inner(&id);
        transfer::share_object(FundingFeeModel { id, multiplier, max });
        model_id
    }

    public fun compute_rebase_fee_rate(
        model: &RebaseFeeModel,
        increase: bool,
        ratio: Rate,
        target_ratio: Rate,
    ): Rate {
        if ((increase && rate::le(&ratio, &target_ratio))
            || (!increase && rate::ge(&ratio, &target_ratio))) {
            model.base
        } else {
            let delta_rate = decimal::mul_with_rate(
                model.multiplier,
                rate::diff(ratio, target_ratio),
            );
            rate::add(model.base, decimal::to_rate(delta_rate))
        }
    }

    public fun compute_reserving_fee_rate(
        model: &ReservingFeeModel,
        utilization: Rate,
        elapsed: u64,
    ): Rate {
        let daily_rate = decimal::to_rate(
            decimal::mul_with_rate(model.multiplier, utilization)
        );
        rate::div_by_u64(
            rate::mul_with_u64(daily_rate, elapsed),
            SECONDS_PER_EIGHT_HOUR,
        )
    }

    public fun compute_funding_fee_rate(
        model: &FundingFeeModel,
        pnl_per_lp: SDecimal,
        elapsed: u64,
    ): SRate {
        let daily_rate = decimal::to_rate(
            decimal::mul(model.multiplier, sdecimal::value(&pnl_per_lp))
        );
        if (rate::gt(&daily_rate, &model.max)) {
            daily_rate = model.max;
        };
        let seconds_rate = rate::div_by_u64(
            rate::mul_with_u64(daily_rate, elapsed),
            SECONDS_PER_EIGHT_HOUR,
        );
        srate::from_rate(
            !sdecimal::is_positive(&pnl_per_lp),
            seconds_rate,
        )
    }
}