package github

import (
	"context"
	"io"
	"net/http"
	"strings"
	"sync"

	"golang.org/x/oauth2"
)

// tokenRefreshFunc invalidates the stale cached token, mints a fresh one,
// and returns it. It is called by tokenRefreshTransport on HTTP 401.
type tokenRefreshFunc func(ctx context.Context) (string, error)

// tokenRefreshTransport wraps an http.RoundTripper to transparently retry
// a request once when the server returns HTTP 401 Unauthorized. This handles
// stale cached installation tokens (e.g., after a GitHub App reinstall).
//
// On a 401 response, the transport:
//  1. Calls refreshToken to invalidate the cache and mint a fresh token
//  2. Clones the original request with the new Authorization header
//  3. Retries the request once through the base transport
//
// Coordination across multiple transports sharing the same cache key is handled
// by the tokenRefreshCoordinator in the refreshToken closure, not by this type.
type tokenRefreshTransport struct {
	base         http.RoundTripper
	refreshToken tokenRefreshFunc
	currentToken func() string
}

func (t *tokenRefreshTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	reqWithLatestToken := req.Clone(req.Context())
	if t.currentToken != nil {
		t.applyAuthHeader(reqWithLatestToken, reqWithLatestToken.Header.Get("Authorization"), t.currentToken())
	}

	resp, err := t.base.RoundTrip(reqWithLatestToken)
	if err != nil {
		return resp, err
	}
	if resp.StatusCode != http.StatusUnauthorized {
		return resp, nil
	}

	newToken, refreshErr := t.refreshToken(req.Context())
	if refreshErr != nil {
		return resp, nil
	}

	// Clone request and replace the Authorization header with the new token.
	retryReq := req.Clone(req.Context())
	t.applyAuthHeader(retryReq, reqWithLatestToken.Header.Get("Authorization"), newToken)

	// Replay request body if present.
	if req.Body != nil {
		if req.GetBody == nil {
			// Body was consumed and can't be replayed; return original 401.
			return resp, nil
		}
		body, bodyErr := req.GetBody()
		if bodyErr != nil {
			return resp, nil
		}
		retryReq.Body = body
	}

	// Drain and close the original response body to reuse the connection.
	if resp.Body != nil {
		_, _ = io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
	}

	return t.base.RoundTrip(retryReq)
}

func (t *tokenRefreshTransport) applyAuthHeader(req *http.Request, currentHeader, token string) {
	if strings.HasPrefix(currentHeader, "token ") {
		req.Header.Set("Authorization", "token "+token)
		return
	}
	req.Header.Set("Authorization", "Bearer "+token)
}

// refreshableTokenSource is an oauth2.TokenSource whose token can be swapped
// after construction. GraphQL clients use this so that when a 401 triggers a
// token refresh, the oauth2 transport picks up the new token on retry.
type refreshableTokenSource struct {
	mu    sync.RWMutex
	token string
}

func newRefreshableTokenSource(token string) *refreshableTokenSource {
	return &refreshableTokenSource{token: token}
}

// Token implements oauth2.TokenSource.
func (s *refreshableTokenSource) Token() (*oauth2.Token, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return &oauth2.Token{AccessToken: s.token}, nil
}

// Update replaces the stored token with a fresh one.
func (s *refreshableTokenSource) Update(token string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.token = token
}

func (s *refreshableTokenSource) Current() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.token
}
