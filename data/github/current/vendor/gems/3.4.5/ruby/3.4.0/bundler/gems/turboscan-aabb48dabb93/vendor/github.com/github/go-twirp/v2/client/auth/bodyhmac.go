// Package auth provides HMAC signing for requests.
package auth

import (
	"bytes"
	"fmt"
	"io"
	"net/http"

	"github.com/github/go-auth/bodyhmac"
	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-twirp/v2/client"
)

// BodyHMACSigner implements the Twirp client interface and signs HTTP requests with a
// "body HMAC" for authenticating internal GitHub API requests.
// See https://github.com/github/go-auth/blob/main/bodyhmac/bodyhmac.go
// for details about how the message authentication code is calculated.
type BodyHMACSigner struct {
	secret string        // The key used to sign requests with HMAC.
	next   client.Client // the next Client used to make a request.
}

// NewBodyHMACSigner returns a new BodyHMACSigner that signs requests with the given secret.
func NewBodyHMACSigner(secret string, next client.Client) (*BodyHMACSigner, error) {
	if secret == "" {
		return nil, fmt.Errorf("secret is required")
	}

	if next == nil {
		return nil, fmt.Errorf("next Client is required")
	}

	return &BodyHMACSigner{secret: secret, next: next}, nil
}

// Do sends an HTTP request by adding a body HMAC header and returns an *http.Response or an error.
func (r *BodyHMACSigner) Do(req *http.Request) (*http.Response, error) {
	bodyBytes, err := io.ReadAll(req.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read request body: %w", err)
	}

	hmacHeaderVal, err := bodyhmac.CreateHeader(bodyBytes, []byte(r.secret))
	if err != nil {
		return nil, fmt.Errorf("failed to create body hmac header: %w", err)
	}
	req.Header.Add(headers.RequestBodyHMAC, hmacHeaderVal)

	// restore the request's body after using it to create the body HMAC header
	req.Body = io.NopCloser(bytes.NewReader(bodyBytes))

	return r.next.Do(req)
}
