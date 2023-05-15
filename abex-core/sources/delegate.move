
// module abex_core::delegate {
//     use sui::transfer;
//     use sui::coin::{Self, Coin};
//     use sui::object::{Self, ID, UID};
//     use sui::balance::{Self, Balance};
//     use sui::tx_context::{Self, TxContext};

//     use abex_core::decimal::{Self, Decimal};
//     use abex_core::direction::parse_direction;
//     use abex_core::agg_price::{Self, AggPrice};
//     use abex_core::position::{Position, PositionConfig};
//     use abex_core::pool::{
//         Self, Vault, Symbol,
//         OpenPositionEvent, PledgeInPositionEvent,
//         RedeemFromPositionEvent, DecreasePositionEvent,
//         ClosePositionEvent, LiquidatePositionEvent,
//     };

//     friend abex_core::market;

//     // ================================ Objects =================================

//     struct OpenPosition<phantom C, phantom I, phantom D> has key {
//         id: UID,

//         owner: address,
//         deadline: u64,
//         open_amount: u64,
//         reserved_amount: u64,
//         pledge: Balance<C>,
//         index_lower_price: Decimal,
//         index_upper_price: Decimal,
//         collateral_lower_price: Decimal,
//         collateral_upper_price: Decimal,
//         fee: Balance<C>,
//     }

//     struct PledgeInPosition<phantom C, phantom I, phantom D> has key {
//         id: UID,

//         position_id: ID,
//         owner: address,
//         deadline: u64,
//         pledge: Balance<C>,
//         index_lower_price: Decimal,
//         index_upper_price: Decimal,
//         collateral_lower_price: Decimal,
//         collateral_upper_price: Decimal,
//         fee: Balance<C>,
//     }

//     struct RedeemFromPosition<phantom C, phantom I, phantom D> has key {
//         id: UID,

//         position_id: ID,
//         owner: address,
//         deadline: u64,
//         redeem_amount: u64,
//         index_lower_price: Decimal,
//         index_upper_price: Decimal,
//         collateral_lower_price: Decimal,
//         collateral_upper_price: Decimal,
//         fee: Balance<C>,
//     }

//     struct DecreasePosition<phantom C, phantom I, phantom D> has key {
//         id: UID,

//         position_id: ID,
//         owner: address,
//         deadline: u64,
//         decrease_amount: u64,
//         index_lower_price: Decimal,
//         index_upper_price: Decimal,
//         collateral_lower_price: Decimal,
//         collateral_upper_price: Decimal,
//         fee: Balance<C>,
//     }

//     struct ClosePosition<phantom C, phantom I, phantom D> has key {
//         id: UID,

//         position_id: ID,
//         owner: address,
//         deadline: u64,
//         index_lower_price: Decimal,
//         index_upper_price: Decimal,
//         collateral_lower_price: Decimal,
//         collateral_upper_price: Decimal,
//         fee: Balance<C>,
//     }

//     struct DelegateCap has key {
//         id: UID,

//         delegate_id: ID,
//     }

//     // ================================ Errors =================================

//     const ERR_INVALID_INDEX_PRICE_THRESHOLD: u64 = 0;
//     const ERR_INVALID_COLLATERAL_PRICE_THRESHOLD: u64 = 1;
//     const ERR_INDEX_PRICE_TOO_HIGH: u64 = 2;
//     const ERR_INDEX_PRICE_TOO_LOW: u64 = 3;
//     const ERR_COLLATERAL_PRICE_TOO_HIGH: u64 = 4;
//     const ERR_COLLATERAL_PRICE_TOO_LOW: u64 = 5;
//     const ERR_DELEGATION_EXPIRED: u64 = 6;
//     const ERR_ZERO_INCREASE: u64 = 7;
//     const ERR_ZERO_DECREASE: u64 = 7;
//     const ERR_ZERO_PLEDGE: u64 = 9;
//     const ERR_ZERO_REDEEM: u64 = 10;
//     const ERR_MISMATCHED_OWNER: u64 = 12;

