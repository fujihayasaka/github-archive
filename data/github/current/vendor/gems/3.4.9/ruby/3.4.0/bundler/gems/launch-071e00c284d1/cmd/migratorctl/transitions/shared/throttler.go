package shared

import (
	"context"
	"time"

	freno "github.com/github/go-freno-client"
)

const timeout = 5 * time.Minute

// Consult Freno before writing to a row
// For transitions that operate on a single row, it may be too slow to check before every write
// Set an appropriate rowInterval to skip checking on every row
func WaitOnThrottler(ctx context.Context, throttler freno.Throttler, rowsProcessed, rowInterval int) error {
	if rowInterval > 0 && rowsProcessed%rowInterval != 0 {
		// Skip checking Freno
		return nil
	}

	timeoutCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	return freno.WaitOnThrottler(timeoutCtx, throttler)
}
