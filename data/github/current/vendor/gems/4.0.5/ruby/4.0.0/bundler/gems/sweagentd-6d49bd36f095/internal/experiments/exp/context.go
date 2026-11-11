package exp

import (
	"context"

	"github.com/github/feature-management-client-go/githubexp"
	"github.com/github/sweagentd/internal/requestctx"
)

// contextKey is a private type for context keys to avoid collisions.
type contextKey struct{}

// assignmentKey is the context key for storing Assignment.
var assignmentKey = contextKey{}

// WithAssignment returns a new context with the given Assignment stored.
// Use this in middleware to store the assignment for later retrieval.
func WithAssignment(ctx context.Context, assignment *githubexp.AssignmentResult) context.Context {
	return context.WithValue(ctx, assignmentKey, assignment)
}

// AssignmentFromContext retrieves the Assignment from context.
// It first checks the mutable requestctx (populated during job build),
// then falls back to the immutable context value, and finally returns a
// noop assignment that yields defaults if neither is set.
func AssignmentFromContext(ctx context.Context) *githubexp.AssignmentResult {
	// Check requestctx first (set by SetSDKAssignmentForJob during Build).
	if assignment, ok := requestctx.GetExpSDKAssignment(ctx); ok {
		return assignment
	}
	if assignment, ok := ctx.Value(assignmentKey).(*githubexp.AssignmentResult); ok {
		return assignment
	}
	// Return empty assignment that yields defaults
	return githubexp.NewAssignmentResult(nil, "", 0)
}
