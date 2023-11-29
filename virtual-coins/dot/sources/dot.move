
module abex_dot::dot {
    use std::option;

    use sui::transfer;
    use sui::coin;
    use sui::tx_context::{Self, TxContext};

    struct DOT has drop {}

    fun init(witness: DOT, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            10,
            b"DOT",
            b"Wrapped Polkadot",
            b"ABEx Virtual Coin",
            option::none(),
            ctx,
        );
        transfer::public_freeze_object(metadata);
        // This is a virtual token, without treasury.
        transfer::public_freeze_object(treasury);
    }
}
