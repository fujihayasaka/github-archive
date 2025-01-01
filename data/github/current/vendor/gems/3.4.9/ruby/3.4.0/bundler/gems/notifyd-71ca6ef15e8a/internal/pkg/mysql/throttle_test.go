package mysql

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"

	"github.com/benbjohnson/clock"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
)

var errTest = errors.New("test error")

type okThrottler struct{}

func (t *okThrottler) CanWrite(ctx context.Context) (bool, error) {
	return true, nil
}

func (t *okThrottler) Wait(ctx context.Context) error {
	return nil
}

type errThrottler struct{}

func (t *errThrottler) CanWrite(ctx context.Context) (bool, error) {
	return false, nil
}

func (t *errThrottler) Wait(ctx context.Context) error {
	return errTest
}

type hangThrottler struct{}

func (t *hangThrottler) CanWrite(ctx context.Context) (bool, error) {
	return false, nil
}

func (t *hangThrottler) Wait(ctx context.Context) error {
	sleep := 500 * time.Millisecond

	for i := 0; ; i++ {
		select {
		case <-ctx.Done():
			return context.DeadlineExceeded
		case <-time.After(sleep):
			continue
		}
	}
}

func Test_WithThrottlingOnSuccess(t *testing.T) {
	r := require.New(t)
	throttler := &okThrottler{}
	fn := func(ctx context.Context) (int, error) {
		return 1, nil
	}

	ctx := context.Background()
	result, err := WithThrottling(ctx, throttler, fn)

	r.NoError(err)
	r.Equal(1, result)
}

func Test_WithThrottlingOnFailure(t *testing.T) {
	r := require.New(t)
	throttler := &errThrottler{}
	fn := func(ctx context.Context) (string, error) {
		return "nope", nil
	}

	ctx := context.Background()
	result, err := WithThrottling(ctx, throttler, fn)

	r.Equal("", result)
	r.ErrorIs(err, errTest)
}

func Test_WithThrottlingDefaultTimeout(t *testing.T) {
	r := require.New(t)
	throttler := &hangThrottler{}
	fn := func(ctx context.Context) (string, error) {
		return "nope", nil
	}

	ctx := context.Background()
	result, err := WithThrottling(ctx, throttler, fn)

	r.Equal("", result)
	r.ErrorIs(err, context.DeadlineExceeded)
}

func Test_WithThrottlingAcceptsToCallback(t *testing.T) {
	r := require.New(t)
	throttler := &okThrottler{}
	fn := func(ctx context.Context) error {
		return nil
	}

	ctx := context.Background()
	result, err := WithThrottling(ctx, throttler, ToCallback(fn))

	r.NoError(err)
	r.Nil(result)
}

func Test_WrapThrottlingOnSuccess(t *testing.T) {
	r := require.New(t)
	throttler := &okThrottler{}
	fn := func(ctx context.Context) (int, error) {
		return 1, nil
	}

	wrap := WrapThrottling(throttler, fn)
	ctx := context.Background()
	result, err := wrap(ctx)

	r.NoError(err)
	r.Equal(1, result)
}

func Test_WrapThrottlingOnFailure(t *testing.T) {
	r := require.New(t)
	throttler := &errThrottler{}
	fn := func(ctx context.Context) (string, error) {
		return "nope", nil
	}

	wrap := WrapThrottling(throttler, fn)
	ctx := context.Background()
	result, err := wrap(ctx)

	r.Equal("", result)
	r.ErrorIs(err, errTest)
}

func Test_WrapThrottlingDefaultTimeout(t *testing.T) {
	r := require.New(t)
	throttler := &hangThrottler{}
	fn := func(ctx context.Context) (string, error) {
		return "nope", nil
	}

	wrap := WrapThrottling(throttler, fn)
	ctx := context.Background()
	result, err := wrap(ctx)

	r.Equal("", result)
	r.ErrorIs(err, context.DeadlineExceeded)
}

func Test_NewThrottlerUsesPassthroughByDefault(t *testing.T) {
	r := require.New(t)
	cfg := FrenoConfig{FrenoEnabled: false}
	throttler := NewFrenoThrottler(cfg, clock.NewMock(), logs.NullTelem, stats.NullStatter)

	err := throttler.Wait(context.Background())

	r.NoError(err)
}

func Test_NewThrottlerUsesFrenoWhenEnabled(t *testing.T) {
	r := require.New(t)
	called := false
	server, addr := testServer(t, func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusOK)
	})
	defer server.Close()

	cfg := FrenoConfig{FrenoEnabled: true, FrenoAddr: addr, FrenoApp: "notifyd", FrenoCluster: "test"}
	throttler := NewFrenoThrottler(cfg, clock.NewMock(), logs.NullTelem, stats.NullStatter)

	err := throttler.Wait(context.Background())

	r.NoError(err)
	r.True(called)
}

func Test_ThrottlerReturnsTimeoutError(t *testing.T) {
	r := require.New(t)
	server, addr := testServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
	})
	defer server.Close()

	cfg := FrenoConfig{FrenoEnabled: true, FrenoAddr: addr, FrenoApp: "notifyd", FrenoCluster: "test"}
	throttler := NewFrenoThrottler(cfg, clock.NewMock(), logs.NullTelem, stats.NullStatter)

	ctx, cancel := context.WithDeadline(context.Background(), time.Now().Add(500*time.Millisecond))
	defer cancel()

	err := throttler.Wait(ctx)
	r.Error(err, &throttleTimeoutError{})
}

func testServer(t *testing.T, handler http.HandlerFunc) (*httptest.Server, string) {
	t.Helper()

	server := httptest.NewServer(handler)
	uri, err := url.Parse(server.URL)
	if err != nil {
		panic(fmt.Sprintf("Error parsing mock test server url: %#v", err))
	}
	addr := fmt.Sprintf("%s:%s", uri.Hostname(), uri.Port())

	return server, addr
}
