// Package featureflags provides feature flag client functionality for sweagentd.
package featureflags

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	"github.com/github/feature-management-client-go/vexi/v2"
	hydro_adapter "github.com/github/feature-management-client-go/vexi/v2/adapter/hydro"
	"github.com/github/feature-management-client-go/vexi/v2/extensions"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-server/runtime/features"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
)

// Feature flag constants - keep these sorted alphabetically by constant name to reduce merge conflicts
const (
	CopilotSWEAgentAINameGeneration                       = "copilot_swe_agent_ai_name_generation"          // Enable AI-powered branch and session name generation
	CopilotSWEAgentAINameGenerationUseGPT5Nano            = "copilot_swe_agent_ai_name_generation_use_gpt5" // Use gpt-5-nano instead of gpt-4o-mini for name generation
	CopilotSWEAgentAgenticApps                            = "copilot_swe_agent_agentic_apps"
	CopilotSWEAgentAPIDisallow                            = "copilot_swe_agent_api_disallow" // Disallow specific users or apps from using the API for abuse
	CopilotSWEAgentCanSelectModel                         = "sweagentd_can_select_model"
	CopilotSWEAgentGZipProblemStatement                   = "copilot_swe_agent_gzip_problem_statement"
	CopilotSWEAgentIntegrationCodeScanningAlerts          = "copilot_swe_agent_integration_code_scanning_alerts"
	CopilotSWEAgentIntegrationCodeScanningAlertsLinksInPR = "copilot_swe_agent_integration_code_scanning_alerts_links_in_pr"
	CopilotSWEAgentIssueBodyEditCheck                     = "sweagentd_issue_body_edit_check"
	CopilotSWEAgentOnlineEvalUseClaudeHaiku45             = "copilot_swe_agent_online_eval_use_claude_haiku_4_5" // Use claude-haiku-4.5 instead of gpt-4.1 for online evaluation
	CopilotSWEAgentOrganizationCustomInstructions         = "org_custom_instructions_for_sweagentd"              // Enable organization-level custom instructions for SWE Agent
	CopilotSWEAgentPRBodyRemoveFixesInSuffix              = "copilot_swe_agent_pr_body_remove_fixes_in_suffix"   // Remove "Fixes" lines from PR body suffix in problem statements
	CopilotSWEAgentPRStateEventsEnabled                   = "coding_agent_sessions_consume_hydro_event_and_patch_session"
	CopilotSWEAgentUseBillingPlatform                     = "copilot_swe_agent_use_billing_platform"   // Use the separate SKU for coding agent
	CopilotSWEAgentUseCustomAgents                        = "copilot_swe_agent_use_subagents"          // Enable custom agent support in sweagentd - left with old name since this is staff shipped
	CopilotSWEAgentCustomAgentsDisallow                   = "copilot_swe_agent_custom_agents_disallow" // Disallow specific users, orgs, or apps from using custom agents
	CodingAgentStackPRs                                   = "coding_agent_stack_prs"                       // Enable @-mentioning Copilot on user PRs, to create a stacked PR
	CopilotSWEAgentValidateRuntimeVariables               = "copilot_swe_agent_validate_runtime_variables" // Validate required runtime variables before launching
	CopilotSWEAgentV2CallbackAPI                          = "copilot_swe_agent_v2_callback_api"
	CopilotSweAgentCommands                               = "copilot_swe_agent_progress_commands"
	CopilotSWEAgentCustomAgentAsAPI                       = "copilot_swe_agent_custom_agent_as_api"
	CopilotSWEAgentSafeRuntimeDeploy                      = "copilot_swe_agent_safe_runtime_deploy"
	CopilotSWEAgenticAppsProvider                         = "copilot_swe_agentic_apps_provider"
	CopilotSWEAgentReturnInvalidCustomAgentsByDefault     = "copilot_swe_agent_return_invalid_custom_agents_by_default" // Temporary ff to return invalid custom agents by default from the /custom-agents list endpoint
	CopilotSWEAgentZeroQuotaTest                          = "copilot_swe_agent_zero_quota_test"                         // Temporary ff to test my zero quota handling in commands
	CopilotSWEAgentRuntimeEntryPointClaude                = "copilot_swe_agent_runtime_entry_point_claude"
	CopilotSWEAgentRuntimeEntryPointCodex                 = "copilot_swe_agent_runtime_entry_point_codex"
	CopilotSWEAgentSelectCustomerError                    = "copilot_swe_agent_select_customer_error" // When enabled, fail session when customer is not selected; when disabled, log and continue
	SweagentdBypassActorCheck                             = "sweagentd_bypass_actor_check"            // Check if Copilot is configured as a bypass actor for repository rulesets
)

// Client is the interface for feature flag operations.
type Client interface {
	IsEnabled(ctx context.Context, featureFlagName string, actors ...vexi.Actor) bool
	IsEnabledForUser(ctx context.Context, featureFlagName string, userID int64) bool
	IsEnabledForRepo(ctx context.Context, featureFlagName string, repoID int64) bool
	IsEnabledForUserOrRepo(ctx context.Context, featureFlagName string, userID, repoID int64) bool
	IsEnabledForUserOrRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.RepositoryWithActor) bool
	IsEnabledForGitHubApp(ctx context.Context, featureFlagName string, appID int64) bool
	IsEnabledForOAuthApp(ctx context.Context, featureFlagName string, appID int64) bool
}

// FeatureFlagClient is the main implementation of the Client interface.
type FeatureFlagClient struct {
	client features.Flagger
	obsv   observability.Exporters
	ready  atomic.Bool
}

