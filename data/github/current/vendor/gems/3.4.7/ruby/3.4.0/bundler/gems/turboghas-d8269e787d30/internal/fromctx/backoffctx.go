package fromctx

import (
	"context"
	"time"

	"github.com/github/turboghas/internal/fields"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/github-telemetry-go/kvp"
)

func DefaultBackOff() backoff.BackOff {
	return backoff.NewExponentialBackOff(
		backoff.WithMaxElapsedTime(2*time.Hour),
		backoff.WithMaxInterval(8*time.Minute),
	)
}

// BackOffOverride allows the context to override any backoff being used by Retry
type BackOffOverride interface {
	context.Context
	BackOff() backoff.BackOff
}

func Retry(ctx context.Context, fn func() error, b backoff.BackOff) error {
	logger := Logger.Value(ctx)

	override, ok := ctx.(BackOffOverride)
	if ok {
		b = override.BackOff()
	} else if Env.Value(ctx).IsTest() {
		// never retry in tests, just return the error immediately
		b = backoff.WithMaxRetries(b, 0)
	}

	return backoff.RetryNotify(fn, backoff.WithContext(b, ctx), func(err error, d time.Duration) {
		if err != nil {
			ExceptionReporter.Report(ctx, err, nil)
			logger.WithError(err).Error("error trying function", append(fields.From(err), kvp.Duration("duration", d))...)
		}
	})
}
