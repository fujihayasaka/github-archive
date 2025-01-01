package headers

import (
	"net/http"
)

const (
	GitHubRequestID = "X-GitHub-Request-ID"
	GLBVia          = "X-GLB-Via"
	RequestHMAC     = "Request-HMAC" // For internal API authentication
	RequestBodyHMAC = "Request-Body-HMAC"
	Tenant          = "X-GitHub-Tenant"
)

// Headers is a middleware that writes a default set of headers to every
// outgoing request, including a "Server" header, and any amount of
// user-configured headers.
// By default, Go will automatically add Content-Length, Content-Type
// and Date headers.
type Headers struct {
	// ServerName will be written as the value for the "Server" header.
	ServerName string

	// Headers is a key-value map of user-supplied headers that will be
	// appended to all outgoing requests.
	Headers map[string]string
}

// Handler allows manual chaining of this middleware
func (m *Headers) Handler(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		for k, v := range m.Headers {
			h.Add(k, v)
		}

		h.Set("Server", m.ServerName)
		next.ServeHTTP(w, r)
	})
}
