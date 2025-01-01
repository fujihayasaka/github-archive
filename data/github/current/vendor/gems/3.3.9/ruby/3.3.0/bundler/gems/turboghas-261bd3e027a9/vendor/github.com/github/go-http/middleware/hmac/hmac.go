package hmac

import (
	"context"
	"net/http"

	"github.com/github/go-http/middleware/headers"
)

// ctxRequestHMACKey is the context key for the Request-HMAC value
const ctxRequestHMACKey = "go-http-RequestHMAC"

// Handler is a middleware that adds the Request-HMAC header to the request context.
func Handler(next http.Handler) http.Handler {
	fn := func(w http.ResponseWriter, r *http.Request) {
		hmac := r.Header.Get(headers.RequestHMAC)
		if hmac != "" {
			r = r.WithContext(WithRequestHMAC(r.Context(), hmac))
		}

		next.ServeHTTP(w, r)
	}
	return http.HandlerFunc(fn)
}

// GetRequestHMAC returns the Request HMAC from the context if one is present.
func GetRequestHMAC(ctx context.Context) string {
	if ctx == nil {
		return ""
	}

	if hmac, ok := ctx.Value(ctxRequestHMACKey).(string); ok {
		return hmac
	}
	return ""
}

// WithRequestHMAC creates a new context based on the supplied parent, with the RequestHMAC
// set to the specified value. If a RequestHMAC already exists, it will be overwritten.
func WithRequestHMAC(ctx context.Context, hmac string) context.Context {
	// nolint:staticcheck SA1029 should be ignored, context collisions are acceptable across major versions
	return context.WithValue(ctx, ctxRequestHMACKey, hmac)
}
