module abex_core::admin {
    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};

    friend abex_core::alp;

    struct AdminCap has key {
        id: UID,
    }

    public(friend) fun create_admin_cap(ctx: &mut TxContext) {
        let admin_cap = AdminCap { id: object::new(ctx) };
        transfer::transfer(admin_cap, tx_context::sender(ctx));
    }
}