/*
Package okta works with okta-network-gateway hmac checks as described in
https://github.com/github/okta-network-gateway/blob/600b228/docs/hmac.md.
*/
package okta

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"time"
)

const (
	timestampHeader = "X-Ong-Hmac-Timestamp"
	tokenHeader     = "X-Ong-Hmac-Token" //nolint:gosec //this is not a hardcoded credential
	usernameHeader  = "X-Okta-Username"
)

// ValidateHMACOptions options for ValidateHMAC
type ValidateHMACOptions struct {
	MaxTimestampAge time.Duration // Oldest allowed timestamp header.  Default 5 seconds.
	MaxClockDrift   time.Duration // Maximum allowed clock drift when validating the timestamp header.  Default 1 second.
}

var defaultValidateOptions = &ValidateHMACOptions{
	MaxTimestampAge: 5 * time.Second,
	MaxClockDrift:   time.Second,
}

// ValidateHMAC validates that the okta hmac header is correct for the given secret
func ValidateHMAC(req *http.Request, hmacSecret []byte, opts *ValidateHMACOptions) error {
	if opts == nil {
		opts = defaultValidateOptions
	}
	if req == nil {
		return fmt.Errorf("nil request")
	}
	username := req.Header.Get(usernameHeader)
	if username == "" {
		return fmt.Errorf("missing header %q", usernameHeader)
	}
	token := req.Header.Get(tokenHeader)
	if token == "" {
		return fmt.Errorf("missing header %q", tokenHeader)
	}
	hexToken, err := hex.DecodeString(token)
	if err != nil {
		return fmt.Errorf("invalid hmac")
	}
	timestamp := req.Header.Get(timestampHeader)
	if timestamp == "" {
		return fmt.Errorf("missing header %q", timestampHeader)
	}
	err = validateRecentTimestamp(timestamp, opts.MaxTimestampAge, opts.MaxClockDrift)
	if err != nil {
		return err
	}
	expectToken := createToken(hmacSecret, username, req.URL.RequestURI(), timestamp)
	if !hmac.Equal(expectToken, hexToken) {
		return fmt.Errorf("invalid hmac")
	}
	return nil
}

func validateRecentTimestamp(timestamp string, maxAge, maxDrift time.Duration) error {
	tm, err := time.ParseInLocation(time.RFC3339, timestamp, time.UTC)
	if err != nil {
		return fmt.Errorf("invalid timestamp")
	}
	since := time.Since(tm)
	if since > maxAge+maxDrift {
		return fmt.Errorf("timestamp too old")
	}
	if (-since) > maxDrift {
		return fmt.Errorf("timestamp in the future")
	}
	return nil
}

type CtxKey struct{}

// GetUsername returns the okta username from a request context. Responds with an empty string if the username is not set.
func GetUsername(ctx context.Context) (username string, ok bool) {
	val := ctx.Value(CtxKey{})
	if val == nil {
		return "", false
	}
	return val.(string), true
}

type middleware struct {
	hmacSecret          []byte
	validateHMACOptions *ValidateHMACOptions
	next                http.Handler
}

// Middleware returns an http middleware that will add the okta username to the request context if the username header
// is set and the hmac header is valid. If the username header isn't set, or if the hmac header is invalid, the username
// simply isn't added to the context.
func Middleware(hmacSecret []byte, opts *ValidateHMACOptions, next http.Handler) http.Handler {
	return &middleware{
		validateHMACOptions: opts,
		hmacSecret:          hmacSecret,
		next:                next,
	}
}

func (c *middleware) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	if !hasUsernameHeader(req) {
		c.next.ServeHTTP(w, req)
		return
	}
	err := ValidateHMAC(req, c.hmacSecret, c.validateHMACOptions)
	if err != nil {
		c.next.ServeHTTP(w, req)
		return
	}
	username := req.Header.Get(usernameHeader)
	req = req.Clone(context.WithValue(req.Context(), CtxKey{}, username))
	c.next.ServeHTTP(w, req)
}

func createToken(key []byte, username, uri, timestamp string) []byte {
	mac := hmac.New(sha256.New, key)
	_, err := mac.Write([]byte(username + "|" + uri + "|" + timestamp))
	_ = err
	return mac.Sum(nil)
}

func hasUsernameHeader(req *http.Request) bool {
	_, ok := req.Header[usernameHeader]
	return ok
}

// RoundTripper returns an http.RoundTripper that adds an okta username and valid hmac to a request
func RoundTripper(username string, secret []byte, transport http.RoundTripper) http.RoundTripper {
	return &roundTripper{
		username:  username,
		secret:    secret,
		transport: transport,
	}
}

type roundTripper struct {
	username  string
	secret    []byte
	transport http.RoundTripper
}

func (r *roundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	transport := r.transport
	if transport == nil {
		transport = http.DefaultTransport
	}
	timestamp := time.Now().UTC().Format(time.RFC3339)
	token := createToken(r.secret, r.username, req.URL.RequestURI(), timestamp)
	req.Header.Set(timestampHeader, timestamp)
	req.Header.Set(usernameHeader, r.username)
	req.Header.Set(tokenHeader, hex.EncodeToString(token))

	response, err := transport.RoundTrip(req)

	if err != nil {
		return nil, fmt.Errorf("Error: %w", err)
	}

	return response, nil
}
