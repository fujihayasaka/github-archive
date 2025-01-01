package fromctx

import (
	"context"

	"github.com/cenkalti/backoff/v4"
	freno "github.com/github/go-freno-client"
	"github.com/pkg/errors"
	"github.com/simon-engledew/ctxkey"
)

type throttlerKey struct {
	ctxkey.ContextKey[freno.Throttler]
}

var Throttler = throttlerKey{
	ctxkey.New[freno.Throttler](freno.DefaultThrottler),
}
var errThrottled = errors.New("throttled")

func (k *throttlerKey) Wait(ctx context.Context) error {
	val := k.Value(ctx)
	return backoff.Retry(func() error {
		canWrite, err := val.CanWrite(ctx)
		if err == nil && !canWrite {
			return errThrottled
		}
		return err
	}, backoff.WithContext(backoff.NewExponentialBackOff(), ctx))
}
