
module abex_core::pool {
    use std::option::{Self, Option};
    use std::type_name::{Self, TypeName};

    use sui::object::{Self, ID};
    use sui::vec_set::{Self, VecSet};
    use sui::balance::{Self, Balance};
    
    use abex_core::rate::{Self, Rate};
    use abex_core::srate::{Self, SRate};
    use abex_core::decimal::{Self, Decimal};
    use abex_core::sdecimal::{Self, SDecimal};
    use abex_core::model::{
        Self, RebaseFeeModel, ReservingFeeModel, FundingFeeModel,
    };
    use abex_core::agg_price::{Self, AggPrice, AggPriceConfig};
    use abex_core::position::{Self, Position, PositionConfig};

    friend abex_core::market;

    // === Storage ===

    struct Vault<phantom C> has store {
        enabled: bool,
        weight: Decimal,
        reserving_fee_model: ID,
        price_config: AggPriceConfig,

        last_update: u64,
        tax: Balance<C>,
        liquidity: Balance<C>,
        reserved_amount: u64,
        unrealised_reserving_fee_amount: Decimal,
        acc_reserving_rate: Rate,
    }

    struct Symbol has store {
        open_enabled: bool,
        decrease_enabled: bool,
        liquidate_enabled: bool,
        supported_collaterals: VecSet<TypeName>,
        funding_fee_model: ID,
        price_config: AggPriceConfig,

        last_update: u64,
        opening_amount: u64,
        opening_size: Decimal,
        realised_pnl: SDecimal,
        unrealised_funding_fee_value: SDecimal,
        acc_funding_rate: SRate,
    }

    // === Cache State ===

    struct OpenPositionResult<phantom C> {
        position: Position<C>,
        rebate: Balance<C>,
        event: OpenPositionSuccessEvent,
    }

    struct DecreasePositionResult<phantom C> {
        to_trader: Balance<C>,
        rebate: Balance<C>,
        event: DecreasePositionSuccessEvent,
    }

    // === Position Events ===

    struct OpenPositionSuccessEvent has copy, drop {
        timestamp: u64,
        position_config: PositionConfig,
        collateral_price: Decimal,
        index_price: Decimal,
        open_amount: u64,
        open_fee_value: Decimal,
        reserve_amount: u64,
        collateral_amount: u64,
    }

    struct OpenPositionFailedEvent has copy, drop {
        timestamp: u64,
        position_config: PositionConfig,
        collateral_price: Decimal,
        index_price: Decimal,
        open_amount: u64,
        collateral_amount: u64,
        code: u64,
    }

    struct DecreasePositionSuccessEvent has copy, drop {
        timestamp: u64,
        collateral_price: Decimal,
        index_price: Decimal,
        decrease_amount: u64,
        decrease_fee_value: Decimal,
        reserving_fee_value: Decimal,
        funding_fee_value: SDecimal,
        closed: bool,
        has_profit: bool,
        settled_amount: u64,
    }

    struct DecreasePositionFailedEvent has copy, drop {
        timestamp: u64,
        collateral_price: Decimal,
        index_price: Decimal,
        decrease_amount: u64,
        code: u64,
    }

    struct DecreaseReservedFromPositionEvent has copy, drop {
        timestamp: u64,
        decrease_amount: u64,
    }

    struct PledgeInPositionEvent has copy, drop {
        timestamp: u64,
        pledge_amount: u64,
    }

    struct RedeemFromPositionEvent has copy, drop {
        timestamp: u64,
        redeem_amount: u64,
    }

    struct LiquidatePositionEvent has copy, drop {
        timestamp: u64,
        liquidator: address,
        collateral_price: Decimal,
        index_price: Decimal,
        reserving_fee_value: Decimal,
        funding_fee_value: SDecimal,
        loss_amount: u64,
        liquidator_bonus_amount: u64,
    }

