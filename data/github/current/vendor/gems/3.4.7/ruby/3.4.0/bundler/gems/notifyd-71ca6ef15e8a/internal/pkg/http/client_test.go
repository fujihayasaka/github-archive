package http

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/stretchr/testify/require"
)

type safeCounter struct {
	mu  sync.Mutex
	val int
}

func (c *safeCounter) Inc() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.val++
}

func (c *safeCounter) Val() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.val
}

// withDefaultTestConfig sets the configuration on the client so that it is easy to test its
// behavior.
func withDefaultTestConfig(t *testing.T) Option {
	t.Helper()

	return func(c *clientConfig) {
		c.retryMax = 2
		c.retryTimeout = 3 * time.Millisecond
		c.retryWaitMax = 0
		c.retryWaitMin = 0
		c.logger = &leveledLoggerAdapter{log.NewNullLogger()}
	}
}

func Test_Retries(t *testing.T) {
	r := require.New(t)

	t.Run("when a retry succeeds", func(t *testing.T) {
		client := NewClient(withDefaultTestConfig(t))
		try := safeCounter{}
		srv := httptest.NewServer(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
			try.Inc()
			if try.Val() > 1 {
				rw.WriteHeader(http.StatusAccepted)
				return
			}

			rw.WriteHeader(http.StatusInternalServerError)
		}))
		defer srv.Close()

		ctx := context.Background()
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, srv.URL, http.NoBody)
		r.NoError(err)

		resp, err := client.Do(req)
		r.NoError(err, "it returns no error")
		defer resp.Body.Close()
		r.Equal(http.StatusAccepted, resp.StatusCode, "it has the status code from the successful retry")
		r.Equal(2, try.Val(), "it only uses a retry")
	})

	t.Run("when all retries fail", func(t *testing.T) {
		client := NewClient(withDefaultTestConfig(t))
		try := safeCounter{}
		srv := httptest.NewServer(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
			try.Inc()
			rw.WriteHeader(http.StatusInternalServerError)
		}))
		defer srv.Close()

		ctx := context.Background()
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, srv.URL, http.NoBody)
		r.NoError(err)

		resp, err := client.Do(req) //nolint:bodyclose // resp is nil
		r.Error(err, "it returns an error")
		r.Nil(resp, "it doesn't return a response")
		r.Equal(3, try.Val(), "it expires all the retries")
	})
}

func Test_RetryTimeout(t *testing.T) {
	r := require.New(t)

	t.Run("when a retry timeout expires", func(t *testing.T) {
		try := safeCounter{}
		client := NewClient(withDefaultTestConfig(t))
		srv := httptest.NewServer(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
			try.Inc()
			if try.Val() > 1 {
				rw.WriteHeader(http.StatusAccepted)

				return
			}

			time.Sleep(4 * time.Millisecond)
		}))
		defer srv.Close()

		ctx := context.Background()
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, srv.URL, http.NoBody)
		r.NoError(err)

		resp, err := client.Do(req)
		r.NoError(err, "the next timeout succeeds")
		defer resp.Body.Close()
		r.GreaterOrEqual(2, try.Val(), "it only consumes 1 timeout")
		r.Equal(http.StatusAccepted, resp.StatusCode, "the status is the one from the succeeding response")
	})
}

func Test_GlobalTimeout(t *testing.T) {
	r := require.New(t)

	t.Run("when the global timeout expires", func(t *testing.T) {
		client := NewClient(withDefaultTestConfig(t))
		srv := httptest.NewServer(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
			time.Sleep(4 * time.Millisecond)
		}))
		defer srv.Close()
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Millisecond)
		defer cancel()

		req, _ := http.NewRequestWithContext(ctx, http.MethodGet, srv.URL, http.NoBody)
		resp, err := client.Do(req) //nolint:bodyclose // resp is nil
		r.ErrorIs(err, context.DeadlineExceeded, "it returns a deadline exceeded error")
		r.Nil(resp, "it doesn't return a response")
	})
}

func Test_Options(t *testing.T) {
	r := require.New(t)

	t.Run("WithRetryTimeout", func(t *testing.T) {
		config := clientConfig{}
		config.applyOptions([]Option{WithRetryTimeout(time.Minute)})

		r.Equal(time.Minute, config.retryTimeout)
	})

	t.Run("WithLogger", func(t *testing.T) {
		config := clientConfig{}
		config.applyOptions([]Option{WithLogger(log.NewNullLogger())})

		r.NotNil(config.logger)
	})
}
