#[test_only]
module abex_core::market_tests {
    use std::option;
    use abex_core::market::{Market, get_referral_data};
    use sui::tx_context;
    use sui::object;
    use abex_core::admin::AdminCap;
    use abex_core::admin;
    use abex_core::market;
    use abex_core::rate;
    use sui::transfer;
    use sui::test_utils;
    use sui::test_scenario;
    use sui::url;
    use sui::coin;

    use pyth::price_info::{PriceInfoObject as PythFeeder};

    const ADMIN: address = @0xAAAA;
    const USER: address = @0xBBBB;
    const REFERRAL: address = @0xCCCC;

    const BTC_FEEDER: address = @0x878b118488aeb5763b5f191675c3739a844ce132cb98150a465d9407d7971e7c;

    // one time witness for the coin used in tests
    struct MARKET_TESTS has drop {}

    #[test]
    fun test_market<L, C, I, D>() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        test_scenario::next_tx(scenario, ADMIN);
        let ctx = test_scenario::ctx(scenario);

        // create admin cap
        admin::create_admin_cap(ctx);

        let witness = test_utils::create_one_time_witness<MARKET_TESTS>();
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

        // create market
        market::create_market(coin::treasury_into_supply(treasury), rate::from_percent(5), ctx);

        let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);
        let market_id = object::id_from_address(tx_context::last_created_object_id(ctx));
        let market = test_scenario::take_from_sender_by_id<Market<L>>(scenario, market_id);

        // btc coin
        let btc_witness = test_utils::create_one_time_witness<I>();
        let (_, btc_metadata) = coin::create_currency(
            btc_witness,
            9,
            b"BTC",
            b"ABEx Test Bitcoin",
            b"ABEx Test Bitcoin",
            option::none(),
            ctx,
        );

        // btc feeder
        let btc_feeder_id = object::id_from_address(BTC_FEEDER);
        let btc_feeder = test_scenario::take_from_sender_by_id<PythFeeder>(scenario, btc_feeder_id);

        // test add btc token

        {
            market::add_new_symbol<L, I, D>(
                &admin_cap,
                &mut market,
                90,
                18446744073709551615,
                &btc_metadata,
                &btc_feeder,
                25000000000000000,
                5000000000000000,
                100,
                30,
                10,
                10000000000000000000,
                1000000000000000,
                1000000000000000,
                980000000000000000,
                10000000000000000,
                ctx
            );
        };

        // test add btc vault
        {
            market::add_new_vault(
                &admin_cap,
                &mut market,
                1000000000000000000,
                90,
                18446744073709551615,
                &btc_metadata,
                &btc_feeder,
                1000000000000000,
                ctx
            );
        };

        // test add new referral
        {
            market::add_new_referral(
                &mut market,
                REFERRAL,
                ctx
            );

            let referrals = &market.referrals;
            let referral_data = get_referral_data(referrals, ADMIN);
        };

        test_scenario::end(scenario_val);
    }
}

