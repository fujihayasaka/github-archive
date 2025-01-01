package measurehttp

import (
	"context"
	"time"

	"github.com/pkg/errors"

	"github.com/github/launch/pkg/mu/ctxkey"
)

type thresholdLogging struct {
	threshold time.Duration
}

var ctxKey = ctxkey.New("thresholdLogging")

// WithThresholdLogging creates a new context with a threshold logging struct
func WithThresholdLogging(ctx context.Context) context.Context {
	return context.WithValue(ctx, ctxKey, &thresholdLogging{})
}

// GetThreshold retrieves the threshold from the context, if present
func GetThreshold(ctx context.Context) time.Duration {
	if t, ok := ctx.Value(ctxKey).(*thresholdLogging); ok {
		return t.threshold
	}

	return 0
}

// SetThreshold sets the threshold in the context
func SetThreshold(ctx context.Context, threshold time.Duration) error {
	if t, ok := ctx.Value(ctxKey).(*thresholdLogging); ok {
		t.threshold = threshold
		return nil
	}
	return errors.New("No threshold in context")
}
