package hkdf

import "time"

// Now returns a timestamp for HKDF calculation
func Now() time.Time {
	// Wipe monotonic data, normalize to UTC
	return time.Now().Truncate(0).In(time.UTC)
}
