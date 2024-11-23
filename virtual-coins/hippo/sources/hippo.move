
module abex_hippo::hippo {
    use std::option;

    use sui::transfer;
    use sui::coin;
    use sui::tx_context::TxContext;

    struct HIPPO has drop {}

    fun init(witness: HIPPO, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            6,
            b"HIPPO",
            b"Wrapped Hippo",
            b"ABEx Virtual Coin",
            option::none(),
            ctx,
        );
        transfer::public_freeze_object(metadata);
        // This is a virtual token, without treasury.
        transfer::public_freeze_object(treasury);
    }
}
