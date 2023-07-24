
module abex_core::referral {
    use abex_core::rate::Rate;

    friend abex_core::market;

    /// `Referral` is a struct that contains the referrer and the rebate rate.
    struct Referral has store {
        referrer: address,
        /// `rebate_rate` is designed to be unique for each referral holder,
        /// which supports modifying in future.
        rebate_rate: Rate,
    }

    public(friend) fun new_referral(
        referrer: address,
        rebate_rate: Rate,
    ): Referral {
        Referral { referrer, rebate_rate }
    }

    public fun get_referrer(referral: &Referral): address {
        referral.referrer
    }

    public fun get_rebate_rate(referral: &Referral): Rate {
        referral.rebate_rate
    }
}
