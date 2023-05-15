
module abex_core::market {
    use std::type_name::{Self, TypeName};

    use sui::event;
    use sui::transfer;
    use sui::bag::{Self, Bag};
    use sui::clock::{Self, Clock};
    use sui::vec_set::{Self, VecSet};
    use sui::vec_map::{Self, VecMap};
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance, Supply};
    use sui::coin::{Self, Coin, CoinMetadata};
    
    // use switchboard_std::aggregator::Aggregator as SwitchboardFeeder;
    
    use abex_feeder::native_feeder::NativeFeeder;

    use abex_core::admin::AdminCap;
    use abex_core::decimal::{Self, Decimal};
    use abex_core::sdecimal::{Self, SDecimal};
    use abex_core::agg_price::{Self, AggPrice};
    use abex_core::position::{Self, Position, PositionConfig};
    use abex_core::model::{
        Self, RebaseFeeModel, ReservingFeeModel, FundingFeeModel,
    };
    use abex_core::pool::{
        Self, Vault, Symbol,
        OpenPositionEvent, PledgeInPositionEvent,
        RedeemFromPositionEvent, DecreasePositionEvent,
        ClosePositionEvent, LiquidatePositionEvent,
    };
    // use abex_core::delegate::{
    //     Self, OpenPosition, ClosePosition, IncreasePosition,
    //     DecreasePosition, PledgeInPosition, RedeemFromPosition,
    // };

    friend abex_core::alp;

    // =============================== Objects ================================

    struct Market<phantom L> has key {
        id: UID,

        rebase_fee_model: ID,

        vaults: Bag,
        symbols: Bag,
        positions: Bag,

        lp_supply: Supply<L>,
    }

    struct PositionCap<phantom C, phantom I, phantom D> has key {
        id: UID,
    }

    struct WrappedPositionConfig<phantom I, phantom D> has key {
        id: UID,

        inner: PositionConfig,
    }

    // ================================ Name =================================

    struct LONG has drop {}

    struct SHORT has drop {}

    struct VaultName<phantom C> has copy, drop, store {}

    struct SymbolName<phantom I, phantom D> has copy, drop, store {}

    struct PositionName<
        phantom C,
        phantom I,
        phantom D,
    > has copy, drop, store {
        id: ID,
        owner: address,
    }

    // =============================== Hot Potato ==============================

    struct VaultInfo has drop {
        price: AggPrice,
        value: Decimal,
    }

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

    // ================================ Events =================================

    struct MarketCreated has copy, drop {
        vaults_parent_id: ID,
        symbols_parent_id: ID,
        positions_parent_id: ID,
    }

    struct PositionUpdated<
        phantom C,
        phantom I,
        phantom D,
        E: copy + drop,
    > has copy, drop {
        position_name: PositionName<C, I, D>,
        event: E,
    }

    // ================================ Errors =================================

    const ERR_VAULT_ALREADY_HANDLED: u64 = 0;
    const ERR_SYMBOL_ALREADY_HANDLED: u64 = 1;
    const ERR_VAULTS_NOT_TOTALLY_HANDLED: u64 = 2;
    const ERR_SYMBOLS_NOT_TOTALLY_HANDLED: u64 = 3;
    const ERR_UNEXPECTED_MARKET_VALUE: u64 = 4;
    const ERR_POSITION_STILL_EXISTS: u64 = 5;
    const ERR_INVALID_DIRECTION: u64 = 6;
    const ERR_MISMATCHED_RESERVING_FEE_MODEL: u64 = 7;
    const ERR_SWAPPING_SAME_COINS: u64 = 8;
    const ERR_COLLATERAL_PRICE_EXCEED_THRESHOLD: u64 = 9;
    const ERR_INDEX_PRICE_EXCEED_THRESHOLD: u64 = 10;
    const ERR_AMOUNT_OUT_TOO_LESS: u64 = 11;

    fun truncate_decimal(value: Decimal): u64 {
        // decimal's precision is 18, we need to truncate it to 6
        let value = decimal::to_raw(value);
        value = value / 1_000_000_000_000;

        (value as u64)
    }

    fun mint_lp<L>(market: &mut Market<L>, amount: u64): Balance<L> {
        balance::increase_supply(&mut market.lp_supply, amount)
    }

    fun burn_lp<L>(market: &mut Market<L>, token: Balance<L>): u64 {
        balance::decrease_supply(&mut market.lp_supply, token)
    }

    fun pay_from_balance<T>(
        balance: Balance<T>,
        receiver: address,
        ctx: &mut TxContext,
    ) {
        transfer::public_transfer(coin::from_balance(balance, ctx), receiver)
    }

    fun check_index_price(
        index_price: &AggPrice,
        long: bool,
        price_threshold: Decimal,
    ) {
        if (long) {
            assert!(
                decimal::le(
                    &agg_price::price_of(index_price),
                    &price_threshold,
                ),
                ERR_INDEX_PRICE_EXCEED_THRESHOLD,
            );
        } else {
            assert!(
                decimal::ge(
                    &agg_price::price_of(index_price),
                    &price_threshold,
                ),
                ERR_INDEX_PRICE_EXCEED_THRESHOLD,
            );
        }
    }

    fun finalize_vaults_valuation(
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

        (handled, total_weight, value)
    }

    fun finalize_symbols_valuation(valuation: SymbolsValuation): SDecimal {
        let SymbolsValuation {
            timestamp: _,
            num,
            lp_supply_amount: _,
            handled,
            value,
        } = valuation;
        assert!(vec_set::size(&handled) == num, ERR_SYMBOLS_NOT_TOTALLY_HANDLED);

        value
    }

    fun finalize_market_valuation(
        vaults_valuation: VaultsValuation,
        symbols_valuation: SymbolsValuation,
    ): (
        VecMap<TypeName, VaultInfo>,
        Decimal,
        Decimal,
        Decimal,
    ) {
        let (handled_vaults, total_weight, total_vaults_value) =
            finalize_vaults_valuation(vaults_valuation);
        let total_symbols_value = finalize_symbols_valuation(symbols_valuation);

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
            rebase_fee_model: model_id,
            vaults: bag::new(ctx),
            symbols: bag::new(ctx),
            positions: bag::new(ctx),
            lp_supply,
        };
        // emit market created
        event::emit(MarketCreated {
            vaults_parent_id: object::id(&market.vaults),
            symbols_parent_id: object::id(&market.symbols),
            positions_parent_id: object::id(&market.positions),
        });
        transfer::share_object(market);
    }

    public entry fun add_new_vault<L, C>(
        _a: &AdminCap,
        market: &mut Market<L>,
        weight: u256,
        max_interval: u64,
        coin_metadata: &CoinMetadata<C>,
        feeder: &NativeFeeder,
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
                coin_metadata,
                feeder,
            ),
        );
        bag::add(&mut market.vaults, VaultName<C> {}, vault);
    }

    public entry fun add_new_symbol<L, I, D>(
        _a: &AdminCap,
        market: &mut Market<L>,
        max_interval: u64,
        coin_metadata: &CoinMetadata<I>,
        feeder: &NativeFeeder,
        param_multiplier: u256,
        param_max: u128,
        max_laverage: u64,
        min_holding_duration: u64,
        max_reserved_multiplier: u64,
        min_size: u256,
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
                inner: position::new_position_config(
                    max_laverage,
                    min_holding_duration,
                    max_reserved_multiplier,
                    min_size,
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
                coin_metadata,
                feeder,
            ),
        );
        bag::add(&mut market.symbols, SymbolName<I, D> {}, symbol);
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
    }

    public entry fun open_position_1<L, C, D>(
        clock: &Clock,
        market: &mut Market<L>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        position_config: &WrappedPositionConfig<C, D>,
        feeder: &NativeFeeder,
        pledge: Coin<C>,
        open_amount: u64,
        reserved_amount: u64,
        price_threshold: u256,
        ctx: &mut TxContext,
    ) {
        open_position_2<L, C, C, D>(
            clock,
            market,
            reserving_fee_model,
            funding_fee_model,
            position_config,
            feeder,
            feeder,
            pledge,
            open_amount,
            reserved_amount,
            price_threshold,
            ctx,
        )
    }

    public entry fun open_position_2<L, C, I, D>(
        clock: &Clock,
        market: &mut Market<L>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        position_config: &WrappedPositionConfig<I, D>,
        collateral_feeder: &NativeFeeder,
        index_feeder: &NativeFeeder,
        pledge: Coin<C>,
        open_amount: u64,
        reserved_amount: u64,
        index_price_threshold: u256,
        ctx: &mut TxContext,
    ) {
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

        let collateral_price = agg_price::parse_native_feeder(
            pool::vault_price_config(vault),
            collateral_feeder,
            timestamp,
        );
        let index_price = agg_price::parse_native_feeder(
            pool::symbol_price_config(symbol),
            index_feeder,
            timestamp,
        );
        check_index_price(
            &index_price,
            long,
            decimal::from_raw(index_price_threshold),
        );

        let position_id = object::new(ctx);
        let position_name = PositionName<C, I, D> {
            id: object::uid_to_inner(&position_id),
            owner,
        };
        let (position, event) = pool::open_position(
            vault,
            symbol,
            reserving_fee_model,
            funding_fee_model,
            position_config.inner,
            &collateral_price,
            &index_price,
            coin::into_balance(pledge),
            long,
            open_amount,
            reserved_amount,
            lp_supply_amount,
            timestamp,
        );
        bag::add(&mut market.positions, position_name, position);

        transfer::transfer(PositionCap<C, I, D> { id: position_id }, owner);

        // emit open position
        event::emit(PositionUpdated<C, I, D, OpenPositionEvent> {
            position_name,
            event,
        });
    }

    public entry fun decrease_reserved_from_position<L, C, I, D>(
        clock: &Clock,
        market: &mut Market<L>,
        position_cap: &PositionCap<C, I, D>,
        reserving_fee_model: &ReservingFeeModel,
        decrease_amount: u64,
        ctx: &mut TxContext,
    ) {
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

        pool::decrease_reserved_from_position(
            vault,
            position,
            reserving_fee_model,
            decrease_amount,
            timestamp,
        );
    }

    public entry fun pledge_in_position<L, C, I, D>(
        clock: &Clock,
        market: &mut Market<L>,
        position_cap: &PositionCap<C, I, D>,
        pledge: Coin<C>,
        ctx: &mut TxContext,
    ) {
        let timestamp = clock::timestamp_ms(clock) / 1000;
        let owner = tx_context::sender(ctx);

        let position_name = PositionName<C, I, D> {
            id: object::uid_to_inner(&position_cap.id),
            owner,
        };
        let position: &mut Position<C> = bag::borrow_mut(
            &mut market.positions,
            position_name,
        );

        let event = pool::pledge_in_position(
            position,
            coin::into_balance(pledge),
            timestamp,
        );

        // emit pledge in position
        event::emit(PositionUpdated<C, I, D, PledgeInPositionEvent> {
            position_name,
            event,
        });
    }

    public entry fun redeem_from_position_1<L, C, D>(
        clock: &Clock,
        market: &mut Market<L>,
        position_cap: &PositionCap<C, C, D>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        feeder: &NativeFeeder,
        redeem_amount: u64,
        price_threshold: u256,
        ctx: &mut TxContext,
    ) {
        redeem_from_position_2(
            clock,
            market,
            position_cap,
            reserving_fee_model,
            funding_fee_model,
            feeder,
            feeder,
            redeem_amount,
            price_threshold,
            ctx,
        )
    }

    public entry fun redeem_from_position_2<L, C, I, D>(
        clock: &Clock,
        market: &mut Market<L>,
        position_cap: &PositionCap<C, I, D>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        collateral_feeder: &NativeFeeder,
        index_feeder: &NativeFeeder,
        redeem_amount: u64,
        index_price_threshold: u256,
        ctx: &mut TxContext,
    ) {
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

        let collateral_price = agg_price::parse_native_feeder(
            pool::vault_price_config(vault),
            collateral_feeder,
            timestamp,
        );
        let index_price = agg_price::parse_native_feeder(
            pool::symbol_price_config(symbol),
            index_feeder,
            timestamp,
        );
        check_index_price(
            &index_price,
            long,
            decimal::from_raw(index_price_threshold),
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
        event::emit(PositionUpdated<C, I, D, RedeemFromPositionEvent> {
            position_name,
            event,
        });
    }

    public entry fun decrease_position_1<L, C, D>(
        clock: &Clock,
        market: &mut Market<L>,
        position_cap: &PositionCap<C, C, D>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        feeder: &NativeFeeder,
        decreased_amount: u64,
        price_threshold: u256,
        ctx: &mut TxContext,
    ) {
        decrease_position_2(
            clock,
            market,
            position_cap,
            reserving_fee_model,
            funding_fee_model,
            feeder,
            feeder,
            decreased_amount,
            price_threshold,
            ctx,
        )
    }

    public entry fun decrease_position_2<L, C, I, D>(
        clock: &Clock,
        market: &mut Market<L>,
        position_cap: &PositionCap<C, I, D>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        collateral_feeder: &NativeFeeder,
        index_feeder: &NativeFeeder,
        decreased_amount: u64,
        index_price_threshold: u256,
        ctx: &mut TxContext,
    ) {
        let timestamp = clock::timestamp_ms(clock) / 1000;
        let owner = tx_context::sender(ctx);
        let lp_supply_amount = lp_supply_amount(market);
        let long = parse_direction<D>();

        let vault: &mut Vault<C> = bag::borrow_mut(&mut market.vaults, VaultName<C> {});
        let symbol: &mut Symbol = bag::borrow_mut(&mut market.symbols, SymbolName<I, D> {});

        let position_name = PositionName<C, I, D> {
            id: object::uid_to_inner(&position_cap.id),
            owner,
        };
        let position: &mut Position<C> = bag::borrow_mut(&mut market.positions, position_name);

        let collateral_price = agg_price::parse_native_feeder(
            pool::vault_price_config(vault),
            collateral_feeder,
            timestamp,
        );
        let index_price = agg_price::parse_native_feeder(
            pool::symbol_price_config(symbol),
            index_feeder,
            timestamp,
        );
        check_index_price(
            &index_price,
            long,
            decimal::from_raw(index_price_threshold),
        );

        let (profit, event) = pool::decrease_position(
            vault,
            symbol,
            position,
            reserving_fee_model,
            funding_fee_model,
            &collateral_price,
            &index_price,
            long,
            decreased_amount,
            lp_supply_amount,
            timestamp,
        );

        if (balance::value(&profit) > 0) {
            pay_from_balance(profit, owner, ctx);
        } else {
            balance::destroy_zero(profit);
        };

        // emit decrease position
        event::emit(PositionUpdated<C, I, D, DecreasePositionEvent> {
            position_name,
            event,
        });
    }

    public entry fun close_position_1<L, C, D>(
        clock: &Clock,
        market: &mut Market<L>,
        position_cap: PositionCap<C, C, D>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        feeder: &NativeFeeder,
        price_threshold: u256,
        ctx: &mut TxContext,
    ) {
        close_position_2(
            clock,
            market,
            position_cap,
            reserving_fee_model,
            funding_fee_model,
            feeder,
            feeder,
            price_threshold,
            ctx,
        )
    }

    public entry fun close_position_2<L, C, I, D>(
        clock: &Clock,
        market: &mut Market<L>,
        position_cap: PositionCap<C, I, D>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        collateral_feeder: &NativeFeeder,
        index_feeder: &NativeFeeder,
        index_price_threshold: u256,
        ctx: &mut TxContext,
    ) {
        let timestamp = clock::timestamp_ms(clock) / 1000;
        let owner = tx_context::sender(ctx);
        let lp_supply_amount = lp_supply_amount(market);
        let long = parse_direction<D>();

        let PositionCap { id: position_id } = position_cap;
        
        let vault: &mut Vault<C> = bag::borrow_mut(&mut market.vaults, VaultName<C> {});
        let symbol: &mut Symbol = bag::borrow_mut(&mut market.symbols, SymbolName<I, D> {});

        let position_name = PositionName<C, I, D> {
            id: object::uid_to_inner(&position_id),
            owner,
        };
        let position: Position<C> = bag::remove(&mut market.positions, position_name);
        // remove position cap
        object::delete(position_id);

        let collateral_price = agg_price::parse_native_feeder(
            pool::vault_price_config(vault),
            collateral_feeder,
            timestamp,
        );
        let index_price = agg_price::parse_native_feeder(
            pool::symbol_price_config(symbol),
            index_feeder,
            timestamp,
        );
        check_index_price(
            &index_price,
            long,
            decimal::from_raw(index_price_threshold),
        );

        let (profit, event) = pool::close_position(
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
        );

        if (balance::value(&profit) > 0) {
            pay_from_balance(profit, owner, ctx);
        } else {
            balance::destroy_zero(profit);
        };

        // emit close position
        event::emit(PositionUpdated<C, I, D, ClosePositionEvent> {
            position_name,
            event,
        });
    }

    public entry fun liquidate_position_1<L, C, D>(
        clock: &Clock,
        market: &mut Market<L>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        feeder: &NativeFeeder,
        owner: address,
        position_id: address,
        ctx: &mut TxContext,
    ) {
        liquidate_position_2<L, C, C, D>(
            clock,
            market,
            reserving_fee_model,
            funding_fee_model,
            feeder,
            feeder,
            owner,
            position_id,
            ctx,
        )
    }

    public entry fun liquidate_position_2<L, C, I, D>(
        clock: &Clock,
        market: &mut Market<L>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        collateral_feeder: &NativeFeeder,
        index_feeder: &NativeFeeder,
        owner: address,
        position_id: address,
        ctx: &mut TxContext,
    ) {
        let timestamp = clock::timestamp_ms(clock) / 1000;
        let liquidator = tx_context::sender(ctx);
        let lp_supply_amount = lp_supply_amount(market);
        let long = parse_direction<D>();

        let vault: &mut Vault<C> = bag::borrow_mut(&mut market.vaults, VaultName<C> {});
        let symbol: &mut Symbol = bag::borrow_mut(&mut market.symbols, SymbolName<I, D> {});

        let position_name = PositionName<C, I, D> {
            id: object::id_from_address(position_id),
            owner,
        };
        let position: Position<C> = bag::remove(&mut market.positions, position_name);

        let collateral_price = agg_price::parse_native_feeder(
            pool::vault_price_config(vault),
            collateral_feeder,
            timestamp,
        );
        let index_price = agg_price::parse_native_feeder(
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
        );

        if (balance::value(&liquidation_fee) > 0) {
            pay_from_balance(liquidation_fee, liquidator, ctx);
        } else {
            balance::destroy_zero(liquidation_fee);
        };

        // emit liquidate position
        event::emit(PositionUpdated<C, I, D, LiquidatePositionEvent> {
            position_name,
            event,
        });
    }

    public entry fun clear_position_cap<L, C, I, D>(
        market: &Market<L>,
        cap: PositionCap<C, I, D>,
        ctx: &TxContext,
    ) {
        let PositionCap { id: position_id } = cap;

        let position_name = PositionName<C, I, D> {
            owner: tx_context::sender(ctx),
            id: object::uid_to_inner(&position_id),
        };
        assert!(
            !bag::contains(&market.positions, position_name),
            ERR_POSITION_STILL_EXISTS,
        );

        object::delete(position_id);
    }

    // public entry fun delegate_open_position_1<L, C, D>(
    //     market: &mut Market<L>,
    //     clock: &Clock,
    //     feeder: &NativeFeeder,
    //     delegate: OpenPosition<C, C, D>,
    //     ctx: &mut TxContext,
    // ) {
    //     delegate_open_position_2(
    //         market,
    //         clock,
    //         feeder,
    //         feeder,
    //         delegate,
    //         ctx,
    //     )
    // }

    // public entry fun delegate_open_position_2<L, C, I, D>(
    //     market: &mut Market<L>,
    //     clock: &Clock,
    //     collateral_feeder: &NativeFeeder,
    //     index_feeder: &NativeFeeder,
    //     delegate: OpenPosition<C, I, D>,
    //     ctx: &mut TxContext,
    // ) {
    //     let owner = delegate::owner_of_open_position(&delegate);

    //     let vault: &mut Vault<C> = bag::borrow_mut(&mut market.vaults, VaultName<C> {});
    //     let symbol: &mut Symbol = bag::borrow_mut(&mut market.symbols, SymbolName<I, D> {});

    //     let timestamp_ms = clock::timestamp_ms(clock);
    //     let collateral_price = agg_price::parse_native_feeder(
    //         pool::vault_price_config(vault),
    //         collateral_feeder,
    //         timestamp_ms,
    //     );
    //     let index_price = agg_price::parse_native_feeder(
    //         pool::symbol_price_config(symbol),
    //         index_feeder,
    //         timestamp_ms,
    //     );

    //     let pst_id = object::new(ctx);
    //     let pst_name = PositionName<C, I, D> {
    //         id: object::uid_to_inner(&pst_id),
    //         owner,
    //     };
    //     let (pst, fee, event) = delegate::execute_open_position(
    //         vault,
    //         symbol,
    //         delegate,
    //         &collateral_price,
    //         &index_price,
    //         timestamp_ms,
    //     );
    //     bag::add(&mut market.positions, pst_name, pst);

    //     transfer::transfer(PositionCap<C, I, D> { id: pst_id }, owner);

    //     if (balance::value(&fee) > 0) {
    //         transfer::public_transfer(coin::from_balance(fee, ctx), tx_context::sender(ctx));
    //     } else {
    //         balance::destroy_zero(fee);
    //     };

    //     // emit delegate open position
    //     event::emit(PositionUpdated<C, I, D, PositionOpened> {
    //         name: pst_name,
    //         event,
    //     });
    // }

    // public entry fun delegate_pledge_in_position_1<L, C, D>(
    //     market: &mut Market<L>,
    //     clock: &Clock,
    //     feeder: &NativeFeeder,
    //     delegate: PledgeInPosition<C, C, D>,
    //     ctx: &mut TxContext,
    // ) {
    //     delegate_pledge_in_position_2(
    //         market,
    //         clock,
    //         feeder,
    //         feeder,
    //         delegate,
    //         ctx,
    //     )
    // }

    // public entry fun delegate_pledge_in_position_2<L, C, I, D>(
    //     market: &mut Market<L>,
    //     clock: &Clock,
    //     collateral_feeder: &NativeFeeder,
    //     index_feeder: &NativeFeeder,
    //     delegate: PledgeInPosition<C, I, D>,
    //     ctx: &mut TxContext,
    // ) {
    //     let vault: &mut Vault<C> = bag::borrow_mut(&mut market.vaults, VaultName<C> {});
    //     let symbol: &Symbol = bag::borrow(&market.symbols, SymbolName<I, D> {});

    //     let pst_name = PositionName<C, I, D> {
    //         id: delegate::pst_id_of_pledge_in_position(&delegate),
    //         owner: delegate::owner_of_pledge_in_position(&delegate),
    //     };
    //     let pst: &mut Position<C> = bag::borrow_mut(&mut market.positions, pst_name);

    //     let timestamp_ms = clock::timestamp_ms(clock);
    //     let collateral_price = agg_price::parse_native_feeder(
    //         pool::vault_price_config(vault),
    //         collateral_feeder,
    //         timestamp_ms,
    //     );
    //     let index_price = agg_price::parse_native_feeder(
    //         pool::symbol_price_config(symbol),
    //         index_feeder,
    //         timestamp_ms,
    //     );

    //     let (fee, event) = delegate::execute_pledge_in_position(
    //         vault,
    //         pst,
    //         delegate,
    //         &collateral_price,
    //         &index_price,
    //         timestamp_ms,
    //     );

    //     if (balance::value(&fee) > 0) {
    //         transfer::public_transfer(coin::from_balance(fee, ctx), tx_context::sender(ctx));
    //     } else {
    //         balance::destroy_zero(fee);
    //     };

    //     // emit delegate pledge in position
    //     event::emit(PositionUpdated<C, I, D, PledgedInPosition> {
    //         name: pst_name,
    //         event,
    //     });
    // }

    // public entry fun delegate_redeem_from_position_1<L, C, D>(
    //     market: &mut Market<L>,
    //     clock: &Clock,
    //     feeder: &NativeFeeder,
    //     delegate: RedeemFromPosition<C, C, D>,
    //     ctx: &mut TxContext,
    // ) {
    //     delegate_redeem_from_position_2(
    //         market,
    //         clock,
    //         feeder,
    //         feeder,
    //         delegate,
    //         ctx,
    //     )
    // }

    // public entry fun delegate_redeem_from_position_2<L, C, I, D>(
    //     market: &mut Market<L>,
    //     clock: &Clock,
    //     collateral_feeder: &NativeFeeder,
    //     index_feeder: &NativeFeeder,
    //     delegate: RedeemFromPosition<C, I, D>,
    //     ctx: &mut TxContext,
    // ) {
    //     let owner = delegate::owner_of_redeem_from_position(&delegate);

    //     let vault: &mut Vault<C> = bag::borrow_mut(&mut market.vaults, VaultName<C> {});
    //     let symbol: &mut Symbol = bag::borrow_mut(&mut market.symbols, SymbolName<I, D> {});

    //     let pst_name = PositionName<C, I, D> {
    //         id: delegate::pst_id_of_redeem_from_position(&delegate),
    //         owner,
    //     };
    //     let pst: &mut Position<C> = bag::borrow_mut(&mut market.positions, pst_name);

    //     let timestamp_ms = clock::timestamp_ms(clock);
    //     let collateral_price = agg_price::parse_native_feeder(
    //         pool::vault_price_config(vault),
    //         collateral_feeder,
    //         timestamp_ms,
    //     );
    //     let index_price = agg_price::parse_native_feeder(
    //         pool::symbol_price_config(symbol),
    //         index_feeder,
    //         timestamp_ms,
    //     );

    //     let (redeem, fee, event) = delegate::execute_redeem_from_position(
    //         vault,
    //         pst,
    //         delegate,
    //         pool::position_config(symbol),
    //         &collateral_price,
    //         &index_price,
    //         timestamp_ms,
    //     );

    //     transfer::public_transfer(coin::from_balance(redeem, ctx), owner);

    //     if (balance::value(&fee) > 0) {
    //         transfer::public_transfer(coin::from_balance(fee, ctx), tx_context::sender(ctx));
    //     } else {
    //         balance::destroy_zero(fee);
    //     };

    //     // emit delegate redeem from position
    //     event::emit(PositionUpdated<C, I, D, RedeemedFromPosition> {
    //         name: pst_name,
    //         event,
    //     });
    // }

    // public entry fun delegate_increase_position_1<L, C, D>(
    //     market: &mut Market<L>,
    //     clock: &Clock,
    //     feeder: &NativeFeeder,
    //     delegate: IncreasePosition<C, C, D>,
    //     ctx: &mut TxContext,
    // ) {
    //     delegate_increase_position_2(
    //         market,
    //         clock,
    //         feeder,
    //         feeder,
    //         delegate,
    //         ctx,
    //     )
    // }

    // public entry fun delegate_increase_position_2<L, C, I, D>(
    //     market: &mut Market<L>,
    //     clock: &Clock,
    //     collateral_feeder: &NativeFeeder,
    //     index_feeder: &NativeFeeder,
    //     delegate: IncreasePosition<C, I, D>,
    //     ctx: &mut TxContext,
    // ) {
    //     let vault: &mut Vault<C> = bag::borrow_mut(&mut market.vaults, VaultName<C> {});
    //     let symbol: &mut Symbol = bag::borrow_mut(&mut market.symbols, SymbolName<I, D> {});

    //     let pst_name = PositionName<C, I, D> {
    //         id: delegate::pst_id_of_increase_position(&delegate),
    //         owner: delegate::owner_of_increase_position(&delegate),
    //     };
    //     let pst: &mut Position<C> = bag::borrow_mut(&mut market.positions, pst_name);

    //     let timestamp_ms = clock::timestamp_ms(clock);
    //     let collateral_price = agg_price::parse_native_feeder(
    //         pool::vault_price_config(vault),
    //         collateral_feeder,
    //         timestamp_ms,
    //     );
    //     let index_price = agg_price::parse_native_feeder(
    //         pool::symbol_price_config(symbol),
    //         index_feeder,
    //         timestamp_ms,
    //     );

    //     let (fee, event) = delegate::execute_increase_position(
    //         vault,
    //         symbol,
    //         pst,
    //         delegate,
    //         &collateral_price,
    //         &index_price,
    //         timestamp_ms,
    //     );

    //     if (balance::value(&fee) > 0) {
    //         transfer::public_transfer(coin::from_balance(fee, ctx), tx_context::sender(ctx));
    //     } else {
    //         balance::destroy_zero(fee);
    //     };

    //     // emit delegate increase position
    //     event::emit(PositionUpdated<C, I, D, PositionIncreased> {
    //         name: pst_name,
    //         event,
    //     });
    // }

    // public entry fun delegate_decrease_position_1<L, C, D>(
    //     market: &mut Market<L>,
    //     clock: &Clock,
    //     feeder: &NativeFeeder,
    //     delegate: DecreasePosition<C, C, D>,
    //     ctx: &mut TxContext,
    // ) {
    //     delegate_decrease_position_2(
    //         market,
    //         clock,
    //         feeder,
    //         feeder,
    //         delegate,
    //         ctx,
    //     )
    // }

    // public entry fun delegate_decrease_position_2<L, C, I, D>(
    //     market: &mut Market<L>,
    //     clock: &Clock,
    //     collateral_feeder: &NativeFeeder,
    //     index_feeder: &NativeFeeder,
    //     delegate: DecreasePosition<C, I, D>,
    //     ctx: &mut TxContext,
    // ) {
    //     let owner = delegate::owner_of_decrease_position(&delegate);

    //     let vault: &mut Vault<C> = bag::borrow_mut(&mut market.vaults, VaultName<C> {});
    //     let symbol: &mut Symbol = bag::borrow_mut(&mut market.symbols, SymbolName<I, D> {});

    //     let pst_name = PositionName<C, I, D> {
    //         id: delegate::pst_id_of_decrease_position(&delegate),
    //         owner,
    //     };
    //     let pst: &mut Position<C> = bag::borrow_mut(&mut market.positions, pst_name);

    //     let timestamp_ms = clock::timestamp_ms(clock);
    //     let collateral_price = agg_price::parse_native_feeder(
    //         pool::vault_price_config(vault),
    //         collateral_feeder,
    //         timestamp_ms,
    //     );
    //     let index_price = agg_price::parse_native_feeder(
    //         pool::symbol_price_config(symbol),
    //         index_feeder,
    //         timestamp_ms,
    //     );

    //     let (profit, fee, event) = delegate::execute_decrease_position(
    //         vault,
    //         symbol,
    //         pst,
    //         delegate,
    //         &collateral_price,
    //         &index_price,
    //         timestamp_ms,
    //     );

    //     if (balance::value(&profit) > 0) {
    //         transfer::public_transfer(coin::from_balance(profit, ctx), owner);
    //     } else {
    //         balance::destroy_zero(profit);
    //     };

    //     if (balance::value(&fee) > 0) {
    //         transfer::public_transfer(coin::from_balance(fee, ctx), tx_context::sender(ctx));
    //     } else {
    //         balance::destroy_zero(fee);
    //     };

    //     // emit delegate decrease position
    //     event::emit(PositionUpdated<C, I, D, PositionDecreased> {
    //         name: pst_name,
    //         event,
    //     });
    // }

    // public entry fun delegate_close_position_1<L, C, D>(
    //     market: &mut Market<L>,
    //     clock: &Clock,
    //     feeder: &NativeFeeder,
    //     delegate: ClosePosition<C, C, D>,
    //     ctx: &mut TxContext,
    // ) {
    //     delegate_close_position_2(
    //         market,
    //         clock,
    //         feeder,
    //         feeder,
    //         delegate,
    //         ctx,
    //     )
    // }

    // public entry fun delegate_close_position_2<L, C, I, D>(
    //     market: &mut Market<L>,
    //     clock: &Clock,
    //     collateral_feeder: &NativeFeeder,
    //     index_feeder: &NativeFeeder,
    //     delegate: ClosePosition<C, I, D>,
    //     ctx: &mut TxContext,
    // ) {
    //     let owner = delegate::owner_of_close_position(&delegate);

    //     let vault: &mut Vault<C> = bag::borrow_mut(&mut market.vaults, VaultName<C> {});
    //     let symbol: &mut Symbol = bag::borrow_mut(&mut market.symbols, SymbolName<I, D> {});

    //     let pst_name = PositionName<C, I, D> {
    //         id: delegate::pst_id_of_close_position(&delegate),
    //         owner,
    //     };
    //     let pst: Position<C> = bag::remove(&mut market.positions, pst_name);

    //     let timestamp_ms = clock::timestamp_ms(clock);
    //     let collateral_price = agg_price::parse_native_feeder(
    //         pool::vault_price_config(vault),
    //         collateral_feeder,
    //         timestamp_ms,
    //     );
    //     let index_price = agg_price::parse_native_feeder(
    //         pool::symbol_price_config(symbol),
    //         index_feeder,
    //         timestamp_ms,
    //     );

    //     let (profit, fee, event) = delegate::execute_close_position(
    //         vault,
    //         symbol,
    //         pst,
    //         delegate,
    //         &collateral_price,
    //         &index_price,
    //         timestamp_ms,
    //     );

    //     if (balance::value(&profit) > 0) {
    //         transfer::public_transfer(coin::from_balance(profit, ctx), owner);
    //     } else {
    //         balance::destroy_zero(profit);
    //     };

    //     if (balance::value(&fee) > 0) {
    //         transfer::public_transfer(coin::from_balance(fee, ctx), tx_context::sender(ctx));
    //     } else {
    //         balance::destroy_zero(fee);
    //     };

    //     // emit delegate close position
    //     event::emit(PositionUpdated<C, I, D, PositionNormalClosed> {
    //         name: pst_name,
    //         event: PositionNormalClosed { inner: event },
    //     });
    // }

    ////////////////////////////////////////////////////////////////////

    public fun deposit<L, C>(
        market: &mut Market<L>,
        model: &RebaseFeeModel,
        deposit: Coin<C>,
        min_amount_out: u64,
        vaults_valuation: VaultsValuation,
        symbols_valuation: SymbolsValuation,
        ctx: &mut TxContext,
    ) {
        assert!(
            object::id(model) == market.rebase_fee_model,
            ERR_MISMATCHED_RESERVING_FEE_MODEL,
        );

        let minter = tx_context::sender(ctx);
        let lp_supply_amount = balance::supply_value(&market.lp_supply);
        let (
            handled_vaults,
            total_weight,
            total_vaults_value,
            market_value,
        ) = finalize_market_valuation(vaults_valuation, symbols_valuation);
        let (_, VaultInfo { price, value: vault_value }) = vec_map::remove(
            &mut handled_vaults,
            &type_name::get<VaultName<C>>(),
        );

        let vault: &mut Vault<C> = bag::borrow_mut(&mut market.vaults, VaultName<C> {});

        let deposit_value = pool::deposit(
            vault,
            model,
            &price,
            coin::into_balance(deposit),
            vault_value,
            total_vaults_value,
            total_weight,
        );
        let mint_amount = if (lp_supply_amount == 0) {
            assert!(decimal::is_zero(&market_value), ERR_UNEXPECTED_MARKET_VALUE);
            truncate_decimal(deposit_value)
        } else {
            assert!(!decimal::is_zero(&market_value), ERR_UNEXPECTED_MARKET_VALUE);
            let exchange_rate = decimal::to_rate(
                decimal::div(deposit_value, market_value)
            );
            decimal::floor_u64(
                decimal::mul_with_rate(
                    decimal::from_u64(lp_supply_amount),
                    exchange_rate,
                )
            )
        };
        assert!(mint_amount >= min_amount_out, ERR_AMOUNT_OUT_TOO_LESS);

        // mint to sender
        let minted = mint_lp(market, mint_amount);
        pay_from_balance(minted, minter, ctx);
    }

    public fun withdraw<L, C>(
        market: &mut Market<L>,
        model: &RebaseFeeModel,
        burn: Coin<L>,
        min_amount_out: u64,
        vaults_valuation: VaultsValuation,
        symbols_valuation: SymbolsValuation,
        ctx: &mut TxContext,
    ) {
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
        ) = finalize_market_valuation(vaults_valuation, symbols_valuation);
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
        let exchange_rate = decimal::to_rate(
            decimal::div(
                decimal::from_u64(burn_amount),
                decimal::from_u64(lp_supply_amount),
            )
        );
        let withdraw_value = decimal::mul_with_rate(market_value, exchange_rate);

        // withdraw to burner
        let withdraw = pool::withdraw(
            vault,
            model,
            &price,
            withdraw_value,
            vault_value,
            total_vaults_value,
            total_weight,
        );
        assert!(balance::value(&withdraw) >= min_amount_out, ERR_AMOUNT_OUT_TOO_LESS);
        pay_from_balance(withdraw, burner, ctx);
    }

    public fun swap<L, S, D>(
        market: &mut Market<L>,
        model: &RebaseFeeModel,
        source: Coin<S>,
        min_amount_out: u64,
        vaults_valuation: VaultsValuation,
        ctx: &mut TxContext,
    ) {
        assert!(
            object::id(model) == market.rebase_fee_model,
            ERR_MISMATCHED_RESERVING_FEE_MODEL,
        );
        assert!(
            type_name::get<S>() != type_name::get<D>(),
            ERR_SWAPPING_SAME_COINS,
        );
        let swapper = tx_context::sender(ctx);
        let (handled_vaults, total_weight, total_vaults_value) =
            finalize_vaults_valuation(vaults_valuation);
        let (_, VaultInfo { price: source_price, value: source_vault_value }) =
            vec_map::remove(&mut handled_vaults, &type_name::get<VaultName<S>>());
        let (_, VaultInfo { price: dest_price, value: dest_vault_value }) =
            vec_map::remove(&mut handled_vaults, &type_name::get<VaultName<D>>());

        // swap step 1
        let swap_value = pool::swap_source<S>(
            bag::borrow_mut(&mut market.vaults, VaultName<S> {}),
            model,
            &source_price,
            coin::into_balance(source),
            source_vault_value,
            total_vaults_value,
            total_weight,
        );

        // swap step 2
        let receiving = pool::swap_dest<D>(
            bag::borrow_mut(&mut market.vaults, VaultName<D> {}),
            model,
            &dest_price,
            swap_value,
            dest_vault_value,
            total_vaults_value,
            total_weight,
        );
        assert!(balance::value(&receiving) >= min_amount_out, ERR_AMOUNT_OUT_TOO_LESS);
        pay_from_balance(receiving, swapper, ctx);
    }

    public fun create_vaults_valuation<L>(
        clock: &Clock,
        market: &Market<L>,
    ): VaultsValuation {
        VaultsValuation {
            timestamp: clock::timestamp_ms(clock) / 1000,
            num: bag::length(&market.vaults),
            handled: vec_map::empty(),
            total_weight: decimal::zero(),
            value: decimal::zero(),
        }
    }

    public fun create_symbols_valuation<L>(
        clock: &Clock,
        market: &Market<L>,
    ): SymbolsValuation {
        SymbolsValuation {
            timestamp: clock::timestamp_ms(clock) / 1000,
            num: bag::length(&market.symbols),
            lp_supply_amount: lp_supply_amount(market),
            handled: vec_set::empty(),
            value: sdecimal::zero(),
        }
    }

    public fun valuate_vault<L, C>(
        market: &mut Market<L>,
        model: &ReservingFeeModel,
        feeder: &NativeFeeder,
        vaults_valuation: &mut VaultsValuation,
    ) {
        let timestamp = vaults_valuation.timestamp;

        let vault: &mut Vault<C> = bag::borrow_mut(&mut market.vaults, VaultName<C> {});
        let vault_name = type_name::get<VaultName<C>>();
        assert!(
            !vec_map::contains(&vaults_valuation.handled, &vault_name),
            ERR_VAULT_ALREADY_HANDLED,
        );

        let price = agg_price::parse_native_feeder(
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

    public fun valuate_symbol<L, I, D>(
        market: &mut Market<L>,
        funding_fee_model: &FundingFeeModel,
        feeder: &NativeFeeder,
        valuation: &mut SymbolsValuation,
    ) {
        let timestamp = valuation.timestamp;
        let long = parse_direction<D>();

        let symbol: &mut Symbol = bag::borrow_mut(&mut market.symbols, SymbolName<I, D> {});
        let symbol_name = type_name::get<SymbolName<I, D>>();
        assert!(
            !vec_set::contains(&valuation.handled, &symbol_name),
            ERR_SYMBOL_ALREADY_HANDLED,
        );

        let price = agg_price::parse_native_feeder(
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

    //////////////////////////// public read functions ////////////////////////////

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