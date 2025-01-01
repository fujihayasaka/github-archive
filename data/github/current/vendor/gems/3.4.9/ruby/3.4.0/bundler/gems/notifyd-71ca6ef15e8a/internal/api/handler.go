// Package api is top-level package containing API service implementations.
package api

import (
	"net/http"
)

// Handler describes an entity that has a path and an http.Handler.
type Handler interface {
	http.Handler
	PathPrefix() string
}
