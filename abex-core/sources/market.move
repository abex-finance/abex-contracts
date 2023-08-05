
module abex_core::market {
    use std::option::{Self, Option};
    use std::type_name::{Self, TypeName};

    use sui::event;
    use sui::transfer;
    use sui::bag::{Self, Bag};
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::vec_set::{Self, VecSet};
    use sui::vec_map::{Self, VecMap};
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance, Supply};
    use sui::coin::{Self, Coin, CoinMetadata};

    use pyth::price_info::{PriceInfoObject as PythFeeder};

    use abex_core::admin::AdminCap;
    use abex_core::rate::{Self, Rate};
    use abex_core::referral::{Self, Referral};
    use abex_core::decimal::{Self, Decimal};
    use abex_core::sdecimal::{Self, SDecimal};
    use abex_core::agg_price::{Self, AggPrice};
    use abex_core::position::{Self, Position, PositionConfig};
    use abex_core::model::{
        Self, RebaseFeeModel, ReservingFeeModel, FundingFeeModel,
    };
    use abex_core::orders::{Self, OpenPositionOrder, DecreasePositionOrder};
    use abex_core::pool::{Self, Vault, Symbol};

    friend abex_core::alp;
    friend abex_core::market_tests;

    // === Objects ===

    /// `Market` is the core storage of the protocol.
    struct Market<phantom L> has key {
        id: UID,

        // bit mask of versioned functions
        fun_mask: u256,

        vaults_locked: bool,
        symbols_locked: bool,

        rebate_rate: Rate,
        rebase_fee_model: ID,

        referrals: Table<address, Referral>,
        vaults: Bag,
        symbols: Bag,
        positions: Bag,
        orders: Bag,

        lp_supply: Supply<L>,
    }

    /// `WrappedPositionConfig` is a wrapper for position config.
    /// Currently, all users share a public object of position config. But we
    /// might support a customized position config for each user in future.
    struct WrappedPositionConfig<phantom I, phantom D> has key {
        id: UID,

        /// `enabled` is a a reserved field, to be used when upgrading
        /// in case of emergency.
        enabled: bool,
        inner: PositionConfig,
    }

    /// `PositionCap` is designed to to facilitate the dapp
    /// to retrieve the positions owned by the user.
    struct PositionCap<phantom C, phantom I, phantom D> has key {
        id: UID,
    }

    /// `OrderCap` is designed to to facilitate the dapp
    /// to retrieve the delegate orders created by the user.
    struct OrderCap<phantom C, phantom I, phantom D, phantom F> has key {
        id: UID,

        position_id: Option<ID>,
    }

    // === Tag structs ===

    /// `LONG` is a tag struct to indicate the direction of a position is long.
    struct LONG has drop {}
    /// `SHORT` is a tag struct to indicate the direction of a position is short.
    struct SHORT has drop {}
    /// `VaultName` is a tag struct to indicate the vault with collateral coin type.
    struct VaultName<phantom C> has copy, drop, store {}
    /// `SymbolName` is a tag struct to indicate the symbol with index coin type and direction.
    struct SymbolName<phantom I, phantom D> has copy, drop, store {}
    /// `PositionName` is a tag struct to indicate the position with collateral coin type,
    /// index coin type, direction, position cap id and owner.
    struct PositionName<phantom C, phantom I, phantom D> has copy, drop, store {
        id: ID,
        owner: address,
    }
    /// `Order` is a tag struct to indicate the open position order with collateral coin type,
    /// index coin type, direction, fee coin type, order id, owner and position id.
    struct OrderName<
        phantom C,
        phantom I,
        phantom D,
        phantom F,
    > has copy, drop, store {
        id: ID,
        owner: address,
        position_id: Option<ID>,
    }

    // === Events ===

    struct MarketCreated has copy, drop {
        referrals_parent: ID,
        vaults_parent: ID,
        symbols_parent: ID,
        positions_parent: ID,
        orders_parent: ID,
    }

    struct VaultCreated<phantom C> has copy, drop {}

    struct SymbolCreated<phantom I, phantom D> has copy, drop {}

    struct CollateralAdded<phantom C, phantom I, phantom D> has copy, drop {}

    struct CollateralRemoved<phantom C, phantom I, phantom D> has copy, drop {}

    struct PositionClaimed<N: copy + drop, E: copy + drop> has copy, drop {
        position_name: Option<N>,
        event: E,
    }

    struct Deposited<phantom C> has copy, drop {
        minter: address,
        price: Decimal,
        deposit_amount: u64,
        mint_amount: u64,
    }

    struct Withdrawn<phantom C> has copy, drop {
        burner: address,
        price: Decimal,
        withdraw_amount: u64,
        burn_amount: u64,
    }

    struct Swapped<phantom S, phantom D> has copy, drop {
        swapper: address,
        source_price: Decimal,
        dest_price: Decimal,
        source_amount: u64,
        dest_amount: u64,
    }

    struct OrderCreated<N: copy + drop, E: copy + drop> has copy, drop {
        order_name: N,
        event: E,
    }

    struct OrderExecuted<N: copy + drop, PC: copy + drop> has copy, drop {
        executor: address,
        order_name: N,
        claim: PC,
    }

    struct OrderCleared<N: copy + drop> has copy, drop {
        order_name: N,
    }

    struct VaultInfo has drop {
        price: AggPrice,
        value: Decimal,
    }

    // === Hot Potato ===

    struct VaultsValuation {
        timestamp: u64,
        num: u64,
        handled: VecMap<TypeName, VaultInfo>,
        total_weight: Decimal,
        value: Decimal,
    }

    struct SymbolsValuation {
        timestamp: u64,
        num: u64,
        lp_supply_amount: Decimal,
        handled: VecSet<TypeName>,
        value: SDecimal,
    }

    // === Errors ===
    // common errors
    const ERR_FUNCTION_VERSION_EXPIRED: u64 = 1;
    const ERR_MARKET_ALREADY_LOCKED: u64 = 2;
    // referral errors
    const ERR_ALREADY_HAS_REFERRAL: u64 = 3;
    // perpetual trading errors
    const ERR_INVALID_DIRECTION: u64 = 4;
    const ERR_CAN_NOT_CREATE_ORDER: u64 = 5;
    const ERR_CAN_NOT_TRADE_IMMEDIATELY: u64 = 6;
    // deposit, withdraw and swap errors
    const ERR_VAULT_ALREADY_HANDLED: u64 = 7;
    const ERR_SYMBOL_ALREADY_HANDLED: u64 = 8;
    const ERR_VAULTS_NOT_TOTALLY_HANDLED: u64 = 9;
    const ERR_SYMBOLS_NOT_TOTALLY_HANDLED: u64 = 10;
    const ERR_UNEXPECTED_MARKET_VALUE: u64 = 11;
    const ERR_MISMATCHED_RESERVING_FEE_MODEL: u64 = 12;
    const ERR_SWAPPING_SAME_COINS: u64 = 13;

    // === Internal functions ===

    fun pay_from_balance<T>(
        balance: Balance<T>,
        receiver: address,
        ctx: &mut TxContext,
    ) {
        if (balance::value(&balance) > 0) {
            transfer::public_transfer(coin::from_balance(balance, ctx), receiver);
        } else {
            balance::destroy_zero(balance);
        }
    }

    public(friend) fun get_referral_data(
        referrals: &Table<address, Referral>,
        owner: address
    ): (Rate, address) {
        if (table::contains(referrals, owner)) {
            let referral = table::borrow(referrals, owner);
            (referral::get_rebate_rate(referral), referral::get_referrer(referral))
        } else {
            (rate::zero(), @0x0)
        }
    }

    fun finalize_vaults_valuation<L>(
        market: &mut Market<L>,
        valuation: VaultsValuation,
    ): (VecMap<TypeName, VaultInfo>, Decimal, Decimal) {
        let VaultsValuation {
            timestamp: _,
            num,
            handled,
            total_weight,
            value,
        } = valuation;
        assert!(vec_map::size(&handled) == num, ERR_VAULTS_NOT_TOTALLY_HANDLED);
        // release vaults
        market.vaults_locked = false;

        (handled, total_weight, value)
    }

    fun finalize_symbols_valuation<L>(
        market: &mut Market<L>,
        valuation: SymbolsValuation,
    ): SDecimal {
        let SymbolsValuation {
            timestamp: _,
            num,
            lp_supply_amount: _,
            handled,
            value,
        } = valuation;
        assert!(vec_set::size(&handled) == num, ERR_SYMBOLS_NOT_TOTALLY_HANDLED);
        // release symbols
        market.symbols_locked = false;

        value
    }

    fun finalize_market_valuation<L>(
        market: &mut Market<L>,
        vaults_valuation: VaultsValuation,
        symbols_valuation: SymbolsValuation,
    ): (
        VecMap<TypeName, VaultInfo>,
        Decimal,
        Decimal,
        Decimal,
    ) {
        let (handled_vaults, total_weight, total_vaults_value) =
            finalize_vaults_valuation(market, vaults_valuation);
        let total_symbols_value =
            finalize_symbols_valuation(market, symbols_valuation);

        let market_value = sdecimal::add_with_decimal(
            total_symbols_value,
            total_vaults_value,
        );
        // This should not happen, but we need to check it
        assert!(sdecimal::is_positive(&market_value), ERR_UNEXPECTED_MARKET_VALUE);

        (
            handled_vaults,
            total_weight,
            total_vaults_value,
            sdecimal::value(&market_value),
        )
    }

    public(friend) fun create_market<L>(
        lp_supply: Supply<L>,
        rebate_rate: Rate,
        ctx: &mut TxContext,
    ) {
        // create rebase fee model
        let model_id = model::create_rebase_fee_model(
            100_000_000_000_000, // 0.0001
            10_000_000_000_000_000, // 0.01
            ctx,
        );

        let market = Market {
            id: object::new(ctx),
            fun_mask: 0x0,
            vaults_locked: false,
            symbols_locked: false,
            rebate_rate,
            rebase_fee_model: model_id,
            referrals: table::new(ctx),
            vaults: bag::new(ctx),
            symbols: bag::new(ctx),
            positions: bag::new(ctx),
            orders: bag::new(ctx),
            lp_supply,
        };
        // emit market created
        event::emit(MarketCreated {
            referrals_parent: object::id(&market.referrals),
            vaults_parent: object::id(&market.vaults),
            symbols_parent: object::id(&market.symbols),
            positions_parent: object::id(&market.positions),
            orders_parent: object::id(&market.orders),
        });

        transfer::share_object(market);
    }

    // === entry functions ===

    public entry fun add_new_vault<L, C>(
        _a: &AdminCap,
        market: &mut Market<L>,
        weight: u256,
        max_interval: u64,
        max_price_confidence: u64,
        coin_metadata: &CoinMetadata<C>,
        feeder: &PythFeeder,
        param_multiplier: u256,
        ctx: &mut TxContext,
    ) {
        // create reserving fee model
        let model_id = model::create_reserving_fee_model(param_multiplier, ctx);

        let vault = pool::new_vault<C>(
            weight,
            model_id,
            agg_price::new_agg_price_config(
                max_interval,
                max_price_confidence,
                coin_metadata,
                feeder,
            ),
        );
        bag::add(&mut market.vaults, VaultName<C> {}, vault);
        
        // emit vault created
        event::emit(VaultCreated<C> {});
    }

    public entry fun add_new_symbol<L, I, D>(
        _a: &AdminCap,
        market: &mut Market<L>,
        max_interval: u64,
        max_price_confidence: u64,
        coin_metadata: &CoinMetadata<I>,
        feeder: &PythFeeder,
        param_multiplier: u256,
        param_max: u128,
        max_leverage: u64,
        min_holding_duration: u64,
        max_reserved_multiplier: u64,
        min_collateral_value: u256,
        open_fee_bps: u128,
        decrease_fee_bps: u128,
        liquidation_threshold: u128,
        liquidation_bonus: u128,
        ctx: &mut TxContext,
    ) {
        // create funding fee model
        let model_id = model::create_funding_fee_model(
            param_multiplier,
            param_max,
            ctx,
        );

        // create public position config
        transfer::share_object(
            WrappedPositionConfig<I, D> {
                id: object::new(ctx),
                enabled: true,
                inner: position::new_position_config(
                    max_leverage,
                    min_holding_duration,
                    max_reserved_multiplier,
                    min_collateral_value,
                    open_fee_bps,
                    decrease_fee_bps,
                    liquidation_threshold,
                    liquidation_bonus,
                ),
            }
        );

        let symbol = pool::new_symbol(
            model_id,
            agg_price::new_agg_price_config(
                max_interval,
                max_price_confidence,
                coin_metadata,
                feeder,
            ),
        );
        bag::add(&mut market.symbols, SymbolName<I, D> {}, symbol);

        // emit symbol created
        event::emit(SymbolCreated<I, D> {});
    }

    public entry fun add_collateral_to_symbol<L, C, I, D>(
        _a: &AdminCap,
        market: &mut Market<L>,
        _ctx: &mut TxContext,
    ) {
        let symbol: &mut Symbol = bag::borrow_mut(
            &mut market.symbols,
            SymbolName<I, D> {},
        );
        pool::add_collateral_to_symbol<C>(symbol);

        // emit collateral added
        event::emit(CollateralAdded<C, I, D> {});
    }

    public entry fun remove_collateral_from_symbol<L, C, I, D>(
        _a: &AdminCap,
        market: &mut Market<L>,
        _ctx: &mut TxContext,
    ) {
        let symbol: &mut Symbol = bag::borrow_mut(
            &mut market.symbols,
            SymbolName<I, D> {},
        );
        pool::remove_collateral_from_symbol<C>(symbol);

        // emit collateral removed
        event::emit(CollateralRemoved<C, I, D> {});
    }
    
    // version = 0x1
    public entry fun add_new_referral<L>(
        market: &mut Market<L>,
        referrer: address,
        ctx: &mut TxContext,
    ) {
        assert!(market.fun_mask & 0x1 == 0, ERR_FUNCTION_VERSION_EXPIRED);

        let owner = tx_context::sender(ctx);
        assert!(
            !table::contains(&market.referrals, owner),
            ERR_ALREADY_HAS_REFERRAL,
        );

        let referral = referral::new_referral(referrer, market.rebate_rate);
        table::add(&mut market.referrals, owner, referral);
    }

    // version = 0x1 << 1
    public entry fun open_position<L, C, I, D, F>(
        clock: &Clock,
        market: &mut Market<L>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        position_config: &WrappedPositionConfig<I, D>,
        collateral_feeder: &PythFeeder,
        index_feeder: &PythFeeder,
        collateral: Coin<C>,
        fee: Coin<F>,
        trade_level: u8, // 0: not, 1: allowed, 2: must
        open_amount: u64,
        reserve_amount: u64,
        collateral_price_threshold: u256,
        limited_index_price: u256,
        ctx: &mut TxContext,
    ) {
        assert!(market.fun_mask & 0x2 == 0, ERR_FUNCTION_VERSION_EXPIRED);
        assert!(!market.vaults_locked && !market.symbols_locked, ERR_MARKET_ALREADY_LOCKED);

        let timestamp = clock::timestamp_ms(clock) / 1000;
        let owner = tx_context::sender(ctx);
        let lp_supply_amount = lp_supply_amount(market);
        let long = parse_direction<D>();

        let symbol: &mut Symbol = bag::borrow_mut(
            &mut market.symbols,
            SymbolName<I, D> {},
        );

        let collateral_price_threshold = decimal::from_raw(collateral_price_threshold);
        let index_price = agg_price::parse_pyth_feeder(
            pool::symbol_price_config(symbol),
            index_feeder,
            timestamp,
        );
        let limited_index_price = agg_price::from_price(
            pool::symbol_price_config(symbol),
            decimal::from_raw(limited_index_price),
        );

        // check if limited order can be placed
        let placed = if (long) {
            decimal::gt(
                &agg_price::price_of(&index_price),
                &agg_price::price_of(&limited_index_price),
            )
        } else {
            decimal::lt(
                &agg_price::price_of(&index_price),
                &agg_price::price_of(&limited_index_price),
            )
        };

        if (placed) {
            assert!(trade_level < 2, ERR_CAN_NOT_CREATE_ORDER);

            let order_id = object::new(ctx);
            let order_name = OrderName<C, I, D, F> {
                id: object::uid_to_inner(&order_id),
                owner,
                position_id: option::none(),
            };
            let (order, event) = orders::new_open_position_order(
                timestamp,
                open_amount,
                reserve_amount,
                limited_index_price,
                collateral_price_threshold,
                position_config.inner,
                coin::into_balance(collateral),
                coin::into_balance(fee),
            );

            bag::add(&mut market.orders, order_name, order);

            transfer::transfer(
                OrderCap<C, I, D, F> {
                    id: order_id,
                    position_id: order_name.position_id,
                },
                owner,
            );

            // emit order created
            event::emit(OrderCreated { order_name, event });
        } else {
            assert!(trade_level > 0, ERR_CAN_NOT_TRADE_IMMEDIATELY);

            let vault: &mut Vault<C> = bag::borrow_mut(
                &mut market.vaults,
                VaultName<C> {},
            );

            let collateral_price = agg_price::parse_pyth_feeder(
                pool::vault_price_config(vault),
                collateral_feeder,
                timestamp,
            );

            let (rebate_rate, referrer) = get_referral_data(&market.referrals, owner);
            let position_id = object::new(ctx);
            let position_name = PositionName<C, I, D> {
                id: object::uid_to_inner(&position_id),
                owner,
            };
            let collateral = coin::into_balance(collateral);
            let (code, result, _) = pool::open_position(
                vault,
                symbol,
                reserving_fee_model,
                funding_fee_model,
                &position_config.inner,
                &collateral_price,
                &index_price,
                &mut collateral,
                collateral_price_threshold,
                rebate_rate,
                long,
                open_amount,
                reserve_amount,
                lp_supply_amount,
                timestamp,
            );
            // should panic when the owner execute the order
            assert!(code == 0, code);
            balance::destroy_zero(collateral);

            let (position, rebate, event) =
                pool::unwrap_open_position_result(option::destroy_some(result));

            bag::add(&mut market.positions, position_name, position);

            transfer::transfer(
                PositionCap<C, I, D> { id: position_id },
                owner,
            );
            
            pay_from_balance(rebate, referrer, ctx);

            transfer::public_transfer(fee, owner);

            // emit position opened
            event::emit(PositionClaimed {
                position_name: option::some(position_name),
                event,
            });
        }
    }

    // version = 0x1 << 2
    public entry fun decrease_position<L, C, I, D, F>(
        clock: &Clock,
        market: &mut Market<L>,
        position_cap: &mut PositionCap<C, I, D>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        collateral_feeder: &PythFeeder,
        index_feeder: &PythFeeder,
        fee: Coin<F>,
        trade_level: u8,  // 0: not, 1: allowed, 2: must
        take_profit: bool,
        decrease_amount: u64,
        collateral_price_threshold: u256,
        limited_index_price: u256,
        ctx: &mut TxContext,
    ) {
        assert!(market.fun_mask & 0x4 == 0, ERR_FUNCTION_VERSION_EXPIRED);
        assert!(!market.vaults_locked && !market.symbols_locked, ERR_MARKET_ALREADY_LOCKED);

        let timestamp = clock::timestamp_ms(clock) / 1000;
        let owner = tx_context::sender(ctx);
        let lp_supply_amount = lp_supply_amount(market);
        let long = parse_direction<D>();

        let symbol: &mut Symbol = bag::borrow_mut(
            &mut market.symbols,
            SymbolName<I, D> {},
        );

        let position_name = PositionName<C, I, D> {
            id: object::uid_to_inner(&position_cap.id),
            owner,
        };

        let collateral_price_threshold = decimal::from_raw(collateral_price_threshold);
        let index_price = agg_price::parse_pyth_feeder(
            pool::symbol_price_config(symbol),
            index_feeder,
            timestamp,
        );
        let limited_index_price = agg_price::from_price(
            pool::symbol_price_config(symbol),
            decimal::from_raw(limited_index_price),
        );

        // check if limit order can be placed
        let placed = if (long) {
            decimal::lt(
                &agg_price::price_of(&index_price),
                &agg_price::price_of(&limited_index_price),
            )
        } else {
            decimal::gt(
                &agg_price::price_of(&index_price),
                &agg_price::price_of(&limited_index_price),
            )
        };

        // Decrease order is allowed to create:
        // 1: limit order can be placed
        // 2: limit order can not placed, but it must be a stop loss order
        if (placed || !take_profit) {
            assert!(trade_level < 2, ERR_CAN_NOT_CREATE_ORDER);

            let order_id = object::new(ctx);
            let order_name = OrderName<C, I, D, F> {
                id: object::uid_to_inner(&order_id),
                owner,
                position_id: option::some(position_name.id),
            };
            let (order, event) = orders::new_decrease_position_order(
                timestamp,
                take_profit,
                decrease_amount,
                limited_index_price,
                collateral_price_threshold,
                coin::into_balance(fee),
            );

            bag::add(&mut market.orders, order_name, order);

            transfer::transfer(
                OrderCap<C, I, D, F> {
                    id: order_id,
                    position_id: order_name.position_id,    
                },
                owner,
            );

            // emit order created
            event::emit(OrderCreated { order_name, event });
        } else {
            assert!(trade_level > 0, ERR_CAN_NOT_TRADE_IMMEDIATELY);

            let vault: &mut Vault<C> = bag::borrow_mut(
                &mut market.vaults,
                VaultName<C> {},
            );
            let position: &mut Position<C> = bag::borrow_mut(
                &mut market.positions,
                position_name,
            );

            let collateral_price = agg_price::parse_pyth_feeder(
                pool::vault_price_config(vault),
                collateral_feeder,
                timestamp,
            );

            let (rebate_rate, referrer) = get_referral_data(&market.referrals, owner);
            let (code, result, _) = pool::decrease_position(
                vault,
                symbol,
                position,
                reserving_fee_model,
                funding_fee_model,
                &collateral_price,
                &index_price,
                collateral_price_threshold,
                rebate_rate,
                long,
                decrease_amount,
                lp_supply_amount,
                timestamp,
            );
            // should panic when the owner execute the order
            assert!(code == 0, code);
            
            let (to_trader, rebate, event) =
                pool::unwrap_decrease_position_result(option::destroy_some(result));

            pay_from_balance(to_trader, owner, ctx);
            pay_from_balance(rebate, referrer, ctx);

            transfer::public_transfer(fee, owner);

            // emit decrease position
            event::emit(PositionClaimed {
                position_name: option::some(position_name),
                event,
            });
        }
    }

    // version = 0x1 << 3
    public entry fun decrease_reserved_from_position<L, C, I, D>(
        clock: &Clock,
        market: &mut Market<L>,
        position_cap: &PositionCap<C, I, D>,
        reserving_fee_model: &ReservingFeeModel,
        decrease_amount: u64,
        ctx: &mut TxContext,
    ) {
        assert!(market.fun_mask & 0x8 == 0, ERR_FUNCTION_VERSION_EXPIRED);
        let timestamp = clock::timestamp_ms(clock) / 1000;
        let owner = tx_context::sender(ctx);

        let vault: &mut Vault<C> = bag::borrow_mut(
            &mut market.vaults,
            VaultName<C> {},
        );

        let position_name = PositionName<C, I, D> {
            id: object::uid_to_inner(&position_cap.id),
            owner,
        };
        let position: &mut Position<C> = bag::borrow_mut(
            &mut market.positions,
            position_name,
        );

        let event = pool::decrease_reserved_from_position(
            vault,
            position,
            reserving_fee_model,
            decrease_amount,
            timestamp,
        );

        // emit decrease reserved from position
        event::emit(PositionClaimed {
            position_name: option::some(position_name),
            event,
        });
    }

    // version = 0x1 << 4
    public entry fun pledge_in_position<L, C, I, D>(
        market: &mut Market<L>,
        position_cap: &PositionCap<C, I, D>,
        pledge: Coin<C>,
        ctx: &mut TxContext,
    ) {
        assert!(market.fun_mask & 0x10 == 0, ERR_FUNCTION_VERSION_EXPIRED);

        let owner = tx_context::sender(ctx);

        let position_name = PositionName<C, I, D> {
            id: object::uid_to_inner(&position_cap.id),
            owner,
        };
        let position: &mut Position<C> = bag::borrow_mut(
            &mut market.positions,
            position_name,
        );

        let event = pool::pledge_in_position(position, coin::into_balance(pledge));

        // emit pledge in position
        event::emit(PositionClaimed {
            position_name: option::some(position_name),
            event,
        });
    }

    // version = 0x1 << 5
    public entry fun redeem_from_position<L, C, I, D>(
        clock: &Clock,
        market: &mut Market<L>,
        position_cap: &PositionCap<C, I, D>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        collateral_feeder: &PythFeeder,
        index_feeder: &PythFeeder,
        redeem_amount: u64,
        ctx: &mut TxContext,
    ) {
        assert!(market.fun_mask & 0x20 == 0, ERR_FUNCTION_VERSION_EXPIRED);
        assert!(!market.vaults_locked && !market.symbols_locked, ERR_MARKET_ALREADY_LOCKED);
        
        let timestamp = clock::timestamp_ms(clock) / 1000;
        let owner = tx_context::sender(ctx);
        let lp_supply_amount = lp_supply_amount(market);
        let long = parse_direction<D>();

        let vault: &mut Vault<C> = bag::borrow_mut(
            &mut market.vaults,
            VaultName<C> {},
        );
        let symbol: &mut Symbol = bag::borrow_mut(
            &mut market.symbols,
            SymbolName<I, D> {},
        );

        let position_name = PositionName<C, I, D> {
            id: object::uid_to_inner(&position_cap.id),
            owner,
        };
        let position: &mut Position<C> = bag::borrow_mut(
            &mut market.positions,
            position_name,
        );

        let collateral_price = agg_price::parse_pyth_feeder(
            pool::vault_price_config(vault),
            collateral_feeder,
            timestamp,
        );
        let index_price = agg_price::parse_pyth_feeder(
            pool::symbol_price_config(symbol),
            index_feeder,
            timestamp,
        );

        let (redeem, event) = pool::redeem_from_position(
            vault,
            symbol,
            position,
            reserving_fee_model,
            funding_fee_model,
            &collateral_price,
            &index_price,
            long,
            redeem_amount,
            lp_supply_amount,
            timestamp,
        );

        pay_from_balance(redeem, owner, ctx);

        // emit redeem from position
        event::emit(PositionClaimed {
            position_name: option::some(position_name),
            event,
        });
    }

    // version = 0x1 << 6
    public entry fun liquidate_position<L, C, I, D>(
        clock: &Clock,
        market: &mut Market<L>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        collateral_feeder: &PythFeeder,
        index_feeder: &PythFeeder,
        owner: address,
        position_id: address,
        ctx: &mut TxContext,
    ) {
        assert!(market.fun_mask & 0x40 == 0, ERR_FUNCTION_VERSION_EXPIRED);
        assert!(!market.vaults_locked && !market.symbols_locked, ERR_MARKET_ALREADY_LOCKED);

        let timestamp = clock::timestamp_ms(clock) / 1000;
        let liquidator = tx_context::sender(ctx);
        let lp_supply_amount = lp_supply_amount(market);
        let long = parse_direction<D>();

        let vault: &mut Vault<C> = bag::borrow_mut(
            &mut market.vaults,
            VaultName<C> {},
        );
        let symbol: &mut Symbol = bag::borrow_mut(
            &mut market.symbols,
            SymbolName<I, D> {},
        );

        let position_name = PositionName<C, I, D> {
            id: object::id_from_address(position_id),
            owner,
        };
        let position: &mut Position<C> = bag::borrow_mut(
            &mut market.positions,
            position_name,
        );

        let collateral_price = agg_price::parse_pyth_feeder(
            pool::vault_price_config(vault),
            collateral_feeder,
            timestamp,
        );
        let index_price = agg_price::parse_pyth_feeder(
            pool::symbol_price_config(symbol),
            index_feeder,
            timestamp,
        );

        let (liquidation_fee, event) = pool::liquidate_position(
            vault,
            symbol,
            position,
            reserving_fee_model,
            funding_fee_model,
            &collateral_price,
            &index_price,
            long,
            lp_supply_amount,
            timestamp,
            liquidator,
        );

        pay_from_balance(liquidation_fee, liquidator, ctx);

        // emit liquidate position
        event::emit(PositionClaimed {
            position_name: option::some(position_name),
            event,
        });
    }

    // version = 0x1 << 7
    public entry fun clear_closed_position<L, C, I, D>(
        market: &mut Market<L>,
        position_cap: PositionCap<C, I, D>,
        ctx: &TxContext,
    ) {
        assert!(market.fun_mask & 0x80 == 0, ERR_FUNCTION_VERSION_EXPIRED);

        let PositionCap { id } = position_cap;

        let position_name = PositionName<C, I, D> {
            owner: tx_context::sender(ctx),
            id: object::uid_to_inner(&id),
        };
        let position: Position<C> = bag::remove(
            &mut market.positions,
            position_name,
        );

        position::destroy_position(position);

        object::delete(id);
    }

    // version = 0x1 << 8
    public entry fun execute_open_position_order<L, C, I, D, F>(
        clock: &Clock,
        market: &mut Market<L>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        collateral_feeder: &PythFeeder,
        index_feeder: &PythFeeder,
        owner: address,
        order_id: address,
        ctx: &mut TxContext,
    ) {
        assert!(market.fun_mask & 0x100 == 0, ERR_FUNCTION_VERSION_EXPIRED);
        assert!(!market.vaults_locked && !market.symbols_locked, ERR_MARKET_ALREADY_LOCKED);

        let timestamp = clock::timestamp_ms(clock) / 1000;
        let executor = tx_context::sender(ctx);
        let lp_supply_amount = lp_supply_amount(market);
        let long = parse_direction<D>();

        let order_name = OrderName<C, I, D, F> {
            id: object::id_from_address(order_id),
            owner,
            position_id: option::none(),
        };
        let order: &mut OpenPositionOrder<C, F> = bag::borrow_mut(
            &mut market.orders,
            order_name,
        );

        let vault: &mut Vault<C> = bag::borrow_mut(
            &mut market.vaults,
            VaultName<C> {},
        );
        let symbol: &mut Symbol = bag::borrow_mut(
            &mut market.symbols,
            SymbolName<I, D> {},
        );

        let collateral_price = agg_price::parse_pyth_feeder(
            pool::vault_price_config(vault),
            collateral_feeder,
            timestamp,
        );
        let index_price = agg_price::parse_pyth_feeder(
            pool::symbol_price_config(symbol),
            index_feeder,
            timestamp,
        );

        let (rebate_rate, referrer) = get_referral_data(&market.referrals, owner);
        let (code, result, failure, fee) = orders::execute_open_position_order(
            order,
            vault,
            symbol,
            reserving_fee_model,
            funding_fee_model,
            &collateral_price,
            &index_price,
            rebate_rate,
            long,
            lp_supply_amount,
            timestamp,
        );
        if (code == 0) {
            let (position, rebate, event) =
                pool::unwrap_open_position_result(option::destroy_some(result));

            let position_id = object::new(ctx);
            let position_name = PositionName<C, I, D> {
                id: object::uid_to_inner(&position_id),
                owner,
            };

            bag::add(&mut market.positions, position_name, position);

            transfer::transfer(
                PositionCap<C, I, D> { id: position_id },
                owner,
            );

            pay_from_balance(rebate, referrer, ctx);

            // emit order executed and open opened
            event::emit(OrderExecuted {
                executor,
                order_name,
                claim: PositionClaimed {
                    position_name: option::some(position_name),
                    event,
                },
            });
        } else {
            // executed order failed
            option::destroy_none(result);
            let event = option::destroy_some(failure);
            
            // emit order executed and open failed
            event::emit(OrderExecuted {
                executor,
                order_name,
                claim: PositionClaimed {
                    position_name: option::none<PositionName<C, I, D>>(),
                    event,
                },
            });
        };

        pay_from_balance(fee, executor, ctx);
    }

    // version = 0x1 << 9
    public entry fun execute_decrease_position_order<L, C, I, D, F>(
        clock: &Clock,
        market: &mut Market<L>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        collateral_feeder: &PythFeeder,
        index_feeder: &PythFeeder,
        owner: address,
        order_id: address,
        position_id: address,
        ctx: &mut TxContext,
    ) {
        assert!(market.fun_mask & 0x200 == 0, ERR_FUNCTION_VERSION_EXPIRED);
        assert!(!market.vaults_locked && !market.symbols_locked, ERR_MARKET_ALREADY_LOCKED);
        
        let timestamp = clock::timestamp_ms(clock) / 1000;
        let executor = tx_context::sender(ctx);
        let lp_supply_amount = lp_supply_amount(market);
        let long = parse_direction<D>();

        let position_name = PositionName<C, I, D> {
            id: object::id_from_address(position_id),
            owner,
        };
        let order_name = OrderName<C, I, D, F> {
            id: object::id_from_address(order_id),
            owner,
            position_id: option::some(position_name.id),
        };
        let order: &mut DecreasePositionOrder<F> = bag::borrow_mut(
            &mut market.orders,
            order_name,
        );

        let vault: &mut Vault<C> = bag::borrow_mut(
            &mut market.vaults,
            VaultName<C> {},
        );
        let symbol: &mut Symbol = bag::borrow_mut(
            &mut market.symbols,
            SymbolName<I, D> {},
        );
        let position: &mut Position<C> = bag::borrow_mut(
            &mut market.positions,
            position_name,
        );

        let collateral_price = agg_price::parse_pyth_feeder(
            pool::vault_price_config(vault),
            collateral_feeder,
            timestamp,
        );
        let index_price = agg_price::parse_pyth_feeder(
            pool::symbol_price_config(symbol),
            index_feeder,
            timestamp,
        );

        let (rebate_rate, referrer) = get_referral_data(&market.referrals, owner);
        let (code, result, failure, fee) = orders::execute_decrease_position_order(
            order,
            vault,
            symbol,
            position,
            reserving_fee_model,
            funding_fee_model,
            &collateral_price,
            &index_price,
            rebate_rate,
            long,
            lp_supply_amount,
            timestamp,
        );
        if (code == 0) {
            let (to_trader, rebate, event) =
                pool::unwrap_decrease_position_result(option::destroy_some(result));

            pay_from_balance(to_trader, owner, ctx);
            pay_from_balance(rebate, referrer, ctx);

            // emit order executed and position decreased
            event::emit(OrderExecuted {
                executor,
                order_name,
                claim: PositionClaimed {
                    position_name: option::some(position_name),
                    event,
                },
            });
        } else {
            // executed order failed
            option::destroy_none(result);
            let event = option::destroy_some(failure);

            // emit order executed and decrease closed
            event::emit(OrderExecuted {
                executor,
                order_name,
                claim: PositionClaimed {
                    position_name: option::some(position_name),
                    event,
                },
            });
        };

        pay_from_balance(fee, executor, ctx);
    }

    // version = 0x1 << 10
    public entry fun clear_open_position_order<L, C, I, D, F>(
        market: &mut Market<L>,
        order_cap: OrderCap<C, I, D, F>,
        ctx: &mut TxContext,
    ) {
        assert!(market.fun_mask & 0x400 == 0, ERR_FUNCTION_VERSION_EXPIRED);

        let owner = tx_context::sender(ctx);

        let OrderCap { id, position_id } = order_cap;

        let order_name = OrderName<C, I, D, F> {
            id: object::uid_to_inner(&id),
            owner,
            position_id,
        };
        let order: OpenPositionOrder<C, F> = bag::remove(&mut market.orders, order_name);
        let (collateral, fee) = orders::destroy_open_position_order(order);

        object::delete(id);

        // emit order cleared
        event::emit(OrderCleared { order_name });

        pay_from_balance(collateral, owner, ctx);
        pay_from_balance(fee, owner, ctx);
    }

    // version = 0x1 << 11
    public entry fun clear_decrease_position_order<L, C, I, D, F>(
        market: &mut Market<L>,
        order_cap: OrderCap<C, I, D, F>,
        ctx: &mut TxContext,
    ) {
        assert!(market.fun_mask & 0x800 == 0, ERR_FUNCTION_VERSION_EXPIRED);

        let owner = tx_context::sender(ctx);

        let OrderCap { id, position_id } = order_cap;

        let order_name = OrderName<C, I, D, F> {
            id: object::uid_to_inner(&id),
            owner,
            position_id,
        };
        let order: DecreasePositionOrder<F> = bag::remove(&mut market.orders, order_name);
        let fee = orders::destroy_decrease_position_order(order);

        object::delete(id);

        // emit order cleared
        event::emit(OrderCleared { order_name });

        pay_from_balance(fee, owner, ctx);
    }

    /// === public write functions ===

    // version = 0x1 << 12
    public fun deposit<L, C>(
        market: &mut Market<L>,
        model: &RebaseFeeModel,
        deposit: Coin<C>,
        min_amount_out: u64,
        vaults_valuation: VaultsValuation,
        symbols_valuation: SymbolsValuation,
        ctx: &mut TxContext,
    ) {
        assert!(market.fun_mask & 0x1000 == 0, ERR_FUNCTION_VERSION_EXPIRED);
        assert!(
            object::id(model) == market.rebase_fee_model,
            ERR_MISMATCHED_RESERVING_FEE_MODEL,
        );

        let minter = tx_context::sender(ctx);
        let deposit_amount = coin::value(&deposit);
        let lp_supply_amount = balance::supply_value(&market.lp_supply);
        let (
            handled_vaults,
            total_weight,
            total_vaults_value,
            market_value,
        ) = finalize_market_valuation(market, vaults_valuation, symbols_valuation);
        let (_, VaultInfo { price, value: vault_value }) = vec_map::remove(
            &mut handled_vaults,
            &type_name::get<VaultName<C>>(),
        );

        let vault: &mut Vault<C> = bag::borrow_mut(&mut market.vaults, VaultName<C> {});

        let mint_amount = pool::deposit(
            vault,
            model,
            &price,
            coin::into_balance(deposit),
            min_amount_out,
            lp_supply_amount,
            market_value,
            vault_value,
            total_vaults_value,
            total_weight,
        );

        // mint to sender
        let minted = balance::increase_supply(&mut market.lp_supply, mint_amount);
        pay_from_balance(minted, minter, ctx);

        // emit deposited
        event::emit(Deposited<C> {
            minter,
            price: agg_price::price_of(&price),
            deposit_amount,
            mint_amount,
        });
    }

    // version = 0x1 << 13
    public fun withdraw<L, C>(
        market: &mut Market<L>,
        model: &RebaseFeeModel,
        burn: Coin<L>,
        min_amount_out: u64,
        vaults_valuation: VaultsValuation,
        symbols_valuation: SymbolsValuation,
        ctx: &mut TxContext,
    ) {
        assert!(market.fun_mask & 0x2000 == 0, ERR_FUNCTION_VERSION_EXPIRED);
        assert!(
            object::id(model) == market.rebase_fee_model,
            ERR_MISMATCHED_RESERVING_FEE_MODEL,
        );

        let burner = tx_context::sender(ctx);
        let lp_supply_amount = balance::supply_value(&market.lp_supply);
        let (
            handled_vaults,
            total_weight,
            total_vaults_value,
            market_value,
        ) = finalize_market_valuation(market, vaults_valuation, symbols_valuation);
        let (_, VaultInfo { price, value: vault_value }) = vec_map::remove(
            &mut handled_vaults,
            &type_name::get<VaultName<C>>(),
        );

        let vault: &mut Vault<C> = bag::borrow_mut(&mut market.vaults, VaultName<C> {});

        // burn LP
        let burn_amount = balance::decrease_supply(
            &mut market.lp_supply,
            coin::into_balance(burn),
        );

        // withdraw to burner
        let withdraw = pool::withdraw(
            vault,
            model,
            &price,
            burn_amount,
            min_amount_out,
            lp_supply_amount,
            market_value,
            vault_value,
            total_vaults_value,
            total_weight,
        );

        let withdraw_amount = balance::value(&withdraw);
        pay_from_balance(withdraw, burner, ctx);

        // emit withdrawn
        event::emit(Withdrawn<C> {
            burner,
            price: agg_price::price_of(&price),
            withdraw_amount,
            burn_amount,
        });
    }

    // version = 0x1 << 14
    public fun swap<L, S, D>(
        market: &mut Market<L>,
        model: &RebaseFeeModel,
        source: Coin<S>,
        min_amount_out: u64,
        vaults_valuation: VaultsValuation,
        ctx: &mut TxContext,
    ) {
        assert!(market.fun_mask & 0x4000 == 0, ERR_FUNCTION_VERSION_EXPIRED);
        assert!(
            object::id(model) == market.rebase_fee_model,
            ERR_MISMATCHED_RESERVING_FEE_MODEL,
        );
        assert!(
            type_name::get<S>() != type_name::get<D>(),
            ERR_SWAPPING_SAME_COINS,
        );

        let swapper = tx_context::sender(ctx);
        let source_amount = coin::value(&source);
        let (handled_vaults, total_weight, total_vaults_value) =
            finalize_vaults_valuation(market, vaults_valuation);
        let (_, VaultInfo { price: source_price, value: source_vault_value }) =
            vec_map::remove(&mut handled_vaults, &type_name::get<VaultName<S>>());
        let (_, VaultInfo { price: dest_price, value: dest_vault_value }) =
            vec_map::remove(&mut handled_vaults, &type_name::get<VaultName<D>>());

        // swap step 1
        let swap_value = pool::swap_in<S>(
            bag::borrow_mut(&mut market.vaults, VaultName<S> {}),
            model,
            &source_price,
            coin::into_balance(source),
            source_vault_value,
            total_vaults_value,
            total_weight,
        );

        // swap step 2
        let receiving = pool::swap_out<D>(
            bag::borrow_mut(&mut market.vaults, VaultName<D> {}),
            model,
            &dest_price,
            min_amount_out,
            swap_value,
            dest_vault_value,
            total_vaults_value,
            total_weight,
        );

        let dest_amount = balance::value(&receiving);
        pay_from_balance(receiving, swapper, ctx);

        // emit swapped
        event::emit(Swapped<S, D> {
            swapper,
            source_price: agg_price::price_of(&source_price),
            dest_price: agg_price::price_of(&dest_price),
            source_amount,
            dest_amount,
        });
    }

    // version = 0x1 << 15
    public fun create_vaults_valuation<L>(
        clock: &Clock,
        market: &mut Market<L>,
    ): VaultsValuation {
        assert!(market.fun_mask & 0x8000 == 0, ERR_FUNCTION_VERSION_EXPIRED);
        assert!(!market.vaults_locked, ERR_MARKET_ALREADY_LOCKED);
        // lock to avoid re-valuation
        market.vaults_locked = true;

        VaultsValuation {
            timestamp: clock::timestamp_ms(clock) / 1000,
            num: bag::length(&market.vaults),
            handled: vec_map::empty(),
            total_weight: decimal::zero(),
            value: decimal::zero(),
        }
    }

    // version = 0x1 << 16
    public fun create_symbols_valuation<L>(
        clock: &Clock,
        market: &mut Market<L>,
    ): SymbolsValuation {
        assert!(market.fun_mask & 0x10000 == 0, ERR_FUNCTION_VERSION_EXPIRED);
        assert!(!market.symbols_locked, ERR_MARKET_ALREADY_LOCKED);
        // lock to avoid re-valuation
        market.symbols_locked = true;

        SymbolsValuation {
            timestamp: clock::timestamp_ms(clock) / 1000,
            num: bag::length(&market.symbols),
            lp_supply_amount: lp_supply_amount(market),
            handled: vec_set::empty(),
            value: sdecimal::zero(),
        }
    }

    // version = 0x1 << 17
    public fun valuate_vault<L, C>(
        market: &mut Market<L>,
        model: &ReservingFeeModel,
        feeder: &PythFeeder,
        vaults_valuation: &mut VaultsValuation,
    ) {
        assert!(market.fun_mask & 0x20000 == 0, ERR_FUNCTION_VERSION_EXPIRED);

        let timestamp = vaults_valuation.timestamp;

        let vault: &mut Vault<C> = bag::borrow_mut(&mut market.vaults, VaultName<C> {});
        let vault_name = type_name::get<VaultName<C>>();
        assert!(
            !vec_map::contains(&vaults_valuation.handled, &vault_name),
            ERR_VAULT_ALREADY_HANDLED,
        );

        let price = agg_price::parse_pyth_feeder(
            pool::vault_price_config(vault),
            feeder,
            timestamp,
        );
        let value = pool::valuate_vault(vault, model, &price, timestamp);
        vaults_valuation.value = decimal::add(vaults_valuation.value, value);
        vaults_valuation.total_weight = decimal::add(
            vaults_valuation.total_weight,
            pool::vault_weight(vault),
        );

        // update handled vault
        vec_map::insert(
            &mut vaults_valuation.handled,
            vault_name,
            VaultInfo { price, value },
        );
    }

    // version = 0x1 << 18
    public fun valuate_symbol<L, I, D>(
        market: &mut Market<L>,
        funding_fee_model: &FundingFeeModel,
        feeder: &PythFeeder,
        valuation: &mut SymbolsValuation,
    ) {
        assert!(market.fun_mask & 0x40000 == 0, ERR_FUNCTION_VERSION_EXPIRED);

        let timestamp = valuation.timestamp;
        let long = parse_direction<D>();

        let symbol: &mut Symbol = bag::borrow_mut(&mut market.symbols, SymbolName<I, D> {});
        let symbol_name = type_name::get<SymbolName<I, D>>();
        assert!(
            !vec_set::contains(&valuation.handled, &symbol_name),
            ERR_SYMBOL_ALREADY_HANDLED,
        );

        let price = agg_price::parse_pyth_feeder(
            pool::symbol_price_config(symbol),
            feeder,
            timestamp,
        );
        valuation.value = sdecimal::add(
            valuation.value,
            pool::valuate_symbol(
                symbol,
                funding_fee_model,
                &price,
                long,
                valuation.lp_supply_amount,
                timestamp,
            ),
        );

        // update handled symbol
        vec_set::insert(&mut valuation.handled, symbol_name);
    }

    // === public read functions ===

    public fun rebase_fee_model<L>(market: &Market<L>): &ID {
        &market.rebase_fee_model
    }

    public fun vault<L, C>(market: &Market<L>): &Vault<C> {
        bag::borrow(&market.vaults, VaultName<C> {})
    }

    public fun symbol<L, I, D>(market: &Market<L>): &Symbol {
        bag::borrow(&market.symbols, SymbolName<I, D> {})
    }

    public fun position<L, C, I, D>(
        market: &Market<L>,
        id: ID,
        owner: address,
    ): &Position<C> {
        bag::borrow(&market.positions, PositionName<C, I, D> { id, owner })
    }

    public fun lp_supply_amount<L>(market: &Market<L>): Decimal {
        // LP decimal is 6
        decimal::div_by_u64(
            decimal::from_u64(balance::supply_value(&market.lp_supply)),
            1_000_000,
        )
    }

    public fun parse_direction<D>(): bool {
        let direction = type_name::get<D>();
        if (direction == type_name::get<LONG>()) {
            true
        } else {
            assert!(
                direction == type_name::get<SHORT>(),
                ERR_INVALID_DIRECTION,
            );
            false
        }
    }
}
