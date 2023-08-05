
module abex_doge::doge {
    use std::option;

    use sui::transfer;
    use sui::coin;
    use sui::tx_context::TxContext;

    struct DOGE has drop {}

    fun init(witness: DOGE, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            8,
            b"DOGE",
            b"Wrapped Dogecoin",
            b"ABEx Virtual Coin",
            option::none(),
            ctx,
        );
        transfer::public_freeze_object(metadata);
        // This is a virtual token, without treasury.
        transfer::public_freeze_object(treasury);
    }
}