// IsEnabled implements Client.
func (f *FeatureFlagClient) IsEnabled(ctx context.Context, featureFlagName string, actors ...vexi.Actor) bool {
	if !f.ready.Load() {
		f.obsv.Logger.Warn("feature flag client not ready, returning default value", kvp.String("feature_flag", featureFlagName))
		return false
	}

	return f.client.IsEnabledWithDefaultValue(ctx, featureFlagName, false, actors...)
}

// IsEnabledForUser checks if a feature flag is enabled for a specific user.
func (f *FeatureFlagClient) IsEnabledForUser(ctx context.Context, featureFlagName string, userID int64) bool {
	return f.IsEnabled(ctx, featureFlagName, extensions.NewUser(strconv.FormatInt(userID, 10)))
}

// IsEnabledForRepo checks if a feature flag is enabled for a specific repository.
func (f *FeatureFlagClient) IsEnabledForRepo(ctx context.Context, featureFlagName string, repoID int64) bool {
	return f.IsEnabled(ctx, featureFlagName, extensions.NewRepository(strconv.FormatInt(repoID, 10)))
}

// IsEnabledForUserOrRepo checks if a feature flag is enabled for a user or repository.
func (f *FeatureFlagClient) IsEnabledForUserOrRepo(ctx context.Context, featureFlagName string, userID, repoID int64) bool {
	actors := []vexi.Actor{
		extensions.NewUser(strconv.FormatInt(userID, 10)),
		extensions.NewRepository(strconv.FormatInt(repoID, 10)),
	}
	return f.IsEnabled(ctx, featureFlagName, actors...)
}

// IsEnabledForUserOrRepoOrOwner checks if a feature flag is enabled for a user, repository, or repository owner using the sweagentd.RepositoryWithActor interface.
func (f *FeatureFlagClient) IsEnabledForUserOrRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.RepositoryWithActor) bool {
	return f.IsEnabled(ctx, featureFlagName,
		extensions.NewUser(strconv.FormatInt(actors.GetActorID(), 10)),
		extensions.NewRepository(strconv.FormatInt(actors.GetRepositoryID(), 10)),
		extensions.NewUser(strconv.FormatInt(actors.GetOwnerID(), 10)), // Owner as a user
		extensions.NewOrganization(strconv.FormatInt(actors.GetOwnerID(), 10)))
}

// IsEnabledForGitHubApp checks if a feature flag is enabled for a specific GitHub App.
func (f *FeatureFlagClient) IsEnabledForGitHubApp(ctx context.Context, featureFlagName string, appID int64) bool {
	return f.IsEnabled(ctx, featureFlagName, extensions.NewGitHubApp(strconv.FormatInt(appID, 10)))
}

// IsEnabledForOAuthApp checks if a feature flag is enabled for a specific OAuth App.
func (f *FeatureFlagClient) IsEnabledForOAuthApp(ctx context.Context, featureFlagName string, appID int64) bool {
	return f.IsEnabled(ctx, featureFlagName, extensions.NewOAuthApplication(strconv.FormatInt(appID, 10)))
}

var _ Client = &FeatureFlagClient{}

// NewClient creates a new feature flag client.
func NewClient(ctx context.Context, cfg *config.Config, obsv observability.Exporters) (Client, error) {
	owningServices := []string{"copilot-coding-agent", "copilot-extensibility", "sweagentd"}
	hydroAdapter, err := hydro_adapter.NewAdapterWithOwningServices(ctx, cfg.ServiceName, owningServices,
		hydro_adapter.WithLogger(obsv.Logger.Named("vexi-hydro")),
		hydro_adapter.WithLogOnUpdate(), // Log each flag update
		hydro_adapter.WithStatsClient(obsv.Statter),
		hydro_adapter.WithHydroBrokers(strings.Join(cfg.HydroBrokers, ",")),
		hydro_adapter.WithCuratedSegments(),
	)
	if err != nil {
		return nil, fmt.Errorf("creating hydro adapter: %w", err)
	}

	cacheReady, err := hydroAdapter.Start(ctx)
	if err != nil {
		return nil, fmt.Errorf("starting hydro adapter: %w", err)
	}

	// Wait for cache to become ready
	ready := false
	select {
	case <-cacheReady:
		// Cache is ready
		ready = true
	case <-time.After(5 * time.Second):
		// Timeout after 5 seconds
		obsv.Logger.Warn("feature flag cache not ready after 5 seconds")
	}

	vexiClient, err := vexi.NewVexiClient(ctx,
		hydroAdapter,
		cfg.ServiceName,
		vexi.WithLogger(obsv.Logger.Named("vexi")),
		vexi.WithStatsClient(obsv.Statter),
	)
	if err != nil {
		return nil, fmt.Errorf("creating vexi client: %w", err)
	}

	ffc := &FeatureFlagClient{
		client: vexiClient,
		obsv:   obsv.WithNamedLogger("feature-flags"),
	}

	if !ready {
		go func() {
			<-cacheReady
			ffc.obsv.Logger.Info("feature flag client is now ready")
			ffc.ready.Store(true)
		}()
	} else {
		ffc.ready.Store(true)
	}

	return ffc, nil
}

// NewClientWithExistingVexiClient creates a new feature flag client using an existing Vexi client.
func NewClientWithExistingVexiClient(flagger features.Flagger, obsv observability.Exporters) Client {
	ffc := &FeatureFlagClient{
		client: flagger,
		obsv:   obsv.WithNamedLogger("feature-flags"),
	}
	// The provided flagger is already cacheReady
	ffc.ready.Store(true)
	return ffc
}
