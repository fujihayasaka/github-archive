// Package traceparent provides functionality for signing and verifying
// OpenTelemetry traceparent headers to safely pass trace context from untrusted sources.
package traceparent

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"net/http"
	"strings"

	"github.com/github/sweagentd/internal/goerrors"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
)

const (
	// XCopilotTraceparentHeader is the HTTP header name for signed traceparent
	XCopilotTraceparentHeader = "X-Copilot-Traceparent"
)

// Propagator abstracts trace context extraction and optional signing.
// It returns trace context suitable for passing to the runtime via environment variables.
type Propagator interface {
	// GetCopilotTraceparent extracts the traceparent from the context and returns it.
	// If signing is configured, returns "traceparent.signature" format.
	// If no signing, returns the raw W3C traceparent string.
	// Returns empty string if no valid span context exists.
	GetCopilotTraceparent(ctx context.Context) (string, error)
}

// NewPropagator creates a Propagator. If secret is non-empty, traceparents will be signed.
func NewPropagator(secret []byte) (Propagator, error) {
	if len(secret) == 0 {
		return &noopPropagator{}, nil
	}
	return &signingPropagator{secret: secret}, nil
}

// noopPropagator returns raw traceparent without signing.
type noopPropagator struct{}

func (p *noopPropagator) GetCopilotTraceparent(ctx context.Context) (string, error) {
	spanContext := trace.SpanContextFromContext(ctx)
	if !spanContext.IsValid() {
		return "", nil
	}
	propagator := propagation.TraceContext{}
	carrier := propagation.MapCarrier{}
	propagator.Inject(ctx, carrier)
	return carrier.Get("traceparent"), nil
}

// signingPropagator signs traceparent using HMAC-SHA256.
type signingPropagator struct {
	secret []byte
}

func (p *signingPropagator) GetCopilotTraceparent(ctx context.Context) (string, error) {
	spanContext := trace.SpanContextFromContext(ctx)
	if !spanContext.IsValid() {
		return "", nil
	}
	propagator := propagation.TraceContext{}
	carrier := propagation.MapCarrier{}
	propagator.Inject(ctx, carrier)
	traceparentStr := carrier.Get("traceparent")
	if traceparentStr == "" {
		return "", nil
	}
	return sign(traceparentStr, p.secret), nil
}

// sign creates a signed traceparent in the format "traceparent.signature"
func sign(traceparent string, secret []byte) string {
	mac := hmac.New(sha256.New, secret)
	_, _ = mac.Write([]byte(traceparent))
	sig := base64.URLEncoding.EncodeToString(mac.Sum(nil))
	return traceparent + "." + sig
}

// verify validates the signature and returns the traceparent if valid
func verify(signed string, secret []byte) (string, bool) {
	idx := strings.LastIndex(signed, ".")
	if idx == -1 {
		return "", false
	}
	traceparent, sig := signed[:idx], signed[idx+1:]

	mac := hmac.New(sha256.New, secret)
	_, _ = mac.Write([]byte(traceparent))
	expected := base64.URLEncoding.EncodeToString(mac.Sum(nil))

	if !hmac.Equal([]byte(sig), []byte(expected)) {
		return "", false
	}
	return traceparent, true
}

// Middleware creates an HTTP middleware that verifies signed traceparent headers from
// X-Copilot-Traceparent and sets them as the active trace context for OpenTelemetry.
func Middleware(secret []byte) (func(http.Handler) http.Handler, error) {
	if len(secret) == 0 {
		return nil, goerrors.New("secret key must not be empty")
	}

	propagator := propagation.TraceContext{}

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ctx := r.Context()

			// Check for the signed traceparent header
			signedTraceparent := r.Header.Get(XCopilotTraceparentHeader)
			if signedTraceparent != "" {
				// Verify the signature and extract traceparent
				traceparent, ok := verify(signedTraceparent, secret)
				if ok {
					// Inject the traceparent into the context
					carrier := propagation.MapCarrier{"traceparent": traceparent}
					ctx = propagator.Extract(ctx, carrier)
					r = r.WithContext(ctx)
				}
			}

			next.ServeHTTP(w, r)
		})
	}, nil
}