//     fun validate_price_thresholds(
//         index_lower_price: u128,
//         index_upper_price: u128,
//         collateral_lower_price: u128,
//         collateral_upper_price: u128,
//     ) {
//         assert!(index_lower_price < index_upper_price, ERR_INVALID_INDEX_PRICE_THRESHOLD);
//         assert!(
//             collateral_lower_price < collateral_upper_price,
//             ERR_INVALID_COLLATERAL_PRICE_THRESHOLD,
//         );
//     }

//     fun validate_price(
//         index_lower_price: &Decimal,
//         index_upper_price: &Decimal,
//         collateral_lower_price: &Decimal,
//         collateral_upper_price: &Decimal,
//         index_price: &AggPrice,
//         collateral_price: &AggPrice,
//     ) {
//         assert!(
//             decimal::ge(&agg_price::price_of(index_price), index_lower_price),
//             ERR_INDEX_PRICE_TOO_LOW,
//         );
//         assert!(
//             decimal::le(&agg_price::price_of(index_price), index_upper_price),
//             ERR_INDEX_PRICE_TOO_HIGH,
//         );
//         assert!(
//             decimal::ge(&agg_price::price_of(collateral_price), collateral_lower_price),
//             ERR_COLLATERAL_PRICE_TOO_LOW,
//         );
//         assert!(
//             decimal::le(&agg_price::price_of(collateral_price), collateral_upper_price),
//             ERR_COLLATERAL_PRICE_TOO_HIGH,
//         );
//     }

//     /////////////////////////// Create or Cancel Delegate Orders ////////////////////////////

//     public entry fun create_open_position<C, I, D>(
//         pledge: Coin<C>,
//         fee: Coin<C>,
//         deadline: u64,
//         open_amount: u64,
//         index_lower_price: u128,
//         index_upper_price: u128,
//         collateral_lower_price: u128,
//         collateral_upper_price: u128,
//         ctx: &mut TxContext,
//     ) {
//         assert!(open_amount > 0, ERR_ZERO_INCREASE);
//         assert!(coin::value(&pledge) > 0, ERR_ZERO_PLEDGE);
//         validate_price_thresholds(
//             index_lower_price,
//             index_upper_price,
//             collateral_lower_price,
//             collateral_upper_price,
//         );

//         let owner = tx_context::sender(ctx);

//         let delegate = OpenPosition<C, I, D> {
//             id: object::new(ctx),
//             owner,
//             deadline,
//             entry_amount,
//             index_lower_price: decimal::from_raw(index_lower_price),
//             index_upper_price: decimal::from_raw(index_upper_price),
//             collateral_lower_price: decimal::from_raw(collateral_lower_price),
//             collateral_upper_price: decimal::from_raw(collateral_upper_price),
//             pledge: coin::into_balance(pledge),
//             fee: coin::into_balance(fee),
//         };

//         transfer::transfer(
//             DelegateCap {
//                 id: object::new(ctx),
//                 delegate_id: object::uid_to_inner(&delegate.id),
//             },
//             owner,
//         );

//         transfer::share_object(delegate);
//     }

//     public entry fun cancel_open_position<C, I, D>(
//         delegate: OpenPosition<C, I, D>,
//         ctx: &mut TxContext,
//     ) {
//         let OpenPosition {
//             id,
//             owner,
//             deadline: _,
//             entry_amount: _,
//             index_lower_price: _,
//             index_upper_price: _,
//             collateral_lower_price: _,
//             collateral_upper_price: _,
//             pledge,
//             fee,
//         } = delegate;

//         assert!(tx_context::sender(ctx) == owner, ERR_MISMATCHED_OWNER);

//         object::delete(id);

//         let _ = balance::join(&mut pledge, fee);
//         transfer::public_transfer(coin::from_balance(pledge, ctx), owner);
//     }

