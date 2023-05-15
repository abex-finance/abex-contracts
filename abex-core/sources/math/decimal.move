/// Defines a fixed-point decimal type with 18 digits of decimal precision.

module abex_core::decimal {
    use abex_core::rate::{Self, Rate};

    struct Decimal has copy, drop, store {
        value: u256,
    }

    // Identity
    const WAD: u256 = 1_000_000_000_000_000_000;
    // Half of identity
    const HALF_WAD: u256 = 500_000_000_000_000_000;

    public fun one(): Decimal {
        Decimal { value: WAD }
    }

    public fun zero(): Decimal {
        Decimal { value: 0 }
    }

    public fun from_raw(value: u256): Decimal {
        Decimal { value }
    }

    public fun from_u64(value: u64): Decimal {
        Decimal {
            value: (value as u256) * WAD,
        }
    }

    public fun from_u128(value: u128): Decimal {
        Decimal {
            value: (value as u256) * WAD,
        }
    }

    public fun from_rate(r: Rate): Decimal {
        Decimal {
            value: (rate::to_raw(r) as u256),
        }
    }

    public fun to_rate(dec: Decimal): Rate {
        rate::from_raw((dec.value as u128))
    }

    public fun to_raw(dec: Decimal): u256 {
        dec.value
    }

    public fun ceil_u64(dec: Decimal): u64 {
        (((WAD - 1 + dec.value) / WAD) as u64)
    }

    public fun floor_u64(dec: Decimal): u64 {
        ((dec.value / WAD) as u64)
    }

    public fun round_u64(dec: Decimal): u64 {
        (((dec.value + HALF_WAD) / WAD) as u64)
    }

    // public fun digits(dec: Decimal): u64 {
    //     let value = round_u64(dec);
    //     let digits = 0;
    //     while (value >= 10) {
    //         value = value / 10;
    //         digits = digits + 1;
    //     };
    //     digits
    // }

    public fun is_zero(dec: &Decimal): bool {
        dec.value == 0
    }

    public fun equals(self: &Decimal, other: &Decimal): bool {
        self.value == other.value
    }

    public fun lt(self: &Decimal, other: &Decimal): bool {
        self.value < other.value
    }

    public fun le(self: &Decimal, other: &Decimal): bool {
        self.value <= other.value
    }

    public fun gt(self: &Decimal, other: &Decimal): bool {
        self.value > other.value
    }

    public fun ge(self: &Decimal, other: &Decimal): bool {
        self.value >= other.value
    }

    public fun diff(a: Decimal, b: Decimal): Decimal {
        let value = if (a.value > b.value) {
            a.value - b.value
        } else {
            b.value - a.value
        };
        Decimal { value }
    }

    public fun add(a: Decimal, b: Decimal): Decimal {
        Decimal {
            value: a.value + b.value
        }
    }

    public fun sub(a: Decimal, b: Decimal): Decimal {
        Decimal {
            value: a.value - b.value
        }
    }

    public fun mul(a: Decimal, b: Decimal): Decimal {
        Decimal {
            value: a.value * b.value / WAD,
        }
    }

    public fun mul_with_u64(a: Decimal, b: u64): Decimal {
        Decimal {
            value: a.value * (b as u256),
        }
    }

    public fun mul_with_rate(a: Decimal, b: Rate): Decimal {
        mul(a, from_rate(b))
    }

    public fun div(a: Decimal, b: Decimal): Decimal {
        Decimal {
            value: a.value * WAD / b.value,
        }
    }

    public fun div_by_u64(a: Decimal, b: u64): Decimal {
        Decimal {
            value: a.value / (b as u256),
        }
    }

    public fun div_by_rate(a: Decimal, b: Rate): Decimal {
        div(a, from_rate(b))
    }
}
