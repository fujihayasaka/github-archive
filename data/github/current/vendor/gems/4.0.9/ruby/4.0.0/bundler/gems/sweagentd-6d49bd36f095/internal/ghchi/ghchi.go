// Package ghchi provides helpers for interacting with requests that use chi routing.
// The implementation in this file is in line with the suggestion here: https://github.com/go-chi/chi/issues/270
package ghchi

import (
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
)

// Route returns the route pattern from the chi context on the request.
// It replaces {param} with :param for compatibility with datadog.
// If the route context is not available, it return "unknownroute".
// An example chi route pattern is "/github/chat/{user_id}/threads".
// A request URL would come in as "/github/chat/12345/threads".
// The resulting string from this method would be "/github/chat/:user_id/threads".
func Route(r *http.Request) string {
	rctx := chi.RouteContext(r.Context())
	if rctx == nil || rctx.Routes == nil {
		// This can happen if the request is not routed through chi, or chi is not configured.
		return "unknownroute"
	}

	var routePattern string
	if routePattern = rctx.RoutePattern(); routePattern == "" {
		route := r.URL.Path
		if r.URL.RawPath != "" {
			route = r.URL.RawPath
		}

		tctx := chi.NewRouteContext()
		if rctx.Routes.Match(tctx, r.Method, route) {
			// tctx has the updated pattern, since Match mutates it
			routePattern = tctx.RoutePattern()
		} else {
			routePattern = "unknownroute" // we don't expect this to happen
		}
	}

	// Replace { and } with : because Datadog doesn't like them.
	// Before: /github/chat/{user_id}/threads
	// After:  /github/chat/:user_id/threads
	routePattern = strings.ReplaceAll(routePattern, "{", ":")
	routePattern = strings.ReplaceAll(routePattern, "}", "")

	return routePattern
}
