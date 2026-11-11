package featureflags

// Feature flag constants - keep these sorted alphabetically by constant name to reduce merge conflicts.
// Comments go on the line above each constant to minimize merge conflicts.
const (
	// ActionsAgentSecrets enables looking up agent secrets and variables instead of copilot environment secrets.
	ActionsAgentSecrets = "actions_agent_secrets"

	// CodingAgent3PAutoModel gates filtering of premium (3x+) models from auto mode selection,
	// ensuring users are only assigned 1x models when they select "auto".
	CodingAgent3PAutoModel = "3p_auto_model"

	// CodingAgentAPIMetricTags gates auth_type and api_target tags on sweagentd.github.api.* metrics.
	CodingAgentAPIMetricTags = "coding_agent_api_metric_tags"

	// CodingAgentAutoModelExpanded enables the expanded auto model list (Sonnet 4.6, Sonnet 4.5, GPT 5.4, GPT 5.3 Codex, GPT 5.2 Codex)
	CodingAgentAutoModelExpanded = "coding_agent_auto_model_expanded"

	// CodingAgentAutoModelExperiment gates the auto mode model experiment and the auto mode repricing strategy
	CodingAgentAutoModelExperiment = "coding_agent_auto_model_experiment"

	// CodingAgentAutoModelForceVariantA forces auto mode to use the variant A model (for testing the session token billing path)
	CodingAgentAutoModelForceVariantA = "coding_agent_auto_model_force_variant_a"

	// CodingAgentAutoModelForceVariantB forces auto mode to use the variant B model (for testing the session token billing path)
	CodingAgentAutoModelForceVariantB = "coding_agent_auto_model_force_variant_b"

	// CodingAgentCAPI3pIntegrationID gates sending the Copilot-Agent-Type header on /models calls
	// for partner agents (e.g. Claude, Codex).
	CodingAgentCAPI3pIntegrationID = "coding_agent_capi_3p_integration_id"

	// CodingAgentCAPIVersion20260109 gates bumping the CAPI API version from 2025-05-01 to 2026-01-09
	CodingAgentCAPIVersion20260109 = "coding_agent_capi_version_20260109"

	// CodingAgentForceRestrictedTelemetry forces restricted telemetry to be emitted for a user (includes GitHub staff and Microsoft members via custom gates).
	CodingAgentForceRestrictedTelemetry = "coding_agent_force_restricted_telemetry"

	// CodingAgentLearningMachinePipelineEvents gates emission of StandardEvent to the unified experiment pipeline.
	CodingAgentLearningMachinePipelineEvents = "coding_agent_learning_machine_pipeline_events"

	// CodingAgentMemoryStandardEvents gates emission of memory standard events.
	CodingAgentMemoryStandardEvents = "coding_agent_memory_standard_events"

	// CodingAgentModelPickerClaudeHaiku45 gates Claude Haiku 4.5 in the coding agent model picker
	CodingAgentModelPickerClaudeHaiku45 = "copilot_swe_agent_model_picker_claude_haiku_45"

	// CodingAgentModelPickerClaudeOpus45 gates Claude Opus 4.5 in the coding agent model picker
	CodingAgentModelPickerClaudeOpus45 = "copilot_swe_agent_model_picker_claude_opus_45"

	// CodingAgentModelPickerClaudeOpus46 gates Claude Opus 4.6 in the coding agent model picker
	CodingAgentModelPickerClaudeOpus46 = "copilot_swe_agent_model_picker_claude_opus_46"

	// CodingAgentModelPickerClaudeOpus47 gates Claude Opus 4.7 in the coding agent model picker
	CodingAgentModelPickerClaudeOpus47 = "copilot_swe_agent_model_picker_claude_opus_47"

	// CodingAgentModelPickerClaudeOpus48 gates Claude Opus 4.8 in the coding agent model picker
	CodingAgentModelPickerClaudeOpus48 = "copilot_swe_agent_model_picker_claude_opus_48"

	// CodingAgentModelPickerClaudeSonnet45 gates Claude Sonnet 4.5 in the coding agent model picker
	CodingAgentModelPickerClaudeSonnet45 = "copilot_swe_agent_model_picker_claude_sonnet_45"

	// CodingAgentModelPickerClaudeSonnet46 gates Claude Sonnet 4.6 in the coding agent model picker
	CodingAgentModelPickerClaudeSonnet46 = "copilot_swe_agent_model_picker_claude_sonnet_46"

	// CodingAgentModelPickerGPT41 gates GPT 4.1 in the coding agent model picker
	CodingAgentModelPickerGPT41 = "copilot_swe_agent_model_picker_gpt_41"

	// CodingAgentModelPickerGPT52 gates GPT 5.2 in the coding agent model picker
	CodingAgentModelPickerGPT52 = "copilot_swe_agent_model_picker_gpt_52"

	// CodingAgentModelPickerGPT52Codex gates GPT 5.2 Codex in the coding agent model picker
	CodingAgentModelPickerGPT52Codex = "copilot_swe_agent_model_picker_gpt_52_codex"

	// CodingAgentModelPickerGPT53Codex gates GPT 5.3 Codex in the coding agent model picker
	CodingAgentModelPickerGPT53Codex = "copilot_swe_agent_model_picker_gpt_53_codex"

	// CodingAgentModelPickerGPT54 gates GPT 5.4 in the coding agent model picker
	CodingAgentModelPickerGPT54 = "copilot_swe_agent_model_picker_gpt_54"

	// CodingAgentModelPickerGPT54Mini gates GPT 5.4 Mini in the coding agent model picker
	CodingAgentModelPickerGPT54Mini = "copilot_swe_agent_model_picker_gpt_54_mini"

	// CodingAgentModelPickerGPT55 gates GPT 5.5 in the coding agent model picker
	CodingAgentModelPickerGPT55 = "copilot_swe_agent_model_picker_gpt_55"

	// CodingAgentModelPickerGPT5Mini gates GPT 5 Mini in the coding agent model picker
	CodingAgentModelPickerGPT5Mini = "copilot_swe_agent_model_picker_gpt_5_mini"

	// CodingAgentModelPickerGemini31ProPreview gates Gemini 3.1 Pro Preview in the coding agent model picker
	CodingAgentModelPickerGemini31ProPreview = "copilot_swe_agent_model_picker_gemini_31_pro_preview"

	// CodingAgentModelPickerGemini35Flash gates Gemini 3.5 Flash in the coding agent model picker
	CodingAgentModelPickerGemini35Flash = "copilot_swe_agent_model_picker_gemini_35_flash"

	// CodingAgentModelPickerOsweMagpie gates OSWE Magpie in the coding agent model picker
	CodingAgentModelPickerOsweMagpie = "copilot_swe_agent_model_picker_oswe_magpie"

	// CodingAgentModelSelectionAllSKUs enables model selection for all SKUs, not just Pro and Pro+ individual plans
	CodingAgentModelSelectionAllSKUs = "coding_agent_model_selection_all_skus"

	// CodingAgentModelSelectionInJobResponse enables including model selection metadata
	// (vendor, available models, default model) in the agent job response
	// so that engines can perform dynamic model selection.
	CodingAgentModelSelectionInJobResponse = "coding_agent_model_selection_in_job_response"

	// CodingAgentPlanTags enables <plan> tag directions in the task agent prompt
	CodingAgentPlanTags = "coding_agent_plan_tags"

	// CodingAgentThirdPartyModelVendorFilter enables vendor-based model filtering for third-party agents
	CodingAgentThirdPartyModelVendorFilter = "coding_agent_third_party_model_vendor_filter"

	// CopilotAutomationsBlockPublicRepos gates blocking automation triggers on public repositories.
	CopilotAutomationsBlockPublicRepos = "copilot_automations_block_public_repos"
	// CopilotCloudAgentIncludeCopilotEnvironmentInDynamicWorkflow keeps the copilot environment
	// attached to dynamic workflows even when agent secrets are enabled.
	CopilotCloudAgentIncludeCopilotEnvironmentInDynamicWorkflow = "copilot_cloud_agent_include_copilot_environment_in_dynamic_workflow"

	// CopilotInjectIntegrationHeaders gates whether the agent runtime injects
	// Copilot-Integration-Id headers on its CAPI calls so that requests are
	// routed to the correct integration (e.g. claude-code-cloud, codex-cloud,
	// third-party-agentic) rather than defaulting to copilot-developer.
	CopilotInjectIntegrationHeaders = "copilot_inject_integration_headers"

	// CopilotMemoryAdminExports gates admin exports of Copilot Memory.
	CopilotMemoryAdminExports = "copilot_memory_admin_exports"

	// CopilotSWEAgentAIBranchNameGenerationFollowsRules ensures that branch names follow specific rules
	CopilotSWEAgentAIBranchNameGenerationFollowsRules = "copilot_swe_agent_ai_branch_name_generation_follows_rules"

	// CopilotSWEAgentAINameGeneration enables AI-powered branch and session name generation
	CopilotSWEAgentAINameGeneration = "copilot_swe_agent_ai_name_generation"

	// CopilotSWEAgentAINameGenerationImprovedPrompt uses an improved prompt that generates appropriate titles for non-coding tasks
	CopilotSWEAgentAINameGenerationImprovedPrompt = "copilot_swe_agent_ai_name_generation_improved_prompt"

	// CopilotSWEAgentAINameGenerationUseEventContent uses the user's base-provided
	// prompt (job event content) instead of the full problem statement when
	// generating job names via AI.
	CopilotSWEAgentAINameGenerationUseEventContent = "copilot_swe_agent_ai_name_generation_use_event_content"

	// CopilotSWEAgentAINameGenerationUseGPT54Nano uses gpt-5.4-nano instead of gpt-4o-mini for name generation
	CopilotSWEAgentAINameGenerationUseGPT54Nano = "copilot_swe_agent_ai_name_generation_use_gpt54_nano"

	// CopilotSWEAgentAPIDisallow disallows specific users or apps from using the API for abuse
	CopilotSWEAgentAPIDisallow = "copilot_swe_agent_api_disallow"

	// CopilotSWEAgentAPIRateLimitHandling enables proper 429 responses with Retry-After headers
	// for rate limit errors during authorization instead of returning 500.
	CopilotSWEAgentAPIRateLimitHandling = "copilot_swe_agent_api_rate_limit_handling"

	// CopilotSWEAgentAgenticAppDisableEtagOnPRLinkage replaces the full-document ETag check
	// with a targeted pull_request_id condition when persisting PR linkage fields on jobs
	// and assignments. This prevents 412 errors from unrelated concurrent field updates
	// while still guarding against duplicate PR linkage.
	CopilotSWEAgentAgenticAppDisableEtagOnPRLinkage = "copilot_swe_agent_disable_etag_on_pr_linkage"

	CopilotSWEAgentAgenticApps = "copilot_swe_agent_agentic_apps"

	// CopilotSWEAgentAqueductTracePropagation enables W3C trace context propagation through Aqueduct job headers
	CopilotSWEAgentAqueductTracePropagation = "copilot_swe_agent_aqueduct_trace_propagation"

	// CopilotSWEAgentAutoIntent gates calling CAPI's POST /models/session/intent
	// (auto-intent ML routing) to refine the auto-mode model picked for a job.
	// Requires that a CAPI auto-mode session token has already been minted for
	// the job; only relevant for jobs that already qualify for auto-mode.
	CopilotSWEAgentAutoIntent = "copilot_swe_agent_auto_intent"

	// CopilotSWEAgentBackgroundMkcertKeygen starts mkcert CA key generation in the background before MCP server startup
	CopilotSWEAgentBackgroundMkcertKeygen = "copilot_swe_agent_background_mkcert_keygen"

	// CopilotSWEAgentBackoffSessionClientRetryNotFound enables retries for not found errors in session client requests
	CopilotSWEAgentBackoffSessionClientRetryNotFound = "copilot_swe_agent_backoff_session_client_retry_not_found"

	// CopilotSWEAgentBackoffSessionClientRetryUnauthorized enables retries for unauthorized errors in session client requests
	CopilotSWEAgentBackoffSessionClientRetryUnauthorized = "copilot_swe_agent_backoff_session_client_retry_unauthorized"

	// CopilotSWEAgentBlockDefaultBranch enables the check that prevents the agent
	// from pushing directly to a repository's default branch.
	CopilotSWEAgentBlockDefaultBranch = "copilot_swe_agent_block_default_branch"

	// CopilotSWEAgentCCATriggeringMCPToolsDisallow is a long-term feature flag that can be used for a user, repo, or org
	// to disallow GH MCP tools that can invoke CCA. It is intended to be an ops/abuse mitigation flag only.
	CopilotSWEAgentCCATriggeringMCPToolsDisallow = "copilot_swe_agent_cca_triggering_mcp_tools_disallow"

	// CopilotSWEAgentCCATriggeringMCPToolsEnabled is a tactical enabling feature flag that controls whether CCA can invoke tools.
	// This will ultimately be replaced by an enterprise policy instead of a dotcom feature flag.
	CopilotSWEAgentCCATriggeringMCPToolsEnabled = "copilot_swe_agent_cca_triggering_mcp_tools_enabled"

	// CopilotSWEAgentCCAUseTSAutofind gates the CCA v1 code_review tool dispatching onto
	// TS Autofind in the agent runtime. See github/agents#1039.
	CopilotSWEAgentCCAUseTSAutofind = "copilot_swe_agent_cca_use_ts_autofind"

	// CopilotSWEAgentCCRDisableFirewall forces the agent firewall off for CCR jobs, bringing the
	// new sweagentd-driven CCR path to parity with the legacy CCR workflow (which never enforced
	// a firewall). Safe today because CCR's only new tooling over legacy is MCP, which already
	// runs outside the firewall. Revisit when CCR exposes a bash tool.
	CopilotSWEAgentCCRDisableFirewall = "sweagentd_ccr_disable_firewall"

	// CopilotSWEAgentCCRDisableRunsOnOverride is a CCR-scoped kill switch: when enabled for a CCR
	// job, drop any runs-on coming from copilot-setup-steps.yml and skip the org-configured
	// default CCA runner override so customer-owned runner configuration (including SHR) does
	// not leak into CCR runs. Runs-on falls back to the next sweagentd layer (custom image label
	// for non-Autofind agents, or the configured default runs-on expression for Autofind agents
	// like CCR today).
	CopilotSWEAgentCCRDisableRunsOnOverride = "sweagentd_ccr_disable_runs_on_override"

	// CopilotSWEAgentCCREnableFirewall cancels the CCR disable-firewall flag for targeted traffic.
	CopilotSWEAgentCCREnableFirewall = "sweagentd_ccr_enable_firewall"

	// CopilotSWEAgentCacheMintedTokensUsingOwnerID switches the minted-token cache keying strategy to use an installation-by-owner
	// ClientTarget instead of an app-level ClientTarget when constructing the token cache key.
	CopilotSWEAgentCacheMintedTokensUsingOwnerID = "copilot_swe_agent_cache_minted_tokens_owner_id" //nolint:gosec // This is not a secret token, just the name of a feature flag.

	// CopilotSWEAgentCacheMissLogging enables verbose logging of token store cache misses for debugging
	CopilotSWEAgentCacheMissLogging = "copilot_swe_agent_cache_miss_logging"

	// CopilotSWEAgentCachedRPCFetchSubspans enables nested fetch spans for cache-backed githubtwirp RPC methods.
	CopilotSWEAgentCachedRPCFetchSubspans = "copilot_swe_agent_cached_rpc_fetch_subspans"

	CopilotSWEAgentCanSelectModel = "sweagentd_can_select_model"

	// CopilotSWEAgentCapClaudeOpusTokenLimits gates capping Claude Opus token limits in the agent runtime.
	CopilotSWEAgentCapClaudeOpusTokenLimits = "copilot_swe_agent_cap_claude_opus_token_limits" //nolint:gosec // This is not a secret token, just the name of a feature flag.

	// CopilotSWEAgentCheckAgenticAppAuth gates the execution-time authorization check for agentic apps.
	CopilotSWEAgentCheckAgenticAppAuth = "copilot_swe_agent_check_agentic_app_auth"

	// CopilotSWEAgentCheckGitHubAppPermissions gates the pre-flight check that requires the
	// originating GitHub App (the App used to post a PR comment or submit a PR review) to have
	// `contents:write` on the repository before sweagentd will trigger an agent job. Closes the
	// privilege-escalation gap where a user-to-server token would otherwise inherit the
	// commenting user's permissions even when the App itself lacks them. See issue #9000.
	CopilotSWEAgentCheckGitHubAppPermissions = "copilot_swe_agent_check_github_app_permissions"

	// CopilotSWEAgentClaudeErrorClassification enables wrapping Claude SDK errors in ClaudeError
	// with message-based classification (e.g., rate_limit) for structured error reporting.
	CopilotSWEAgentClaudeErrorClassification = "copilot_swe_agent_claude_error_classification"

	// CopilotSWEAgentClientTokenRefreshOn401 enables automatic token refresh and retry on HTTP 401
	// for server-to-server GitHub API clients, handling stale cached tokens after app reinstalls.
	CopilotSWEAgentClientTokenRefreshOn401 = "copilot_swe_agent_client_token_refresh_on_401" //nolint:gosec // This is not a secret token, just the name of a feature flag.

	// CopilotSWEAgentCodeScanningCopilotAuth gates using Copilot app credentials for Code Scanning
	// agent dynamic workflow launches instead of the Code Scanning app's own credentials.
	CopilotSWEAgentCodeScanningCopilotAuth = "copilot_swe_agent_code_scanning_copilot_auth"

	// CopilotSWEAgentCodeScanningDisableFirewall forces the agent firewall off for Code Scanning
	// jobs. The Code Scanning app has a narrow, well-known egress profile and the repo-level CCA
	// firewall settings are not applicable to it.
	CopilotSWEAgentCodeScanningDisableFirewall = "sweagentd_code_scanning_disable_firewall"

	// CopilotSWEAgentCodexErrorClassification enables wrapping Codex SDK errors in CodexError
	// with message-based classification (e.g., rate_limit) for structured error reporting.
	CopilotSWEAgentCodexErrorClassification = "copilot_swe_agent_codex_error_classification"

	// CopilotSWEAgentConfigSync enables the agent config sync service that persists custom agent configs to CosmosDB
	CopilotSWEAgentConfigSync = "copilot_swe_agent_config_sync"

	// CopilotSWEAgentConfigSyncEnvRouting gates environment routing for agentsync.
	// When enabled, only the correct environment processes each sync event,
	// preventing duplicate CosmosDB records across environments.
	CopilotSWEAgentConfigSyncEnvRouting = "copilot_swe_agent_config_sync_env_routing"

	// CopilotSWEAgentCopilotOnlyCommentAction restricts the agent's feedback prompt
	// to only act on PR comments that explicitly @copilot-mention the agent.
	// When enabled, the runtime treats non-mentioning comments as context only.
	CopilotSWEAgentCopilotOnlyCommentAction = "copilot_swe_agent_copilot_only_comment_action"

	CopilotSWEAgentCustomAgentAsAPI = "copilot_swe_agent_custom_agent_as_api"

	// CopilotSWEAgentCustomAgentListDefaultToAll when enabled, defaults to listing all custom agents if no target is specified
	CopilotSWEAgentCustomAgentListDefaultToAll = "copilot_swe_agent_custom_agent_list_default_to_all"

	// CopilotSWEAgentCustomAgentListFilterNonUserInvocableTriggered filters the public custom agent list endpoint
	// to exclude agents that are not user-invocable and have triggers configured.
	CopilotSWEAgentCustomAgentListFilterNonUserInvocableTriggered = "copilot_swe_agent_custom_agent_list_filter_non_user_invocable_triggered"

	// CopilotSWEAgentCustomAgentPrivilegedRepo allows repo-level custom agents to be privileged
	CopilotSWEAgentCustomAgentPrivilegedRepo = "copilot_swe_agent_custom_agent_privileged_repo"

	// CopilotSWEAgentCustomAgentTriggers gates processing of all custom agent trigger events
	CopilotSWEAgentCustomAgentTriggers = "copilot_swe_agent_custom_agent_triggers"

	// CopilotSWEAgentCustomAgentTriggersDisableInterval disables interval trigger scheduling and execution as a safety measure.
	// Syncing and DB persistence of interval triggers continue unaffected.
	CopilotSWEAgentCustomAgentTriggersDisableInterval = "copilot_swe_agent_custom_agent_triggers_disable_interval"

	// CopilotSWEAgentCustomAgentTriggersDisableManual gates processing of manual automation run requests.
	CopilotSWEAgentCustomAgentTriggersDisableManual = "copilot_swe_agent_custom_agent_triggers_disable_manual"

	// CopilotSWEAgentCustomAgentsDisallow disallows specific users, orgs, or apps from using custom agents
	CopilotSWEAgentCustomAgentsDisallow = "copilot_swe_agent_custom_agents_disallow"

	// CopilotSWEAgentDedupJobCreation rejects CreateJobForAssignment when a queued or running job already exists for the assignment.
	CopilotSWEAgentDedupJobCreation = "copilot_swe_agent_dedup_job_creation"

	// CopilotSWEAgentDisableCustomImage disables using the custom VM image snapshot for specific users, repositories, or organizations.
	CopilotSWEAgentDisableCustomImage = "copilot_swe_agent_disable_custom_image"

	// CopilotSWEAgentDisableCustomImageOverride continues to use the custom image for specific users even if it's disabled globally
	CopilotSWEAgentDisableCustomImageOverride = "copilot_swe_agent_disable_custom_image_override"

	// CopilotSWEAgentDisallow disallows specific repositories from using the
	// Copilot coding agent. Mirrors the repo-level disallow flag enforced by
	// the monolith's RepoEligibilityChecker.
	CopilotSWEAgentDisallow = "copilot_swe_agent_disallow"

	// CopilotSWEAgentDynamicWorkflowOSDispatch renders the dynamic Actions workflow using the new OS-specific
	// template set (one OS-specific step body per render) instead of the legacy template that emits both Linux
	// and Windows variants of every step gated at runtime by `if: runner.os == 'X'`. The new path only takes
	// effect when the target OS can be statically determined from runs-on; runs-on values that resolve to
	// targetOSUnknown (runtime expressions, arrays/objects, self-hosted, custom-image label) always fall back
	// to the legacy template regardless of this flag.
	CopilotSWEAgentDynamicWorkflowOSDispatch = "copilot_swe_agent_dynamic_workflow_os_dispatch"

	// CopilotSWEAgentEmitAgentSlugTelemetry enables emitting agent_slug in telemetry stats and structured logs
	CopilotSWEAgentEmitAgentSlugTelemetry = "sweagent_emit_agent_slug_telemetry"

	// CopilotSWEAgentEmitCopilotAccessTypeStats enables emitting copilot access type in telemetry stats for analytics
	CopilotSWEAgentEmitCopilotAccessTypeStats = "sweagent_emit_copilot_access_type_stats"

	// CopilotSWEAgentEmitCopilotPlanStats enables emitting copilot plan in telemetry stats for analytics
	CopilotSWEAgentEmitCopilotPlanStats = "sweagent_emit_copilot_plan_stats"

	// CopilotSWEAgentEngineMode enables running an external engine instead of the built-in CCA runtime.
	// When enabled, the Actions launcher downloads the engine repo and executes its entrypoint
	// wrapped in the eBPF firewall.
	CopilotSWEAgentEngineMode = "copilot_swe_agent_engine_mode"

	// CopilotSWEAgentErrorAnnotations enables runtime error annotations for improved SLO tracking.
	// When enabled, the runtime emits a GitHub Actions annotation with structured error info
	// if it fails to send the error via callback to sweagentd.
	CopilotSWEAgentErrorAnnotations = "copilot_swe_agent_error_annotations"

	// CopilotSWEAgentFirewallMaterialized enables consuming materialized firewall rules from the
	// Twirp ConfigurationForRepository API instead of reading from Actions Variables directly.
	CopilotSWEAgentFirewallMaterialized = "sweagentd_firewall_rules_in_config"

	// CopilotSWEAgentForwardCAPIStatusCodes forwards CAPI rate limit (429) responses from the
	// /models endpoint to the client instead of returning 500 Internal Server Error.
	CopilotSWEAgentForwardCAPIStatusCodes = "copilot_swe_agent_forward_capi_status_codes"

	// CopilotSWEAgentGetLatestAssignment enables GetLatestAssignmentForPR which returns the most
	// recently created assignment when multiple assignments are linked to the same PR.
	CopilotSWEAgentGetLatestAssignment = "copilot_swe_agent_get_latest_assignment"

	// CopilotSWEAgentGranularMCPToolsets enables granular MCP toolsets (issues_granular, pull_requests_granular) for triggered jobs
	CopilotSWEAgentGranularMCPToolsets = "copilot_swe_agent_granular_mcp_toolsets"

	// CopilotSWEAgentHTTPRateLimit enables HTTP-level rate limiting for select sweagentd API endpoints
	CopilotSWEAgentHTTPRateLimit = "copilot_swe_agent_http_rate_limit"

	// CopilotSWEAgentHTTPTokensRateLimit enables rate limiting for the /agent/jobs/{jobID}/tokens endpoint.
	CopilotSWEAgentHTTPTokensRateLimit = "copilot_swe_agent_http_tokens_rate_limit" //nolint:gosec // not a credential

	CopilotSWEAgentIgnoreNonAgenticEventsReviewSubmit = "copilot_swe_agent_ignore_non_agentic_events_review_submit"

	CopilotSWEAgentIntegrationCodeScanningAlerts = "copilot_swe_agent_integration_code_scanning_alerts"

	// CopilotSWEAgentIntegrationQuotaExempt exempts specific apps/integrations from premium quota checks.
	// When enabled for a repository and the app declares IsQuotaExempt() = true, quota checks are skipped.
	CopilotSWEAgentIntegrationQuotaExempt = "copilot_swe_agent_integration_quota_exempt"

	// CopilotSWEAgentIntervalAgentPromptAsProblemStatement makes interval and manual automation triggers use the automation's prompt as the problem statement and skip the runtime's custom agent prompt injection. Read by the runtime via the feature flags forwarded in runtime_feature_flags.go.
	CopilotSWEAgentIntervalAgentPromptAsProblemStatement = "copilot_swe_agent_interval_agent_prompt_as_problem_statement"

	CopilotSWEAgentIssueBodyEditCheck = "sweagentd_issue_body_edit_check"

	// CopilotSWEAgentIssueOpenedTrigger gates processing of issues.opened automation trigger events per repo,
	// in addition to the CopilotSWEAgentCustomAgentTriggers umbrella flag. Both flags must be on for the trigger to fire.
	CopilotSWEAgentIssueOpenedTrigger = "copilot_swe_agent_issue_opened_trigger"

	CopilotSWEAgentIssuesCrossRepoAssignment = "issues_copilot_cross_repo_assign"

	// CopilotSWEAgentLimiterFailOpen allows jobs to proceed when the copilot-limiter
	// service is unavailable or returns transient errors during quota checks.
	// Only transient Twirp errors (Internal, Unavailable, DeadlineExceeded) are
	// eligible for fail-open; data/invariant errors remain fail-closed.
	CopilotSWEAgentLimiterFailOpen = "copilot_swe_agent_limiter_fail_open"

	// CopilotSWEAgentLogInvalidUTF8Workflow enables logging hex-encoded snippets of workflow yaml
	// that contains invalid UTF-8 bytes before dispatching the dynamic workflow run. Used to
	// investigate monolith Encoding::UndefinedConversionError errors (availability-incident-4338).
	CopilotSWEAgentLogInvalidUTF8Workflow = "copilot_swe_agent_log_invalid_utf8_workflow"

	// CopilotSWEAgentLogsURLTrailer enables adding an agent logs URL trailer to commits
	CopilotSWEAgentLogsURLTrailer = "copilot_swe_agent_logs_url_trailer"

	// CopilotSWEAgentMCPPermissionGate gates interactive user approval for non-readOnly MCP tool calls in CCA sessions
	CopilotSWEAgentMCPPermissionGate = "copilot_swe_agent_mcp_permission_gate"

	// CopilotSWEAgentMaxTriggerRetries gates the max-retry cap for workflow_run failed triggers
	CopilotSWEAgentMaxTriggerRetries = "copilot_swe_agent_max_trigger_retries"

	// CopilotSWEAgentMemoryAsyncVoting moves secret scanning and Cosmos storage for voting
	// off the HTTP critical path. When enabled, voting returns 204 immediately after
	// synchronous validations and completes the I/O work in a background goroutine.
	CopilotSWEAgentMemoryAsyncVoting = "copilot_swe_agent_memory_async_voting"

	// CopilotSWEAgentMemoryDisabledVSCode is a kill switch that disables all memory
	// operations (store, retrieve, vote, prompt) for VS Code clients.
	CopilotSWEAgentMemoryDisabledVSCode = "copilot_swe_agent_memory_disabled_vscode"

	// CopilotSWEAgentMemoryVotingCCR gates memory voting for Copilot Code Reviews clients
	CopilotSWEAgentMemoryVotingCCR = "copilot_swe_agent_memory_voting_ccr"

	// CopilotSWEAgentMemoryVotingCLI gates memory voting for Copilot CLI clients
	CopilotSWEAgentMemoryVotingCLI = "copilot_swe_agent_memory_voting_cli"

	// CopilotSWEAgentMemoryVotingCodingAgent gates memory voting for coding agent clients (CCA, Claude Code, OpenAI Codex)
	CopilotSWEAgentMemoryVotingCodingAgent = "copilot_swe_agent_memory_voting_coding_agent"

	// CopilotSWEAgentMemoryVotingVSCode gates memory voting for VS Code clients
	CopilotSWEAgentMemoryVotingVSCode = "copilot_swe_agent_memory_voting_vscode"

	// CopilotSWEAgentMergeConflictTrigger gates processing of merge conflict trigger events per repo
	CopilotSWEAgentMergeConflictTrigger = "copilot_swe_agent_merge_conflict_trigger"

	// CopilotSWEAgentMockLimiterDown simulates dependency failures in quota checks for targeted users,
	// including limiter GetQuotaRemaining and CanProceedWithUsage callback failures.
	// Temporary testing flag: remove this flag and related mock paths after validation is complete.
	CopilotSWEAgentMockLimiterDown = "copilot_swe_agent_tbb_mock_limiter_down"

	// CopilotSWEAgentMultiRepoRead gates any feature relating to multi-repo
	CopilotSWEAgentMultiRepoRead = "copilot_swe_agent_multi_repo_read"

	// CopilotSWEAgentOIDCSettingsJSON enables separate "settings.json" file that can be used to define OIDC configuration
	// for testing, multiple MCP servers or, once applicable, separate engines independent of spin up MCPs.
	CopilotSWEAgentOIDCSettingsJSON = "copilot_swe_agent_oidc_settings_json"

	// CopilotSWEAgentOIDCTokenExchange enables OIDC token exchange support for third-party integrations and MCP servers
	CopilotSWEAgentOIDCTokenExchange = "copilot_swe_agent_oidc_token_exchange" //nolint:gosec // This is not a secret token, just the name of a feature flag.

	// CopilotSWEAgentOIDCTokenExchangeDisallow is a long term ff that disables OIDC token exchange for specific users, orgs, repos, or agentic apps.
	CopilotSWEAgentOIDCTokenExchangeDisallow = "copilot_swe_agent_oidc_token_exchange_disallow" //nolint:gosec // This is not a secret token, just the name of a feature flag.

	// CopilotSWEAgentOIDCUseRepoRootMCPJSON enables loading OIDC configuration from a repository root .mcp.json file.
	CopilotSWEAgentOIDCUseRepoRootMCPJSON = "copilot_swe_agent_oidc_use_repo_root_mcp_json"

	// CopilotSWEAgentOnlineEvalUseClaudeHaiku45 uses claude-haiku-4.5 instead of gpt-4.1 for online evaluation
	CopilotSWEAgentOnlineEvalUseClaudeHaiku45 = "copilot_swe_agent_online_eval_use_claude_haiku_4_5"

	// CopilotSWEAgentOnlineEvalUseGPT54Nano uses gpt-5.4-nano instead of gpt-4.1 for online evaluation
	CopilotSWEAgentOnlineEvalUseGPT54Nano = "copilot_swe_agent_online_eval_use_gpt_5_4_nano"

	// CopilotSWEAgentPRCommentModelPicker enables model selection via @copilot+model mentions in PR comments
	CopilotSWEAgentPRCommentModelPicker = "copilot_swe_agent_pr_comment_model_picker"

	// CopilotSWEAgentPRCommentRulesCheck enables pre-flight repository rules checking
	// (both repository rulesets and classic branch protection rules) before queueing
	// a job from a PR comment or review mention.
	CopilotSWEAgentPRCommentRulesCheck = "copilot_swe_agent_pr_comment_rules_check"

	// CopilotSWEAgentPRContextQueryFallback enables a fallback to a lighter-weight GraphQL query
	// (without reactions) when the full PR context query exceeds GitHub's resource limits.
	// See https://github.com/github/sweagentd/issues/9923
	CopilotSWEAgentPRContextQueryFallback = "copilot_swe_agent_pr_context_query_fallback"

	// CopilotSWEAgentPRContextSeparateReviewThreads enables fetching review thread resolved
	// status via a separate lightweight query instead of embedding it in the main PR context query.
	// See https://github.com/github/sweagentd/issues/11901
	CopilotSWEAgentPRContextSeparateReviewThreads = "copilot_swe_agent_pr_context_separate_review_threads"

	// CopilotSWEAgentPRDescCache enables caching of PR descriptions
	CopilotSWEAgentPRDescCache = "copilot_swe_agent_pr_desc_cache"

	// CopilotSWEAgentPRStateChangeAssignmentCheck enables checking for existing
	// agent assignments when a non-agent-authored PR is closed or merged.
	CopilotSWEAgentPRStateChangeAssignmentCheck = "copilot_swe_agent_pr_state_change_assignment_check"

	// CopilotSWEAgentParallelValidation enables parallel validation for the coding agent
	CopilotSWEAgentParallelValidation = "copilot_swe_agent_parallel_validation"

	// CopilotSWEAgentParallelValidationDisabled disables parallel validation for the coding agent
	CopilotSWEAgentParallelValidationDisabled = "copilot_swe_agent_parallel_validation_disable"

	// CopilotSWEAgentPatternRuleFailureDetails includes the rejected value and expected pattern in repository pattern rule errors.
	CopilotSWEAgentPatternRuleFailureDetails = "copilot_swe_agent_pattern_rule_failure_details"

	// CopilotSWEAgentPluginsEnabled enables plugin loading from repo settings in the job DTO.
	CopilotSWEAgentPluginsEnabled = "copilot_swe_agent_plugins_enabled"

	// CopilotSWEAgentPluginsListAPIEnabled enables the plugins list API endpoint.
	CopilotSWEAgentPluginsListAPIEnabled = "copilot_swe_agent_plugins_list_api_enabled"

	// CopilotSWEAgentPullRequestMergedTrigger gates processing of pull_request.merged
	// automation trigger events per repo, in addition to the CopilotSWEAgentCustomAgentTriggers
	// umbrella flag. Both flags must be on for the trigger to fire.
	CopilotSWEAgentPullRequestMergedTrigger = "copilot_swe_agent_pull_request_merged_trigger"

	// CopilotSWEAgentPullRequestOpenedTrigger gates processing of pull_request.opened
	// automation trigger events per repo, in addition to the CopilotSWEAgentCustomAgentTriggers
	// umbrella flag. Both flags must be on for the trigger to fire.
	CopilotSWEAgentPullRequestOpenedTrigger = "copilot_swe_agent_pull_request_opened_trigger"

	// CopilotSWEAgentPullRequestSynchronizeTrigger gates processing of pull_request.synchronize
	// automation triggers. Allows independent rollout from other trigger families.
	CopilotSWEAgentPullRequestSynchronizeTrigger = "copilot_swe_agent_pull_request_synchronize_trigger"

	// CopilotSWEAgentRejectBotActors rejects bot actors from creating jobs via the twirp API.
	// Bots don't have Copilot seats or valid billing, so allowing them causes downstream failures.
	CopilotSWEAgentRejectBotActors = "copilot_swe_agent_reject_bot_actors"

	CopilotSWEAgentReplyToCommentMentionsOnNonCopilotPRs = "copilot_swe_agent_reply_to_comment_mentions_on_non_copilot_prs"

	// CopilotSWEAgentRepoConfigCustomPermissions dictates whether repo-level config can alter base permissions.
	CopilotSWEAgentRepoConfigCustomPermissions = "copilot_swe_agent_repo_config_custom_permissions"

	// CopilotSWEAgentRepoIDForDynamicWorkflows uses repo ID instead of owner/repo in the dynamic workflows API URL
	// This handles repository renames gracefully since repo IDs are immutable
	CopilotSWEAgentRepoIDForDynamicWorkflows = "copilot_swe_agent_repo_id_for_dynamic_workflows"

	// CopilotSWEAgentRunnerControlSettings enables using the organization's configured default runner when no copilot-setup-steps.yml is found
	CopilotSWEAgentRunnerControlSettings = "copilot_swe_agent_runner_control_settings"

	CopilotSWEAgentRuntimeEntryPointCCAV2 = "copilot_swe_agent_runtime_entry_point_cca_v2"

	CopilotSWEAgentRuntimeEntryPointCCAV3App = "copilot_swe_agent_runtime_entry_point_cca_v3_app"

	// CopilotSWEAgentRuntimeEntryPointCCAV3AppOptOut prevents selecting the CCA v3 runtime when the CCA v3 runtime flag is enabled.
	CopilotSWEAgentRuntimeEntryPointCCAV3AppOptOut = "copilot_swe_agent_runtime_entry_point_cca_v3_app_opt_out"

	CopilotSWEAgentRuntimeEntryPointClaude = "copilot_swe_agent_runtime_entry_point_claude"

	CopilotSWEAgentRuntimeEntryPointCodex = "copilot_swe_agent_runtime_entry_point_codex"

	// CopilotSWEAgentRuntimeFilterSecretsFromMCPToolCalls enables filtering of secrets from MCP tool calls in the runtime
	CopilotSWEAgentRuntimeFilterSecretsFromMCPToolCalls = "copilot_swe_agent_runtime_filter_secrets_from_mcp_tool_calls" //nolint:gosec // This is not a secret token, just the name of a feature flag.

	// CopilotSWEAgentRuntimeTimingTelemetry enables runtime timing telemetry emission and server-side processing
	CopilotSWEAgentRuntimeTimingTelemetry = "copilot_swe_agent_runtime_timing_telemetry"

	// CopilotSWEAgentSandboxDebugRetain retains a sandbox VM on error instead of deleting it during cleanup, so it can be inspected for debugging.
	CopilotSWEAgentSandboxDebugRetain = "copilot_swe_agent_sandbox_debug_retain"

	// CopilotSWEAgentSandboxLauncher routes jobs to the Sandbox VM launcher instead of Actions
	CopilotSWEAgentSandboxLauncher = "copilot_swe_agent_sandbox_launcher"

	// CopilotSWEAgentSandboxPersistCallbackFieldsBeforeCLIExec persists sandbox callback auth/routing fields before executing the CLI.
	CopilotSWEAgentSandboxPersistCallbackFieldsBeforeCLIExec = "copilot_swe_agent_persist_callback_fields_before_launch"

	// CopilotSWEAgentSandboxPrereleaseImage uses the prerelease sandbox disk image (cca-prerelease) instead of the stable image (cca)
	CopilotSWEAgentSandboxPrereleaseImage = "copilot_swe_agent_sandbox_prerelease_image"

	// CopilotSWEAgentScopeGitTokenWorkflows scopes GITHUB_COPILOT_GIT_TOKEN's
	// workflows:write permission to the triggering credential's authority.
	CopilotSWEAgentScopeGitTokenWorkflows = "copilot_swe_agent_scope_git_token_workflows" //nolint:gosec // This is not a secret token, just the name of a feature flag.

	// CopilotSWEAgentSelectCustomerError when enabled, fails session when customer is not selected; when disabled, logs and continues
	CopilotSWEAgentSelectCustomerError = "copilot_swe_agent_select_customer_error"

	// CopilotSWEAgentSendSessionsToAgentProgressAPI when enabled, sends (legacy) session updates to the Agent Progress API
	CopilotSWEAgentSendSessionsToAgentProgressAPI = "copilot_swe_agent_send_sessions_to_agent_progress_api"

	// CopilotSWEAgentSetupStepOutputCapture enables capturing stdout+stderr from bash setup steps and displaying them in session logs
	CopilotSWEAgentSetupStepOutputCapture = "copilot_swe_agent_setup_step_output_capture"

	// CopilotSWEAgentSetupStepOutputCaptureProcessSubstitution uses process substitution > >(tee ...) instead of a pipe (| tee)
	// for setup step output capture. This prevents steps that launch background processes (e.g. "fm server &") from hanging
	// indefinitely, because bash does not wait for process substitution subprocesses to exit.
	CopilotSWEAgentSetupStepOutputCaptureProcessSubstitution = "copilot_swe_agent_setup_step_output_capture_process_substitution"

	// CopilotSWEAgentShellTokenPermissions is a feature flag that dictates whether the shell will get the read-only CAPI token or the full-permissions token
	// or the variable token GitHub MCP servers will get. We will need to do this as a near term mitigation until we build a git proxy given changes unrelated
	// to the permissions feature. This feature flag allows us to test both scenarios locally or in staging while this proxy is being developed.
	CopilotSWEAgentShellTokenPermissions = "copilot_swe_agent_shell_token_permissions" //nolint:gosec // This is not a secret token, just the name of a feature flag.

	// CopilotSWEAgentSkillsEnabled enables skills loading from repo, org, and enterprise sources in the job DTO.
	CopilotSWEAgentSkillsEnabled = "copilot_swe_agent_skills_enabled"

	// CopilotSWEAgentSkipCallbackEnablementCheck skips the IsAgentEnabled check in agent callback, cleanup, and HTTP handlers
	CopilotSWEAgentSkipCallbackEnablementCheck = "copilot_swe_agent_skip_callback_enablement_check"

	// CopilotSWEAgentSkipDefaultBranchHeadRefCheck skips the rejection of CreateJob requests whose
	// features.pull_request.head_ref equals the repository default branch in lookupExistingPRForHeadRef.
	// Branchless agents (e.g. Copilot Code Review) are exempted regardless of this flag; the flag exists
	// to allow disabling the protection for all agents in case of incident.
	CopilotSWEAgentSkipDefaultBranchHeadRefCheck = "copilot_swe_agent_skip_default_branch_head_ref_check"

	// CopilotSWEAgentSkipPRBodyUpdateForSubsequentJobs skips updating the PR body with plan steps for
	// subsequent jobs (e.g. fix-pr-comment) on the same PR, only allowing the initial fix job to update it.
	CopilotSWEAgentSkipPRBodyUpdateForSubsequentJobs = "copilot_swe_agent_skip_pr_body_update_for_subsequent_jobs"

	// CopilotSWEAgentSkipPRCloseCancel gates the OnPullRequestStateChanged
	// skip behaviour: when enabled for a repo/owner, sweagentd does NOT
	// cancel running jobs whose agentic app opts out via
	// sweagentd.AgenticAppSkipPRCloseCancel (e.g., Copilot Code Review).
	// The in-flight job is left to complete so it does not surface as a
	// "Copilot encountered an error" review on a just-closed PR. Apps
	// that do not implement the interface are still cancelled regardless
	// of the flag.
	CopilotSWEAgentSkipPRCloseCancel = "sweagentd_skip_pr_close_cancel"

	// CopilotSWEAgentSkipPRUpdatesForCodeReviewFixJobs skips updating the PR title and body
	// for jobs created to fix a Copilot code review finding on an existing pull request
	// (event type: code_review_fix_with_copilot). This applies to both mid-session and
	// post-session updates via jobs.ShouldSkipMidSessionPRUpdate /
	// jobs.ShouldSkipPostSessionPRUpdate.
	CopilotSWEAgentSkipPRUpdatesForCodeReviewFixJobs = "copilot_swe_agent_skip_pr_updates_for_code_review_fix_jobs"

	// CopilotSWEAgentSkipPRUpdatesForFixFailedWorkflowJobs skips updating the PR title and body
	// for jobs created to fix a failed workflow run (event type: fix_failed_workflow). This applies
	// to both mid-session and post-session updates via jobs.ShouldSkipMidSessionPRUpdate /
	// jobs.ShouldSkipPostSessionPRUpdate.
	CopilotSWEAgentSkipPRUpdatesForFixFailedWorkflowJobs = "copilot_swe_agent_skip_pr_updates_for_fix_failed_workflow_jobs"

	// CopilotSWEAgentSkipPRUpdatesForPullRequestTriggerJobs skips updating the PR title and body
	// for jobs triggered by a pull request event (event types: pull_request_opened,
	// pull_request_synchronize). This applies to both mid-session and post-session updates via
	// jobs.ShouldSkipMidSessionPRUpdate / jobs.ShouldSkipPostSessionPRUpdate.
	CopilotSWEAgentSkipPRUpdatesForPullRequestTriggerJobs = "copilot_swe_agent_skip_pr_updates_for_pull_request_trigger_jobs"

	// CopilotSWEAgentSkipSecondaryRateLimitCache disables reading from the secondary (abuse) rate limit
	// cache in job processing. When enabled, jobs skip the secondary rate limit check and proceed directly
	// to primary rate limit checks. The secondary cache is still written to for observability, but reads
	// are bypassed. This prevents a single installation's secondary rate limit from globally blocking all
	// job processing (see incident #5336 / #4229).
	CopilotSWEAgentSkipSecondaryRateLimitCache = "copilot_swe_agent_skip_secondary_rate_limit_cache"

	// CopilotSWEAgentTaskAPI enables the Task API parameters for SWE Agent sessions
	CopilotSWEAgentTaskAPI = "copilot_swe_agent_task_api_parameters"

	// CopilotSWEAgentThirdPartyAgenticIntegrationID gates emission of the
	// shared `third-party-agentic` CAPI integration ID for dynamic third-party
	// agentic apps. When disabled, ThirdParty apps fall back to the runtime's
	// default integration. See ADR 0018.
	CopilotSWEAgentThirdPartyAgenticIntegrationID = "copilot_swe_agent_third_party_agentic_integration_id"

	// CopilotSWEAgentTriggersDisallowCodeChangeTools disallows GitHub MCP code-change tools for triggered
	// CCA jobs only, not the normal user-invoked flow. This covers GitHub branch/PR write tools.
	// Issue creation and similar non-code-change actions remain allowed.
	CopilotSWEAgentTriggersDisallowCodeChangeTools = "copilot_swe_agent_triggers_disallow_code_change_tools"

	// CopilotSWEAgentTriggersDisallowRuntimePublishTools disables runtime-owned publish tools
	// create_pull_request and report_progress when enabled.
	CopilotSWEAgentTriggersDisallowRuntimePublishTools = "copilot_swe_agent_triggers_disallow_runtime_publish_tools"

	// CopilotSWEAgentTrivialChange asks the model to determine whether the change is trivial
	CopilotSWEAgentTrivialChange = "copilot_swe_agent_trivial_change"

	// CopilotSWEAgentTrivialChangeCodeReview gates trivial-change awareness for the code_review tool.
	// Must be enabled in addition to CopilotSWEAgentTrivialChange for code_review to participate.
	CopilotSWEAgentTrivialChangeCodeReview = "copilot_swe_agent_trivial_change_code_review"

	// CopilotSWEAgentTrivialChangeCodeReviewDisable disables trivial-change handling for the
	// code_review tool (kill switch). Also disables per-tool skip.
	CopilotSWEAgentTrivialChangeCodeReviewDisable = "copilot_swe_agent_trivial_change_code_review_disable"

	// CopilotSWEAgentTrivialChangeDisable disables model triviality assessment (kill switch)
	CopilotSWEAgentTrivialChangeDisable = "copilot_swe_agent_trivial_change_disable"

	// CopilotSWEAgentTrivialChangeSkip actually skips validation tools when the change is trivial
	CopilotSWEAgentTrivialChangeSkip = "copilot_swe_agent_trivial_change_skip"

	// CopilotSWEAgentTrivialChangeSkipCodeReview gates the short-circuit skip for the code_review tool.
	// Must be enabled in addition to CopilotSWEAgentTrivialChangeSkip for code_review to skip.
	CopilotSWEAgentTrivialChangeSkipCodeReview = "copilot_swe_agent_trivial_change_skip_code_review"

	// CopilotSWEAgentTrivialChangeSkipDisable disables tool skipping for trivial changes (kill switch)
	CopilotSWEAgentTrivialChangeSkipDisable = "copilot_swe_agent_trivial_change_skip_disable"

	// CopilotSWEAgentTwirpProximaHookHeadersOnly enables tenant context propagation only from incoming Twirp hook headers.
	CopilotSWEAgentTwirpProximaHookHeadersOnly = "sweagentd_twirp_proxima_hook_headers_only"

	// CopilotSWEAgentUseAgentProgressAPI uses the Agent Progress API to report progress from agents
	CopilotSWEAgentUseAgentProgressAPI = "copilot_swe_agent_use_agent_progress_api"

	// CopilotSWEAgentUseAsyncSessions determines whether assignments should use async sessions
	CopilotSWEAgentUseAsyncSessions = "copilot_swe_agent_use_async_sessions"

	// CopilotSWEAgentUseAttachmentProxy enables the runtime to resolve user-attachment GUIDs via
	// the sweagentd proxy endpoint instead of calling the internal GitHub user-attachments API
	// directly from runner IPs. See #11694.
	CopilotSWEAgentUseAttachmentProxy = "copilot_swe_agent_use_attachment_proxy"

	// CopilotSWEAgentUseCustomImageAutofind enables the custom VM image for dist-autofind-ts agents (e.g. code review, code scanning)
	CopilotSWEAgentUseCustomImageAutofind = "copilot_swe_agent_use_custom_image_autofind"

	// CopilotSWEAgentUseInternalAPI enables using the internal API (internal-api.service.iad.github.net) instead of public API (api.github.com)
	CopilotSWEAgentUseInternalAPI = "copilot_swe_agent_use_internal_api"

	// CopilotSWEAgentUseNonBlockingCallbacks enables non-blocking callbacks via ExecutionQueue
	CopilotSWEAgentUseNonBlockingCallbacks = "copilot_swe_agent_use_non_blocking_callbacks"

	// CopilotSWEAgentUseReleaseAssets enables app-specific runtime version format (runtime-{app}-{sha})
	CopilotSWEAgentUseReleaseAssets = "copilot_swe_agent_use_release_assets"

	// CopilotSWEAgentValidateRuntimeVariables validates required runtime variables before launching
	CopilotSWEAgentValidateRuntimeVariables = "copilot_swe_agent_validate_runtime_variables"

	// CopilotSWEAgentValidationToolSettings gates passing validation tool settings (CodeQL, CCR, secret scanning, dependency vuln checks) as env vars to the runtime
	CopilotSWEAgentValidationToolSettings = "copilot_swe_agent_validation_tool_settings"

	// CopilotSWEAgentWorkflowErrorClassification enables improved error classification for workflow failures
	CopilotSWEAgentWorkflowErrorClassification = "copilot_swe_agent_workflow_error_classification"

	// CopilotSWEAgentWorkflowParserValidation enables validation of generated workflows using
	// the actions-workflow-parser library. When enabled, workflows are validated before being
	// sent to Actions and invalid workflows will fail the job.
	CopilotSWEAgentWorkflowParserValidation = "copilot_swe_agent_workflow_parser_validation"

	CopilotSWEAgenticAppsProvider = "copilot_swe_agentic_apps_provider"

	// CopilotSWEPropagateTraceParent enables end-to-end tracing by passing the OpenTelemetry TraceParent header to the runtime
	CopilotSWEPropagateTraceParent = "copilot_swe_propagate_trace_parent"

	// CopilotSWERepoFromParams fetches the repository in the API middleware and passes it to handlers via parameters.
	// This fixes issues with renamed repositories where the old NWO is used in the URL.
	CopilotSWERepoFromParams = "copilot_swe_repo_from_params"

	// CopilotSWESkipAgentJobConcurrencyLimit bypasses concurrency limits for agent jobs
	CopilotSWESkipAgentJobConcurrencyLimit = "copilot_swe_agent_skip_agent_job_concurrency_limit"

	// CopilotSWESkipEnablementCheckOnRead skips the agent enablement check for selected REST API endpoints,
	// including some non-read-only endpoints such as cancel job.
	CopilotSWESkipEnablementCheckOnRead = "copilot_swe_skip_enablement_check_on_read"

	// CopilotSWESubscriptionBasedCapiURL enables subscription-based CAPI URLs (api.business/enterprise/individual.githubcopilot.com)
	CopilotSWESubscriptionBasedCapiURL = "copilot_swe_subscription_based_capi_url"
)