//     public entry fun create_increase_position<C, I, D>(
//         fee: Coin<C>,
//         position_id: address,
//         deadline: u64,
//         increase_amount: u64,
//         index_lower_price: u128,
//         index_upper_price: u128,
//         collateral_lower_price: u128,
//         collateral_upper_price: u128,
//         ctx: &mut TxContext,
//     ) {
//         assert!(increase_amount > 0, ERR_ZERO_INCREASE);
//         validate_price_thresholds(
//             index_lower_price,
//             index_upper_price,
//             collateral_lower_price,
//             collateral_upper_price,
//         );

//         let owner = tx_context::sender(ctx);

//         let delegate = IncreasePosition<C, I, D> {
//             id: object::new(ctx),
//             position_id: object::id_from_address(position_id),
//             owner,
//             deadline,
//             increase_amount,
//             index_lower_price: decimal::from_raw(index_lower_price),
//             index_upper_price: decimal::from_raw(index_upper_price),
//             collateral_lower_price: decimal::from_raw(collateral_lower_price),
//             collateral_upper_price: decimal::from_raw(collateral_upper_price),
//             fee: coin::into_balance(fee),
//         };

//         transfer::transfer(
//             DelegateCap {
//                 id: object::new(ctx),
//                 delegate_id: object::uid_to_inner(&delegate.id),
//             },
//             owner,
//         );

//         transfer::share_object(delegate);
//     }

//     public entry fun cancel_increase_position<C, I, D>(
//         delegate: IncreasePosition<C, I, D>,
//         ctx: &mut TxContext,
//     ) {
//         let IncreasePosition {
//             id,
//             position_id: _,
//             owner,
//             deadline: _,
//             increase_amount: _,
//             index_lower_price: _,
//             index_upper_price: _,
//             collateral_lower_price: _,
//             collateral_upper_price: _,
//             fee,
//         } = delegate;

//         assert!(tx_context::sender(ctx) == owner, ERR_MISMATCHED_OWNER);

//         object::delete(id);

//         transfer::public_transfer(coin::from_balance(fee, ctx), owner);
//     }

//     public entry fun create_decrease_position<C, I, D>(
//         fee: Coin<C>,
//         position_id: address,
//         deadline: u64,
//         decrease_amount: u64,
//         index_lower_price: u128,
//         index_upper_price: u128,
//         collateral_lower_price: u128,
//         collateral_upper_price: u128,
//         ctx: &mut TxContext,
//     ) {
//         assert!(decrease_amount > 0, ERR_ZERO_DECREASE);
//         validate_price_thresholds(
//             index_lower_price,
//             index_upper_price,
//             collateral_lower_price,
//             collateral_upper_price,
//         );

//         let owner = tx_context::sender(ctx);

//         let delegate = DecreasePosition<C, I, D> {
//             id: object::new(ctx),
//             position_id: object::id_from_address(position_id),
//             owner,
//             deadline,
//             decrease_amount,
//             index_lower_price: decimal::from_raw(index_lower_price),
//             index_upper_price: decimal::from_raw(index_upper_price),
//             collateral_lower_price: decimal::from_raw(collateral_lower_price),
//             collateral_upper_price: decimal::from_raw(collateral_upper_price),
//             fee: coin::into_balance(fee),
//         };

//         transfer::transfer(
//             DelegateCap {
//                 id: object::new(ctx),
//                 delegate_id: object::uid_to_inner(&delegate.id),
//             },
//             owner,
//         );

//         transfer::share_object(delegate);
//     }

//     public entry fun cancel_decrease_position<C, I, D>(
//         delegate: DecreasePosition<C, I, D>,
//         ctx: &mut TxContext,
//     ) {
//         let DecreasePosition {
//             id,
//             position_id: _,
//             owner,
//             deadline: _,
//             decrease_amount: _,
//             index_lower_price: _,
//             index_upper_price: _,
//             collateral_lower_price: _,
//             collateral_upper_price: _,
//             fee,
//         } = delegate;

//         assert!(tx_context::sender(ctx) == owner, ERR_MISMATCHED_OWNER);

//         object::delete(id);

