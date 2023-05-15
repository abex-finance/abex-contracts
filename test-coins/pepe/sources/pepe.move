
module abex_pepe::pepe {
    use std::option;

    use sui::transfer;
    use sui::coin;
    use sui::tx_context::TxContext;

    struct PEPE has drop {}

    fun init(witness: PEPE, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            0,
            b"PEPE",
            b"ABEx Test Pepe",
            b"ABEx Test Pepe",
            option::none(),
            ctx,
        );
        transfer::public_freeze_object(metadata);
        // This is a virtual token.
        transfer::public_freeze_object(treasury);
    }
}
