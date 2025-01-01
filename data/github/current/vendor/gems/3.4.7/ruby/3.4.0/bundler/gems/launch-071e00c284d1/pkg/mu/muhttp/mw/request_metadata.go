package mw

import (
	"context"
	"net/http"
	"strings"

	"github.com/github/go-kvp"
	gokvp "github.com/github/go-kvp"

	"github.com/github/launch/pkg/mu/reqmeta"
)

// RequestMetadata sets up the request context with common values logged or
// reported for all requests.
func RequestMetadata(rmd *reqmeta.RequestMetadata) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		fn := func(w http.ResponseWriter, r *http.Request) {
			rmd2 := rmd.Copy()
			rmd2.LogWith(
				gokvp.String("http.method", r.Method),
				gokvp.String("http.url", r.URL.String()),
				gokvp.String("gh.request_id", GetGitHubRequestID(r.Context())),
				gokvp.String("gh.auth.method", authHeader(r)),
				gokvp.String("http.user_agent", userAgent(r)),
			)

			r = r.WithContext(context.WithValue(r.Context(), reqmeta.RMDContextKey, rmd2))
			next.ServeHTTP(w, r)
		}

		return http.HandlerFunc(fn)
	}
}

// GetRequestMetadata gets the request metadata from the Context
func GetRequestMetadata(ctx context.Context) *reqmeta.RequestMetadata {
	if ctx == nil {
		return nil
	}

	if rmd, ok := ctx.Value(reqmeta.RMDContextKey).(*reqmeta.RequestMetadata); ok {
		return rmd
	}

	return nil
}

// LogWith adds the log fields to the request's metadata
func LogWith(ctx context.Context, fields ...kvp.Field) {
	if rmd := GetRequestMetadata(ctx); rmd != nil {
		rmd.LogWith(fields...)
	}
}

// TagStatsWith adds the stat tags to the request's metadata
func TagStatsWith(ctx context.Context, tags reqmeta.Tags) {
	if rmd := GetRequestMetadata(ctx); rmd != nil {
		rmd.TagStatsWith(tags)
	}
}

func userAgent(r *http.Request) string {
	ua := r.UserAgent()
	if len(ua) < 1 {
		return "<none>"
	}
	return ua
}

func authHeader(r *http.Request) string {
	auth := r.Header.Get("Authorization")
	if len(auth) < 1 {
		return "<none>"
	}

	words := strings.Split(auth, " ")
	if len(words) < 2 {
		return "<unknown>"
	}

	first := strings.ToLower(words[0])
	switch first {
	case "basic", "remoteauth":
		return first
	}

	return "<unknown>"
}
