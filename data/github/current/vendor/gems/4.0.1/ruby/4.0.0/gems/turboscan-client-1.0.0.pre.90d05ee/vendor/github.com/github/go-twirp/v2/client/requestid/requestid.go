// Package requestid provides Twirp middleware that forwards the GitHub Request ID, if it can be found in the context.
package requestid

import (
	"net/http"

	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-twirp/v2/client"
)

// NewForwarder returns a Twirp client that forwards the GitHub Request ID, if it can be found in the context.
func NewForwarder(next client.Client) *Forwarder {
	return &Forwarder{next: next}
}

// Forwarder provides a client that executes a request after adding the GitHub Request ID as a header.
type Forwarder struct {
	next client.Client // the next Client used to make a request
}

// Do executes a request after adding the GitHub Request ID as a header.
func (r *Forwarder) Do(req *http.Request) (*http.Response, error) {
	requestid.Forward(req)

	return r.next.Do(req)
}
