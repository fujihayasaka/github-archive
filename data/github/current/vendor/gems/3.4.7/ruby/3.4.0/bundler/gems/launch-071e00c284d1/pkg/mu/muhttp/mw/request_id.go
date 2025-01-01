package mw

import (
	"context"
	"net/http"
	"time"

	"github.com/streadway/simpleuuid"

	"github.com/github/launch/pkg/mu/ctxkey"
)

// RequestIDKey is the context key for the X-GitHub-Request-ID value
var RequestIDKey = ctxkey.New("RequestID")

// GitHubRequestID is a middle handler that handles the github request id stuff
func GitHubRequestID(next http.Handler) http.Handler {
	fn := func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-GitHub-Request-Id")
		if len(id) == 0 {
			if uuid, err := simpleuuid.NewTime(time.Now()); err == nil {
				id = uuid.String()
			} else {
				id = "none"
			}
		}

		ctx := r.Context()
		ctx = context.WithValue(ctx, RequestIDKey, id)
		r = r.WithContext(ctx)

		next.ServeHTTP(w, r)
	}
	return http.HandlerFunc(fn)
}

// GetGitHubRequestID returns the GitHub request ID if one is present.
func GetGitHubRequestID(ctx context.Context) string {
	if ctx == nil {
		return ""
	}
	if reqID, ok := ctx.Value(RequestIDKey).(string); ok {
		return reqID
	}
	return ""
}
