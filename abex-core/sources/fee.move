module abex_core::fee {
    use sui::object::{Self, UID};
    use sui::tx_context::TxContext;
    use sui::coin::{Self, Coin};
    use sui::transfer::{Self};
    use sui::event::{Self};

    use abex_core::decimal::{Self};
    use abex_core::rate::{Self, Rate};

    friend abex_core::market;
    friend abex_core::pool;
    friend abex_core::orders;

    const ERR_INVALID_FEE_RATE: u64 = 1001;
    const ERR_INVALID_FEE_COLLECTOR: u64 = 1002;

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

    /// `FeeCollected` is a struct that contains the fee collector, amount, and fee rate.
    struct FeeCollected has copy, drop {
        /// `collector` is the address that collects the fee.
        collector: address,
        /// `amount` is the amount of fee collected.
        amount: u64,
        /// `fee_rate` is the fee rate.
        fee_rate: Rate,
    }

    /// `FeeCollected` is a struct that contains the fee collector, amount, and fee rate.
    struct FeeCollectedV2 has copy, drop {
        /// `collector` is the address that collects the fee.
        collector: address,
        /// `fee_amount` is the amount of fee collected.
        fee_amount: u64,
        /// `coin_amount` is the amount of coin collected.
        coin_amount: u64,
        /// `fee_rate` is the fee rate.
        fee_rate: Rate,
    }

    /// Create a new `FeeConfig`.
    public(friend) fun new_fee_config(
        fee_rate: Rate,
        fee_collector: address,
        ctx: &mut TxContext,
    ): FeeConfig {
        let one = rate::one();
        let zero = rate::zero();
        assert!(rate::lt(&fee_rate, &one), ERR_INVALID_FEE_RATE);
        assert!(rate::gt(&fee_rate, &zero), ERR_INVALID_FEE_RATE);
        assert!(fee_collector != @0x0, ERR_INVALID_FEE_COLLECTOR);
        FeeConfig {
            id: object::new(ctx),
            fee_rate,
            fee_collector,
        }
    }

    /// Delete a `FeeConfig`.
    public(friend) fun delete_fee_config(
        fee_config: FeeConfig,
    ) {
        let FeeConfig { id: id, fee_rate: _, fee_collector: _ } = fee_config;
        object::delete(id);
    }

    /// Estimate the fee amount.
    public fun estimate_fee(fee_config: &FeeConfig, amount: u64): u64 {
        decimal::ceil_u64(decimal::mul_with_rate(
            decimal::from_raw((amount as u256)),
            get_fee_rate(fee_config),
        ))
    }

    // using fee config split balance from market
    // and transfer the coin to fee collector
    public(friend) fun pay_fee<F>(
        fee_config: &FeeConfig,
        fee_coin: &mut Coin<F>,
        ctx: &mut TxContext,
    ) {
        let collector = get_fee_collector(fee_config);
        assert!(collector != @0x0, ERR_INVALID_FEE_COLLECTOR);
        let coin_value = coin::value(fee_coin);
        let fee_value = estimate_fee(fee_config, coin_value);
        if (fee_value > 0) {
            let splited_fee_coin = coin::split(fee_coin, fee_value, ctx);
            if (coin::value(&splited_fee_coin) > 0) {
                transfer::public_transfer(splited_fee_coin, collector);
            } else {
                coin::destroy_zero(splited_fee_coin);
            }
        };
        event::emit(FeeCollectedV2 {
            collector,
            fee_amount: fee_value,
            coin_amount: coin_value,
            fee_rate: get_fee_rate(fee_config),
        });
    }

    public(friend) fun pay_fee_directly<F>(
        fee_config: &FeeConfig,
        fee_coin: Coin<F>
    ) {
        let collector = get_fee_collector(fee_config);
        assert!(collector != @0x0, ERR_INVALID_FEE_COLLECTOR);
        let fee_amount = coin::value(&fee_coin);
        if (fee_amount > 0) {
            transfer::public_transfer(fee_coin, collector);
        } else {
            coin::destroy_zero(fee_coin);
        };
        event::emit(FeeCollected {
            collector,
            amount: fee_amount,
            fee_rate: get_fee_rate(fee_config),
        });
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
