package auth

import (
	"fmt"
	"net/http"

	"github.com/github/go-auth/hmac"
	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-twirp/v2/client"
)

// RequestHMACSigner implements the Twirp client interface and signs HTTP requests with a
// "request HMAC" (which does not consider any content of the request) for
// authenticating internal GitHub API requests. See auth/hmac/requesthmac.go for
// details about how the message authentication code is calculated.
type RequestHMACSigner struct {
	secret string        // The key used to sign requests with HMAC.
	next   client.Client // the next Client used to make a request.
}

// NewRequestHMACSigner returns a new Client that signs outgoing requests or an error.
func NewRequestHMACSigner(secret string, next client.Client) (*RequestHMACSigner, error) {
	if secret == "" {
		return nil, fmt.Errorf("secret is required")
	}

	if next == nil {
		return nil, fmt.Errorf("next Client is required")
	}

	return &RequestHMACSigner{secret: secret, next: next}, nil
}

// Do sends an HTTP request by adding a signed HMAC header and returns an *http.Response or an error.
func (r *RequestHMACSigner) Do(req *http.Request) (*http.Response, error) {
	req.Header.Add(headers.RequestHMAC, hmac.NewRequestHMAC(r.secret).String())

	return r.next.Do(req)
}
