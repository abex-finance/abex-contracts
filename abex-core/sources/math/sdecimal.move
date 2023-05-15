
module abex_core::sdecimal {
    use abex_core::rate::Rate;
    use abex_core::srate::{Self, SRate};
    use abex_core::decimal::{Self, Decimal};

    struct SDecimal has copy, drop, store {
        is_positive: bool,
        value: Decimal,
    }

    public fun is_zero(self: &SDecimal): bool {
        decimal::is_zero(&self.value)
    }

    public fun is_positive(self: &SDecimal): bool {
        self.is_positive
    }

    public fun value(self: &SDecimal): Decimal {
        self.value
    }

    public fun zero(): SDecimal {
        SDecimal {
            is_positive: true,
            value: decimal::zero(),
        }
    }

    public fun from_decimal(is_positive: bool, value: Decimal): SDecimal {
        SDecimal { is_positive, value }
    }

    public fun from_srate(srate: SRate): SDecimal {
        SDecimal {
            is_positive: srate::is_positive(&srate),
            value: decimal::from_rate(srate::value(&srate)),
        }
    }

    public fun to_srate(self: SDecimal): SRate {
        srate::from_rate(
            self.is_positive,
            decimal::to_rate(self.value),
        )
    }

    public fun add_with_decimal(a: SDecimal, b: Decimal): SDecimal {
        let (is_positive, value) = if (a.is_positive) {
            (true, decimal::add(a.value, b))
        } else {
            if (decimal::gt(&a.value, &b)) {
                (false, decimal::sub(a.value, b))
            } else {
                (true, decimal::sub(b, a.value))
            }
        };

        SDecimal { is_positive, value }
    }

    public fun sub_with_decimal(a: SDecimal, b: Decimal): SDecimal {
        let (is_positive, value) = if (a.is_positive) {
            if (decimal::gt(&a.value, &b)) {
                (true, decimal::sub(a.value, b))
            } else {
                (false, decimal::sub(b, a.value))
            }
        } else {
            (false, decimal::add(a.value, b))
        };

        SDecimal { is_positive, value }
    }

    public fun add(a: SDecimal, b: SDecimal): SDecimal {
        let (is_positive, value) = if (a.is_positive == b.is_positive) {
            (a.is_positive, decimal::add(a.value, b.value))
        } else {
            if (decimal::gt(&a.value, &b.value)) {
                (a.is_positive, decimal::sub(a.value, b.value))
            } else {
                (b.is_positive, decimal::sub(b.value, a.value))
            }
        };

        SDecimal { is_positive, value }
    }

    public fun sub(a: SDecimal, b: SDecimal): SDecimal {
        let (is_positive, value) = if (a.is_positive != b.is_positive) {
            (a.is_positive, decimal::add(a.value, b.value))
        } else {
            if (decimal::gt(&a.value, &b.value)) {
                (a.is_positive, decimal::sub(a.value, b.value))
            } else {
                (b.is_positive, decimal::sub(b.value, a.value))
            }
        };

        SDecimal { is_positive, value }
    }

    public fun mul_with_u64(a: SDecimal, b: u64): SDecimal {
        SDecimal {
            is_positive: a.is_positive,
            value: decimal::mul_with_u64(a.value, b),
        }
    }

    public fun mul_with_rate(a: SDecimal, b: Rate): SDecimal {
        SDecimal {
            is_positive: a.is_positive,
            value: decimal::mul_with_rate(a.value, b),
        }
    }

    public fun mul_with_decimal(a: SDecimal, b: Decimal): SDecimal {
        SDecimal {
            is_positive: a.is_positive,
            value: decimal::mul(a.value, b),
        }
    }

    public fun mul_with_srate(a: SDecimal, b: SRate): SDecimal {
        SDecimal {
            is_positive: a.is_positive == srate::is_positive(&b),
            value: decimal::mul_with_rate(a.value, srate::value(&b)),
        }
    }

    public fun mul(a: SDecimal, b: SDecimal): SDecimal {
        SDecimal {
            is_positive: a.is_positive == b.is_positive,
            value: decimal::mul(a.value, b.value),
        }
    }

    public fun div_by_u64(a: SDecimal, b: u64): SDecimal {
        SDecimal {
            is_positive: a.is_positive,
            value: decimal::div_by_u64(a.value, b),
        }
    }

    public fun div_by_rate(a: SDecimal, b: Rate): SDecimal {
        SDecimal {
            is_positive: a.is_positive,
            value: decimal::div_by_rate(a.value, b),
        }
    }

    public fun div_by_srate(a: SDecimal, b: SRate): SDecimal {
        SDecimal {
            is_positive: a.is_positive == srate::is_positive(&b),
            value: decimal::div_by_rate(a.value, srate::value(&b)),
        }
    }

    public fun div_by_decimal(a: SDecimal, b: Decimal): SDecimal {
        SDecimal {
            is_positive: a.is_positive,
            value: decimal::div(a.value, b),
        }
    }

    public fun div(a: SDecimal, b: SDecimal): SDecimal {
        SDecimal {
            is_positive: a.is_positive == b.is_positive,
            value: decimal::div(a.value, b.value),
        }
    }
}