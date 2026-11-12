package exp

import (
	"context"
	"testing"

	"github.com/github/feature-management-client-go/githubexp"
	"github.com/stretchr/testify/assert"
)

func TestAssignmentFromContext_NoAssignment(t *testing.T) {
	ctx := context.Background()
	result := AssignmentFromContext(ctx)
	assert.NotNil(t, result, "should never return nil, even without stored assignment")
}

func TestWithAssignment_RoundTrip(t *testing.T) {
	vars := map[string]string{"flag_a": "treatment", "flag_b": "control"}
	assignment := githubexp.NewAssignmentResult(vars, "ctx-abc", 7)

	ctx := WithAssignment(context.Background(), assignment)
	got := AssignmentFromContext(ctx)

	assert.Equal(t, assignment, got)
}

func TestAssignmentFromContext_OverwritesPrevious(t *testing.T) {
	first := githubexp.NewAssignmentResult(map[string]string{"f": "v1"}, "c1", 1)
	second := githubexp.NewAssignmentResult(map[string]string{"f": "v2"}, "c2", 2)

	ctx := WithAssignment(context.Background(), first)
	ctx = WithAssignment(ctx, second)

	got := AssignmentFromContext(ctx)
	assert.Equal(t, second, got)
}

func TestAssignmentFromContext_NilAssignment(t *testing.T) {
	ctx := WithAssignment(context.Background(), nil)
	result := AssignmentFromContext(ctx)
	// nil *AssignmentResult satisfies the type assertion, so we get nil back
	assert.Nil(t, result, "nil stored value passes type assertion for pointer type")
}

type testContextKey string

func TestAssignmentFromContext_DifferentContextKeys(t *testing.T) {
	assignment := githubexp.NewAssignmentResult(map[string]string{"x": "y"}, "ctx", 1)

	parent := WithAssignment(context.Background(), assignment)
	child := context.WithValue(parent, testContextKey("unrelated-key"), "unrelated-value")

	got := AssignmentFromContext(child)
	assert.Equal(t, assignment, got, "assignment should be accessible from child context")
}
