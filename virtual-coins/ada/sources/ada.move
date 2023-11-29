
module abex_ada::ada {
    use std::option;

    use sui::transfer;
    use sui::coin;
    use sui::tx_context::{Self, TxContext};

    struct ADA has drop {}

    fun init(witness: ADA, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            6,
            b"ADA",
            b"Wrapped Cardano",
            b"ABEx Virtual Coin",
            option::none(),
            ctx,
        );
        transfer::public_freeze_object(metadata);
        // This is a virtual token, without treasury.
        transfer::public_freeze_object(treasury);
    }
}