    // === Errors ===
    // vault errors
    const ERR_VAULT_DISABLED: u64 = 0;
    const ERR_INSUFFICIENT_SUPPLY: u64 = 1;
    const ERR_INSUFFICIENT_LIQUIDITY: u64 = 2;
    // symbol errors
    const ERR_COLLATERAL_NOT_SUPPORTED: u64 = 3;
    const ERR_OPEN_DISABLED: u64 = 4;
    const ERR_DECREASE_DISABLED: u64 = 5;
    const ERR_LIQUIDATE_DISABLED: u64 = 6;
    // swap errors
    const ERR_SOURCE_EQUALS_TO_DEST: u64 = 7;
    const ERR_INVALID_SWAP_AMOUNT: u64 = 8;
    // deposit/withdraw errors
    const ERR_INVALID_DEPOSIT: u64 = 9;
    const ERR_INVALID_WITHDRAW_AMOUNT: u64 = 10;
    // model errors
    const ERR_MISMATCHED_RESERVING_FEE_MODEL: u64 = 11;
    const ERR_MISMATCHED_FUNDING_FEE_MODEL: u64 = 12;

    fun refresh_vault<C>(
        vault: &mut Vault<C>,
        reserving_fee_model: &ReservingFeeModel,
        supply_amount: Decimal,
        timestamp: u64,
    ) {
        let delta_rate = vault_delta_reserving_rate(
            vault,
            reserving_fee_model,
            supply_amount,
            timestamp,
        );
        vault.acc_reserving_rate = vault_acc_reserving_rate(vault, delta_rate);
        vault.unrealised_reserving_fee_amount =
            vault_unrealised_reserving_fee_amount(vault, delta_rate);
        vault.last_update = timestamp;
    }

    fun refresh_symbol(
        symbol: &mut Symbol,
        funding_fee_model: &FundingFeeModel,
        delta_size: SDecimal,
        lp_supply_amount: Decimal,
        timestamp: u64,
    ) {
        let delta_rate = symbol_delta_funding_rate(
            symbol,
            funding_fee_model,
            delta_size,
            lp_supply_amount,
            timestamp,
        );
        symbol.acc_funding_rate = symbol_acc_funding_rate(symbol, delta_rate);
        symbol.unrealised_funding_fee_value =
            symbol_unrealised_funding_fee_value(symbol, delta_rate);
        symbol.last_update = timestamp;
    }

    public(friend) fun new_vault<C>(
        weight: u256,
        model_id: ID,
        price_config: AggPriceConfig,
    ): Vault<C> {
        Vault {
            enabled: true,
            weight: decimal::from_raw(weight),
            reserving_fee_model: model_id,
            price_config,
            last_update: 0,
            tax: balance::zero(),
            liquidity: balance::zero(),
            reserved_amount: 0,
            unrealised_reserving_fee_amount: decimal::zero(),
            acc_reserving_rate: rate::zero(),
        }
    }

    public(friend) fun new_symbol(
        model_id: ID,
        price_config: AggPriceConfig,
    ): Symbol {
        Symbol {
            open_enabled: true,
            decrease_enabled: true,
            liquidate_enabled: true,
            supported_collaterals: vec_set::empty(),
            funding_fee_model: model_id,
            price_config,
            last_update: 0,
            opening_amount: 0,
            opening_size: decimal::zero(),
            realised_pnl: sdecimal::zero(),
            unrealised_funding_fee_value: sdecimal::zero(),
            acc_funding_rate: srate::zero(),
        }
    }

    public(friend) fun add_collateral_to_symbol<C>(config: &mut Symbol) {
        vec_set::insert(&mut config.supported_collaterals, type_name::get<C>());
    }

    public(friend) fun remove_collateral_from_symbol<C>(config: &mut Symbol) {
        vec_set::remove(&mut config.supported_collaterals, &type_name::get<C>());
    }

    // TODO: add event here
    public(friend) fun deposit<C>(
        vault: &mut Vault<C>,
        fee_model: &RebaseFeeModel,
        price: &AggPrice,
        deposit: Balance<C>,
        vault_value: Decimal,
        total_vaults_value: Decimal,
        total_weight: Decimal,
    ): Decimal {
        assert!(vault.enabled, ERR_VAULT_DISABLED);
        let deposit_amount = balance::value(&deposit);
        assert!(deposit_amount > 0, ERR_INVALID_DEPOSIT);
        let deposit_value = agg_price::coins_to_value(price, deposit_amount);

        // handle fee
        let fee_rate = compute_rebase_fee_rate(
            fee_model,
            true,
            decimal::add(vault_value, deposit_value),
            decimal::add(total_vaults_value, deposit_value),
            vault.weight,
            total_weight,
        );
        deposit_value = decimal::sub(
            deposit_value,
            decimal::mul_with_rate(deposit_value, fee_rate),
        );

        balance::join(&mut vault.liquidity, deposit);

        deposit_value
    }

