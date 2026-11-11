// Package interactionmeta provides utilities to manage CAPI interaction metadata required for request headers in context.
package interactionmeta

import "context"

type capiInteractionCtxKey struct{}

const (
	// InteractionIDHeader is sent by clients to identify which interaction the request is related to.
	InteractionIDHeader = "X-Interaction-Id"
	// InteractionTypeHeader is sent by clients to identify the type of interaction that is taking place.
	// Possible examples from CCR: "agent_mode", "code_review", etc.
	InteractionTypeHeader = "X-Interaction-Type"
	// InitiatorHeader is sent by clients like CCRA to identify the initiator of the request. Expected
	// values are "user" or "agent".
	InitiatorHeader = "X-Initiator"
)

// CAPIInteractionMeta holds CAPI required headers
type CAPIInteractionMeta struct {
	ID        string
	Type      string
	Initiator string
}

// WithCAPIInteractionMeta adds metadata to ctx.
func WithCAPIInteractionMeta(ctx context.Context, meta CAPIInteractionMeta) context.Context {
	if (meta == CAPIInteractionMeta{}) {
		return ctx
	}
	return context.WithValue(ctx, capiInteractionCtxKey{}, meta)
}

// CAPIInteractionMetaFromContext retrieves metadata from ctx.
func CAPIInteractionMetaFromContext(ctx context.Context) (CAPIInteractionMeta, bool) {
	v := ctx.Value(capiInteractionCtxKey{})
	if v == nil {
		return CAPIInteractionMeta{}, false
	}
	meta, ok := v.(CAPIInteractionMeta)
	if !ok || (meta == CAPIInteractionMeta{}) {
		return CAPIInteractionMeta{}, false
	}
	return meta, true
}

// isFirstCallKeyType is used to track if this is the first LLM call.
// This is used to differentiate between first user-initiated and subsequent tool calls.
type isFirstCallKeyType struct{}

var isFirstCallKey = isFirstCallKeyType{}

// MarkCallMade marks in context that an LLM call has been made, changing isFirstCall to false.
func MarkCallMade(ctx context.Context) context.Context {
	return context.WithValue(ctx, isFirstCallKey, false)
}

// IsFirstCall checks if this is the first LLM call.
func IsFirstCall(ctx context.Context) bool {
	if v, ok := ctx.Value(isFirstCallKey).(bool); ok {
		return v
	}
	return true
}
