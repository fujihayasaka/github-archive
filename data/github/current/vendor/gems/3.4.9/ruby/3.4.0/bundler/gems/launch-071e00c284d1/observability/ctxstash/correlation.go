package ctxstash

import (
	"context"

	"github.com/github/go-kvp"
)

const (
	AqueductJobIDKey      = "aqueduct_job_id"
	OrigAqueductJobIDKey  = "orig_aqueduct_job_id"
	VSSOrchestrationIDKey = "gh.actions.orchestration_id"
	VSSReqE2EIDKey        = "req_vss_e2e_id"
	VSSRespE2EIDKey       = "resp_vss_e2e_id"
	VSSCorrelationIDKey   = "vss_e2e_id"

	gitHubRequestID = "gh.request_id"
)

type GitHubCorrelations struct {
	RequestID string
}

type AqueductCorrelations struct {
	JobID, OriginalJobID string
}

type VSSCorrelations struct {
	OrchestrationID string
	RequestE2EID    string
	ResponseE2EID   string
	CorrelationID   string
}

// Correlations are well-known identifiers associated with the context of the Stash.
type Correlations struct {
	GitHub   GitHubCorrelations
	Aqueduct AqueductCorrelations
	VSS      VSSCorrelations
}

// WithReqID stores the given github request ID in the new returned `ctx`.
// The original context is unchanged, including any fields it stored.
func WithReqID(ctx context.Context, githubReqID string) context.Context {
	return withID(ctx, gitHubRequestID, githubReqID)
}

// WithAqueductJobID stores the given aqueduct job ID in the new returned `ctx`.
// The original context is unchanged, including any fields it stored.
func WithAqueductJobID(ctx context.Context, aqueductJobID string) context.Context {
	return withID(ctx, AqueductJobIDKey, aqueductJobID)
}

// WithOrigAqueductJobID stores the given original aqueduct job ID in the new returned `ctx`.
// The original context is unchanged, including any fields it stored.
func WithOrigAqueductJobID(ctx context.Context, origAqueductJobID string) context.Context {
	return withID(ctx, OrigAqueductJobIDKey, origAqueductJobID)
}

// WithVSSOrchestrationID stores the given VSS OrchestrationID in the new returned `ctx`.
// The original context is unchanged, including any fields it stored.
func WithVSSOrchestrationID(ctx context.Context, orchestrationID string) context.Context {
	return withID(ctx, VSSOrchestrationIDKey, orchestrationID)
}

// WithVSSRequestID stores the given VSS E2E request ID in the new returned `ctx`.
// The original context is unchanged, including any fields it stored.
func WithVSSRequestID(ctx context.Context, vssReqID string) context.Context {
	return withID(ctx, VSSReqE2EIDKey, vssReqID)
}

// WithVSSResponseID stores the given VSS E2E response ID in the new returned `ctx`.
// The original context is unchanged, including any fields it stored.
func WithVSSResponseID(ctx context.Context, vssRespID string) context.Context {
	return withID(ctx, VSSRespE2EIDKey, vssRespID)
}

// WithVSSCorrelationID stores the given VSS Correlation ID in the new returned `ctx`.
// The original context is unchanged, including any fields it stored.
func WithVSSCorrelationID(ctx context.Context, vssCorrelationID string) context.Context {
	return withID(ctx, VSSCorrelationIDKey, vssCorrelationID)
}

func withID(ctx context.Context, key, value string) context.Context {
	if value == "" {
		return ctx
	}

	ns := copyStash(ctx)
	nc := ns.Correlations()

	extraFields := []kvp.Field{
		kvp.String(key, value),
	}

	// handle collision
	currValue := nc.getValueByKey(key)
	if currValue != "" && currValue != value {
		extraFields = append(extraFields, kvp.String("parent_"+key, currValue))
	}

	ns.fields = dedup(ns.fields, extraFields)
	nc = setValue(nc, key, value)
	ns.correlations = nc

	return context.WithValue(ctx, stashCtxKey{}, ns)
}

func copyStash(ctx context.Context) *stash {
	priorStash := From(ctx)
	return &stash{
		correlations: priorStash.Correlations(),
		fields:       priorStash.Fields(),
		tags:         priorStash.Tags(),
	}
}

func (c Correlations) getValueByKey(key string) (value string) {
	switch key {
	case gitHubRequestID:
		value = c.GitHub.RequestID
	case AqueductJobIDKey:
		value = c.Aqueduct.JobID
	case OrigAqueductJobIDKey:
		value = c.Aqueduct.OriginalJobID
	case VSSOrchestrationIDKey:
		value = c.VSS.OrchestrationID
	case VSSReqE2EIDKey:
		value = c.VSS.RequestE2EID
	case VSSRespE2EIDKey:
		value = c.VSS.ResponseE2EID
	case VSSCorrelationIDKey:
		value = c.VSS.CorrelationID
	}
	return value
}

func setValue(correlations Correlations, key, value string) Correlations {
	c := correlations
	switch key {
	case gitHubRequestID:
		c.GitHub.RequestID = value
	case AqueductJobIDKey:
		c.Aqueduct.JobID = value
	case OrigAqueductJobIDKey:
		c.Aqueduct.OriginalJobID = value
	case VSSOrchestrationIDKey:
		c.VSS.OrchestrationID = value
	case VSSReqE2EIDKey:
		c.VSS.RequestE2EID = value
	case VSSRespE2EIDKey:
		c.VSS.ResponseE2EID = value
	case VSSCorrelationIDKey:
		c.VSS.CorrelationID = value
	}
	return c
}