//         transfer::public_transfer(coin::from_balance(fee, ctx), owner);
//     }

//     public entry fun create_pledge_in_position<C, I, D>(
//         pledge: Coin<C>,
//         fee: Coin<C>,
//         position_id: address,
//         deadline: u64,
//         index_lower_price: u128,
//         index_upper_price: u128,
//         collateral_lower_price: u128,
//         collateral_upper_price: u128,
//         ctx: &mut TxContext,
//     ) {
//         assert!(coin::value(&pledge) > 0, ERR_ZERO_PLEDGE);
//         validate_price_thresholds(
//             index_lower_price,
//             index_upper_price,
//             collateral_lower_price,
//             collateral_upper_price,
//         );

//         let owner = tx_context::sender(ctx);

//         let delegate = PledgeInPosition<C, I, D> {
//             id: object::new(ctx),
//             position_id: object::id_from_address(position_id),
//             owner,
//             deadline,
//             index_lower_price: decimal::from_raw(index_lower_price),
//             index_upper_price: decimal::from_raw(index_upper_price),
//             collateral_lower_price: decimal::from_raw(collateral_lower_price),
//             collateral_upper_price: decimal::from_raw(collateral_upper_price),
//             pledge: coin::into_balance(pledge),
//             fee: coin::into_balance(fee),
//         };

//         transfer::transfer(
//             DelegateCap {
//                 id: object::new(ctx),
//                 delegate_id: object::uid_to_inner(&delegate.id),
//             },
//             owner,
//         );

//         transfer::share_object(delegate);
//     }

//     public entry fun cancel_pledge_in_position<C, I, D>(
//         delegate: PledgeInPosition<C, I, D>,
//         ctx: &mut TxContext,
//     ) {
//         let PledgeInPosition {
//             id,
//             position_id: _,
//             owner,
//             deadline: _,
//             index_lower_price: _,
//             index_upper_price: _,
//             collateral_lower_price: _,
//             collateral_upper_price: _,
//             pledge,
//             fee,
//         } = delegate;

//         assert!(tx_context::sender(ctx) == owner, ERR_MISMATCHED_OWNER);

//         object::delete(id);

//         let _ = balance::join(&mut pledge, fee);
//         transfer::public_transfer(coin::from_balance(pledge, ctx), owner);
//     }

//     public entry fun create_redeem_from_position<C, I, D>(
//         fee: Coin<C>,
//         position_id: address,
//         deadline: u64,
//         index_lower_price: u128,
//         index_upper_price: u128,
//         collateral_lower_price: u128,
//         collateral_upper_price: u128,
//         redeem_amount: u64,
//         ctx: &mut TxContext,
//     ) {
//         assert!(redeem_amount > 0, ERR_ZERO_REDEEM);
//         validate_price_thresholds(
//             index_lower_price,
//             index_upper_price,
//             collateral_lower_price,
//             collateral_upper_price,
//         );

//         let owner = tx_context::sender(ctx);

//         let delegate = RedeemFromPosition<C, I, D> {
//             id: object::new(ctx),
//             position_id: object::id_from_address(position_id),
//             owner,
//             deadline,
//             index_lower_price: decimal::from_raw(index_lower_price),
//             index_upper_price: decimal::from_raw(index_upper_price),
//             collateral_lower_price: decimal::from_raw(collateral_lower_price),
//             collateral_upper_price: decimal::from_raw(collateral_upper_price),
//             redeem_amount,
//             fee: coin::into_balance(fee),
//         };

//         transfer::transfer(
//             DelegateCap {
//                 id: object::new(ctx),
//                 delegate_id: object::uid_to_inner(&delegate.id),
//             },
//             owner,
//         );

//         transfer::share_object(delegate);
//     }

//     public entry fun cancel_redeem_from_position<C, I, D>(
//         delegate: RedeemFromPosition<C, I, D>,
//         ctx: &mut TxContext,
//     ) {
//         let RedeemFromPosition {
//             id,
//             position_id: _,
//             owner,
//             deadline: _,
//             index_lower_price: _,
//             index_upper_price: _,
//             collateral_lower_price: _,
//             collateral_upper_price: _,
//             redeem_amount: _,
//             fee,
//         } = delegate;

