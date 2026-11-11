package launcher

import (
	"context"
	"strings"

	"github.com/github/sweagentd/internal/featureflags"
)

// RuntimeFeatureFlags contains the set of feature flags to be passed to the agent runtime.
type RuntimeFeatureFlags struct {
	// Contains feature flags that can be enabled via any method: user, repo, or owner.
	enabledViaAny []string
	// Contains feature flags that can be enabled via any method (user/repo/owner)
	// but are ONLY forwarded to the runtime when the launching agentic app is the
	// Copilot coding agent (CCA).
	enabledViaAnyCopilotOnly []string
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

// ℹ️ If you need to flag runtime functionality using complex rules, add a function to runtime_policy.go instead.
//
// NOTE: feature flag names may be visible to the user in logs or other output.
var runtimeFeatureFlags = RuntimeFeatureFlags{
	enabledViaAny: []string{
		featureflags.CopilotSWEAgentAutoIntent,
		featureflags.CopilotInjectIntegrationHeaders,
		"copilot_swe_agent_background_agents",
		"copilot_swe_agent_blackbird_tool_use",
		featureflags.CopilotSWEAgentCapClaudeOpusTokenLimits,
		"copilot_swe_agent_cleanup_partial_clone",
		"copilot_swe_agent_clone_session_logging",
		"copilot_swe_agent_firewall_enabled_by_default",
		"copilot_swe_agent_online_evaluation_disabled",
		"copilot_swe_agent_online_eval_use_claude_haiku_4_5",
		"copilot_swe_agent_online_eval_use_gpt_5_4_nano",
		// TODO: Remove this once we are confident about error handling in prod
		"copilot_swe_agent_simulate_runtime_git_clone_error",
		// TODO: Remove this once we are confident about error handling in prod
		"copilot_swe_agent_simulate_runtime_git_push_error",
		"copilot_swe_agent_vision",
		"copilot_swe_agent_parallel_tool_execution",
		"copilot_swe_agent_parallel_task_execution",
		"copilot_swe_agent_playwright_use_firewall",
		"copilot_swe_agent_enable_security_tool",
		"copilot_swe_agent_enable_security_tool_disabled",
		"copilot_swe_agent_request_logging",
		"copilot_swe_agent_code_review",
		"copilot_swe_agent_code_review_disabled",
		featureflags.CopilotSWEAgentCCAUseTSAutofind,
		featureflags.CopilotSWEAgentCopilotOnlyCommentAction,
		featureflags.CopilotSWEAgentIntervalAgentPromptAsProblemStatement,
		"copilot_swe_agent_validation_agent_dependencies",
		"copilot_swe_agent_validation_tool_settings",
		"copilot_swe_agent_secret_scanning_hook",
		"copilot_swe_agent_secret_scanning_iterate_on_secrets",
		"copilot_swe_agent_secret_scanning_update_pr_description",
		"copilot_swe_agent_v2_callback_api",
		"copilot_swe_agent_new_out_proc_mcp",
		"copilot_swe_agent_enable_dependabot_checker",
		"copilot_swe_agent_enable_dependabot_checker_disabled",
		"copilot_swe_agent_enable_responses_api",
		"copilot_swe_agent_use_agent_progress_api",
		featureflags.CopilotSWEAgentUseNonBlockingCallbacks,
		"copilot_swe_agent_overlay_analysis",
		featureflags.CodingAgentPlanTags,
		featureflags.CopilotSWEAgentTrivialChange,
		featureflags.CopilotSWEAgentTrivialChangeCodeReview,
		featureflags.CopilotSWEAgentTrivialChangeCodeReviewDisable,
		featureflags.CopilotSWEAgentTrivialChangeDisable,
		featureflags.CopilotSWEAgentTrivialChangeSkip,
		featureflags.CopilotSWEAgentTrivialChangeSkipCodeReview,
		featureflags.CopilotSWEAgentTrivialChangeSkipDisable,
		"copilot_swe_agent_unified_task_tool",
		"copilot_swe_agent_unified_task_tool_disable",
		"copilot_swe_agent_snippy_annotations",
		featureflags.CopilotSWEAgentErrorAnnotations,
		featureflags.CopilotSWEAgentCodexErrorClassification,
		featureflags.CopilotSWEAgentClaudeErrorClassification,
		featureflags.CopilotSWEAgentRuntimeTimingTelemetry,
		"copilot_swe_agent_snippy_soft_blocking",
		"copilot_swe_agent_snippy_hard_blocking",
		// Cross-product flag uses a different naming scheme (hyphens) to be
		// consistent with flag names across different repositories.
		"copilot-feature-agentic-memory-disabled",
		featureflags.CopilotSWEAgentPRDescCache,
		featureflags.CopilotSWEAgentParallelValidation,
		featureflags.CopilotSWEAgentParallelValidationDisabled,
		"copilot_swe_agent_3p_security_prompt",
		"copilot_swe_agent_new_security_tools",
		featureflags.CopilotSWEAgentRuntimeFilterSecretsFromMCPToolCalls,
		featureflags.CopilotSWEAgentOIDCTokenExchange,
		featureflags.CopilotSWEAgentLogsURLTrailer,
		featureflags.CopilotSWEAgentUseAttachmentProxy,
		"sweagentd_report_progress_only_push",
		"sweagentd_force_push_after_rebase",
		"copilot_swe_agent_co_author_hook",
		"copilot_coding_agent_token_based_billing",
		"copilot_swe_agent_high_reasoning_gpt_53_codex",
		"copilot_swe_agent_high_reasoning_gpt_54",
		"copilot_feature_agentic_memory_user_scoped",
		"copilot_feature_agentic_memory_user_scoped_cfi",
		"copilot_swe_agent_chronicle",
	},
	enabledViaRepo: []string{
		// The agentic memory feature flag is only enabled via repo only so that we don't
		// accidentally try to store (or retrieve) memories for personal repos outside
		// of the GH org that belong to staff during the staffship.
		// Cross-product flag uses a different naming scheme (hyphens) to be
		// consistent with flag names across different repositories.
		"copilot-feature-agentic-memory",
	},
	enabledViaAnyCopilotOnly: []string{
		// The MCP permission gate is only implemented in the CCA runtime.
		// Third-party agents (Claude, Codex) are tactically excluded for now
		// until we get feature parity in those runtime variances.
		featureflags.CopilotSWEAgentMCPPermissionGate,
	},
}

func getFeatureFlags(
	ctx context.Context,
	ffClient featureflags.Client,
	opts *LaunchAgentOpts,
	isCopilotCodingAgent bool) ([]string, error) {
	var result []string

	// Check flags that can be enabled via any method
	for _, flag := range runtimeFeatureFlags.enabledViaAny {
		if ffClient.IsEnabledForUserOrRepoOrOwner(ctx, flag, opts) {
			result = append(result, strings.TrimSpace(flag))
		}
	}

	// Check flags that can be enabled via any method but only forwarded for
	// the Copilot coding agent.
	if isCopilotCodingAgent {
		for _, flag := range runtimeFeatureFlags.enabledViaAnyCopilotOnly {
			if ffClient.IsEnabledForUserOrRepoOrOwner(ctx, flag, opts) {
				result = append(result, strings.TrimSpace(flag))
			}
		}
	}

	// Check flags that can only be enabled via repo
	for _, flag := range runtimeFeatureFlags.enabledViaRepo {
		if ffClient.IsEnabledForRepo(ctx, flag, opts.GetRepositoryID()) {
			result = append(result, strings.TrimSpace(flag))
		}
	}

	// Evaluate runtime policy rules and append outcomes as prefixed feature flags
	pe := &RuntimePolicyEvaluator{ffClient: ffClient}
	flags, err := pe.EvaluateAsFlags(ctx, opts)
	if err != nil {
		return nil, err
	}
	result = append(result, flags...)

	return result, nil
}
