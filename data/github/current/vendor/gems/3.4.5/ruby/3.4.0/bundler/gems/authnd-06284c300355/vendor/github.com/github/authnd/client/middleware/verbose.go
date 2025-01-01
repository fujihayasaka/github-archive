package middleware

import (
	"log"
	"net/http"

	pb "github.com/github/authnd/client/proto/authentication/v0"
)

type verboseLoggingHTTPClientMiddleware struct {
	delegate pb.HTTPClient
	logger   *log.Logger
}

// ApplyVerboseLoggingHTTPClient wraps the provided http client to log
// HTTP response code and headers for each request.  Should only be used
// debugging and local development.  Should NEVER be used in production.
func ApplyVerboseLoggingHTTPClient(c pb.HTTPClient, logger *log.Logger) pb.HTTPClient {
	return &verboseLoggingHTTPClientMiddleware{
		delegate: c,
		logger:   logger,
	}
}

func (m *verboseLoggingHTTPClientMiddleware) Do(req *http.Request) (*http.Response, error) {
	resp, err := m.delegate.Do(req)
	if err == nil {
		// log http response status and request headers
		m.logger.Printf("[DEBUG] %s %s", req.Proto, resp.Status)
		for k, vs := range resp.Header {
			for _, v := range vs {
				m.logger.Printf("[DEBUG] %s: %s", k, v)
			}
		}
	}

	return resp, err
}
