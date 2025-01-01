package propagators

import (
	"context"
	"fmt"
	"os"
	"sync"
	"time"

	"github.com/google/uuid"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
)

// GLBPropagator implements [propagation.TextMapPropagator]
type GLBPropagator struct{}

const glbViaField = "x-glb-via"
const githubRequestIDField = "x-github-request-id"
const githubRequestIDContextKey contextKey = githubRequestIDField

type contextKey string

var (
	memoizedHostname string
	hostnameOnce     sync.Once
)

func memoizeHostname() string {
	hostnameOnce.Do(func() {
		host, err := os.Hostname()
		if err != nil {
			memoizedHostname = "unknown"
		} else {
			memoizedHostname = host
		}
	})
	return memoizedHostname
}

// Inject adds x-github-request-id headers and x-glb-via headers into the Text Map.
// The x-github-request-id value will be set to:
//   - the x-github-request-id on the carrier, if it exists; otherwise
//   - x-github-request-id, if it exists; otherwise
//   - trace-id, if it exists; otherwise falls back to
//   - a UUID
//
// The x-glb-via value will be set to:
//   - the x-glb-via on the carrier, if it exists; otherwise
//   - hostname, t=<current unix timestamp>
func (p GLBPropagator) Inject(ctx context.Context, carrier propagation.TextMapCarrier) {
	// Check for existing x-github-request-id in the carrier
	githubRequestID := carrier.Get(githubRequestIDField)
	if githubRequestID == "" {
		// Check for existing GitHub request IDs in the context
		var ok bool
		githubRequestID, ok = ctx.Value(githubRequestIDContextKey).(string)
		if !ok || githubRequestID == "" {
			sp := trace.SpanContextFromContext(ctx)
			if sp.IsValid() {
				githubRequestID = sp.TraceID().String()
			} else {
				// Fallback to a UUID
				githubRequestID = uuid.New().String()
			}
		}
	}

	glbVia := carrier.Get(glbViaField)
	if glbVia == "" {
		glbVia = fmt.Sprintf("hostname=%s t=%d", memoizeHostname(), time.Now().Unix())
	}

	carrier.Set(githubRequestIDField, githubRequestID)
	carrier.Set(glbViaField, glbVia)
}

// Extract extracts the x-github-request-id header to the context.
func (p GLBPropagator) Extract(ctx context.Context, carrier propagation.TextMapCarrier) context.Context {
	githubRequestID := carrier.Get(githubRequestIDField)
	if githubRequestID != "" {
		// Set the request ID in the context or span
		return context.WithValue(ctx, githubRequestIDContextKey, githubRequestID)
	}
	return ctx
}

// Fields returns the keys whose values are set with Inject.
func (p GLBPropagator) Fields() []string {
	return []string{glbViaField, githubRequestIDField}
}