    public(friend) fun withdraw<C>(
        vault: &mut Vault<C>,
        fee_model: &RebaseFeeModel,
        price: &AggPrice,
        withdraw_value: Decimal,
        vault_value: Decimal,
        total_vaults_value: Decimal,
        total_weight: Decimal,
    ): Balance<C> {
        assert!(vault.enabled, ERR_VAULT_DISABLED);
        assert!(
            decimal::lt(&withdraw_value, &total_vaults_value),
            ERR_INSUFFICIENT_SUPPLY,
        );

        // handle fee
        let fee_rate = compute_rebase_fee_rate(
            fee_model,
            false,
            decimal::sub(vault_value, withdraw_value),
            decimal::sub(total_vaults_value, withdraw_value),
            vault.weight,
            total_weight,
        );
        withdraw_value = decimal::sub(
            withdraw_value,
            decimal::mul_with_rate(withdraw_value, fee_rate),
        );

        let withdraw_amount = decimal::floor_u64(
            agg_price::value_to_coins(price, withdraw_value)
        );
        assert!(
            withdraw_amount < balance::value(&vault.liquidity),
            ERR_INSUFFICIENT_LIQUIDITY,
        );
        
        balance::split(&mut vault.liquidity, withdraw_amount)
    }

    public(friend) fun swap_in<S>(
        source_vault: &mut Vault<S>,
        model: &RebaseFeeModel,
        source_price: &AggPrice,
        source: Balance<S>,
        source_vault_value: Decimal,
        total_vaults_value: Decimal,
        total_weight: Decimal,
    ): Decimal {
        assert!(source_vault.enabled, ERR_VAULT_DISABLED);
        let source_amount = balance::value(&source);
        assert!(source_amount > 0, ERR_INVALID_SWAP_AMOUNT);

        balance::join(&mut source_vault.liquidity, source);

        // handle swapping in
        let swap_value = agg_price::coins_to_value(source_price, source_amount);
        let source_fee_rate = compute_rebase_fee_rate(
            model,
            true,
            decimal::add(source_vault_value, swap_value),
            decimal::add(total_vaults_value, swap_value),
            source_vault.weight,
            total_weight,
        );
        decimal::sub(
            swap_value,
            decimal::mul_with_rate(swap_value, source_fee_rate),
        )
    }

    public(friend) fun swap_out<D>(
        dest_vault: &mut Vault<D>,
        model: &RebaseFeeModel,
        dest_price: &AggPrice,
        swap_value: Decimal,
        dest_vault_value: Decimal,
        total_vaults_value: Decimal,
        total_weight: Decimal,
    ): Balance<D> {
        assert!(dest_vault.enabled, ERR_VAULT_DISABLED);

        // handle swapping out
        assert!(
            decimal::lt(&swap_value, &dest_vault_value),
            ERR_INSUFFICIENT_SUPPLY,
        );
        let dest_fee_rate = compute_rebase_fee_rate(
            model,
            false,
            decimal::sub(dest_vault_value, swap_value),
            total_vaults_value,
            dest_vault.weight,
            total_weight,
        );
        swap_value = decimal::sub(
            swap_value,
            decimal::mul_with_rate(swap_value, dest_fee_rate),
        );
        let dest_amount = decimal::floor_u64(
            agg_price::value_to_coins(dest_price, swap_value)
        );
        assert!(
            dest_amount < balance::value(&dest_vault.liquidity),
            ERR_INSUFFICIENT_LIQUIDITY,
        );

        balance::split(&mut dest_vault.liquidity, dest_amount)
    }

