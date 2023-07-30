
module abex_core::srate {
    use abex_core::rate::{Self, Rate};

    struct SRate has copy, drop, store {
        is_positive: bool,
        value: Rate,
    }

    public fun is_zero(self: &SRate): bool {
        rate::is_zero(&self.value)
    }

    public fun is_positive(self: &SRate): bool {
        self.is_positive
    }

    public fun value(self: &SRate): Rate {
        self.value
    }

    public fun zero(): SRate {
        SRate {
            is_positive: true,
            value: rate::zero(),
        }
    }

    public fun from_rate(is_positive: bool, value: Rate): SRate {
        SRate { is_positive, value }
    }

    public fun add_with_rate(a: SRate, b: Rate): SRate {
        if (is_zero(&a)) {
            return from_rate(true, b)
        };

        let (is_positive, value) = if (a.is_positive) {
            (true, rate::add(a.value, b))
        } else {
            if (rate::gt(&a.value, &b)) {
                (false, rate::sub(a.value, b))
            } else {
                (true, rate::sub(b, a.value))
            }
        };

        SRate { is_positive, value }
    }

    public fun sub_with_rate(a: SRate, b: Rate): SRate {
        if (is_zero(&a)) {
            return from_rate(false, b)
        };

        let (is_positive, value) = if (a.is_positive) {
            if (rate::gt(&a.value, &b)) {
                (true, rate::sub(a.value, b))
            } else {
                (false, rate::sub(b, a.value))
            }
        } else {
            (false, rate::add(a.value, b))
        };

        SRate { is_positive, value }
    }

    public fun add(a: SRate, b: SRate): SRate {
        if (is_zero(&a)) {
            return b
        };
        if (is_zero(&b)) {
            return a
        };

        let (is_positive, value) = if (a.is_positive == b.is_positive) {
            (a.is_positive, rate::add(a.value, b.value))
        } else {
            if (rate::gt(&a.value, &b.value)) {
                (a.is_positive, rate::sub(a.value, b.value))
            } else {
                (b.is_positive, rate::sub(b.value, a.value))
            }
        };
        SRate { is_positive, value }
    }

    public fun sub(a: SRate, b: SRate): SRate {
        if (is_zero(&a)) {
            return from_rate(!b.is_positive, b.value)
        };
        if (is_zero(&b)) {
            return a
        };
        
        let (is_positive, value) = if (a.is_positive != b.is_positive) {
            (a.is_positive, rate::add(a.value, b.value))
        } else {
            if (rate::gt(&a.value, &b.value)) {
                (a.is_positive, rate::sub(a.value, b.value))
            } else {
                (!a.is_positive, rate::sub(b.value, a.value))
            }
        };
        SRate { is_positive, value }
    }

    public fun mul_with_u64(a: SRate, b: u64): SRate {
        SRate {
            is_positive: a.is_positive,
            value: rate::mul_with_u64(a.value, b),
        }
    }

    public fun div_by_u64(a: SRate, b: u64): SRate {
        SRate {
            is_positive: a.is_positive,
            value: rate::div_by_u64(a.value, b),
        }
    }
}