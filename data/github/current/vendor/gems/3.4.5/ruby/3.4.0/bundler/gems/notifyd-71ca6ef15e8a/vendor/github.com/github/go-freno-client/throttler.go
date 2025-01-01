// Package throttler is the Go client for the database throttling service Freno
package throttler

import (
	"context"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"strings"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/go-http/middleware/requestid"
)

// DefaultThrottler defines a default passthrough throttler.
var DefaultThrottler Throttler = &passthroughThrottler{}

// Throttler is the interface that defines the throttling method.
type Throttler interface {
	// CanWrite returns whether the delay is small enough for us to write.
	CanWrite(ctx context.Context) (bool, error)
}

// ErrTimeout is returned from the WaitOnThrottler if the passed context is
// cancelled/done. It'll include the elapsed time since WaitOnThrottler has
// started.
//
//nolint:errname // Keeping ErrTimeout to avoid breaking changes.
type ErrTimeout struct {
	time.Duration
}

func (t *ErrTimeout) Error() string {
	return "timeout after " + t.String()
}

// A pass-through throttler that always allows writing to be used as the default.
type passthroughThrottler struct{}

func (t *passthroughThrottler) CanWrite(ctx context.Context) (bool, error) {
	return true, nil
}

// FrenoThrottler implements the Throttler interface.
type FrenoThrottler struct {
	url    *url.URL
	client *http.Client
}

// NewFrenoThrottler returns a new FrenoThrottler instance for the given host,
// app and cluser.
func NewFrenoThrottler(host, app, cluster string) *FrenoThrottler {
	frenoURL := &url.URL{
		Scheme: "http",
		Host:   host,
		Path:   strings.Join([]string{"check", app, "mysql", cluster}, "/"),
	}

	attributes := otelhttp.WithSpanOptions(trace.WithAttributes(attribute.String("peer.service", "freno")))
	// TODO(fatih): make client replaceable to allow us to set the timeouts
	return &FrenoThrottler{
		url:    frenoURL,
		client: &http.Client{Transport: otelhttp.NewTransport(http.DefaultTransport, attributes), Timeout: 30 * time.Second},
	}
}

// CanWrite makes a request to Freno and returns a boolean on whether we may
// make a request to the DB or not. An error by default will return false.
func (t *FrenoThrottler) CanWrite(ctx context.Context) (bool, error) {
	// Implementation details:
	// https://github.com/github/freno/blob/master/doc/clients.md
	req, err := http.NewRequestWithContext(ctx, http.MethodHead, t.url.String(), http.NoBody)
	if err != nil {
		return false, fmt.Errorf("failed to generate request: %w", err)
	}

	// Looks for X-GitHub-Request-Id in the incoming context and adds them to
	// Requst headers. It also sets the X-GLB-Via header, otherwise
	// X-GitHub-Request-Id will be stripped. This is needed so GLB doesn't
	// strip OpenTracing headers we inject below
	// For more information check out:
	// https://github.com/github/go-trace#connecting-traces-with-outgoing-requests
	requestid.Forward(req)

	resp, err := t.client.Do(req)
	if err != nil {
		return false, fmt.Errorf("failed to get HEAD: %w", err)
	}
	// The body should be read and closed to allow the connection to be reused
	// Source: https://pkg.go.dev/net/http#Client.Do
	_, _ = io.ReadAll(resp.Body)
	defer resp.Body.Close()

	return resp.StatusCode == http.StatusOK, nil
}

// WaitOnThrottler waits exponentially until the given throttler allows us to
// write or the context is canceled (typical use would be to pass a context with
// a timeout or deadline). The wait time between requests to the throttler is
// capped at 1s as that's how long the github/github code sleeps and we'd lose
// every time if we sleep too long. It returns an error if writing should not be
// done.
func WaitOnThrottler(ctx context.Context, t Throttler) error {
	st := time.Now()

	for tries := 0; ; tries++ {
		can, err := t.CanWrite(ctx)
		if can {
			return nil
		}

		sleepTime := time.Duration(math.Exp2(float64(tries))) * 20 * time.Millisecond
		if sleepTime > 1*time.Second {
			sleepTime = 1 * time.Second
		}
		select {
		case <-ctx.Done():
			if err != nil {
				return fmt.Errorf("error waiting on the throttler: %w", err)
			}
			return fmt.Errorf("throttler wait timeout: %w", &ErrTimeout{time.Since(st)})
		case <-time.After(sleepTime):
			continue
		}
	}
}

// Wait on the default throttler; see WaitOnThrottler.
func Wait(ctx context.Context) error {
	return WaitOnThrottler(ctx, DefaultThrottler)
}
