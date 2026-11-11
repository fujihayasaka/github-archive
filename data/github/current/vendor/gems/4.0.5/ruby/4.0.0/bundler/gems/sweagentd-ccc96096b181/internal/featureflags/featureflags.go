package featureflags

// Feature flag constants - keep these sorted alphabetically by constant name to reduce merge conflicts.
// Comments go on the line above each constant to minimize merge conflicts.
const (
	// CodingAgentFreeUsersExperiment enables free-plan users to use chat quota for coding agent access.
	CodingAgentFreeUsersExperiment = "copilot_coding_agent_free_users_exp"

	// CodingAgentModelSelectionAllSKUs enables model selection for all SKUs, not just Pro and Pro+ individual plans
	CodingAgentModelSelectionAllSKUs = "coding_agent_model_selection_all_skus"

	// CodingAgentProposeTasks enables CCA to use the "task" action, and to propose tasks outside of PR context
	CodingAgentProposeTasks = "coding_agent_propose_tasks"

	// CodingAgentStackPRs enables @-mentioning Copilot on user PRs, to create a stacked PR
	CodingAgentStackPRs = "coding_agent_stack_prs"

	// CopilotSWEAgentAINameGeneration enables AI-powered branch and session name generation
	CopilotSWEAgentAINameGeneration = "copilot_swe_agent_ai_name_generation"

	// CopilotSWEAgentAINameGenerationUseGPT5Nano uses gpt-5-nano instead of gpt-4o-mini for name generation
	CopilotSWEAgentAINameGenerationUseGPT5Nano = "copilot_swe_agent_ai_name_generation_use_gpt5"

	// CopilotSWEAgentAPIDisallow disallows specific users or apps from using the API for abuse
	CopilotSWEAgentAPIDisallow = "copilot_swe_agent_api_disallow"

	CopilotSWEAgentAgenticApps = "copilot_swe_agent_agentic_apps"

	// CopilotSWEAgentBackoffSessionClientRetryNotFound enables retries for not found errors in session client requests
	CopilotSWEAgentBackoffSessionClientRetryNotFound = "copilot_swe_agent_backoff_session_client_retry_not_found"

	// CopilotSWEAgentBackoffSessionClientRetryUnauthorized enables retries for unauthorized errors in session client requests
	CopilotSWEAgentBackoffSessionClientRetryUnauthorized = "copilot_swe_agent_backoff_session_client_retry_unauthorized"

	// CopilotSWEAgentCacheMintedTokens enables caching of minted tokens in Redis
	CopilotSWEAgentCacheMintedTokens = "copilot_swe_agent_cache_minted_tokens" //nolint:gosec // This is not a secret token, just the name of a feature flag.

	CopilotSWEAgentCanSelectModel = "sweagentd_can_select_model"

	// CopilotSWEAgentCleanGitConfig adds extra step of cleaning git config prior to runtime start
	CopilotSWEAgentCleanGitConfig = "copilot_swe_agent_clean_git_config"

	CopilotSWEAgentCustomAgentAsAPI = "copilot_swe_agent_custom_agent_as_api"

	// CopilotSWEAgentCustomAgentListDefaultToAll when enabled, defaults to listing all custom agents if no target is specified
	CopilotSWEAgentCustomAgentListDefaultToAll = "copilot_swe_agent_custom_agent_list_default_to_all"

	// CopilotSWEAgentCustomAgentPermissions enables configuration of token scopes in custom agents
	CopilotSWEAgentCustomAgentPermissions = "copilot_swe_agent_custom_agent_permissions"

	// CopilotSWEAgentCustomAgentPrivilegedRepo allows repo-level custom agents to be privileged
	CopilotSWEAgentCustomAgentPrivilegedRepo = "copilot_swe_agent_custom_agent_privileged_repo"

	// CopilotSWEAgentCustomAgentTriggers enables configuration of events in custom agents
	CopilotSWEAgentCustomAgentTriggers = "copilot_swe_agent_custom_agent_triggers"

	// CopilotSWEAgentCustomAgentTriggersCreatePR defaults custom agents to create PRs in response to triggers
	CopilotSWEAgentCustomAgentTriggersCreatePR = "copilot_swe_agent_custom_agent_triggers_create_pr"

	// CopilotSWEAgentCustomAgentValidateJobNonce enables job-based validation when getting custom agent details via the /agent/custom-agents endpoint
	CopilotSWEAgentCustomAgentValidateJobNonce = "copilot_swe_agent_custom_agent_validate_job_nonce"

	// CopilotSWEAgentCustomAgentsDisallow disallows specific users, orgs, or apps from using custom agents
	CopilotSWEAgentCustomAgentsDisallow = "copilot_swe_agent_custom_agents_disallow"

	// CopilotSWEAgentEmitCopilotAccessTypeStats enables emitting copilot access type in telemetry stats for analytics
	CopilotSWEAgentEmitCopilotAccessTypeStats = "sweagent_emit_copilot_access_type_stats"

	// CopilotSWEAgentErrorAnnotations enables runtime error annotations for improved SLO tracking.
	// When enabled, the runtime emits a GitHub Actions annotation with structured error info
	// if it fails to send the error via callback to sweagentd.
	CopilotSWEAgentErrorAnnotations = "copilot_swe_agent_error_annotations"

	CopilotSWEAgentGZipProblemStatement = "copilot_swe_agent_gzip_problem_statement"

	CopilotSWEAgentIgnoreNonAgenticEventsReviewSubmit = "copilot_swe_agent_ignore_non_agentic_events_review_submit"

	CopilotSWEAgentIntegrationCodeScanningAlerts = "copilot_swe_agent_integration_code_scanning_alerts"

	CopilotSWEAgentIssueBodyEditCheck = "sweagentd_issue_body_edit_check"

	CopilotSWEAgentIssuesCrossRepoAssignment = "issues_copilot_cross_repo_assign"

	// CopilotSWEAgentOnlineEvalUseClaudeHaiku45 uses claude-haiku-4.5 instead of gpt-4.1 for online evaluation
	CopilotSWEAgentOnlineEvalUseClaudeHaiku45 = "copilot_swe_agent_online_eval_use_claude_haiku_4_5"

	// CopilotSWEAgentPRCommentModelPicker enables model selection via @copilot+model mentions in PR comments
	CopilotSWEAgentPRCommentModelPicker = "copilot_swe_agent_pr_comment_model_picker"

	CopilotSWEAgentPRStateEventsEnabled = "coding_agent_sessions_consume_hydro_event_and_patch_session"

	// CopilotSWEAgentPlaywrightLazyStart enables starting the Playwright MCP server on first tool invocation
	CopilotSWEAgentPlaywrightLazyStart = "copilot_swe_agent_playwright_lazy_start"

	CopilotSWEAgentReplyToCommentMentionsOnNonCopilotPRs = "copilot_swe_agent_reply_to_comment_mentions_on_non_copilot_prs"

	// CopilotSWEAgentRepoIDForDynamicWorkflows uses repo ID instead of owner/repo in the dynamic workflows API URL
	// This handles repository renames gracefully since repo IDs are immutable
	CopilotSWEAgentRepoIDForDynamicWorkflows = "copilot_swe_agent_repo_id_for_dynamic_workflows"

	CopilotSWEAgentRuntimeEntryPointCCAV2 = "copilot_swe_agent_runtime_entry_point_cca_v2"

	CopilotSWEAgentRuntimeEntryPointClaude = "copilot_swe_agent_runtime_entry_point_claude"

	CopilotSWEAgentRuntimeEntryPointCodex = "copilot_swe_agent_runtime_entry_point_codex"

	// CopilotSWEAgentSelectCustomerError when enabled, fails session when customer is not selected; when disabled, logs and continues
	CopilotSWEAgentSelectCustomerError = "copilot_swe_agent_select_customer_error"

	// CopilotSWEAgentSendSessionsToAgentProgressAPI when enabled, sends (legacy) session updates to the Agent Progress API
	CopilotSWEAgentSendSessionsToAgentProgressAPI = "copilot_swe_agent_send_sessions_to_agent_progress_api"

	// CopilotSWEAgentSkipSessionFailures allows jobs to continue even if we fail to update session status
	CopilotSWEAgentSkipSessionFailures = "copilot_swe_agent_skip_session_failures"

	// CopilotSWEAgentTaskAPI enables the Task API parameters for SWE Agent sessions
	CopilotSWEAgentTaskAPI = "copilot_swe_agent_task_api_parameters"

	// CopilotSWEAgentUseAgentProgressAPI uses the Agent Progress API to report progress from agents
	CopilotSWEAgentUseAgentProgressAPI = "copilot_swe_agent_use_agent_progress_api"

	// CopilotSWEAgentUseAsyncSessions determines whether assignments should use async sessions
	CopilotSWEAgentUseAsyncSessions = "copilot_swe_agent_use_async_sessions"

	// CopilotSWEAgentUseInternalAPI enables using the internal API (internal-api.service.iad.github.net) instead of public API (api.github.com)
	CopilotSWEAgentUseInternalAPI = "copilot_swe_agent_use_internal_api"

	// CopilotSWEAgentUseNonBlockingCallbacks enables non-blocking callbacks via ExecutionQueue
	CopilotSWEAgentUseNonBlockingCallbacks = "copilot_swe_agent_use_non_blocking_callbacks"

	// CopilotSWEAgentUseReleaseAssets enables app-specific runtime version format (runtime-{app}-{sha})
	CopilotSWEAgentUseReleaseAssets = "copilot_swe_agent_use_release_assets"

	// CopilotSWEAgentValidateRuntimeVariables validates required runtime variables before launching
	CopilotSWEAgentValidateRuntimeVariables = "copilot_swe_agent_validate_runtime_variables"

	// CopilotSWEAgentWindowsOSRunner enables Windows OS runner support for the coding agent
	CopilotSWEAgentWindowsOSRunner = "copilot_swe_agent_windows_os_runner"

	// CopilotSWEAgentWorkOnCurrentBranch enables CCA to work on the current branch instead of creating stacked PRs
	CopilotSWEAgentWorkOnCurrentBranch = "copilot_swe_agent_work_on_current_branch"

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

	// CopilotSWESubscriptionBasedCapiURL enables subscription-based CAPI URLs (api.business/enterprise/individual.githubcopilot.com)
	CopilotSWESubscriptionBasedCapiURL = "copilot_swe_subscription_based_capi_url"
)