//         assert!(tx_context::sender(ctx) == owner, ERR_MISMATCHED_OWNER);

//         object::delete(id);

//         transfer::public_transfer(coin::from_balance(fee, ctx), owner);
//     }

//     public entry fun create_close_position<C, I, D>(
//         fee: Coin<C>,
//         position_id: address,
//         deadline: u64,
//         index_lower_price: u128,
//         index_upper_price: u128,
//         collateral_lower_price: u128,
//         collateral_upper_price: u128,
//         ctx: &mut TxContext,
//     ) {
//         validate_price_thresholds(
//             index_lower_price,
//             index_upper_price,
//             collateral_lower_price,
//             collateral_upper_price,
//         );

//         let owner = tx_context::sender(ctx);

//         let delegate = ClosePosition<C, I, D> {
//             id: object::new(ctx),
//             position_id: object::id_from_address(position_id),
//             owner,
//             deadline,
//             index_lower_price: decimal::from_raw(index_lower_price),
//             index_upper_price: decimal::from_raw(index_upper_price),
//             collateral_lower_price: decimal::from_raw(collateral_lower_price),
//             collateral_upper_price: decimal::from_raw(collateral_upper_price),
//             fee: coin::into_balance(fee),
//         };

//         transfer::transfer(
//             DelegateCap {
//                 id: object::new(ctx),
//                 delegate_id: object::uid_to_inner(&delegate.id),
//             },
//             owner,
//         );

//         transfer::share_object(delegate);
//     }

//     public entry fun cancel_close_position<C, I, D>(
//         delegate: ClosePosition<C, I, D>,
//         ctx: &mut TxContext,
//     ) {
//         let ClosePosition {
//             id,
//             position_id: _,
//             owner,
//             deadline: _,
//             index_lower_price: _,
//             index_upper_price: _,
//             collateral_lower_price: _,
//             collateral_upper_price: _,
//             fee,
//         } = delegate;

//         assert!(tx_context::sender(ctx) == owner, ERR_MISMATCHED_OWNER);

//         object::delete(id);

//         transfer::public_transfer(coin::from_balance(fee, ctx), owner);
//     }

//     /////////////////////////// Excution Methods ///////////////////////////////

//     public(friend) fun execute_open_position<C, I, D>(
//         vault: &mut Vault<C>,
//         symbol: &mut Symbol,
//         delegate: OpenPosition<C, I, D>,
//         collateral_price: &AggPrice,
//         index_price: &AggPrice,
//         timestamp: u64,
//     ): (Position<C>, Balance<C>, PositionOpened) {
//         let OpenPosition {
//             id,
//             owner: _,
//             deadline,
//             index_lower_price,
//             index_upper_price,
//             collateral_lower_price,
//             collateral_upper_price,
//             entry_amount,
//             pledge,
//             fee,
//         } = delegate;

//         // check delegate
//         assert!(timestamp < deadline, ERR_DELEGATION_EXPIRED);
//         validate_price(
//             &index_lower_price,
//             &index_upper_price,
//             &collateral_lower_price,
//             &collateral_upper_price,
//             index_price,
//             collateral_price,
//         );

//         // delete open position order
//         object::delete(id);

//         let (pst, event) = pool::open_position(
//             vault,
//             symbol,
//             collateral_price,
//             index_price,
//             pledge,
//             entry_amount,
//             timestamp,
//         );

//         (pst, fee, event)
//     }

//     public(friend) fun execute_increase_position<C, I, D>(
//         vault: &mut Vault<C>,
//         symbol: &mut Symbol,
//         pst: &mut Position<C>,
//         delegate: IncreasePosition<C, I, D>,
//         collateral_price: &AggPrice,
//         index_price: &AggPrice,
//         timestamp: u64,
//     ): (Balance<C>, PositionIncreased) {
//         let IncreasePosition {
//             id,
//             position_id: _,
//             owner: _,
//             deadline,
//             increase_amount,
//             index_lower_price,
//             index_upper_price,
//             collateral_lower_price,
//             collateral_upper_price,
//             fee,
//         } = delegate;

