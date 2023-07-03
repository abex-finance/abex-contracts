
module abex_core::alp {
    use std::option;

    use sui::transfer;
    use sui::coin;
    use sui::url;
    use sui::tx_context::TxContext;

    use abex_core::rate;
    use abex_core::market::create_market;
    use abex_core::admin::create_admin_cap;

    struct ALP has drop {}

    fun init(witness: ALP, ctx: &mut TxContext) {
        create_admin_cap(ctx);

        let (treasury, metadata) = coin::create_currency(
            witness,
            6,
            b"ALP",
            b"ABEx LP Token",
            b"LP Token for ABEx Market",
            option::some(url::new_unsafe_from_bytes(
                b"https://arweave.net/_doZFc5BTE7z9RXATSRI0yN5tUC69jZqwoLflk2vQu8"
            )),
            ctx,
        );
        transfer::public_freeze_object(metadata);

        create_market(
            coin::treasury_into_supply(treasury),
            rate::from_percent(5),
            rate::from_percent(30),
            ctx,
        );
    }
}
