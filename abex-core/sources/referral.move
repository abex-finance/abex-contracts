
module abex_core::referral {
    use abex_core::rate::Rate;

    friend abex_core::market;

    struct Referral has store {
        referrer: address,
        rebate_rate: Rate,
    }

    public(friend) fun new_referral(
        referrer: address,
        rebate_rate: Rate,
    ): Referral {
        Referral { referrer, rebate_rate }
    }

    public(friend) fun refresh_rebate_rate(
        referral: &mut Referral,
        rebate_rate: Rate,
    ) {
        referral.rebate_rate = rebate_rate;
    }

    public fun get_referrer(referral: &Referral): address {
        referral.referrer
    }

    public fun get_rebate_rate(referral: &Referral): Rate {
        referral.rebate_rate
    }
}
