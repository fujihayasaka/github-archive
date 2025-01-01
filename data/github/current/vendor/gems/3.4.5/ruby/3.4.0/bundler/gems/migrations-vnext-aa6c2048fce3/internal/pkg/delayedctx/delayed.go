// Package delayedctx provides a way to create a context that is canceled
// after a delay once the parent context is canceled.
package delayedctx

import (
	"context"
	"time"
)

// WithDelayedCancelContext creates a new context that is canceled after a delay once the parent context is canceled.
func WithDelayedCancelContext(parent context.Context, delay time.Duration) (context.Context, context.CancelFunc) {
	// Create a new context that can be canceled.
	ctx, cancel := context.WithCancel(context.Background())

	// Watch for the parent context's cancellation.
	go func() {
		select {
		case <-parent.Done(): // When the parent is canceled
			time.Sleep(delay) // Wait for the specified delay
			cancel()          // Then cancel the delayed context
		case <-ctx.Done(): // If the delayed context is canceled manually
			return
		}
	}()

	return ctx, cancel
}
