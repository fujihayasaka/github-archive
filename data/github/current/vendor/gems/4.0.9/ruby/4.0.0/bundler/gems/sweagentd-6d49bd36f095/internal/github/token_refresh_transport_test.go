package github

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// roundTripFunc adapts a function to the http.RoundTripper interface.
type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) {
	return f(req)
}

func TestTokenRefreshTransport(t *testing.T) {
	t.Run("retries once on 401 with new token", func(t *testing.T) {
		var calls int32
		base := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			n := atomic.AddInt32(&calls, 1)
			if n == 1 {
				require.Equal(t, "Bearer old-token", req.Header.Get("Authorization"))
				return &http.Response{
					StatusCode: http.StatusUnauthorized,
					Body:       io.NopCloser(bytes.NewReader(nil)),
				}, nil
			}
			require.Equal(t, "Bearer new-token", req.Header.Get("Authorization"))
			return &http.Response{
				StatusCode: http.StatusOK,
				Body:       io.NopCloser(bytes.NewReader(nil)),
			}, nil
		})

		refreshCalls := 0
		transport := &tokenRefreshTransport{
			base: base,
			refreshToken: func(context.Context) (string, error) {
				refreshCalls++
				return "new-token", nil
			},
		}

		req, err := http.NewRequest("GET", "https://api.github.com/repos/foo/bar", nil)
		require.NoError(t, err)
		req.Header.Set("Authorization", "Bearer old-token")

		resp, err := transport.RoundTrip(req)
		require.NoError(t, err)
		require.Equal(t, http.StatusOK, resp.StatusCode)
		require.Equal(t, int32(2), atomic.LoadInt32(&calls))
		require.Equal(t, 1, refreshCalls)
	})

	t.Run("preserves token prefix for REST", func(t *testing.T) {
		var calls int32
		base := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			n := atomic.AddInt32(&calls, 1)
			if n == 1 {
				return &http.Response{
					StatusCode: http.StatusUnauthorized,
					Body:       io.NopCloser(bytes.NewReader(nil)),
				}, nil
			}
			require.Equal(t, "token fresh-token", req.Header.Get("Authorization"))
			return &http.Response{
				StatusCode: http.StatusOK,
				Body:       io.NopCloser(bytes.NewReader(nil)),
			}, nil
		})

		tokenSrc := newRefreshableTokenSource("old-token")
		transport := &tokenRefreshTransport{
			base:         base,
			currentToken: tokenSrc.Current,
			refreshToken: func(context.Context) (string, error) {
				tokenSrc.Update("fresh-token")
				return "fresh-token", nil
			},
		}

		req, err := http.NewRequest("GET", "https://api.github.com/repos/foo/bar", nil)
		require.NoError(t, err)
		req.Header.Set("Authorization", "token old-token")

		resp, err := transport.RoundTrip(req)
		require.NoError(t, err)
		require.Equal(t, http.StatusOK, resp.StatusCode)
	})

	t.Run("uses latest token on each request", func(t *testing.T) {
		var calls int32
		tokenSrc := newRefreshableTokenSource("old-token")
		base := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			n := atomic.AddInt32(&calls, 1)
			auth := req.Header.Get("Authorization")
			switch n {
			case 1:
				require.Equal(t, "token old-token", auth)
				return &http.Response{
					StatusCode: http.StatusUnauthorized,
					Body:       io.NopCloser(bytes.NewReader(nil)),
				}, nil
			case 2:
				require.Equal(t, "token new-token", auth)
				return &http.Response{
					StatusCode: http.StatusOK,
					Body:       io.NopCloser(bytes.NewReader(nil)),
				}, nil
			case 3:
				require.Equal(t, "token new-token", auth)
				return &http.Response{
					StatusCode: http.StatusOK,
					Body:       io.NopCloser(bytes.NewReader(nil)),
				}, nil
			default:
				t.Fatalf("unexpected call %d", n)
				return nil, nil
			}
		})

		transport := &tokenRefreshTransport{
			base:         base,
			currentToken: tokenSrc.Current,
			refreshToken: func(context.Context) (string, error) {
				tokenSrc.Update("new-token")
				return "new-token", nil
			},
		}

		req, err := http.NewRequest("GET", "https://api.github.com/repos/foo/bar", nil)
		require.NoError(t, err)
		req.Header.Set("Authorization", "token old-token")

		resp, err := transport.RoundTrip(req)
		require.NoError(t, err)
		require.Equal(t, http.StatusOK, resp.StatusCode)

		resp, err = transport.RoundTrip(req)
		require.NoError(t, err)
		require.Equal(t, http.StatusOK, resp.StatusCode)
	})

	t.Run("does not retry on non-401 errors", func(t *testing.T) {
		var calls int32
		base := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			atomic.AddInt32(&calls, 1)
			return &http.Response{
				StatusCode: http.StatusForbidden,
				Body:       io.NopCloser(bytes.NewReader(nil)),
			}, nil
		})

		refreshCalls := 0
		transport := &tokenRefreshTransport{
			base: base,
			refreshToken: func(context.Context) (string, error) {
				refreshCalls++
				return "new-token", nil
			},
		}

		req, err := http.NewRequest("GET", "https://api.github.com/repos/foo/bar", nil)
		require.NoError(t, err)

		resp, err := transport.RoundTrip(req)
		require.NoError(t, err)
		require.Equal(t, http.StatusForbidden, resp.StatusCode)
		require.Equal(t, int32(1), atomic.LoadInt32(&calls))
		require.Equal(t, 0, refreshCalls)
	})

	t.Run("retries refresh after earlier refresh failure", func(t *testing.T) {
		var calls int32
		base := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			n := atomic.AddInt32(&calls, 1)
			if n == 1 || n == 2 {
				return &http.Response{
					StatusCode: http.StatusUnauthorized,
					Body:       io.NopCloser(bytes.NewReader(nil)),
				}, nil
			}
			require.Equal(t, "Bearer fresh-token", req.Header.Get("Authorization"))
			return &http.Response{
				StatusCode: http.StatusOK,
				Body:       io.NopCloser(bytes.NewReader(nil)),
			}, nil
		})

		refreshCalls := 0
		transport := &tokenRefreshTransport{
			base: base,
			refreshToken: func(context.Context) (string, error) {
				refreshCalls++
				if refreshCalls == 1 {
					return "", io.ErrUnexpectedEOF
				}
				return "fresh-token", nil
			},
		}

		req, err := http.NewRequest("GET", "https://api.github.com/repos/foo/bar", nil)
		require.NoError(t, err)
		req.Header.Set("Authorization", "Bearer old-token")

		resp, err := transport.RoundTrip(req)
		require.NoError(t, err)
		require.Equal(t, http.StatusUnauthorized, resp.StatusCode)

		resp, err = transport.RoundTrip(req)
		require.NoError(t, err)
		require.Equal(t, http.StatusOK, resp.StatusCode)
		require.Equal(t, 2, refreshCalls)
	})

	t.Run("passes request context to refresh function", func(t *testing.T) {
		base := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: http.StatusUnauthorized,
				Body:       io.NopCloser(bytes.NewReader(nil)),
			}, nil
		})

		type ctxKeyType string
		ctxKey := ctxKeyType("refresh-key")
		transport := &tokenRefreshTransport{
			base: base,
			refreshToken: func(ctx context.Context) (string, error) {
				require.Equal(t, "refresh-value", ctx.Value(ctxKey))
				return "new-token", nil
			},
		}

		ctx := context.WithValue(context.Background(), ctxKey, "refresh-value")
		req, err := http.NewRequestWithContext(ctx, "GET", "https://api.github.com/repos/foo/bar", nil)
		require.NoError(t, err)

		_, err = transport.RoundTrip(req)
		require.NoError(t, err)
	})

	t.Run("replays request body on retry", func(t *testing.T) {
		var calls int32
		base := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			n := atomic.AddInt32(&calls, 1)
			body, bodyErr := io.ReadAll(req.Body)
			require.NoError(t, bodyErr)
			require.Equal(t, `{"test":true}`, string(body))
			if n == 1 {
				return &http.Response{
					StatusCode: http.StatusUnauthorized,
					Body:       io.NopCloser(bytes.NewReader(nil)),
				}, nil
			}
			return &http.Response{
				StatusCode: http.StatusOK,
				Body:       io.NopCloser(bytes.NewReader(nil)),
			}, nil
		})

		transport := &tokenRefreshTransport{
			base: base,
			refreshToken: func(context.Context) (string, error) {
				return "new-token", nil
			},
		}

		bodyBytes := []byte(`{"test":true}`)
		req, err := http.NewRequest("POST", "https://api.github.com/repos/foo/bar", bytes.NewReader(bodyBytes))
		require.NoError(t, err)
		req.GetBody = func() (io.ReadCloser, error) {
			return io.NopCloser(bytes.NewReader(bodyBytes)), nil
		}
		req.Header.Set("Authorization", "Bearer old-token")

		resp, err := transport.RoundTrip(req)
		require.NoError(t, err)
		require.Equal(t, http.StatusOK, resp.StatusCode)
		require.Equal(t, int32(2), atomic.LoadInt32(&calls))
	})

	t.Run("skips retry when body cannot be replayed", func(t *testing.T) {
		base := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			_, _ = io.ReadAll(req.Body) // consume body
			return &http.Response{
				StatusCode: http.StatusUnauthorized,
				Body:       io.NopCloser(bytes.NewReader(nil)),
			}, nil
		})

		transport := &tokenRefreshTransport{
			base: base,
			refreshToken: func(context.Context) (string, error) {
				return "new-token", nil
			},
		}

		req, err := http.NewRequest("POST", "https://api.github.com/repos/foo/bar", bytes.NewReader([]byte("data")))
		require.NoError(t, err)
		req.GetBody = nil
		req.Header.Set("Authorization", "Bearer old-token")

		resp, err := transport.RoundTrip(req)
		require.NoError(t, err)
		require.Equal(t, http.StatusUnauthorized, resp.StatusCode)
	})
}

