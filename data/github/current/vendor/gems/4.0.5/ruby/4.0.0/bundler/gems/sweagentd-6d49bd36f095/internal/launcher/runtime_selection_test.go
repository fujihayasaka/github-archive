package launcher

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/stretchr/testify/assert"
)

func TestSelectRuntime_ThirdPartyAppsOnlyUseCCAV3Variant(t *testing.T) {
	ctx := context.Background()
	thirdParty := agenticapp.NewThirdParty(1, "third-party-agent", "", 2, "third-party-agent-bot", "commit-login", "commit@email.com", nil, nil)

	tests := []struct {
		name                string
		featureFlags        map[string]bool
		expectedEntryPoint  string
		expectedReleaseSlug string
		expectedSetup       string
	}{
		{
			name:                "default Copilot runtime",
			featureFlags:        map[string]bool{},
			expectedEntryPoint:  copilotRuntimeEntrypoint,
			expectedReleaseSlug: agenticapp.CopilotComputeSlug,
		},
		{
			name: "CCA v3 flag selects CCA v3 runtime",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: true,
			},
			expectedEntryPoint:  ccaV3RuntimeEntrypoint,
			expectedReleaseSlug: copilotRuntimeSlugCCAV3,
		},
		{
			name: "CCA v2 flag does not select CCA v2 runtime",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV2: true,
			},
			expectedEntryPoint:  copilotRuntimeEntrypoint,
			expectedReleaseSlug: agenticapp.CopilotComputeSlug,
		},
		{
			name: "Claude flag does not select Claude runtime",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointClaude: true,
			},
			expectedEntryPoint:  copilotRuntimeEntrypoint,
			expectedReleaseSlug: agenticapp.CopilotComputeSlug,
		},
		{
			name: "Codex flag does not select Codex runtime or setup",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCodex: true,
			},
			expectedEntryPoint:  copilotRuntimeEntrypoint,
			expectedReleaseSlug: agenticapp.CopilotComputeSlug,
		},
		{
			name: "non-CCA v3 flags together do not select another runtime",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV2:  true,
				featureflags.CopilotSWEAgentRuntimeEntryPointClaude: true,
				featureflags.CopilotSWEAgentRuntimeEntryPointCodex:  true,
			},
			expectedEntryPoint:  copilotRuntimeEntrypoint,
			expectedReleaseSlug: agenticapp.CopilotComputeSlug,
		},
		{
			name: "CCA v3 flag takes precedence over other runtime flags",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: true,
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV2:    true,
				featureflags.CopilotSWEAgentRuntimeEntryPointClaude:   true,
				featureflags.CopilotSWEAgentRuntimeEntryPointCodex:    true,
			},
			expectedEntryPoint:  ccaV3RuntimeEntrypoint,
			expectedReleaseSlug: copilotRuntimeSlugCCAV3,
		},
		{
			name: "CCA v3 opt-out flag prevents CCA v3 runtime",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App:       true,
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3AppOptOut: true,
			},
			expectedEntryPoint:  copilotRuntimeEntrypoint,
			expectedReleaseSlug: agenticapp.CopilotComputeSlug,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			opts := &LaunchAgentOpts{
				ActorID:           12345,
				GitHubRepoID:      67890,
				GitHubRepoOwnerID: 11111,
				Agent:             thirdParty,
			}
			ffClient := featureflags.NewNoopClient(tt.featureFlags)

			selection := selectRuntime(ctx, ffClient, opts)

			assert.Equal(t, tt.expectedEntryPoint, selection.entryPoint)
			assert.Equal(t, tt.expectedReleaseSlug, selection.releaseSlug)
			assert.Equal(t, tt.expectedSetup, selection.setup)
		})
	}
}

func TestSelectRuntime_AnalysisEventTypesBypassesVariants(t *testing.T) {
	ctx := context.Background()
	copilotAgent := agenticapp.NewCopilot(1, "copilot", 2, "copilot-bot", "commit", "commit@email.com")

	tests := []struct {
		name         string
		eventType    string
		featureFlags map[string]bool
	}{
		{
			name:      "ci_check_run_failure_analysis bypasses CCA v3",
			eventType: "ci_check_run_failure_analysis",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: true,
			},
		},
		{
			name:      "ci_failure_analysis bypasses CCA v3",
			eventType: "ci_failure_analysis",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: true,
			},
		},
		{
			name:      "verification_platform_findings bypasses CCA v3",
			eventType: "verification_platform_findings",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: true,
			},
		},
		{
			name:      "ci_check_run_failure_analysis bypasses CCA v2",
			eventType: "ci_check_run_failure_analysis",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV2: true,
			},
		},
		{
			name:      "ci_check_run_failure_analysis bypasses all variants",
			eventType: "ci_check_run_failure_analysis",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: true,
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV2:    true,
				featureflags.CopilotSWEAgentRuntimeEntryPointClaude:   true,
				featureflags.CopilotSWEAgentRuntimeEntryPointCodex:    true,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			opts := &LaunchAgentOpts{
				ActorID:           12345,
				GitHubRepoID:      67890,
				GitHubRepoOwnerID: 11111,
				Agent:             copilotAgent,
				JobEventType:      tt.eventType,
			}
			ffClient := featureflags.NewNoopClient(tt.featureFlags)

			selection := selectRuntime(ctx, ffClient, opts)

			assert.Equal(t, copilotRuntimeEntrypoint, selection.entryPoint,
				"analysis event type %q should always use default entry point", tt.eventType)
		})
	}
}

func TestSelectRuntime_NonAnalysisEventTypeStillUsesVariants(t *testing.T) {
	ctx := context.Background()
	copilotAgent := agenticapp.NewCopilot(1, "copilot", 2, "copilot-bot", "commit", "commit@email.com")

	opts := &LaunchAgentOpts{
		ActorID:           12345,
		GitHubRepoID:      67890,
		GitHubRepoOwnerID: 11111,
		Agent:             copilotAgent,
		JobEventType:      "issue_created",
	}
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: true,
	})

	selection := selectRuntime(ctx, ffClient, opts)

	assert.Equal(t, ccaV3RuntimeEntrypoint, selection.entryPoint,
		"non-analysis event types should still use CCA v3 when flag is enabled")
}
