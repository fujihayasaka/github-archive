package dependencies

import (
	"errors"
	"net/http"

	"github.com/github/go-http/middleware/headers"
	"github.com/github/go-twirp/client"
)

// RequestHMACClient implements the Twirp client interface and signs HTTP requests with a
// "request HMAC" header.
type RequestHMACClient struct {
	hmacKey string        // The key used to make requests with HMAC.
	next    client.Client // the next Client used to make a request.
}

// NewRequestHMACClient returns a new Client that signs outgoing requests or an error.
func NewRequestHMACClient(hmacKey string, next client.Client) (*RequestHMACClient, error) {
	if hmacKey == "" {
		return nil, errors.New("hmacKey is required")
	}

	return &RequestHMACClient{hmacKey: hmacKey, next: next}, nil
}

// Do sends an HTTP request by adding a signed HMAC header and returns an *http.Response or an error.
func (r *RequestHMACClient) Do(req *http.Request) (*http.Response, error) {
	req.Header.Add(headers.RequestHMAC, r.hmacKey)

	return r.next.Do(req)
}
