package featureflags

import "context"

// integrationIDKeyType is an unexported type used as the context key for the
// integration ID, preventing collisions with keys defined in other packages.
type integrationIDKeyType struct{}

// ContextWithIntegrationID returns a copy of ctx that carries the given
// integration ID. Handlers should call this early so that downstream code
// can resolve the per-client memory voting feature flag.
func ContextWithIntegrationID(ctx context.Context, integrationID string) context.Context {
	return context.WithValue(ctx, integrationIDKeyType{}, integrationID)
}

// IntegrationIDFromContext extracts the integration ID previously stored with
// ContextWithIntegrationID. Returns an empty string when no value is present.
func IntegrationIDFromContext(ctx context.Context) string {
	v, _ := ctx.Value(integrationIDKeyType{}).(string)
	return v
}

// integrationFlags holds the per-client feature flag constants for a given
// CAPI integration ID.
type integrationFlags struct {
	// votingFlag gates memory voting for this client.
	votingFlag string
	// disabledFlag is a kill switch that disables all memory operations
	// (store, retrieve, vote, prompt) for this client.
	disabledFlag string
}

// integrationToFlags maps known CAPI integration IDs to their per-client
// memory feature flag constants.
var integrationToFlags = map[string]integrationFlags{
	"claude-code-cloud":      {votingFlag: CopilotSWEAgentMemoryVotingCodingAgent},
	"codex-cloud":            {votingFlag: CopilotSWEAgentMemoryVotingCodingAgent},
	"claude-code":            {votingFlag: CopilotSWEAgentMemoryVotingCodingAgent},
	"openai-codex-cli":       {votingFlag: CopilotSWEAgentMemoryVotingCodingAgent},
	"copilot-developer":      {votingFlag: CopilotSWEAgentMemoryVotingCodingAgent},
	"copilot-developer-dev":  {votingFlag: CopilotSWEAgentMemoryVotingCodingAgent},
	"copilot-pr-reviews":     {votingFlag: CopilotSWEAgentMemoryVotingCCR},
	"copilot-pr-reviews-dev": {votingFlag: CopilotSWEAgentMemoryVotingCCR},
	"copilot-developer-cli":  {votingFlag: CopilotSWEAgentMemoryVotingCLI},
	"vscode-chat":            {votingFlag: CopilotSWEAgentMemoryVotingVSCode, disabledFlag: CopilotSWEAgentMemoryDisabledVSCode},
	"vscode-chat-dev":        {votingFlag: CopilotSWEAgentMemoryVotingVSCode, disabledFlag: CopilotSWEAgentMemoryDisabledVSCode},
}

// MemoryVotingFlagForIntegration returns the per-client memory voting feature
// flag for the given integration ID. Unknown or empty integration IDs return
// an empty string so that voting is disabled for unmapped clients.
func MemoryVotingFlagForIntegration(integrationID string) string {
	if flags, ok := integrationToFlags[integrationID]; ok {
		return flags.votingFlag
	}
	return ""
}

// MemoryVotingFlagFromContext is a convenience wrapper that extracts the
// integration ID from ctx and resolves the per-client feature flag.
func MemoryVotingFlagFromContext(ctx context.Context) string {
	return MemoryVotingFlagForIntegration(IntegrationIDFromContext(ctx))
}

// MemoryDisabledFlagForIntegration returns the per-client memory disabled
// feature flag for the given integration ID. Unknown or empty integration IDs
// return an empty string so that memory remains enabled for unmapped clients.
func MemoryDisabledFlagForIntegration(integrationID string) string {
	if flags, ok := integrationToFlags[integrationID]; ok {
		return flags.disabledFlag
	}
	return ""
}

// MemoryDisabledFlagFromContext is a convenience wrapper that extracts the
// integration ID from ctx and resolves the per-client memory disabled flag.
func MemoryDisabledFlagFromContext(ctx context.Context) string {
	return MemoryDisabledFlagForIntegration(IntegrationIDFromContext(ctx))
}