//         // check delegate
//         assert!(timestamp < deadline, ERR_DELEGATION_EXPIRED);
//         validate_price(
//             &index_lower_price,
//             &index_upper_price,
//             &collateral_lower_price,
//             &collateral_upper_price,
//             index_price,
//             collateral_price,
//         );

//         // delete increase position order
//         object::delete(id);

//         let event = pool::increase_position(
//             vault,
//             symbol,
//             pst,
//             collateral_price,
//             index_price,
//             parse_direction<D>(),
//             increase_amount,
//             timestamp,
//         );

//         (fee, event)
//     }

//     public(friend) fun execute_decrease_position<C, I, D>(
//         vault: &mut Vault<C>,
//         symbol: &mut Symbol,
//         pst: &mut Position<C>,
//         delegate: DecreasePosition<C, I, D>,
//         collateral_price: &AggPrice,
//         index_price: &AggPrice,
//         timestamp: u64,
//     ): (Balance<C>, Balance<C>, PositionDecreased) {
//         let DecreasePosition {
//             id,
//             position_id: _,
//             owner: _,
//             deadline,
//             decrease_amount,
//             index_lower_price,
//             index_upper_price,
//             collateral_lower_price,
//             collateral_upper_price,
//             fee,
//         } = delegate;

//         // check delegate
//         assert!(timestamp < deadline, ERR_DELEGATION_EXPIRED);
//         validate_price(
//             &index_lower_price,
//             &index_upper_price,
//             &collateral_lower_price,
//             &collateral_upper_price,
//             index_price,
//             collateral_price,
//         );

//         // delete decrease position order
//         object::delete(id);

//         let (profit, event) = pool::decrease_position(
//             vault,
//             symbol,
//             pst,
//             collateral_price,
//             index_price,
//             parse_direction<D>(),
//             decrease_amount,
//             timestamp,
//         );

//         (profit, fee, event)
//     }

//     public(friend) fun execute_pledge_in_position<C, I, D>(
//         vault: &mut Vault<C>,
//         pst: &mut Position<C>,
//         delegate: PledgeInPosition<C, I, D>,
//         collateral_price: &AggPrice,
//         index_price: &AggPrice,
//         timestamp: u64,
//     ): (Balance<C>, PledgedInPosition) {
//         let PledgeInPosition {
//             id,
//             position_id: _,
//             owner: _,
//             deadline,
//             index_lower_price,
//             index_upper_price,
//             collateral_lower_price,
//             collateral_upper_price,
//             pledge,
//             fee,
//         } = delegate;

//         // check delegate
//         assert!(timestamp < deadline, ERR_DELEGATION_EXPIRED);
//         validate_price(
//             &index_lower_price,
//             &index_upper_price,
//             &collateral_lower_price,
//             &collateral_upper_price,
//             index_price,
//             collateral_price,
//         );

//         // delete pledge in position order
//         object::delete(id);

//         let event = pool::pledge_in_position(
//             vault,
//             pst,
//             collateral_price,
//             pledge,
//             timestamp,
//         );

//         (fee, event)
//     }

//     public(friend) fun execute_redeem_from_position<C, I, D>(
//         vault: &mut Vault<C>,
//         pst: &mut Position<C>,
//         delegate: RedeemFromPosition<C, I, D>,
//         position_config: &PositionConfig,
//         collateral_price: &AggPrice,
//         index_price: &AggPrice,
//         timestamp: u64,
//     ): (Balance<C>, Balance<C>, RedeemedFromPosition) {
//         let RedeemFromPosition {
//             id,
//             position_id: _,
//             owner: _,
//             deadline,
//             index_lower_price,
//             index_upper_price,
//             collateral_lower_price,
//             collateral_upper_price,
//             redeem_amount,
//             fee,
//         } = delegate;

