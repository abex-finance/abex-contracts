
module abex_ltc::ltc {
    use std::option;

    use sui::transfer;
    use sui::coin;
    use sui::tx_context::{Self, TxContext};

    struct LTC has drop {}

    fun init(witness: LTC, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            8,
            b"LTC",
            b"Wrapped Litecoin",
            b"ABEx Virtual Coin",
            option::none(),
            ctx,
        );
        transfer::public_freeze_object(metadata);
        // This is a virtual token, without treasury.
        transfer::public_freeze_object(treasury);
    }
}
