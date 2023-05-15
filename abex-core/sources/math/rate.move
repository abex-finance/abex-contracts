
module abex_core::rate {

    struct Rate has copy, drop, store {
        value: u128,
    }

    // Identity
    const WAD: u128 = 1_000_000_000_000_000_000;
    // Half of identity
    const HALF_WAD: u128 = 500_000_000_000_000_000;
    // Scale for percentages
    const PERCENT_SCALER: u128 = 10_000_000_000_000_000;
    // Scale for permillages
    const PERMILLE_SCALER: u128 = 1_000_000_000_000_000;
    // Scale for permyriad
    const PERMYRIAD_SCALER: u128 = 100_000_000_000_000;

    public fun one(): Rate {
        Rate { value: WAD }
    }

    public fun zero(): Rate {
        Rate { value: 0 }
    }

    public fun from_raw(value: u128): Rate {
        Rate { value }
    }

    public fun from_percent(percent: u8): Rate {
        Rate {
            value: (percent as u128) * PERCENT_SCALER
        }
    }

    public fun from_permille(permille: u16): Rate {
        Rate {
            value: (permille as u128) * PERMILLE_SCALER
        }
    }

    public fun from_permyriad(permyriad: u16): Rate {
        Rate {
            value: (permyriad as u128) * PERMYRIAD_SCALER
        }
    }

    public fun from_u64(value: u64): Rate {
        Rate {
            value: (value as u128) * WAD,
        }
    }

    public fun to_raw(rate: Rate): u128 {
        rate.value
    }

    public fun round_u64(rate: Rate): u64 {
        (((HALF_WAD + rate.value) / WAD) as u64)
    }

    public fun equals(self: &Rate, other: &Rate): bool {
        self.value == other.value
    }

    public fun lt(self: &Rate, other: &Rate): bool {
        self.value < other.value
    }

    public fun le(self: &Rate, other: &Rate): bool {
        self.value <= other.value
    }

    public fun gt(self: &Rate, other: &Rate): bool {
        self.value > other.value
    }

    public fun ge(self: &Rate, other: &Rate): bool {
        self.value >= other.value
    }

    public fun is_zero(self: &Rate): bool {
        self.value == 0
    }

    public fun diff(a: Rate, b: Rate): Rate {
        let value = if (a.value > b.value) {
            a.value - b.value
        } else {
            b.value - a.value
        };
        Rate { value }
    }

    public fun add(a: Rate, b: Rate): Rate {
        Rate {
            value: a.value + b.value
        }
    }

    public fun sub(a: Rate, b: Rate): Rate {
        Rate {
            value: a.value - b.value
        }
    }

    public fun mul_with_u64(a: Rate, b: u64): Rate {
        Rate {
            value: a.value * (b as u128)
        }
    }

    public fun div_by_u64(a: Rate, b: u64): Rate {
        Rate {
            value: a.value / (b as u128)
        }
    }
}