    public(friend) fun open_position<C>(
        vault: &mut Vault<C>,
        symbol: &mut Symbol,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        position_config: &PositionConfig,
        collateral_price: &AggPrice,
        index_price: &AggPrice,
        collateral: &mut Balance<C>,
        rebate_rate: Rate,
        long: bool,
        open_amount: u64,
        reserve_amount: u64,
        lp_supply_amount: Decimal,
        timestamp: u64,
    ): (u64, Option<OpenPositionResult<C>>, Option<OpenPositionFailedEvent>) {
        // Pool errors are no need to be catched
        assert!(vault.enabled, ERR_VAULT_DISABLED);
        assert!(symbol.open_enabled, ERR_OPEN_DISABLED);
        assert!(
            object::id(reserving_fee_model) == vault.reserving_fee_model,
            ERR_MISMATCHED_RESERVING_FEE_MODEL,
        );
        assert!(
            object::id(funding_fee_model) == symbol.funding_fee_model,
            ERR_MISMATCHED_FUNDING_FEE_MODEL,
        );
        assert!(
            vec_set::contains(
                &symbol.supported_collaterals,
                &type_name::get<C>(),
            ),
            ERR_COLLATERAL_NOT_SUPPORTED,
        );
        assert!(
            balance::value(&vault.liquidity) > reserve_amount,
            ERR_INSUFFICIENT_LIQUIDITY,
        );

        // refresh vault
        let supply_amount = vault_supply_amount(vault);
        refresh_vault(vault, reserving_fee_model, supply_amount, timestamp);
        // refresh symbol
        let delta_size = symbol_delta_size(symbol, index_price, long);
        refresh_symbol(
            symbol,
            funding_fee_model,
            delta_size,
            lp_supply_amount,
            timestamp,
        );

        // open position
        let (code, result) = position::open_position(
            position_config,
            collateral_price,
            index_price,
            &mut vault.liquidity,
            collateral,
            open_amount,
            reserve_amount,
            vault.acc_reserving_rate,
            symbol.acc_funding_rate,
            timestamp,
        );
        if (code > 0) {
            option::destroy_none(result);
            
            let event = OpenPositionFailedEvent {
                timestamp,
                position_config: *position_config,
                collateral_price: agg_price::price_of(collateral_price),
                index_price: agg_price::price_of(index_price),
                open_amount,
                collateral_amount: balance::value(collateral),
                code,
            };
            return (code, option::none(), option::some(event))
        };

        let (position, open_fee, open_fee_value, open_fee_amount) =
            position::unwrap_open_position_result(option::destroy_some(result));

        // compute rebate
        let rebate = balance::split(
            &mut open_fee,
            decimal::floor_u64(decimal::mul_with_rate(open_fee_amount, rebate_rate)),
        );

        // update vault
        vault.reserved_amount = vault.reserved_amount + reserve_amount;
        let _ = balance::join(&mut vault.liquidity, open_fee);

        // update symbol
        symbol.opening_size = decimal::add(
            symbol.opening_size,
            position::position_size(&position),
        );
        symbol.opening_amount = symbol.opening_amount + open_amount;

        let collateral_amount = position::collateral_amount(&position);
        let result = OpenPositionResult {
            position,
            rebate,
            event: OpenPositionSuccessEvent {
                timestamp,
                position_config: *position_config,
                collateral_price: agg_price::price_of(collateral_price),
                index_price: agg_price::price_of(index_price),
                open_amount,
                open_fee_value,
                reserve_amount,
                collateral_amount,
            },
        };
        (code, option::some(result), option::none())
    }

    public(friend) fun unwrap_open_position_result<C>(res: OpenPositionResult<C>): (
        Position<C>,
        Balance<C>,
        OpenPositionSuccessEvent,
    ) {
        let OpenPositionResult {
            position,
            rebate,
            event,
        } = res;

        (position, rebate, event)
    }

