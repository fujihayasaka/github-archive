package nano

import (
	"testing"
)

func Test_Div(t *testing.T) {
	tests := []struct {
		name        string
		numerator   float64
		denominator float64
		expected    int64
	}{
		{"does not round up", 2.0, 3.0, ToWholeAmount[int64](0.666666666)},
		{"does not round", 1.0, 3.0, ToWholeAmount[int64](0.333333333)},
		{"large denominator", 4.1, 50000000, ToWholeAmount[int64](0.000000082)},
		{"float that can't be represented", 1.0, 0.000000001, ToWholeAmount[int64](1000000000.0)},
		{"denominator larger than supported precision", 4.1, 5000000000, ToWholeAmount[int64](0)},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			numerator := NewFromFloat(tt.numerator)
			denominator := NewFromFloat(tt.denominator)
			amount := numerator.Div(denominator)
			if amount.Int64() != tt.expected {
				t.Errorf("expected billed amount to be %d, got %d", tt.expected, amount.Int64())
			}
		})
	}
}
