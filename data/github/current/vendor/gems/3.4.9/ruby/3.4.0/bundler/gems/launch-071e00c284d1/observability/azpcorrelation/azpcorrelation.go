// azpcorrelation adds/supports AZP telemetry for GitHub/AZP
// request/usage introspection.
//
// see: https://github.com/github/dreamlifter/issues/119
//
// note: don't assume VSS correlation IDs work the same
// as GitHub request IDs, e.g they may be treated as part of the
// body - https://github.com/github/pe-actions-experience/issues/1839
package azpcorrelation

import (
	"context"

	"github.com/github/go-kvp"
	"github.com/google/uuid"
	"go.opentelemetry.io/otel/attribute"
	oteltrace "go.opentelemetry.io/otel/trace"

	"github.com/github/launch/pkg/mu/ctxkey"

	"github.com/github/launch/observability/ctxstash"
)

const (
	// UserAgentHeaderName is the HTTP Header to store the User-Agent
	UserAgentHeaderName = "User-Agent"
	// VSSE2EIDHeaderName is the HTTP Header to store the VSS E2E Identifier (this needs to be a UUID or it's ignored by AZP)
	VSSE2EIDHeaderName = "X-VSS-E2EID"
	// VSSOrchestrationIDHeaderName is the HTTP Header to send the orchestration identifier used for workflow run and job correlation
	VSSOrchestrationIDHeaderName = "X-VSS-OrchestrationId"
	// VSSE2EIDMetadataName is the key used within the metadata
	VSSE2EIDMetadataName = "vss-e2e-id"
)

// UserAgentContextKey is the context.Context key to store the User Agent value across boundaries
var UserAgentContextKey = ctxkey.New("UserAgent")

// GetOrMakeVSSCorrelationID returns a VSS Correlation ID if one is present, if not it generates a new one. It is the callers responsibility
// to ensure that the correlation ID is persisted.
func GetOrMakeVSSCorrelationID(ctx context.Context) string {
	if ctx == nil {
		return ""
	}
	if id := ctxstash.From(ctx).Correlations().VSS.CorrelationID; id != "" {
		return id
	}
	uuid, err := uuid.NewRandom()
	if err != nil {
		return ""
	}
	return uuid.String()
}

// GetOrMakeVSSCorrelationID returns a VSS Orchestration ID if one is present
func GetVSSOrchestrationID(ctx context.Context) string {
	stash := ctxstash.From(ctx)
	id := stash.Correlations().VSS.CorrelationID
	return id
}

// WithVSSCorrelationID returns a context with the VSS E2E ID injected.
func WithVSSCorrelationID(ctx context.Context, e2eID string) context.Context {
	return ctxstash.WithVSSCorrelationID(ctx, e2eID)
}

func WithVSSOrchestrationID(ctx context.Context, orchestrationID string) context.Context {
	return ctxstash.WithVSSOrchestrationID(ctx, orchestrationID)
}

// WithVSSID adds the given VSS ID to the logging context.
func WithVSSID(ctx context.Context, vssID string) context.Context {
	if vssID != "" {
		return ctxstash.WithFields(ctx, kvp.String("vss_e2e_id", vssID))
	}
	return ctx
}

func AddVSSCorrelationIDToSpan(ctx context.Context, span oteltrace.Span) {
	vssID := ctxstash.From(ctx).Correlations().VSS.RequestE2EID
	if vssID == "" {
		return
	}

	span.SetAttributes(attribute.String("gh.actions.vss_e2e_id", vssID))
}
