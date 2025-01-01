package callcounter

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestCounter(t *testing.T) {
	ctx := WithCounter(context.Background(), "test-counter")
	ExternalCall(ctx, "sql")
	assert.Equal(t, &counter{name: "test-counter", counts: map[string]int64{"sql": 1}}, get(ctx))

	ExternalCall(ctx, "sql")
	assert.Equal(t, &counter{name: "test-counter", counts: map[string]int64{"sql": 2}}, get(ctx))

	ExternalCall(ctx, "azp")
	assert.Equal(t, &counter{name: "test-counter", counts: map[string]int64{"sql": 2, "azp": 1}}, get(ctx))
}

func TestNoCounter(t *testing.T) {
	ctx := context.Background()

	ExternalCall(ctx, "sql")                                                                 // Doesn't error out if not in context
	assert.Equal(t, &counter{name: "unknown_counter", counts: map[string]int64{}}, get(ctx)) // Empty result
}
