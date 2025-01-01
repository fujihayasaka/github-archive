package launchhttp

import "net/http"

// RequestMiddleware is like http.RoundTripper, but scoped to a single http request serviced by *Client.Do
type RequestMiddleware interface {
	Do(*http.Request) (*http.Response, error)
}
