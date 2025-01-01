// Package hmac provides middleware that adds the Request-HMAC header to the request context.
package hmac

import (
	"context"
	"crypto/sha256"
	"fmt"
	"net/http"

	"github.com/github/github-telemetry-go/log"
	auth "github.com/github/go-auth/hmac"
	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-stats"
)

// ctxRequestHMACKey is the context key for the Request-HMAC value.
const ctxRequestHMACKey = "go-http-RequestHMAC"

// Handler is a middleware that adds the Request-HMAC header to the request context.
//
// Deprecated: Make an HmacValidator struct and use its Handler method instead, as it also
// validates the HMAC using the provided secrets. This handler requires you to validate the HMAC
// yourself separately.
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

// Validator is a middleware that:
// 1) adds the Request-HMAC header to the request context and
// 2) validates the HMAC using the provided secrets.
type Validator struct {
	// Secrets is one or more secrets to use to validate the HMAC. If any secret works, then the
	// HMAC is valid. This array must not be empty.
	Secrets []string

	// A logger to use for logging. Use nil to get a default logger named hmac. Use a
	// log.NewNullLogger() to suppress logging.
	Logger log.Logger

	// A stats client to use for emitting metrics. Use nil to suppress metrics.
	StatsClient stats.Client
}

// Handler produces the http.Handler middleware to use.
func (hv *Validator) Handler(next http.Handler) http.Handler {
	if hv.Logger == nil {
		hv.Logger = log.Named("hmac")
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Use logger that includes fields from context
		loggerWithContext := hv.Logger.WithContext(r.Context())

		hmacString := r.Header.Get(headers.RequestHMAC)
		if hmacString == "" {
			loggerWithContext.Error("request hmac is missing")
			http.Error(w, "request hmac is missing", http.StatusBadRequest)
			return
		}

		requestHmac, err := auth.ParseRequestHMAC(hmacString)
		if err != nil {
			loggerWithContext.WithError(err).Error("error parsing request hmac")
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		for _, secret := range hv.Secrets {
			if secret == "" {
				loggerWithContext.Error("empty hmac secret")
				http.Error(w, "empty hmac secret", http.StatusInternalServerError)
				return
			}

			err = requestHmac.Validate(secret)

			if err == nil {
				loggerWithContext.Debug("request hmac validated")

				if hv.StatsClient != nil {
					secretHash := ""
					hash := sha256.New()
					_, err := hash.Write([]byte(secret))
					if err == nil {
						secretHash = fmt.Sprintf("%x", hash.Sum(nil))
					}
					hv.StatsClient.Counter("hmac.validated", stats.Tags{"secret_hash": secretHash}, 1)
				}

				r = r.WithContext(WithRequestHMAC(r.Context(), hmacString))

				next.ServeHTTP(w, r)
				return
			}
		}
		loggerWithContext.Error("invalid hmac token")
		http.Error(w, "invalid hmac token", http.StatusUnauthorized)
	})
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
	//nolint:staticcheck,revive // SA1029 should be ignored, context collisions are acceptable across major versions
	return context.WithValue(ctx, ctxRequestHMACKey, hmac)
}
