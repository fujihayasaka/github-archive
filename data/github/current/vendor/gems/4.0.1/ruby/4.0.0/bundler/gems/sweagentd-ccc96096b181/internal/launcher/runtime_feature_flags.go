package launcher

import (
	"context"
	"strings"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/sweagentd"
)

// RuntimeFeatureFlags contains the set of feature flags to be passed to the agent runtime.
type RuntimeFeatureFlags struct {
	// Contains feature flags that can be enabled via any method: user, repo, or owner.
	enabledViaAny []string
	// Contains feature flags that can only be enabled via the repo.
	enabledViaRepo []string
}

// The set of feature flags that will be pre-queried and passed to the agent
// runtime process.
//
// Only flags listed here are passed to the runtime.
//
// To add a new flag:
//   - Define it in accordance with the feature flag docs: https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/
//   - Check whether it exists in the following object.
//   - ⚠️ IMPORTANT - set the owning service as 'sweagentd' to ensure that this code
//     can read its value and pass it to the runtime.
//
// NOTE: feature flag names may be visible to the user in logs or other output.
var runtimeFeatureFlags = RuntimeFeatureFlags{
	enabledViaAny: []string{
		"copilot_swe_agent_blackbird_tool_use",
		"copilot_swe_agent_firewall_enabled_by_default",
		"copilot_swe_agent_online_evaluation_disabled",
		"copilot_swe_agent_online_eval_use_claude_haiku_4_5",
		// TODO: Remove this once we are confident about error handling in prod
		"copilot_swe_agent_simulate_runtime_git_clone_error",
		// TODO: Remove this once we are confident about error handling in prod
		"copilot_swe_agent_simulate_runtime_git_push_error",
		"copilot_swe_agent_vision",
		"copilot_swe_agent_parallel_tool_execution",
		"copilot_swe_agent_playwright_use_firewall",
		featureflags.CopilotSWEAgentPlaywrightLazyStart,
		"copilot_swe_agent_enable_security_tool",
		"copilot_swe_agent_enable_security_tool_disabled",
		"copilot_swe_agent_request_logging",
		"copilot_swe_agent_code_review",
		"copilot_swe_agent_code_review_disabled",
		"copilot_swe_agent_validation_agent_dependencies",
		"copilot_swe_agent_secret_scanning_hook",
		"copilot_swe_agent_secret_scanning_iterate_on_secrets",
		"copilot_swe_agent_secret_scanning_update_pr_description",
		"copilot_swe_agent_v2_callback_api",
		"copilot_swe_agent_enable_dependabot_checker",
		"copilot_swe_agent_enable_dependabot_checker_disabled",
		"copilot_swe_agent_enable_responses_api",
		"copilot_swe_agent_use_agent_progress_api",
		featureflags.CopilotSWEAgentUseNonBlockingCallbacks,
		"copilot_swe_agent_overlay_analysis",
		featureflags.CodingAgentProposeTasks,
		featureflags.CodingAgentProposeTasks + "_disabled",
		"copilot_swe_agent_unified_task_tool",
		"copilot_swe_agent_unified_task_tool_disable",
		"copilot_swe_agent_snippy_annotations",
		featureflags.CopilotSWEAgentCleanGitConfig,
		featureflags.CopilotSWEAgentErrorAnnotations,
	},
	enabledViaRepo: []string{
		// The agentic memory feature flag is only enabled via repo only so that we don't
		// accidentally try to store (or retrieve) memories for personal repos outside
		// of the GH org that belong to staff during the staffship.
		"copilot-feature-agentic-memory",
		"copilot_swe_agent_parallel_task_execution",
	},
}

func getFeatureFlags(
	ctx context.Context,
	ffClient featureflags.Client,
	actors sweagentd.RepositoryWithActor) []string {
	var result []string

	// Check flags that can be enabled via any method
	for _, flag := range runtimeFeatureFlags.enabledViaAny {
		if ffClient.IsEnabledForUserOrRepoOrOwner(ctx, flag, actors) {
			result = append(result, strings.TrimSpace(flag))
		}
	}

	// Check flags that can only be enabled via repo
	for _, flag := range runtimeFeatureFlags.enabledViaRepo {
		if ffClient.IsEnabledForRepo(ctx, flag, actors.GetRepositoryID()) {
			result = append(result, strings.TrimSpace(flag))
		}
	}

	return result
}
