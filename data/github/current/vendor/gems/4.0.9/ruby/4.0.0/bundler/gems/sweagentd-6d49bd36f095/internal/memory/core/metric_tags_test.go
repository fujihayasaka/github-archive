package core_test

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
)

func TestMetricTags(t *testing.T) {
	t.Run("returns nil when no integration id and no caller tags", func(t *testing.T) {
		got := core.MetricTags(context.Background(), nil)
		assert.Nil(t, got)
	})

	t.Run("adds known integration id from context", func(t *testing.T) {
		for _, integrationID := range []string{"claude-code", "claude-code-cloud", "codex-cloud"} {
			t.Run(integrationID, func(t *testing.T) {
				ctx := featureflags.ContextWithIntegrationID(context.Background(), integrationID)
				got := core.MetricTags(ctx, nil)
				assert.Equal(t, map[string]string{
					core.TagKeyIntegrationID: integrationID,
				}, got)
			})
		}
	})

	t.Run("replaces unknown integration id with unknown", func(t *testing.T) {
		ctx := featureflags.ContextWithIntegrationID(context.Background(), "spoofed-client")
		got := core.MetricTags(ctx, nil)
		assert.Equal(t, map[string]string{
			core.TagKeyIntegrationID: "unknown",
		}, got)
	})

	t.Run("merges caller tags with integration id", func(t *testing.T) {
		ctx := featureflags.ContextWithIntegrationID(context.Background(), "copilot-developer")
		got := core.MetricTags(ctx, map[string]string{"agent": "swe-agent"})
		assert.Equal(t, map[string]string{
			core.TagKeyIntegrationID: "copilot-developer",
			"agent":                  "swe-agent",
		}, got)
	})

	t.Run("caller tags override context-derived tags", func(t *testing.T) {
		ctx := featureflags.ContextWithIntegrationID(context.Background(), "claude-code")
		got := core.MetricTags(ctx, map[string]string{core.TagKeyIntegrationID: "override"})
		assert.Equal(t, map[string]string{
			core.TagKeyIntegrationID: "override",
		}, got)
	})

	t.Run("returns caller tags when no integration id in context", func(t *testing.T) {
		got := core.MetricTags(context.Background(), map[string]string{"error_type": "not_found"})
		assert.Equal(t, map[string]string{
			"error_type": "not_found",
		}, got)
	})
}