    public(friend) fun decrease_position<C>(
        vault: &mut Vault<C>,
        symbol: &mut Symbol,
        position: &mut Position<C>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        collateral_price: &AggPrice,
        index_price: &AggPrice,
        rebate_rate: Rate,
        long: bool,
        decrease_amount: u64,
        lp_supply_amount: Decimal,
        timestamp: u64,
    ): (u64, Option<DecreasePositionResult<C>>, Option<DecreasePositionFailedEvent>) {
        // Pool errors are no need to be catched
        assert!(vault.enabled, ERR_VAULT_DISABLED);
        assert!(symbol.decrease_enabled, ERR_DECREASE_DISABLED);
        assert!(
            object::id(reserving_fee_model) == vault.reserving_fee_model,
            ERR_MISMATCHED_RESERVING_FEE_MODEL,
        );
        assert!(
            object::id(funding_fee_model) == symbol.funding_fee_model,
            ERR_MISMATCHED_FUNDING_FEE_MODEL,
        );

        // refresh vault
        let supply_amount = vault_supply_amount(vault);
        refresh_vault(vault, reserving_fee_model, supply_amount, timestamp);
        // refresh symbol
        let delta_size = symbol_delta_size(symbol, index_price, long);
        refresh_symbol(
            symbol,
            funding_fee_model,
            delta_size,
            lp_supply_amount,
            timestamp,
        );

        // decrease position
        let (code, result) = position::decrease_position(
            position,
            collateral_price,
            index_price,
            long,
            decrease_amount,
            vault.acc_reserving_rate,
            symbol.acc_funding_rate,
            timestamp,
        );
        if (code > 0) {
            option::destroy_none(result);

            let event = DecreasePositionFailedEvent {
                timestamp,
                collateral_price: agg_price::price_of(collateral_price),
                index_price: agg_price::price_of(index_price),
                decrease_amount,
                code,
            };
            return (code, option::none(), option::some(event))
        };

        let (
            closed,
            has_profit,
            settled_amount,
            decreased_reserved_amount,
            decrease_size,
            reserving_fee_amount,
            decrease_fee_value,
            reserving_fee_value,
            funding_fee_value,
            to_vault,
            to_trader,
        ) = position::unwrap_decrease_position_result(option::destroy_some(result));

        // compute rebate
        let rebate_value = decimal::mul_with_rate(decrease_fee_value, rebate_rate);
        let rebate = balance::split(
            &mut to_vault,
            decimal::floor_u64(agg_price::value_to_coins(collateral_price, rebate_value)),
        );

        // update vault
        vault.reserved_amount = vault.reserved_amount - decreased_reserved_amount;
        vault.unrealised_reserving_fee_amount = decimal::sub(
            vault.unrealised_reserving_fee_amount,
            reserving_fee_amount,
        );
        let _ = balance::join(&mut vault.liquidity, to_vault);

        // update symbol
        symbol.opening_size = decimal::sub(symbol.opening_size, decrease_size);
        symbol.opening_amount = symbol.opening_amount - decrease_amount;
        symbol.unrealised_funding_fee_value = sdecimal::sub(
            symbol.unrealised_funding_fee_value,
            funding_fee_value,
        );
        symbol.realised_pnl = sdecimal::add(
            symbol.realised_pnl,
            sdecimal::sub_with_decimal(
                sdecimal::from_decimal(
                    !has_profit,
                    agg_price::coins_to_value(collateral_price, settled_amount),
                ),
                // exclude: decrease fee - rebate + reserving fee
                decimal::add(
                    decimal::sub(decrease_fee_value, rebate_value),
                    reserving_fee_value,
                ),
            ),
        );

        let result = DecreasePositionResult {
            to_trader,
            rebate,
            event: DecreasePositionSuccessEvent {
                timestamp,
                collateral_price: agg_price::price_of(collateral_price),
                index_price: agg_price::price_of(index_price),
                decrease_amount,
                decrease_fee_value,
                reserving_fee_value,
                funding_fee_value,
                closed,
                has_profit,
                settled_amount,
            },
        };
        (code, option::some(result), option::none())
    }

    public(friend) fun unwrap_decrease_position_result<C>(res: DecreasePositionResult<C>): (
        Balance<C>,
        Balance<C>,
        DecreasePositionSuccessEvent,
    ) {
        let DecreasePositionResult {
            to_trader,
            rebate,
            event,
        } = res;

        (to_trader, rebate, event)
    }

    public(friend) fun decrease_reserved_from_position<C>(
        vault: &mut Vault<C>,
        position: &mut Position<C>,
        reserving_fee_model: &ReservingFeeModel,
        decrease_amount: u64,
        timestamp: u64,
    ): DecreaseReservedFromPositionEvent {
        assert!(
            object::id(reserving_fee_model) == vault.reserving_fee_model,
            ERR_MISMATCHED_RESERVING_FEE_MODEL,
        );

        // refresh vault
        let supply_amount = vault_supply_amount(vault);
        refresh_vault(vault, reserving_fee_model, supply_amount, timestamp);

        let decreased_reserved = position::decrease_reserved_from_position(
            position,
            decrease_amount,
            vault.acc_reserving_rate,
        );

        // update vault
        vault.reserved_amount = vault.reserved_amount - balance::value(&decreased_reserved);
        let _ = balance::join(&mut vault.liquidity, decreased_reserved);

        DecreaseReservedFromPositionEvent {
            timestamp,
            decrease_amount,
        }
    }

