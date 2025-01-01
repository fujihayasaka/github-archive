package nano

import (
	"fmt"
	"math"
	"math/big"
	"strconv"

	decimal "github.com/shopspring/decimal"
)

// Nano represents a float value as an int64 using Nano (10^9) as the base divisor
type Nano struct {
	value *big.Int
}

const (
	NanoExponent         = 9
	NanoDivisor  int64   = 1000000000
	ToNanoCents  float64 = 1000000000
	unit         float64 = 0.0000000005
)

// NewFromInt creates a new Nano from an int64
func NewFromInt(v int64) *Nano {
	return &Nano{
		value: big.NewInt(v),
	}
}

// NewFromFloat creates a new Nano from a float64
func NewFromFloat(v float64) *Nano {
	return &Nano{
		value: big.NewInt(ToWholeAmount[int64](v)),
	}
}

// Add creates a new Nano by adding two nanos
func (n *Nano) Add(v *Nano) *Nano {
	sum := big.NewInt(0).Add(n.value, v.value)
	return &Nano{
		value: sum,
	}
}

func (n *Nano) Sub(v *Nano) *Nano {
	sum := big.NewInt(0).Sub(n.value, v.value)
	return &Nano{
		value: sum,
	}
}

// Div divides two Nanos and returns a Nano without rounding. If the result is
// less than 10 x 10^-9, the result will be 0 since we only support 9 digits of precision.
func (n *Nano) Div(v *Nano) *Nano {
	numerator := decimal.NewFromBigInt(n.value, NanoExponent)
	denominator := decimal.NewFromBigInt(v.value, NanoExponent)
	amt := numerator.Div(denominator)
	nanoAmt := amt.Mul(decimal.NewFromInt(NanoDivisor))

	return &Nano{
		value: nanoAmt.BigInt(),
	}
}

// Mul multiplies two Nanos and returns a Nano
func (n *Nano) Mul(v *Nano) *Nano {
	product := big.NewInt(0).Mul(n.value, v.value)

	// We must divide by the divisor to get the correct value when multiplying
	// two Nanos
	return &Nano{
		value: big.NewInt(0).Div(product, big.NewInt(NanoDivisor)),
	}
}

// Int64 returns the int64 value of the Nano
func (n *Nano) Int64() int64 {
	return n.value.Int64()
}

func ToWholeAmount[T int64 | uint64](price float64) T {
	// round it to the nearest whole number for precision greater than 10
	// this handles 4.1 == 4.0999999999999996447286321199499070644378662109375 rounding the float
	priceByUnit := price / unit        // 4.1 * 0.000005 = 819999.9999999999
	rounded := math.Round(priceByUnit) // 819999.9999999999 -> 820000
	backToFloat := rounded * unit      // 4.1000000000000005
	// this convertes to the whole number
	x := backToFloat * ToNanoCents // 410000.00000000006
	ret := T(x)                    // 410000

	// 99.999999, which is 1 digit past our max precision rounds up to 100 which is wrong
	// but its an edge case that we can live with. the string implemention works but is much slower
	// I don't know if it matters if its slower but accurate
	if ToDecimalAmount(ret) != price {
		return ToWholeAmountString[T](price)
	}
	return ret
}

func ToWholeAmountString[T int64 | uint64](price float64) T {
	c := price * ToNanoCents
	s := fmt.Sprintf("%.05f", c)
	f, _ := strconv.ParseFloat(s, 64)
	i := T(f)
	return i
}

func ToDecimalAmount[T int64 | uint64](price T) float64 {
	return float64(price) / ToNanoCents
}

func ToInt64[T int64 | uint64](number T) int64 {
	return int64(number) / NanoDivisor
}
