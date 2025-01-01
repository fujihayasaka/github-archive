package launchhttp

import "net/http"

// Client is an interface that aligns with http.Client from the standard library.
type Client interface {
	Do(*http.Request) (*http.Response, error)
}
