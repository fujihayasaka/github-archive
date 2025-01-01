package middleware

import (
	"fmt"
	"net/http"

	pb "github.com/github/authnd/client/proto/authentication/v0"
)

type userAgentMiddleware struct {
	delegate  pb.HTTPClient
	userAgent string
}

// ApplyUserAgent wraps an HTTP client with middleware
// that sets the "User-Agent" header in requests
// uses the provided clientVersion to derive the value.
func ApplyUserAgent(c pb.HTTPClient, clientVersion string) pb.HTTPClient {
	return &userAgentMiddleware{
		delegate:  c,
		userAgent: fmt.Sprintf("authnd-go/%s", clientVersion),
	}
}

func (m *userAgentMiddleware) Do(req *http.Request) (*http.Response, error) {
	req.Header.Set("User-Agent", m.userAgent)
	return m.delegate.Do(req)
}