    public(friend) fun pledge_in_position<C>(
        position: &mut Position<C>,
        pledge: Balance<C>,
        timestamp: u64,
    ): PledgeInPositionEvent {
        let pledge_amount = balance::value(&pledge);
        position::pledge_in_position(position, pledge);

        // there is no need to refresh vault and symbol here

        PledgeInPositionEvent {
            timestamp,
            pledge_amount,
        }
    }

    public(friend) fun redeem_from_position<C>(
        vault: &mut Vault<C>,
        symbol: &mut Symbol,
        position: &mut Position<C>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        collateral_price: &AggPrice,
        index_price: &AggPrice,
        long: bool,
        redeem_amount: u64,
        lp_supply_amount: Decimal,
        timestamp: u64,
    ): (Balance<C>, RedeemFromPositionEvent) {
        assert!(
            object::id(reserving_fee_model) == vault.reserving_fee_model,
            ERR_MISMATCHED_RESERVING_FEE_MODEL,
        );
        assert!(
            object::id(funding_fee_model) == symbol.funding_fee_model,
            ERR_MISMATCHED_FUNDING_FEE_MODEL,
        );

        // refresh vault
        let supply_amount = vault_supply_amount(vault);
        refresh_vault(vault, reserving_fee_model, supply_amount, timestamp);
        // refresh symbol
        let delta_size = symbol_delta_size(symbol, index_price, long);
        refresh_symbol(
            symbol,
            funding_fee_model,
            delta_size,
            lp_supply_amount,
            timestamp,
        );

        // redeem
        let redeem = position::redeem_from_position(
            position,
            collateral_price,
            index_price,
            long,
            redeem_amount,
            vault.acc_reserving_rate,
            symbol.acc_funding_rate,
            timestamp,
        );

        let event = RedeemFromPositionEvent {
            timestamp,
            redeem_amount,
        };

        (redeem, event)
    }

    public(friend) fun liquidate_position<C>(
        vault: &mut Vault<C>,
        symbol: &mut Symbol,
        position: &mut Position<C>,
        reserving_fee_model: &ReservingFeeModel,
        funding_fee_model: &FundingFeeModel,
        collateral_price: &AggPrice,
        index_price: &AggPrice,
        long: bool,
        lp_supply_amount: Decimal,
        timestamp: u64,
        liquidator: address,
    ): (Balance<C>, LiquidatePositionEvent) {
        assert!(vault.enabled, ERR_VAULT_DISABLED);
        assert!(symbol.liquidate_enabled, ERR_LIQUIDATE_DISABLED);
        assert!(
            object::id(reserving_fee_model) == vault.reserving_fee_model,
            ERR_MISMATCHED_RESERVING_FEE_MODEL,
        );
        assert!(
            object::id(funding_fee_model) == symbol.funding_fee_model,
            ERR_MISMATCHED_FUNDING_FEE_MODEL,
        );

        // refresh vault
        let supply_amount = vault_supply_amount(vault);
        refresh_vault(vault, reserving_fee_model, supply_amount, timestamp);
        // refresh symbol
        let delta_size = symbol_delta_size(symbol, index_price, long);
        refresh_symbol(
            symbol,
            funding_fee_model,
            delta_size,
            lp_supply_amount,
            timestamp,
        );

        let (
            liquidator_bonus_amount,
            trader_loss_amount,
            position_amount,
            reserved_amount,
            position_size,
            reserving_fee_amount,
            reserving_fee_value,
            funding_fee_value,
            to_vault,
            to_liquidator,
        ) = position::liquidate_position(
            position,
            collateral_price,
            index_price,
            long,
            vault.acc_reserving_rate,
            symbol.acc_funding_rate,
        );

        // update vault
        vault.reserved_amount = vault.reserved_amount - reserved_amount;
        vault.unrealised_reserving_fee_amount = decimal::sub(
            vault.unrealised_reserving_fee_amount,
            reserving_fee_amount,
        );
        let _ = balance::join(&mut vault.liquidity, to_vault);

        // update symbol
        symbol.opening_size = decimal::sub(symbol.opening_size, position_size);
        symbol.opening_amount = symbol.opening_amount - position_amount;
        symbol.unrealised_funding_fee_value = sdecimal::sub(
            symbol.unrealised_funding_fee_value,
            funding_fee_value,
        );
        symbol.realised_pnl = sdecimal::add(
            symbol.realised_pnl,
            sdecimal::sub_with_decimal(
                sdecimal::from_decimal(
                    true,
                    agg_price::coins_to_value(
                        collateral_price,
                        trader_loss_amount,
                    ),
                ),
                // exclude reserving fee
                reserving_fee_value,
            )
        );

        let event = LiquidatePositionEvent {
            timestamp,
            liquidator,
            collateral_price: agg_price::price_of(collateral_price),
            index_price: agg_price::price_of(index_price),
            reserving_fee_value,
            funding_fee_value,
            loss_amount: trader_loss_amount,
            liquidator_bonus_amount,
        };

        (to_liquidator, event)
    }

