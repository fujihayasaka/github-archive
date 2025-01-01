package middleware

import (
	"net/http"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/go-auth/hmac"
	"github.com/github/go-http/v2/middleware/headers"
)

type hmacMiddleware struct {
	delegate   pb.HTTPClient
	hmac       string
	isRawValue bool
}

// ApplyHMAC wraps an HTTP client with middleware
// that sets the "Request-HMAC" header in each request
// HMAC is a raw HMAC string that will be applied directly as the header value.
func ApplyHMAC(c pb.HTTPClient, HMAC string) pb.HTTPClient {
	return &hmacMiddleware{
		delegate:   c,
		hmac:       HMAC,
		isRawValue: true,
	}
}

// ApplyHMACKey wraps an HTTP client with middleware
// that sets the "Request-HMAC" header in each request
// HMACKey is a HMAC secret key
// Each request generates a new HMAC using the provided HMAC Key.
func ApplyHMACKey(c pb.HTTPClient, HMACKey string) pb.HTTPClient {
	return &hmacMiddleware{
		delegate:   c,
		hmac:       HMACKey,
		isRawValue: false,
	}
}

func (m *hmacMiddleware) Do(req *http.Request) (*http.Response, error) {
	hmacValue := m.hmac
	if !m.isRawValue {
		hmacValue = hmac.NewRequestHMAC(hmacValue).String()
	}
	req.Header.Set(headers.RequestHMAC, hmacValue)
	return m.delegate.Do(req)
}