//         // check delegate
//         assert!(timestamp < deadline, ERR_DELEGATION_EXPIRED);
//         validate_price(
//             &index_lower_price,
//             &index_upper_price,
//             &collateral_lower_price,
//             &collateral_upper_price,
//             index_price,
//             collateral_price,
//         );

//         // delete redeem from position order
//         object::delete(id);

//         let (redeem, event) = pool::redeem_from_position(
//             vault,
//             pst,
//             position_config,
//             collateral_price,
//             index_price,
//             parse_direction<D>(),
//             redeem_amount,
//             timestamp,
//         );

//         (redeem, fee, event)
//     }

//     public(friend) fun execute_close_position<C, I, D>(
//         vault: &mut Vault<C>,
//         symbol: &mut Symbol,
//         pst: Position<C>,
//         delegate: ClosePosition<C, I, D>,
//         collateral_price: &AggPrice,
//         index_price: &AggPrice,
//         timestamp: u64,
//     ): (Balance<C>, Balance<C>, PositionRemoved) {
//         let ClosePosition {
//             id,
//             position_id: _,
//             owner: _,
//             deadline,
//             index_lower_price,
//             index_upper_price,
//             collateral_lower_price,
//             collateral_upper_price,
//             fee,
//         } = delegate;

//         // check delegate
//         assert!(timestamp < deadline, ERR_DELEGATION_EXPIRED);
//         validate_price(
//             &index_lower_price,
//             &index_upper_price,
//             &collateral_lower_price,
//             &collateral_upper_price,
//             index_price,
//             collateral_price,
//         );

//         // delete close position order
//         object::delete(id);

//         let (profit, event) = pool::close_position(
//             vault,
//             symbol,
//             pst,
//             collateral_price,
//             index_price,
//             parse_direction<D>(),
//             false,
//             timestamp,
//         );

//         (profit, fee, event)
//     }

//     //////////////////////////// Public Methods /////////////////////////////////
    
//     public fun owner_of_open_position<C, I, D>(
//         delegate: &OpenPosition<C, I, D>,
//     ): address {
//         delegate.owner
//     }

//     public fun owner_of_increase_position<C, I, D>(
//         delegate: &IncreasePosition<C, I, D>,
//     ): address {
//         delegate.owner
//     }

//     public fun position_id_of_increase_position<C, I, D>(
//         delegate: &IncreasePosition<C, I, D>,
//     ): ID {
//         delegate.position_id
//     }

//     public fun owner_of_decrease_position<C, I, D>(
//         delegate: &DecreasePosition<C, I, D>,
//     ): address {
//         delegate.owner
//     }

//     public fun position_id_of_decrease_position<C, I, D>(
//         delegate: &DecreasePosition<C, I, D>,
//     ): ID {
//         delegate.position_id
//     }

//     public fun owner_of_pledge_in_position<C, I, D>(
//         delegate: &PledgeInPosition<C, I, D>,
//     ): address {
//         delegate.owner
//     }

//     public fun position_id_of_pledge_in_position<C, I, D>(
//         delegate: &PledgeInPosition<C, I, D>,
//     ): ID {
//         delegate.position_id
//     }

//     public fun owner_of_redeem_from_position<C, I, D>(
//         delegate: &RedeemFromPosition<C, I, D>,
//     ): address {
//         delegate.owner
//     }

//     public fun position_id_of_redeem_from_position<C, I, D>(
//         delegate: &RedeemFromPosition<C, I, D>,
//     ): ID {
//         delegate.position_id
//     }

//     public fun owner_of_close_position<C, I, D>(
//         delegate: &ClosePosition<C, I, D>,
//     ): address {
//         delegate.owner
//     }
    
//     public fun position_id_of_close_position<C, I, D>(
//         delegate: &ClosePosition<C, I, D>,
//     ): ID {
//         delegate.position_id
//     }
// }