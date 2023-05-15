
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
            b"ABEx Test Doge",
            b"ABEx Test Doge",
            option::none(),
            ctx,
        );
        transfer::public_freeze_object(metadata);
        // This is a virtual token.
        transfer::public_freeze_object(treasury);
    }
}
