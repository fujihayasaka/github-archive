package core

import (
	"context"
	"maps"

	"github.com/github/sweagentd/internal/featureflags"
)

// Tag key constants shared across memory service metrics and HTTP middleware.
const (
	TagKeyIntegrationID  = "copilot_integration_id"
	TagKeyRuntimeVersion = "copilot_agent_runtime_version"
)

// knownTelemetryIntegrations is the allow-list of integration IDs that may
// appear as metric tag values. IDs not in this set are replaced with
// "unknown" to prevent high-cardinality tag explosion in Datadog.
var knownTelemetryIntegrations = map[string]struct{}{
	"copilot-developer":       {},
	"copilot-developer-dev":   {},
	"copilot-developer-cli":   {},
	"copilot-developer-app":   {},
	"claude-code":             {},
	"claude-code-cloud":       {},
	"codex-cloud":             {},
	"openai-codex-cli":        {},
	"agentic-workflows":       {},
	"copilot-4-cli":           {},
	"copilot-pr-reviews":      {},
	"copilot-pr-reviews-dev":  {},
	"copilot-pr-reviews-eval": {},
	"vscode-chat":             {},
	"vscode-chat-dev":         {},
}

// MetricTags merges the integration ID from ctx into the supplied tag map.
// If the integration ID is not in the known telemetry allow-list it is
// replaced with "unknown" to bound tag cardinality.
// Caller-supplied tags take precedence over the context-derived value.
func MetricTags(ctx context.Context, tags map[string]string) map[string]string {
	id := featureflags.IntegrationIDFromContext(ctx)
	if id == "" && len(tags) == 0 {
		return nil
	}

	merged := make(map[string]string, len(tags)+1)
	if id != "" {
		if _, ok := knownTelemetryIntegrations[id]; !ok {
			id = "unknown"
		}
		merged[TagKeyIntegrationID] = id
	}
	maps.Copy(merged, tags)
	return merged
}
