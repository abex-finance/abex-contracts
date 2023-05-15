
module abex_feeder::native_feeder {

    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::clock::{Self, Clock};

    struct NativeFeeder has key {
        id: UID,

        owner: address,
        enabled: bool,
        last_update: u64,
        exp: u8,
        value: u128,
    }

    const ERR_MISMATCHED_OWNER: u64 = 0;

    public entry fun create_native_feeder(ctx: &mut TxContext) {
        transfer::share_object(
            NativeFeeder {
                id: object::new(ctx),
                owner: tx_context::sender(ctx),
                enabled: false,
                last_update: 0,
                exp: 0,
                value: 0,
            },
        );
    }

    public entry fun feed(
        feeder: &mut NativeFeeder,
        clock: &Clock,
        exp: u8,
        value: u128,
        ctx: &TxContext,
    ) {
        assert!(tx_context::sender(ctx) == feeder.owner, ERR_MISMATCHED_OWNER);

        feeder.enabled = true;
        feeder.last_update = clock::timestamp_ms(clock) / 1000;
        feeder.exp = exp;
        feeder.value = value;
    }

    public fun enabled(feeder: &NativeFeeder): bool {
        feeder.enabled
    }

    public fun last_update(feeder: &NativeFeeder): u64 {
        feeder.last_update
    }

    public fun value(feeder: &NativeFeeder): (u8, u128) {
        (feeder.exp, feeder.value)
    }
}