    public(friend) fun valuate_vault<C>(
        vault: &mut Vault<C>,
        reserving_fee_model: &ReservingFeeModel,
        price: &AggPrice,
        timestamp: u64,
    ): Decimal {
        assert!(vault.enabled, ERR_VAULT_DISABLED);
        assert!(
            object::id(reserving_fee_model) == vault.reserving_fee_model,
            ERR_MISMATCHED_RESERVING_FEE_MODEL,
        );

        let supply_amount = vault_supply_amount(vault);
        refresh_vault(vault, reserving_fee_model, supply_amount, timestamp);
        supply_amount = decimal::add(
            supply_amount,
            vault.unrealised_reserving_fee_amount,
        );
        agg_price::coins_to_value(price, decimal::floor_u64(supply_amount))
    }

    public(friend) fun valuate_symbol(
        symbol: &mut Symbol,
        funding_fee_model: &FundingFeeModel,
        price: &AggPrice,
        long: bool,
        lp_supply_amount: Decimal,
        timestamp: u64,
    ): SDecimal {
        assert!(
            object::id(funding_fee_model) == symbol.funding_fee_model,
            ERR_MISMATCHED_FUNDING_FEE_MODEL,
        );

        let delta_size = symbol_delta_size(symbol, price, long);
        refresh_symbol(
            symbol,
            funding_fee_model,
            delta_size,
            lp_supply_amount,
            timestamp,
        );
        sdecimal::add(delta_size, symbol.unrealised_funding_fee_value)
    }

    //////////////////////////// public read functions ////////////////////////////

    public fun vault_enabled<C>(vault: &Vault<C>): bool {
        vault.enabled
    }

    public fun vault_weight<C>(vault: &Vault<C>): Decimal {
        vault.weight
    }

    public fun vault_reserving_fee_model<C>(vault: &Vault<C>): &ID {
        &vault.reserving_fee_model
    }

    public fun vault_price_config<C>(vault: &Vault<C>): &AggPriceConfig {
        &vault.price_config
    }

    public fun vault_liquidity_amount<C>(vault: &Vault<C>): u64 {
        balance::value(&vault.liquidity)
    }

    public fun vault_reserved_amount<C>(vault: &Vault<C>): u64 {
        vault.reserved_amount
    }

    public fun vault_utilization<C>(
        vault: &Vault<C>,
        supply_amount: Decimal,
    ): Rate {
        if (decimal::is_zero(&supply_amount)) {
            rate::zero()
        } else {
            decimal::to_rate(
                decimal::div(
                    decimal::from_u64(vault.reserved_amount),
                    supply_amount,
                )
            )
        }
    }

    public fun vault_supply_amount<C>(vault: &Vault<C>): Decimal {
        // liquidity_amount + reserved_amount + unrealised_reserving_fee_amount
        decimal::add(
            decimal::from_u64(
                balance::value(&vault.liquidity) + vault.reserved_amount
            ),
            vault.unrealised_reserving_fee_amount,
        )
    }

    public fun vault_delta_reserving_rate<C>(
        vault: &Vault<C>,
        reserving_fee_model: &ReservingFeeModel,
        supply_amount: Decimal,
        timestamp: u64,
    ): Rate {
        if (vault.last_update > 0) {
            let elapsed = timestamp - vault.last_update;
            if (elapsed > 0) {
                return model::compute_reserving_fee_rate(
                    reserving_fee_model,
                    vault_utilization(vault, supply_amount),
                    elapsed,
                )
            }
        };
        rate::zero()
    }