func TestRefreshableTokenSource(t *testing.T) {
	src := newRefreshableTokenSource("initial")

	tok, err := src.Token()
	require.NoError(t, err)
	require.Equal(t, "initial", tok.AccessToken)
	require.Equal(t, "initial", src.Current())

	src.Update("refreshed")

	tok, err = src.Token()
	require.NoError(t, err)
	require.Equal(t, "refreshed", tok.AccessToken)
	require.Equal(t, "refreshed", src.Current())
}

func TestTokenRefreshTransportConcurrentWithCoordinator(t *testing.T) {
	coord := newTokenRefreshCoordinator()
	tokenSrc := newRefreshableTokenSource("old-token")
	refreshStarted := make(chan struct{})
	releaseRefresh := make(chan struct{})
	var refreshCalls int32
	var oldTokenCalls int32
	var newTokenCalls int32

	base := roundTripFunc(func(req *http.Request) (*http.Response, error) {
		auth := req.Header.Get("Authorization")
		if auth == "Bearer old-token" {
			atomic.AddInt32(&oldTokenCalls, 1)
			return &http.Response{
				StatusCode: http.StatusUnauthorized,
				Body:       io.NopCloser(bytes.NewReader(nil)),
			}, nil
		}
		require.Equal(t, "Bearer new-token", auth)
		atomic.AddInt32(&newTokenCalls, 1)
		return &http.Response{
			StatusCode: http.StatusOK,
			Body:       io.NopCloser(bytes.NewReader(nil)),
		}, nil
	})

	coordinatedRefresh := func(ctx context.Context) (string, error) {
		return coord.Refresh(ctx, "test-key", func(refreshCtx context.Context) (string, error) {
			if atomic.AddInt32(&refreshCalls, 1) == 1 {
				close(refreshStarted)
			}
			<-releaseRefresh
			tokenSrc.Update("new-token")
			return "new-token", nil
		})
	}

	// Two separate transports (simulating REST and GraphQL) sharing the coordinator
	transport1 := &tokenRefreshTransport{
		base:         base,
		currentToken: tokenSrc.Current,
		refreshToken: coordinatedRefresh,
	}
	transport2 := &tokenRefreshTransport{
		base:         base,
		currentToken: tokenSrc.Current,
		refreshToken: coordinatedRefresh,
	}

	req1, err := http.NewRequest("GET", "https://api.github.com/repos/foo/bar", nil)
	require.NoError(t, err)
	req1.Header.Set("Authorization", "Bearer old-token")
	req2, err := http.NewRequest("GET", "https://api.github.com/repos/foo/bar", nil)
	require.NoError(t, err)
	req2.Header.Set("Authorization", "Bearer old-token")

	result1 := make(chan *http.Response, 1)
	result2 := make(chan *http.Response, 1)

	go func() {
		resp, _ := transport1.RoundTrip(req1)
		result1 <- resp
	}()

	<-refreshStarted

	go func() {
		resp, _ := transport2.RoundTrip(req2)
		result2 <- resp
	}()

	// Give second goroutine time to enter the coordinator
	time.Sleep(10 * time.Millisecond)
	close(releaseRefresh)

	resp := <-result1
	require.Equal(t, http.StatusOK, resp.StatusCode)
	resp = <-result2
	require.Equal(t, http.StatusOK, resp.StatusCode)

	// Only one actual refresh should have occurred
	require.Equal(t, int32(1), atomic.LoadInt32(&refreshCalls))
	require.Equal(t, int32(2), atomic.LoadInt32(&newTokenCalls))
}
