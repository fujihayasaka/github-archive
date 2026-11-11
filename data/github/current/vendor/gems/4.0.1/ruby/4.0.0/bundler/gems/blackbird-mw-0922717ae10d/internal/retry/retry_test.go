package retry

import (
	"context"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func Test_checkHTTPResponse(t *testing.T) {
	type httpTest struct {
		name     string
		resp     *http.Response
		err      error
		expected error
	}

	tests := []httpTest{
		{
			name:     "error is returned as-is",
			resp:     nil,
			err:      errors.New("some error"),
			expected: errors.New("some error"),
		},
		{
			name:     "non-retried status is permament failure",
			resp:     &http.Response{StatusCode: http.StatusBadRequest},
			err:      nil,
			expected: backoff.Permanent(errors.New("request failed with HTTP status code 400 <no response body>")),
		},
		{
			name:     "context canceled is permament failure",
			resp:     nil,
			err:      context.Canceled,
			expected: backoff.Permanent(context.Canceled),
		},
	}

	for i := 200; i < 300; i++ {
		test := httpTest{
			name:     fmt.Sprintf("HTTP success %d returns nil", i),
			resp:     &http.Response{StatusCode: http.StatusOK},
			err:      nil,
			expected: nil,
		}

		tests = append(tests, test)
	}

	retriedStatuses := []int{
		http.StatusGatewayTimeout,
		http.StatusRequestTimeout,
		http.StatusBadGateway,
		http.StatusServiceUnavailable,
		http.StatusInternalServerError,
	}

	for _, status := range retriedStatuses {
		test := httpTest{
			name:     fmt.Sprintf("HTTP %d is retried", status),
			resp:     &http.Response{StatusCode: status},
			err:      nil,
			expected: fmt.Errorf("request failed with HTTP status code %d <no response body>", status),
		}

		tests = append(tests, test)
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()

			err := CheckHTTPResponse(test.resp, test.err)
			if test.expected == nil {
				require.NoError(t, err)
			} else {
				require.EqualError(t, err, test.expected.Error())
				if _, ok := test.expected.(*backoff.PermanentError); ok {
					require.IsType(t, &backoff.PermanentError{}, err)
				}
			}
		})
	}

	t.Run("nil error and nil response", func(t *testing.T) {
		require.Panics(t, func() { CheckHTTPResponse(nil, nil) }) //nolint:errcheck
	})
}

func Test_checkTwirpErrResponse(t *testing.T) {
	type twirpTest struct {
		name     string
		err      error
		expected error
	}

	var tests = []twirpTest{
		{
			name:     "nil error returns nil",
			err:      nil,
			expected: nil,
		},
		{
			name:     "context canceled does not retry",
			err:      twirp.InternalErrorWith(context.Canceled),
			expected: backoff.Permanent(twirp.InternalErrorWith(context.Canceled)),
		},
		{
			name:     "other internal errors are retried",
			err:      twirp.InternalErrorWith(errors.New("network error")),
			expected: twirp.InternalErrorWith(errors.New("network error")),
		},
		{
			name:     "non-retryable twirp error does not retry",
			err:      twirp.NotFoundError("not found"),
			expected: backoff.Permanent(twirp.NotFoundError("not found")),
		},
		{
			name:     "non-twirp error retries",
			err:      errors.New("not a twirp error"),
			expected: errors.New("not a twirp error"),
		},
	}

	retryable := []twirp.ErrorCode{twirp.Unavailable, twirp.DeadlineExceeded, twirp.Canceled}
	for _, code := range retryable {
		test := twirpTest{
			name:     fmt.Sprintf("twirp error %s is retried", string(code)),
			err:      twirp.NewError(code, "error"),
			expected: twirp.NewError(code, "error"),
		}

		tests = append(tests, test)
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()

			err := CheckTwirpErrResponse(test.err)
			if test.expected == nil {
				require.NoError(t, err)
			} else {
				require.EqualError(t, err, test.expected.Error())
				if _, ok := test.expected.(*backoff.PermanentError); ok {
					require.IsType(t, &backoff.PermanentError{}, err)
				}
			}
		})
	}
}

func Test_WithExceptions(t *testing.T) {
	ctx := context.Background()
	const (
		retries          = 1 // NOTE: An operation is always run once, so this is two attempts
		ignoreAttempts   = 2
		expectedAttempts = 4
	)
	attempts := 0
	errException := errors.New("don't count this one")
	errException2 := errors.New("or this one")
	errFoo := errors.New("foo: some other error")
	op := func() error {
		attempts++

		if attempts <= ignoreAttempts {
			ignored := errException
			if attempts%2 == 0 {
				ignored = errException2
			}
			return fmt.Errorf("ignored err: %w: %w", ignored, errFoo)
		}

		return fmt.Errorf("boom: %w", errFoo)
	}

	err := WithExceptions(ctx, op, retries, errException, errException2)
	require.Error(t, err)
	require.ErrorIs(t, err, errFoo)
	require.Equal(t, expectedAttempts, attempts, "expected 4 total attempts: initial (1) + retries (%d) + ignoreAttempts (%d)", retries, ignoreAttempts)
}

