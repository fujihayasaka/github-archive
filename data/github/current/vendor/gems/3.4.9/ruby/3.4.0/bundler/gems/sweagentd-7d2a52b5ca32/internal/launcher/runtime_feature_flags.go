package launcher

import (
	"context"
	"strings"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/sweagentd"
)

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
		"copilot_swe_agent_firewall_enabled_by_default",
		"copilot_swe_agent_online_evaluation_disabled",
		"copilot_swe_agent_online_eval_use_claude_haiku_4_5",
		// TODO: Remove this once we are confident about error handling in prod
		"copilot_swe_agent_simulate_runtime_git_clone_error",
		// TODO: Remove this once we are confident about error handling in prod
		"copilot_swe_agent_simulate_runtime_git_push_error",
		"copilot_swe_agent_resolve_repo_images",
		"copilot_swe_agent_vision",
		"copilot_swe_agent_parallel_tool_execution",
		"copilot_swe_agent_memory_in_repo_store",
		"copilot_swe_agent_memory_service",
		"copilot_swe_agent_playwright_use_firewall",
		"copilot_swe_agent_enable_security_tool",
		"copilot_swe_agent_enable_security_tool_disabled",
		"copilot_swe_agent_request_logging",
		"copilot_swe_agent_code_review",
		"copilot_swe_agent_validation_agent_dependencies",
		"copilot_swe_agent_resize_image_references",
		"copilot_swe_agent_secret_scanning_hook",
		"copilot_swe_agent_secret_scanning_iterate_on_secrets",
		"copilot_swe_agent_secret_scanning_update_pr_description",
		// TODO: Remove this once subagents enabled by default - left with old name given ff is staff shipped
		"copilot_swe_agent_use_subagents",
		"copilot_swe_agent_search",
		"copilot_swe_agent_v2_callback_api",
		"copilot_swe_agent_progress_commands",
		"copilot_swe_agent_use_subagents_as_tools",
		"copilot_swe_agent_memory_storage",
		"copilot_swe_agent_memory_usage",
		"copilot_swe_agent_respect_pr_templates",
		"copilot_swe_agent_enable_dependabot_checker",
		"copilot_swe_agent_enable_dependabot_checker_disabled",
		"copilot_swe_agent_org_instructions_priority",
		"copilot_swe_agent_enable_responses_api",
	},
	enabledViaRepo: []string{},
}

func getFeatureFlags(
	ffClient featureflags.Client,
	ctx context.Context,
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
