// Package staffbar is for tracking and reporting timings to be displayed in the staffbar on dotcom
package staffbar

import (
	"net/http"
)

// Handler creates a middleware for tracking and reporting timings to be
// displayed in the staffbar on dotcom.
func Handler(next http.Handler) http.Handler {
	fn := func(w http.ResponseWriter, r *http.Request) {
		includeTimings := r.Header.Get("X-GitHub-Staffbar-Include-Timings") != "" //nolint:canonicalheader // Will changing the casing of the header like the linter wants break something?
		if !includeTimings {
			next.ServeHTTP(w, r)
			return
		}

		queryReporter := &QueryReporter{}
		r = r.WithContext(queryReporter.newContext(r.Context()))
		rw := responseWrapper{ResponseWriter: w, queryReporter: queryReporter}
		next.ServeHTTP(&rw, r)
	}
	return http.HandlerFunc(fn)
}

type responseWrapper struct {
	http.ResponseWriter
	queryReporter *QueryReporter
}

func (rw *responseWrapper) WriteHeader(code int) {
	payload := rw.queryReporter.ToPayload()
	if payload != "" {
		rw.ResponseWriter.Header().Set("X-GitHub-Staffbar-Timings", payload) //nolint:canonicalheader // Will changing the casing of the header like the linter wants break something?
	}
	rw.ResponseWriter.WriteHeader(code)
}
