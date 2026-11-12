package aqueduct

import (
	"context"
	"errors"
	"time"

	"github.com/avast/retry-go"
)

type repeater struct {
	fn       func(context.Context) error
	interval time.Duration
	timeout  time.Duration
	opts     []retry.Option
}

func (r *repeater) Do(ctx context.Context) error {
	if r.fn == nil {
		return errors.New("func must be non-nil")
	}
	if r.interval <= 0 {
		return errors.New("interval must be > 0")
	}

	ticker := time.NewTicker(r.interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
			if err := r.exec(ctx); err != nil {
				return err
			}
		}
	}
}

func (r *repeater) exec(ctx context.Context) error {
	if r.timeout > 0 {
		var cancel func()
		ctx, cancel = context.WithTimeout(ctx, r.timeout)
		defer cancel()
	}

	err := retry.Do(
		func() error {
			return r.fn(ctx)
		},
		append(r.opts, retry.Context(ctx))...,
	)

	// ctx errors takes precedence for timeout signaling
	if err := ctx.Err(); err != nil {
		return err
	}
	return err
}
