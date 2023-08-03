
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

    public fun eq(self: &SDecimal, other: &SDecimal): bool {
        if (decimal::eq(&self.value, &other.value)) {
            if (is_zero(self)) {
                true
            } else {
                self.is_positive == other.is_positive
            }
        } else {
            false
        }
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
        if (is_zero(&a)) {
            return from_decimal(true, b)
        };

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
        if (is_zero(&a)) {
            return from_decimal(false, b)
        };

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
        if (is_zero(&a)) {
            return b
        };
        if (is_zero(&b)) {
            return a
        };

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
        if (is_zero(&a)) {
            return from_decimal(!b.is_positive, b.value)
        };
        if (is_zero(&b)) {
            return a
        };

        let (is_positive, value) = if (a.is_positive != b.is_positive) {
            (a.is_positive, decimal::add(a.value, b.value))
        } else {
            if (decimal::gt(&a.value, &b.value)) {
                (a.is_positive, decimal::sub(a.value, b.value))
            } else {
                (!a.is_positive, decimal::sub(b.value, a.value))
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

#[test_only]
module abex_core::sdecimal_tests {
    use abex_core::decimal;
    use abex_core::sdecimal::{
        from_decimal, add, add_with_decimal, sub, sub_with_decimal, eq,
    };

    #[test]
    fun test_add() {
        // a1 = +0
        let a1 = from_decimal(true, decimal::zero());
        // a2 = -0
        let a2 = from_decimal(false, decimal::zero());
        // b = 1
        let b = from_decimal(true, decimal::one());
        // c = -1
        let c = from_decimal(false, decimal::one());
        // d = 2
        let d = from_decimal(true, decimal::from_u64(2));
        // e = -2
        let e = from_decimal(false, decimal::from_u64(2));

        // a1 + a2 = a2 + a1 = a1 = a2
        assert!(eq(&add(a1, a2), &a1), 0);
        assert!(eq(&add(a2, a1), &a2), 1);
        // a1 + b = a2 + b = b
        assert!(eq(&add(a1, b), &b), 2);
        assert!(eq(&add(a2, b), &b), 3);
        // a1 + c = a2 + c = c
        assert!(eq(&add(a1, c), &c), 4);
        assert!(eq(&add(a2, c), &c), 5);
        // b + b = d
        assert!(eq(&add(b, b), &d), 6);
        // b + c = c + b = 0
        assert!(eq(&add(b, c), &a1), 7);
        assert!(eq(&add(c, b), &a1), 8);
        // b + e = e + b = c
        assert!(eq(&add(b, e), &c), 9);
        assert!(eq(&add(e, b), &c), 10);
        // c + c = e
        assert!(eq(&add(c, c), &e), 11);
        // c + d = d + c = b
        assert!(eq(&add(c, d), &b), 12);
        assert!(eq(&add(d, c), &b), 13);
    }

    #[test]
    fun test_sub() {
        // a1 = +0
        let a1 = from_decimal(true, decimal::zero());
        // a2 = -0
        let a2 = from_decimal(false, decimal::zero());
        // b = 1
        let b = from_decimal(true, decimal::one());
        // c = -1
        let c = from_decimal(false, decimal::one());
        // d = 2
        let d = from_decimal(true, decimal::from_u64(2));
        // e = -2
        let e = from_decimal(false, decimal::from_u64(2));

        // a1 - a2 = a2 - a1 = a1 = a2
        assert!(eq(&sub(a1, a2), &a1), 0);
        assert!(eq(&sub(a2, a1), &a2), 1);
        // a1 - b = a2 - b = c
        assert!(eq(&sub(a1, b), &c), 2);
        assert!(eq(&sub(a2, b), &c), 3);
        // a1 - c = a2 - c = b
        assert!(eq(&sub(a1, c), &b), 4);
        assert!(eq(&sub(a2, c), &b), 5);
        // b - b = a1
        assert!(eq(&sub(b, b), &a1), 6);
        // b - c = d
        assert!(eq(&sub(b, c), &d), 7);
        // b - d = c
        assert!(eq(&sub(b, d), &c), 8);
        // c - c = a1
        assert!(eq(&sub(c, c), &a1), 9);
        // d - b = b
        assert!(eq(&sub(d, b), &b), 10);
        // a1 - e = a2 - e = d
        assert!(eq(&sub(a1, e), &d), 11);
        assert!(eq(&sub(a2, e), &d), 12);
        // e - c = c
        assert!(eq(&sub(e, c), &c), 13);
    }

    #[test]
    fun test_add_with_decimal() {
        // a1 = +0
        let a1 = from_decimal(true, decimal::zero());
        // a2 = -0
        let a2 = from_decimal(false, decimal::zero());
        // b = +1
        let b = from_decimal(true, decimal::one());
        // c = -1
        let c = from_decimal(false, decimal::one());
        // d = +2
        let d = from_decimal(true, decimal::from_u64(2));
        // e = -2
        let e = from_decimal(false, decimal::from_u64(2));
        // f = 2
        let f = decimal::from_u64(2);

        // a1 + e = a2 + e = d
        assert!(eq(&add_with_decimal(a1, f), &d), 0);
        assert!(eq(&add_with_decimal(a2, f), &d), 1);
        // c + e = b
        assert!(eq(&add_with_decimal(c, f), &b), 2);
        // e + f = a1
        assert!(eq(&add_with_decimal(e, f), &a1), 3);
    }

    #[test]
    fun test_sub_with_decimal() {
        // a1 = +0
        let a1 = from_decimal(true, decimal::zero());
        // a2 = -0
        let a2 = from_decimal(false, decimal::zero());
        // b = +1
        let b = from_decimal(true, decimal::one());
        // c = -1
        let c = from_decimal(false, decimal::one());
        // d = 1
        let d = decimal::one();
        // e = 2
        let e = decimal::from_u64(2);

        // a1 - d = a2 - d = c
        assert!(eq(&sub_with_decimal(a1, d), &c), 0);
        assert!(eq(&sub_with_decimal(a2, d), &c), 1);
        // b - d = a1
        assert!(eq(&sub_with_decimal(b, d), &a1), 2);
        // b - e = c
        assert!(eq(&sub_with_decimal(b, e), &c), 3);
    }
}

