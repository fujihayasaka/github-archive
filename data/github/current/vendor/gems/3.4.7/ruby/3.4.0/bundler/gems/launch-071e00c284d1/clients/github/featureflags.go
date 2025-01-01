package github

const (
	// LaunchInLabFeatureFlag is the flag (per repo) that checks if
	// the actor can run workflows in the lab environment.
	LaunchInLabFeatureFlag = "launch_lab"

	// https://github.com/github/c2c-actions/blob/master/docs/adrs/2875-addressing-customers-reactions-to-dependabot-limitations.md#option-d-feature-flag-to-opt-out-of-permissions-and-secrets
	DisableDependabotSecurityEnforcementFeatureFlag = "actions_disable_dependabot_enforcement"

	// DisableScheduledWorkflowsFeatureFlag is the flag that disables scheduled
	// workflows from running.
	DisableScheduledWorkflowsFeatureFlag = "actions_disable_scheduled_workflows"

	// DisableScheduledWorkflowsInLabFeatureFlag is the flag that disables scheduled
	// workflows from running.
	DisableScheduledWorkflowsInLabFeatureFlag = "actions_disable_scheduled_workflows_in_lab"

	// DisableStatusPostbacksFeatureFlag is the flag that disables status
	// postbacks to Actions.
	DisableStatusPostbacksFeatureFlag = "actions_disable_status_postbacks"

	// queue plan via run service, currently only for dev and lab environments
	RunServiceFeatureFlag = "actions_launch_run_service"

	// queue plan via run service for free plans, that is "gh.launch.plan.sku" is ("free" OR "free_organization") for these plans
	RunServiceFeatureFlagForFreePlans = "actions_launch_run_service_free_plans"

	// queue plan via run service for all hosted
	// Warning: If customer overrides the label to use self-hosted/larger runner, they would still be flagged in
	RunServiceFeatureFlagForHardCodedHostedLabels = "actions_launch_run_service_hosted_labels"

	// queue plan via run service if it is a dependabot dynamic workflow
	RunServiceDependabotFlag = "actions_launch_run_service_dependabot"

	// queue plan via run service if it is a pages dynamic workflow
	RunServicePagesFlag = "actions_launch_run_service_pages"

	// override for pages dynamic workflows to use a self hosted runner, special label, ref: https://github.com/github/github/blob/18121ad187addad3769d69fd8b1385abfb91b65a/packages/artifacts/app/models/page.rb#L701
	PagesMariner2RunnerLabelFlag = "pages_mariner2_runner_label"

	// override for pages dynamic workflows to use a self hosted runner, ref: https://github.com/github/github/blob/18121ad187addad3769d69fd8b1385abfb91b65a/packages/artifacts/app/models/page.rb#L908C13-L908C51
	PagesSelfHostedRunnerLabelFlag = "pages_self_hosted_runner_label"

	// Allow queuing the plan via run service if the workflow has a custom annotation
	AllowRunServiceAnnotation = "actions_allow_run_service_annotation"

	// Enable workflow reuse if matching tree_ids are found between different events
	GreenTreesFeatureFlag = "actions_green_trees"

	// Allows enabling configuration variables in workflows
	ConfigurationVariablesEnabledFlag = "actions_launch_configuration_variables"

	// Compare parsing errors from actions-dotnet and actions-workflow-parser
	CompareParserErrorsFlag = "actions_compare_parser_errors"

	// Exclude called workflows from redirected repositories
	ExcludeCalledWorkflowsFromRedirectedRepositoriesFlag = "actions_exclude_called_workflows_from_redirected_repositories"

	// Enable Runner to use Results Service
	ActionsUseResultsServiceRunnerFlag = "actions_use_results_service"

	// An reverse feature flag for customers to opt out the Results Service flow
	ActionsOptOutResultsServiceRunnerFlag = "actions_opt_out_results_service"

	// Enable Actions Service to use Results Service to host build results
	ActionsStreamLogsViaResultsServiceFlag = "actions_stream_logs_via_results_service"

	// Compare plans from actions-dotnet and actions-workflow-parser
	CompareParserPlansFlag = "actions_compare_parser_plans"

	// Allows enabling increased count in configuration variables in workflows, size restricted to 256KB
	SizeRestrictedVarCountEnabledFlag = "actions_launch_size_restricted_variables"

	// Allows enabling increased max in workflow file references
	IncreasedMaxWorkflowFilesReferencedEnabledFlag = "actions_increased_max_workflow_files"

	// Compare concurrency values from launch and actions-dotnet
	EvaluateConcurrencyFlag = "actions_evaluate_concurrency"

	// Enable public fork policy
	PublicForkPrWorkflowsPolicyFlag = "actions_public_fork_pr_workflows_policy"

	// ExperimentalBillingFeatureFlag is the flag that enables skipping billing for specific actors for experimental SKUs
	ExperimentalBillingFeatureFlag = "actions_experimental_skip_billing_launch"

	// ActionsUseBillingPlatform determines whether to reach out to billing platform for usage data
	ActionsUseBillingPlatform = "actions_use_billing_platform"

	// actions_pipeline_round_robin is the flag that enables randomly selecting a Pipelines scale unit URL when creating a new org
	PipelineRoundRobin = "actions_pipeline_round_robin"

	// Enable Constructing the direct scale unit URL from the scale unit identifier
	ConstructScaleUnitURL = "actions_launch_construct_scale_unit_url"

	// Enables retrieving the host url from the runner registration payload
	PlumbRunnerHostURL = "actions_plumb_runner_host_url"

	GatesUseDefaultAuth = "actions_gates_use_default_auth"

	// Ensure that ruleset workflow path matches environment
	MatchEnvPathLabRulesetWorkflows = "match_env_path_lab_ruleset_workflows"

	// Enable the "snapshot" keyword in workflows
	SnapshotKeywordEnabledFlag = "actions_enable_snapshot_keyword"

	// Allow paths-ignore on push events with empty commits to bypass
	// parser globbing logic and filter in a workflow so it will run
	PathsIgnoreEmptyPushBypassesParser = "actions_paths_ignore_empty_push_bypasses_parser"

	// Allow "empty" diff advisory responses from Dotcom's ActionsFilterDiff
	// to pass initial filtering logic instead of automatically failing
	TreatEmptyAdvisoriesAsPassed = "actions_treat_empty_advisories_as_passed"

	// Cancel context for build healing queries exceeded 6 seconds
	ClampBuildHealingQueriesAfter6Seconds = "actions_heal_builds_6_second_clamp"

	// EnableWebhookRateLimitingDarkMode checks a per-repository rate limit backed by Redis before reading webhooks from aqueduct
	EnableWebhookRateLimitingDarkMode = "actions_enable_webhook_rate_limiting_dark_mode"

	// Exempt blocking Artifacts v3
	BlockArtifactsV3Exempted = "block_artifacts_v3_exempted"

	// Enable the use of the PR author for workflow approvals
	WorkflowApprovalsUsePRAuthorFlag = "actions_workflow_approvals_use_pr_author"

	// Skip reporting parser errors as queue run failures
	// Temporary mitigation for https://github.com/github/actions-relaunch/issues/1067
	SkipParserErrorsFlag = "actions_skip_parser_errors"

	// Allow proxima runs to be queued to run service
	RunServiceProximaFeatureFlag = "actions_enable_run_service_proxima"

	// Enable the use of Cache Service v2
	EnableCacheServiceV2 = "actions_uses_cache_service_v2"

	// Opt out of Cache Service v2
	OptOutOfCacheServiceV2 = "actions_opt_out_of_cache_service_v2"

	// Enforces the custom image usage policy for hosted runners
	HostedRunnerCustomImagesPolicyEnforced = "actions_enforce_custom_image_policy"

	// Allows ruleset workflows that aren't filtered out in dotcom to run even if actions is disabled
	RequiredWorkflowsRepoActionsDisabled = "required_workflows_repo_actions_disabled"

	// Return 404 for actions account details if the entity does not exist on dotcom
	ActionsAccountDetailsCheckEntityExists = "actions_account_details_check_entity_exists"

	// Enable new logic for using CanProceedWithUsage to discern where usage data should be sent
	BillingCanProceedWithUsageProductEnabled = "billing_can_proceed_with_usage_product_enabled_check"
)
