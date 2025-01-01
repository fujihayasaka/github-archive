package timeutils

import (
	"time"
)

// Scales a duration value by the amount provided.
// Returns scale * d.
func ScaleDuration[T int | int64 | float64](scale T, d time.Duration) time.Duration {
	// Under the hood Duration is an int64, so we can't just cast scale to time.Duration
	// without losing precision (especially for the case that scale is some value < 1.0).
	// Future:  support uint/uint64 by preserving the sign of d.
	return time.Duration(scale * T(d))
}
