// Package http provides middleware and configuration for http clients.
package http

import (
	"fmt"
	net_http "net/http"

	"github.com/github/feature-management-client-go/vexi/v2/version"
	"github.com/github/go-auth/hmac"
)

// Client enables the creation of middlewares around *(net/http).Client.
type Client interface {
	Do(req *net_http.Request) (*net_http.Response, error)
}

// WithHMACSignature sets the Request-HMAC header with a token generated from the provided secret.
func WithHMACSignature(c Client, secret string) Client {
	return httpClientFunc(func(r *net_http.Request) (*net_http.Response, error) {
		hmacToken := hmac.NewRequestHMAC(secret).String()
		r.Header.Set("Request-Hmac", hmacToken)
		return c.Do(r)
	})
}

// WithGitHubUser sets the X-GitHub-User header with the provided value.
func WithGitHubUser(c Client, user string) Client {
	return httpClientFunc(func(r *net_http.Request) (*net_http.Response, error) {
		r.Header.Set("X-Github-User", user)
		return c.Do(r)
	})
}

// WithVexiVersion sets the User-Agent with the vexi-go/{VERSION}.
func WithVexiVersion(c Client) Client {
	return httpClientFunc(func(r *net_http.Request) (*net_http.Response, error) {
		r.Header.Set("User-Agent", fmt.Sprintf("vexi-go/%s", version.Version))
		return c.Do(r)
	})
}

type httpClientFunc func(req *net_http.Request) (*net_http.Response, error)

func (h httpClientFunc) Do(req *net_http.Request) (*net_http.Response, error) {
	return h(req)
}
