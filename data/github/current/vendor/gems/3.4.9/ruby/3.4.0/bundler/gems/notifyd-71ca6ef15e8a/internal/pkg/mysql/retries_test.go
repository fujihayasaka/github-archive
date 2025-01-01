package mysql

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/benbjohnson/clock"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/go-sql-driver/mysql"
	"github.com/stretchr/testify/require"
)

func Test_WithRetriesOptions(t *testing.T) {
	r := require.New(t)
	oops := errors.New("oops")

	errorCases := []struct {
		name      string
		operation func() CallbackNoReturn
		result    error
		options   []RetryOption
	}{
		{
			name: "catch all retrier",
			operation: func() CallbackNoReturn {
				return func(ctx context.Context) error {
					return oops
				}
			},
			result: oops,
			options: []RetryOption{
				WithRetrier(func(err error) bool { return err != nil }),
			},
		},
		{
			name: "error.Is retrier",
			operation: func() CallbackNoReturn {
				return func(ctx context.Context) error {
					return oops
				}
			},
			result: oops,
			options: []RetryOption{
				WithRetrier(func(err error) bool { return errors.Is(err, oops) }),
			},
		},
	}

	for _, test := range errorCases {
		t.Run(test.name, func(t *testing.T) {
			ctx := context.Background()
			_, result := WithRetries(ctx, clock.NewMock(), logs.NullTelem, ToCallback(test.operation()), test.options...)

			r.ErrorIs(result, oops)
		})
	}

	noErrorCases := []struct {
		name      string
		operation func() CallbackNoReturn
		result    error
		options   []RetryOption
	}{
		{
			name: "catch all retrier",
			operation: func() CallbackNoReturn {
				return func(ctx context.Context) error {
					return nil
				}
			},
			result: nil,
			options: []RetryOption{
				WithRetrier(func(err error) bool { return err != nil }),
			},
		},
		{
			name: "error.Is retrier",
			operation: func() CallbackNoReturn {
				return func(ctx context.Context) error {
					return nil
				}
			},
			result: nil,
			options: []RetryOption{
				WithRetrier(func(err error) bool { return errors.Is(err, oops) }),
			},
		},
	}

	for _, test := range noErrorCases {
		t.Run(test.name, func(t *testing.T) {
			ctx := context.Background()
			_, result := WithRetries(ctx, clock.NewMock(), logs.NullTelem, ToCallback(test.operation()))

			r.NoError(result)
		})
	}
}

func Test_WithRetriesDefaults(t *testing.T) {
	r := require.New(t)
	cases := []struct {
		name      string
		operation func() CallbackNoReturn
		result    error
	}{
		{
			name: "when the operation succeeds",
			operation: func() CallbackNoReturn {
				return func(ctx context.Context) error {
					return nil
				}
			},
			result: nil,
		},
		{
			name: "when the operation fails with a non retriable error",
			operation: func() CallbackNoReturn {
				return func(ctx context.Context) error {
					return context.DeadlineExceeded
				}
			},
			result: context.DeadlineExceeded,
		},
		{
			name: "when the operation fails with a timeout error and then succeeds on a retry",
			operation: func() CallbackNoReturn {
				failed := false
				return func(ctx context.Context) error {
					if !failed {
						failed = true
						return newErrThrottleTimeout(1 * time.Second)
					}
					return nil
				}
			},
			result: nil,
		},
		{
			name: "when the operation fails with a retriable error and drains the retries",
			operation: func() CallbackNoReturn {
				return func(ctx context.Context) error {
					return mysql.ErrInvalidConn
				}
			},
			result: mysql.ErrInvalidConn,
		},
	}

	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			ctx := context.Background()
			_, result := WithRetries(ctx, clock.NewMock(), logs.NullTelem, ToCallback(test.operation()))

			if test.result == nil {
				r.NoError(result, "it doesn't return an error")
			} else {
				r.ErrorIs(result, test.result, "it propagates the error")
			}
		})
	}
}
