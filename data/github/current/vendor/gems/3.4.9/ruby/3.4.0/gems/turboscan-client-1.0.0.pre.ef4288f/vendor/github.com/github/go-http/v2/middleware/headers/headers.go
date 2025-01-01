// Package headers provides middleware that writes a default set of headers to every outgoing request.
package headers

import (
	"net/http"
)

const (
	// GitHubRequestID is the X-GitHub-Request-ID header key.
	GitHubRequestID = "X-GitHub-Request-ID"
	// GLBVia is the X-GLB-Via header key.
	GLBVia = "X-GLB-Via"
	// ONGHMACTimestamp is the X-ONG-Hmac-Timestamp header key.
	ONGHMACTimestamp = "X-ONG-Hmac-Timestamp"
	// ONGHMACToken is the X-ONG-Hmac-Token header key.
	ONGHMACToken = "X-ONG-Hmac-Token" //nolint:gosec // not a credential, just header name
	// OktaUsername is the X-Okta-Username header key.
	OktaUsername = "X-Okta-Username"
	// RequestHMAC is the Request-HMAC header key.
	RequestHMAC = "Request-HMAC" // For internal API authentication
	// RequestBodyHMAC is the Request-Body-HMAC header key.
	RequestBodyHMAC = "Request-Body-HMAC"
	// Tenant is the X-GithHub-Tenant header key.
	Tenant = "X-GitHub-Tenant"
	// TenantID is the X-GithHub-Tenant-ID header key that identifies Proxima customers.
	TenantID = "X-GitHub-Tenant-ID"
	// StaffHeader is the X-GitHub-Staff header key.
	StaffHeader = "X-GitHub-Staff"
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

// Handler allows manual chaining of this middleware.
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
