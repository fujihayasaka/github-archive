package common

import (
	"context"
	"testing"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type testThrottler struct {
	canWriteFn func(ctx context.Context) (bool, error)
}

func (t *testThrottler) CanWrite(ctx context.Context) (bool, error) {
	return t.canWriteFn(ctx)
}

func TestWithThrottling(t *testing.T) {
	t.Run("can write", func(t *testing.T) {
		throttler := &testThrottler{
			canWriteFn: func(ctx context.Context) (bool, error) {
				return true, nil
			},
		}

		var called bool
		err := WithThrottling(context.Background(), throttler, func() error {
			called = true
			return nil
		})
		require.NoError(t, err)
		require.True(t, called)
	})

	t.Run("throttle", func(t *testing.T) {
		throttler := &testThrottler{
			canWriteFn: func(ctx context.Context) (bool, error) {
				return false, nil
			},
		}

		var called bool
		err := WithThrottling(context.Background(), throttler, func() error {
			called = true
			return nil
		})
		assert.ErrorIs(t, err, WriteThrottledError)
		assert.False(t, called)
	})

	t.Run("no throttle", func(t *testing.T) {
		throttler := &testThrottler{
			canWriteFn: func(ctx context.Context) (bool, error) {
				return true, nil
			},
		}

		var called bool
		err := WithThrottling(context.Background(), throttler, func() error {
			called = true
			return nil
		})
		require.NoError(t, err)
		assert.True(t, called)
	})

	t.Run("error checking throttler", func(t *testing.T) {
		failedErr := errors.New("bad thing happened")
		throttler := &testThrottler{
			canWriteFn: func(ctx context.Context) (bool, error) {
				return false, failedErr
			},
		}

		var called bool
		err := WithThrottling(context.Background(), throttler, func() error {
			called = true
			return nil
		})
		require.ErrorIs(t, err, failedErr)
		assert.False(t, called)
	})
}