func Test_WithExceptionsUnhandledError(t *testing.T) {
	ctx := context.Background()
	const (
		retries          = 1 // NOTE: An operation is always run once, so this is 2 attempts
		expectedAttempts = 2
	)
	attempts := 0
	errException := errors.New("don't count this one")
	errFoo := errors.New("foo: some other error")
	op := func() error {
		attempts++

		return fmt.Errorf("boom: %w", errFoo)
	}

	err := WithExceptions(ctx, op, retries, errException)
	require.Error(t, err)
	require.ErrorIs(t, err, errFoo)
	require.Equal(t, expectedAttempts, attempts, "expected 2 total attempts: initial (1) + retries (%d)", retries)
}

func Test_WithExceptionsOperationSucceedsAfterRetries(t *testing.T) {
	ctx := context.Background()
	const (
		retries          = 1 // NOTE: An operation is always run once, so this is two attempts
		expectedAttempts = 3
	)
	attempts := 0
	errException := errors.New("don't count this one")
	errFoo := errors.New("foo: some other error")
	op := func() error {
		attempts++

		switch attempts {
		case 1:
			return fmt.Errorf("attempt %d ignored err: %w", attempts, errException)
		case 2:
			return fmt.Errorf("attempt %d boom: %w", attempts, errFoo)
		default:
			return nil
		}
	}

	err := WithExceptions(ctx, op, retries, errException)
	require.NoError(t, err)
	require.Equal(t, expectedAttempts, attempts, "expected 3 total attempts: initial (1) + retries (%d) + excepted attempt (1)", retries)
}

// The default instance of ExponentialBackOff gives up after 15 minutes. We don't want to do that.
func Test_WithExceptionsLongDurationShouldNotFail(t *testing.T) {
	t.Skip("This test requires > 15 minutes to run, comment this line and run locally if you want to run it.")

	ctx := context.Background()
	start := time.Now()

	const (
		retries          = 2 // NOTE: An operation is always run once, so this is three attempts
		expectedAttempts = 3
	)
	attempts := 0
	errException := errors.New("don't count this one")
	errFoo := errors.New("foo: some other error")
	op := func() error {
		attempts++

		t.Logf("%s operation attempt %d (elapsed: %s)", t.Name(), attempts, time.Since(start))

		switch attempts {
		case 1:
			time.Sleep(15 * time.Minute)
			t.Logf("%s operation attempt %d failed with excepted error (elapsed: %s)", t.Name(), attempts, time.Since(start))
			return fmt.Errorf("attempt %d ignored err: %w", attempts, errException)
		case 2:
			t.Logf("%s operation attempt %d failed with error (elapsed: %s)", t.Name(), attempts, time.Since(start))
			return fmt.Errorf("attempt %d boom: %w", attempts, errFoo)
		default:
			t.Logf("%s operation attempt %d is successful! (elapsed: %s)", t.Name(), attempts, time.Since(start))
			return nil
		}
	}

	err := WithExceptions(ctx, op, retries, errException)
	t.Logf("%s retries took %s to run %d attempts", t.Name(), time.Since(start), attempts)

	require.NoError(t, err, "ultimate value should be success")
	require.Equal(t, expectedAttempts, attempts, "expected 3 total attempts")
}

func Test_WithExceptionsContextCanceledAfterError(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())

	const (
		retries          = 3 // NOTE: An operation is always run once, so this is 4 attempts
		expectedAttempts = 1
	)
	attempts := 0
	errException := errors.New("don't count this one")
	errFoo := errors.New("foo: some other error")

	op := func() error {
		defer cancel()

		attempts++

		return fmt.Errorf("boom: %w", errFoo)
	}

	err := WithExceptions(ctx, op, retries, errException)
	require.Error(t, err)
	require.ErrorIs(t, err, ctx.Err(), "ctx.Err() should be returned from the operation")
	require.Equal(t, expectedAttempts, attempts, "expected context cancellation to prevent retries")
}

func Test_RetryDefaultBackOffContextCanceledAfterError(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())

	const (
		retries          = 3 // NOTE: An operation is always run once, so this is 4 attempts
		expectedAttempts = 1
	)
	attempts := 0
	errFoo := errors.New("foo: some other error")

	op := func() error {
		defer cancel()

		attempts++

		return fmt.Errorf("boom: %w", errFoo)
	}

	err := backoff.Retry(op, DefaultBackOff(ctx, retries))
	require.Error(t, err)
	require.ErrorIs(t, err, ctx.Err(), "ctx.Err() should be returned from the operation")
	require.Equal(t, expectedAttempts, attempts, "expected context cancellation to prevent retries")
}

func Test_DefaultBackOffContextCanceledDuringOperation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())

	const (
		retries          = 3 // NOTE: An operation is always run once, so this is 4 attempts
		expectedAttempts = 2
	)
	attempts := 0
	errFoo := errors.New("foo: some other error")

	// represents calling some other function with a context, like an RPC or database call
	helperFn := func(ctx context.Context) error {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			return nil
		}
	}

	op := func() error {
		attempts++

		if attempts > 1 {
			cancel()
		}

		if err := helperFn(ctx); err != nil {
			return err
		}

		return fmt.Errorf("boom: %w", errFoo)
	}

	err := backoff.Retry(op, DefaultBackOff(ctx, retries))
	require.Error(t, err)
	require.ErrorIs(t, err, context.Canceled, "errFoo is not returned from the operation")
	require.Equal(t, expectedAttempts, attempts, "expected context cancellation to prevent retries")
}
