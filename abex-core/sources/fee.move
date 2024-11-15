module abex_core::fee {
    use sui::object::{Self, UID};
    use sui::tx_context::TxContext;
    use sui::dynamic_object_field::{Self};

    use abex_core::rate::Rate;
    use abex_core::market::Market;

    friend abex_core::market;

    /// The dynamic key for `FeeConfig`.
    const FEE_CONFIG_DYNAMIC_KEY: u64 = 10001;

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
    public(friend) fun new_fee_config<L>(
        market: &Market<L>,
        fee_rate: Rate,
        fee_collector: address,
        ctx: &mut TxContext,
    ) {
        let fee_config = FeeConfig {
            id: object::new(ctx),
            fee_rate,
            fee_collector,
        };
        if (dynamic_object_field::contains(
            &market.id,
            FEE_CONFIG_DYNAMIC_KEY,
        )) {
            // remove the old fee config
            let old_fee_config = dynamic_object_field::remove(
                &mut market.id,
                FEE_CONFIG_DYNAMIC_KEY,
            );
            // delete the old fee config
            let FeeConfig { id, .. } = old_fee_config;
            object::delete(id);
        }
        dynamic_object_field::add(
            &mut market.id,
            FEE_CONFIG_DYNAMIC_KEY,
            fee_config,
        );
    }

    /// Update the `FeeConfig`.
    public(friend) fun update_fee_config<L>(
        market: &Market<L>,
        fee_rate: Rate,
        fee_collector: address,
        ctx: &mut TxContext,
    ) {
        let fee_config = dynamic_object_field::borrow_mut(
            &mut market.id,
            FEE_CONFIG_DYNAMIC_KEY,
        );
        fee_config.fee_rate = fee_rate;
        fee_config.fee_collector = fee_collector;
    }

    /// Borrow the `FeeConfig`.
    public(friend) fun borrow_fee_config(market: &Market<L>): &FeeConfig {
        dynamic_object_field::borrow(
            &market.id,
            FEE_CONFIG_DYNAMIC_KEY,
        )
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
