package github

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestTransportRetryBehavior(t *testing.T) {
	tests := []struct {
		name               string
		useRetry           bool
		failuresBeforeOK   int // number of 500s before returning 200; -1 means always fail
		failureStatusCode  int
		expectedCallCount  int32
		expectedStatusCode int
	}{
		{
			name:               "retries on 500 with retryable endpoint",
			useRetry:           true,
			failuresBeforeOK:   1,
			failureStatusCode:  http.StatusInternalServerError,
			expectedCallCount:  2,
			expectedStatusCode: http.StatusOK,
		},
		{
			name:               "no retry on 500 without retryable endpoint",
			useRetry:           false,
			failuresBeforeOK:   -1,
			failureStatusCode:  http.StatusInternalServerError,
			expectedCallCount:  1,
			expectedStatusCode: http.StatusInternalServerError,
		},
		{
			name:               "no retry on non-500 errors",
			useRetry:           true,
			failuresBeforeOK:   -1,
			failureStatusCode:  http.StatusNotFound,
			expectedCallCount:  1,
			expectedStatusCode: http.StatusNotFound,
		},
		{
			name:               "retry eventually succeeds after multiple failures",
			useRetry:           true,
			failuresBeforeOK:   2,
			failureStatusCode:  http.StatusInternalServerError,
			expectedCallCount:  3,
			expectedStatusCode: http.StatusOK,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var callCount atomic.Int32

			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				count := callCount.Add(1)
				if tc.failuresBeforeOK == -1 || int(count) <= tc.failuresBeforeOK {
					w.WriteHeader(tc.failureStatusCode)
					w.Write([]byte(`{"message": "error"}`))
				} else {
					w.WriteHeader(http.StatusOK)
					w.Write([]byte(`{"status": "ok"}`))
				}
			}))
			defer ts.Close()

			ctx := context.Background()
			if tc.useRetry {
				ctx = withRetryableEndpoint(ctx)
			}

			target := sweagentd.ClientTargetForApp(0)
			lim := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
			rt := ClientTransport(http.DefaultTransport, observability.NewNoopExporters(), lim, target, "github-app")

			req, err := http.NewRequestWithContext(ctx, http.MethodGet, ts.URL+"/test", http.NoBody)
			require.NoError(t, err)

			resp, err := rt.RoundTrip(req)
			require.NoError(t, err)
			defer resp.Body.Close()

			assert.Equal(t, tc.expectedCallCount, callCount.Load())
			assert.Equal(t, tc.expectedStatusCode, resp.StatusCode)
		})
	}
}
