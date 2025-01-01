package muhttp

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"net/http"
)

// NewRequest wraps http.NewRequest adding the passed context to the request's
// context. Use this to tie an incoming request's context to this request. This
// allows the outbound request to be cancelled if the incoming request's
// context is cancelled.
func NewRequest(ctx context.Context, method, url string, body io.Reader) (*http.Request, error) {
	req, err := http.NewRequest(method, url, body)
	if err != nil {
		return req, err
	}

	req = req.WithContext(ctx)
	return req, nil
}

// NewSignedRequest creates a new request and signs it with the HMAC
// key, adding a Content-HMAC header. This requires reading the body
// into memory to generate the signature, so be aware of using this
// with large payloads.
func NewSignedRequest(ctx context.Context, method, urlStr, key string, body io.Reader) (*http.Request, error) {
	if body == nil {
		return nil, errors.New("signed request requires a body")
	}

	if len(key) == 0 {
		return nil, errors.New("signed request requires a key")
	}

	var buf bytes.Buffer
	reader := io.TeeReader(body, &buf)
	by, err := io.ReadAll(reader)
	if err != nil {
		return nil, err
	}

	mac := hmac.New(sha256.New, []byte(key))
	if _, err := mac.Write(by); err != nil {
		return nil, err
	}

	req, err := NewRequest(ctx, method, urlStr, io.NopCloser(bytes.NewBuffer(by)))
	if err != nil {
		return req, err
	}

	req.Header.Set("Content-HMAC", "sha256 "+hex.EncodeToString(mac.Sum(nil)))
	return req, nil
}