    public fun vault_acc_reserving_rate<C>(
        vault: &Vault<C>,
        delta_rate: Rate,
    ): Rate {
        rate::add(vault.acc_reserving_rate, delta_rate)
    }

    public fun vault_unrealised_reserving_fee_amount<C>(
        vault: &Vault<C>,
        delta_rate: Rate,
    ): Decimal {
        decimal::add(
            vault.unrealised_reserving_fee_amount,
            decimal::mul_with_rate(
                decimal::from_u64(vault.reserved_amount),
                delta_rate,
            ),
        )
    }

    public fun symbol_open_enabled(symbol: &Symbol): bool {
        symbol.open_enabled
    }

    public fun symbol_decrease_enabled(symbol: &Symbol): bool {
        symbol.decrease_enabled
    }

    public fun symbol_liquidate_enabled(symbol: &Symbol): bool {
        symbol.liquidate_enabled
    }

    public fun symbol_supported_collaterals(symbol: &Symbol): &VecSet<TypeName> {
        &symbol.supported_collaterals
    }

    public fun symbol_funding_fee_model(symbol: &Symbol): &ID {
        &symbol.funding_fee_model
    }

    public fun symbol_price_config(symbol: &Symbol): &AggPriceConfig {
        &symbol.price_config
    }

    public fun symbol_opening_amount(symbol: &Symbol): u64 {
        symbol.opening_amount
    }

    public fun symbol_opening_size(symbol: &Symbol): Decimal {
        symbol.opening_size
    }

    public fun symbol_pnl_per_lp(
        symbol: &Symbol,
        delta_size: SDecimal,
        lp_supply_amount: Decimal,
    ): SDecimal {
        let pnl = sdecimal::add(
            sdecimal::add(
                symbol.realised_pnl,
                symbol.unrealised_funding_fee_value,
            ),
            delta_size,
        );
        sdecimal::div_by_decimal(pnl, lp_supply_amount)
    }

    public fun symbol_delta_funding_rate(
        symbol: &Symbol,
        funding_fee_model: &FundingFeeModel,
        delta_size: SDecimal,
        lp_supply_amount: Decimal,
        timestamp: u64,
    ): SRate {
        if (symbol.last_update > 0) {
            let elapsed = timestamp - symbol.last_update;
            if (elapsed > 0) {
                return model::compute_funding_fee_rate(
                    funding_fee_model,
                    symbol_pnl_per_lp(symbol, delta_size, lp_supply_amount),
                    elapsed,
                )
            }
        };
        srate::zero()
    }

    public fun symbol_acc_funding_rate(
        symbol: &Symbol,
        delta_rate: SRate,
    ): SRate {
        srate::add(symbol.acc_funding_rate, delta_rate)
    }

    public fun symbol_unrealised_funding_fee_value(
        symbol: &Symbol,
        delta_rate: SRate,    
    ): SDecimal {
        sdecimal::add(
            symbol.unrealised_funding_fee_value,
            sdecimal::from_decimal(
                srate::is_positive(&delta_rate),
                decimal::mul_with_rate(
                    symbol.opening_size,
                    srate::value(&delta_rate),
                ),
            ),
        )
    }

    public fun symbol_delta_size(
        symbol: &Symbol,
        price: &AggPrice,
        long: bool,
    ): SDecimal {
        let latest_size = agg_price::coins_to_value(
            price,
            symbol.opening_amount,
        );
        let cmp = decimal::gt(&latest_size, &symbol.opening_size);
        let (is_positive, value) = if (cmp) {
            (!long, decimal::sub(latest_size, symbol.opening_size))
        } else {
            (long, decimal::sub(symbol.opening_size, latest_size))
        };

        sdecimal::from_decimal(is_positive, value)
    }

    public fun compute_rebase_fee_rate(
        model: &RebaseFeeModel,
        increase: bool,
        vault_value: Decimal,
        total_vaults_value: Decimal,
        vault_weight: Decimal,
        total_vaults_weight: Decimal,
    ): Rate {
        let ratio = if (decimal::is_zero(&total_vaults_value)) {
            rate::zero()
        } else {
            decimal::to_rate(
                decimal::div(vault_value, total_vaults_value)
            )
        };
        let target_ratio = decimal::to_rate(
            decimal::div(vault_weight, total_vaults_weight)
        );

        model::compute_rebase_fee_rate(model, increase, ratio, target_ratio)
    }
}
