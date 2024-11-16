module abex_core::fee {
    use sui::object::{Self, UID};
    use sui::tx_context::TxContext;
    use sui::coin::{Self, Coin};
    use sui::transfer::{Self};

    use abex_core::decimal::{Self};
    use abex_core::rate::Rate;

    friend abex_core::market;
    friend abex_core::orders;

    /// `FeeConfig` is a struct that contains the fee rate.
    struct FeeConfig has key, store {
        /// The ID of the fee config.
        id: UID,
        /// `fee_rate` is designed to be unique for each fee holder,
        /// which supports modifying in future.
        fee_rate: Rate,

        /// `fee_collector` is the address that collects the fee.
        fee_collector: address,
    }

    /// Create a new `FeeConfig`.
    public(friend) fun new_fee_config(
        fee_rate: Rate,
        fee_collector: address,
        ctx: &mut TxContext,
    ): FeeConfig {
        FeeConfig {
            id: object::new(ctx),
            fee_rate,
            fee_collector,
        }
    }

    // using fee config split balance from market
    // and transfer the coin to fee collector
    public(friend) fun split_fee_from_coin<F>(
        fee_config: &FeeConfig,
        coin: &mut Coin<F>,
        ctx: &mut TxContext,
    ) {
        let collector = get_fee_collector(fee_config);
        let fee_rate = get_fee_rate(fee_config);
        let fee_value = decimal::mul_with_rate(
            decimal::from_u64(coin::value(coin)),
            fee_rate,
        );
        let fee = coin::split(coin, decimal::ceil_u64(fee_value), ctx);
        transfer::public_transfer(fee, collector);
    }

    /// Get the fee rate.
    public fun get_fee_rate(fee_config: &FeeConfig): Rate {
        fee_config.fee_rate
    }

    /// Get the fee collector.
    public fun get_fee_collector(fee_config: &FeeConfig): address {
        fee_config.fee_collector
    }
}
