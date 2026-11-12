package launcher

import (
	"bytes"
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"html/template"
	"net/url"
	"slices"
	"strconv"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/mcp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/permissions"
	"github.com/github/sweagentd/internal/proxima"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/runnerlabels"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
	"go.opentelemetry.io/otel/attribute"
	"golang.org/x/sync/errgroup"
)

// These are variables explicitly called out in the workflow yaml. They should not
// be passed into the actions_workflow.yaml template to avoid duplicates.
var workflowDirectlyReferencedVarNames = []string{
	"COPILOT_AGENT_BACKGROUND_MKCERT",
	"COPILOT_AGENT_DEBUG",
	"COPILOT_AGENT_FIREWALL_ALLOW_LIST",
	"COPILOT_AGENT_FIREWALL_ALLOW_LIST_ADDITIONS",
	"COPILOT_AGENT_FIREWALL_ENABLED",
	"COPILOT_AGENT_RESUME_SESSION_ID",
	"COPILOT_AGENT_RUNS_ON_LABELS",
	"COPILOT_AGENT_SESSION_ID",
	"COPILOT_API_URL",
}

// Same as the previous list, but these are only ref'd in development mode
var developmentWorkflowDirectlyReferencedVarNames = []string{
	"COPILOT_INTEGRATION_ID_OVERRIDE",
	"CAPI_HMAC_KEY_OVERRIDE",
}

// ActionsLauncherOpts are the options for the ActionsLauncher.
type ActionsLauncherOpts struct {
	AgentLauncherOpts

	ActionsDefaultRunsOnLabels string
}

// ActionsLauncher is an AgentLauncher that launches agents using GitHub Actions.
type ActionsLauncher struct {
	obsv                observability.Exporters
	ffClient            featureflags.Client
	githubClientFactory github.ClientFactoryInterface
	ghTwirp             githubtwirp.ClientInterface
	spokes              sweagentd.Spokes
	opts                ActionsLauncherOpts
	appProvider         *agenticapp.Provider
}

// Ensure that ActionsLauncher implements AgentLauncher
var _ AgentLauncher = &ActionsLauncher{}

// NewActionsLauncher creates a new ActionsLauncher.
func NewActionsLauncher(
	obsv observability.Exporters,
	ffClient featureflags.Client,
	githubClientFactory github.ClientFactoryInterface,
	ghTwirp githubtwirp.ClientInterface,
	spokes sweagentd.Spokes,
	opts ActionsLauncherOpts, //nolint:gocritic // hugeParam: while the params here are larger, passing by pointer adds risk of nil dereference
	appProvider *agenticapp.Provider,
) (*ActionsLauncher, error) {
	return &ActionsLauncher{
		obsv:                obsv,
		ffClient:            ffClient,
		githubClientFactory: githubClientFactory,
		ghTwirp:             ghTwirp,
		spokes:              spokes,
		opts:                opts,
		appProvider:         appProvider,
	}, nil
}

// LauncherType returns the type of launcher.
func (a *ActionsLauncher) LauncherType() Type {
	return TypeActions
}

// LaunchAgent launches an agent using GitHub Actions.
//
//nolint:maintidx // complexity is inherent to the orchestration logic
func (a *ActionsLauncher) LaunchAgent(ctx context.Context, opts *LaunchAgentOpts) (*LaunchResult, error) {
	ctx, span := a.obsv.Tracer.Start(ctx, "launcher.actions.LaunchAgent")
	defer span.End()

	// Track whether custom setup steps were used and the runs-on value
	customSetupStepsUsed := false
	runsOn := ""

	environment, err := config.ParseEnvironment(a.opts.Environment)
	if err != nil {
		return nil, NonRetriableLaunchError(goerrors.Errorf("failed to parse environment: %w", err))
	}

	urls, err := a.getURLsForEnvironment(ctx, environment, opts)
	if err != nil {
		return nil, NonRetriableLaunchError(goerrors.Errorf("failed to generate tenant specific capi urls: %w", err))
	}

	overrides := &Variables{
		// Callback URL is passed into the dynamic workflow twice, this could probably be addressed to only use the workflowData.
		"COPILOT_AGENT_CALLBACK_URL": {Value: urls.AgentCallbackURL},
		"COPILOT_API_URL":            {Value: urls.CopilotAPIURL},
		"GITHUB_UPLOADS_URL":         {Value: urls.UploadURL},
		"GITHUB_DOWNLOADS_URL":       {Value: urls.DownloadURL},
		"SECRET_SCANNING_URL":        {Value: urls.SecretScanningURL},
	}

	inputs, err := a.environmentVariables(ctx, opts, overrides)
	if err != nil {
		return nil, NonRetriableLaunchError(goerrors.Errorf("failed to generate environment variables: %w", err))
	}

	err = validateInputs(inputs)
	if err != nil {
		return nil, NonRetriableLaunchError(goerrors.Errorf("invalid inputs: %w", err))
	}

	// Determine which app to use for authentication.
	// For third-party agents, we use Copilot credentials
	// instead of the 3P app's credentials for security reasons.
	// The 3P agent's bot ID is passed as the actor instead.
	isCopilotCodingAgent := a.appProvider.IsCopilotCodingAgentApp(opts.Agent.AppID())
	authApp := opts.Agent
	var actorBotID *int64
	isThirdPartyAgent := a.appProvider.IsThirdPartyAgent(opts.Agent)
	isCCRAgent := a.appProvider.IsCopilotCodeReviewApp(opts.Agent.AppID())
	isCSAgent := a.appProvider.IsCodeScanningApp(opts.Agent.AppID()) && a.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentCodeScanningCopilotAuth, opts)
	useCopilotAppForAuth := isThirdPartyAgent || isCCRAgent || isCSAgent

	if useCopilotAppForAuth {
		authApp = a.appProvider.CopilotApp()
		// Pass the agent's bot ID as the actor
		botID := opts.Agent.BotID()
		actorBotID = &botID
		a.obsv.LoggerWithTelemetry(ctx).Info("Using Copilot credentials for CCR or 3P agent dynamic workflow",
			kvp.Int64("agent_app_id", opts.Agent.AppID()),
			kvp.Int64("actor_bot_id", botID))
	}

	client, err := a.githubClientFactory.NewClientFromRepo(ctx, authApp, opts.GitHubRepoID, opts.GitHubRepoOwnerID)
	if err != nil {
		return nil, ClassifyLaunchError(err, "failed to create GitHub client")
	}

	// Check if agent secrets feature flag is enabled
	useAgentSecrets := a.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.ActionsAgentSecrets, opts)

	// Fetch secrets/variables concurrently with the rest of the launch
	// preparation (firewall placeholder replacement + feature flag lookup).
	// The secrets are only consumed downstream when constructing workflowData,
	// and the prep work doesn't depend on them, so overlapping the two cuts
	// LaunchAgent p50 latency by the lesser of the two paths.
	//
	// Note that secrets and variables should be **unfiltered** here since they
	// are used to mask all secrets in session logs and elsewhere. Specifically,
	// this should also include MCP secrets/variables in addition to others to
	// handle unexpected scenarios that cross both sets.
	var (
		secrets, variables        []string
		firewallRequiredAllowList string
		flags                     []string
		secretsErr                error
		prepareErr                error
	)

	prepareCtx, prepareSpan := a.obsv.Tracer.Start(ctx, "launcher.actions.LaunchAgent.prepare")
	prepareSpan.SetAttributes(attribute.Bool("launcher.use_agent_secrets", useAgentSecrets))

	// Deliberately use a plain errgroup.Group (not errgroup.WithContext) so the
	// two goroutines don't cancel each other. If we derived a context and the
	// prep goroutine failed first, the in-flight secrets HTTP call would
	// observe ctx.Canceled and write a context-cancellation error into
	// secretsErr. Since the error-precedence logic below reports secretsErr
	// first, the user would see a misleading "failed to get agent secrets:
	// context canceled" instead of the actual prep failure — and worse, a
	// non-retriable prep failure would be reclassified as retriable by
	// ClassifyLaunchError. We need both goroutines to complete regardless, so
	// cross-cancellation buys us nothing here.
	var eg errgroup.Group
	eg.Go(func() error {
		if useAgentSecrets {
			isRepoOwnedByOrganization := opts.OwnerType == sweagentd.OwnerTypeOrganization
			secrets, variables, secretsErr = client.GetAgentSecretsAndVariables(prepareCtx, opts.GitHubRepoOwner, opts.GitHubRepoName, isRepoOwnedByOrganization)
		} else {
			secrets, variables, secretsErr = client.GetCopilotEnvironmentSecretsAndVariables(prepareCtx, opts.GitHubRepoOwner, opts.GitHubRepoName, opts.GitHubRepoID)
		}
		return secretsErr
	})
	eg.Go(func() error {
		allowList, err := replaceFirewallTenantPlaceholders(prepareCtx, a.opts.AgentFirewallRequiredAllowList)
		if err != nil {
			prepareErr = NonRetriableLaunchError(goerrors.Errorf("failed to replace firewall tenant placeholders: %w", err))
			return prepareErr
		}

		// Replace repo-specific placeholders
		if opts.GitHubRepoOwner != "" && opts.GitHubRepoName != "" {
			allowList = replaceFirewallRepoPlaceholders(allowList, opts.GitHubRepoOwner, opts.GitHubRepoName)
		}

		if urls.CopilotAPIHost != "" {
			if allowList == "" {
				allowList = urls.CopilotAPIHost
			} else {
				allowList = allowList + "," + urls.CopilotAPIHost
			}
		}
		firewallRequiredAllowList = allowList

		ffs, err := getFeatureFlags(prepareCtx, a.ffClient, opts, isCopilotCodingAgent)
		if err != nil {
			// These errors should be transient if they occur
			prepareErr = RetriableLaunchError(err)
			return prepareErr
		}
		flags = ffs
		return nil
	})
	_ = eg.Wait()
	prepareSpan.End()

	// Preserve the original sequential error precedence: a secrets fetch
	// failure is reported before any prep-side failure.
	if secretsErr != nil {
		if useAgentSecrets {
			return nil, ClassifyLaunchError(secretsErr, "failed to get agent secrets and variables")
		}
		return nil, ClassifyLaunchError(secretsErr, "failed to get copilot environment secrets and variables")
	}
	if prepareErr != nil {
		return nil, prepareErr
	}

	// Emit Datadog metrics for Copilot environment secrets and variables counts
	metricTags := a.obsv.TelemetryTags(ctx)
	a.obsv.Statter.Distribution("agent.copilot_environment.secrets.count", metricTags, float64(len(secrets)))
	a.obsv.Statter.Distribution("agent.copilot_environment.variables.count", metricTags, float64(len(variables)))

	includeCopilotEnvironmentInDynamicWorkflow := a.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotCloudAgentIncludeCopilotEnvironmentInDynamicWorkflow, opts)
	data := workflowData{
		RunName:                        template.HTML(GenerateRunName(opts)), //nolint:gosec // This is controlled input
		JobName:                        opts.Agent.ComputeSlug(),
		Secrets:                        secrets,
		Variables:                      variables,
		AgentDebug:                     a.opts.AgentDebug,
		AgentFirewallEnabledDefault:    isFirewallEnabledByDefault(ctx, a.ffClient, &a.opts.AgentLauncherOpts),
		AgentFirewallRequiredAllowList: template.HTML(firewallRequiredAllowList), //nolint:gosec // This is controlled input
		UploadsURL:                     a.opts.UploadsURL,
		JobID:                          opts.JobID,
		IsDevelopmentEnvironment:       a.opts.IsDevelopmentEnvironment,
		IsStagingEnvironment:           a.opts.IsStagingEnvironment,
		Environment:                    a.opts.Environment,
		MCPEnabled:                     a.opts.MCPEnabled,
		MCP3PEnabled:                   true,
		McpRemoteEnabled:               a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "sweagentd_mcp_remote_enabled", opts),
		MCPReadOnlyMode:                isCCRAgent,
		MCPVariables:                   []string{},
		MCPSecrets:                     []string{},
		Customization: map[string]template.HTML{
			"runs-on":         a.defaultRunsOnValue(),
			"timeout-minutes": template.HTML(fmt.Sprintf("%d", a.opts.AgentTimeoutMin)), //nolint:gosec // This is controlled input
		},
		BlackbirdMode:                 "disabled",
		InjectedSecretNames:           strings.Join(secrets, ","),
		AgentOnlineEvaluationDisabled: "false",
		FeatureFlags:                  strings.Join(flags, ","),
		Experiments:                   opts.Experiments,
		ExperimentAssignmentContext:   opts.ExperimentAssignmentContext,
		PlaywrightVersion:             playwrightVersion,
		TokenSecretNames:              getGitHubTokenSecretNames(ctx, a.ffClient, opts),
		CopilotTraceParent:            getCopilotTraceParent(ctx, a.ffClient, opts, a.opts.TraceParentPropagator),
		URLs:                          urls,
		BackgroundMkcertKeygen:        a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentBackgroundMkcertKeygen, opts),
		RepositoryOwner:               opts.GitHubRepoOwner,
		UseAgentSecrets:               useAgentSecrets,
		IncludeCopilotEnvironmentInDynamicWorkflow: includeCopilotEnvironmentInDynamicWorkflow,
	}

	switch environment {
	case config.EnvironmentStaging, config.EnvironmentProxima:
		data.ActionDownloadURL = urls.ActionDownloadURL
	default:
		// In production, we always use the public action URL
	}

	data.AgentFirewallRuleSetAllowListDefault = template.HTML(a.opts.AgentFirewallRuleSetAllowListDefault) //nolint:gosec // This is controlled input

	// Use materialized firewall config from the repository configuration when the feature flag
	// is enabled. This reuses the config already fetched by the job executor, avoiding a
	// redundant Twirp call. The materialized rules combine enterprise, org, and repo-level
	// firewall policies, replacing the Actions Variables-based approach.
	if a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentFirewallMaterialized, opts) {
		a.obsv.LoggerWithTelemetry(ctx).Info("attempting to use materialized firewall configuration from repo config")

		if opts.RepoConfig != nil {
			data.UseMaterializedFirewall = true
			data.MaterializedFirewallEnabled = opts.RepoConfig.GetIsFirewallEnabled()
			data.MaterializedFirewallUseDefaultRules = opts.RepoConfig.GetShouldFirewallUseDefaultRules()
			data.MaterializedFirewallAllowedRules = template.HTML(strings.Join(opts.RepoConfig.GetFirewallAllowedRules(), ",")) //nolint:gosec // This is controlled input from Twirp API
			a.obsv.LoggerWithTelemetry(ctx).Info("using materialized firewall configuration from repo config",
				kvp.Bool("enabled", data.MaterializedFirewallEnabled),
				kvp.Bool("use_default_rules", data.MaterializedFirewallUseDefaultRules),
				kvp.String("allowed_rules", string(data.MaterializedFirewallAllowedRules)))
		} else {
			a.obsv.LoggerWithTelemetry(ctx).Warn("repo config is nil, falling back to Actions Variables for firewall config")
		}
	}

	if isFirewallDisabled(ctx, a.ffClient, opts.Agent, opts, a.appProvider) {
		disableAgentFirewall(&data)
		a.obsv.LoggerWithTelemetry(ctx).Info("agent firewall bypass applied",
			kvp.Int64("agent_app_id", opts.Agent.AppID()))
	}

	if isOnlineEvaluationDisabled(ctx, a.ffClient, &a.opts.AgentLauncherOpts, opts) {
		data.AgentOnlineEvaluationDisabled = "true"
	}

	if opts.OwnerType == "" {
		a.obsv.LoggerWithTelemetry(ctx).Warn("no owner type found when launching job")
	}

	var defaultRunnerSettings *sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse
	if opts.OwnerType == sweagentd.OwnerTypeOrganization && a.ffClient.IsEnabledForOrganization(ctx, featureflags.CopilotSWEAgentRunnerControlSettings, opts.GitHubRepoOwnerID) {
		defaultRunnerSettings, err = a.ghTwirp.SweagentdAPI().GetOrganizationCCARunnerSettings(ctx, &sweagentdTwirp.GetOrganizationCCARunnerSettingsRequest{
			OrganizationId: uint64(opts.GitHubRepoOwnerID),
		})
		if err != nil {
			return nil, RetriableLaunchError(goerrors.Errorf("failed to get default runner settings: %w", err))
		}
	}

	// Apply setup steps if enabled for the job.
	var setupStepsResult *SetupStepsResult
	if opts.Features.CopilotSetupStepsEnabled() {
		setupStepsResult, err = a.applySetupSteps(ctx, client, opts, &data, urls.CopilotAPIURL)
		if err != nil {
			// If there is an error processing the setup steps, we log a warning but do not fail the workflow run
			a.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("failed to apply setup steps")
		}
	} else {
		a.obsv.LoggerWithTelemetry(ctx).Info("copilot-setup-steps disabled by feature on job")
	}

	if setupStepsResult != nil {
		data.Customization = setupStepsResult.Customization
		customSetupStepsUsed = setupStepsResult.WasApplied
		runsOn = setupStepsResult.RunsOn
	}

	// if no runs on present, or, if it is present but we don't allow overrides, use the org default setting
	if defaultRunnerSettings != nil && (runsOn == "" || !defaultRunnerSettings.AllowRepositoryCustomization) {
		runsOn = a.applyOrgDefaultRunnerSettings(ctx, defaultRunnerSettings, &data)
	}

	// Kill switch for CCR (Copilot Code Review): customer-controllable runs-on overrides above
	// (copilot-setup-steps.yml, org-configured default CCA runner) can drag customer-owned
	// runner labels (including SHR) onto CCR runs the customer is not equipped to host. When
	// this flag is enabled for a CCR job, undo those overrides so runs-on falls back to
	// whichever layer sweagentd would otherwise pick (custom image for non-Autofind agents, or
	// the configured default runs-on expression for Autofind agents like CCR today).
	//
	// To keep new customer-controllable override layers covered by this kill switch, add them
	// ABOVE this block. The sweagentd-internal custom-image override below runs after the kill
	// switch and is intentionally not affected.
	forceDefaultRunsOn := isCCRAgent &&
		a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCCRDisableRunsOnOverride, opts)
	if forceDefaultRunsOn {
		a.obsv.LoggerWithTelemetry(ctx).Info("CCR disable-runs-on-override kill switch active; resetting runs-on to sweagentd default")
		a.obsv.Statter.Counter("ccr_disable_runs_on_override.applied", a.obsv.TelemetryTags(ctx), 1)
		runsOn = ""
		data.Customization["runs-on"] = a.defaultRunsOnValue()
	}

	// Determine custom image usage once, then pass that decision to both
	// MCP configuration and workflow customization to keep them in sync.
	customImage := a.useCustomImage(ctx, runsOn, opts)

	// Apply MCP settings after setup-steps so the custom image decision reflects runsOn.
	inputs[mcp.ServerConfigEnvVar], inputs[mcp.InteractionIDEnvVar], inputs[mcp.PermissionsInputName], err = a.applyMCPSettings(ctx, &data, opts, customImage)
	if err != nil {
		return nil, ClassifyLaunchError(err, "failed to apply MCP settings")
	}

	// Scope GITHUB_COPILOT_GIT_TOKEN's workflows:write based on the triggering
	// credential. Computed outside applyMCPSettings so it still runs when
	// sweagentd_mcp_disable is on.
	if includeWorkflows := a.gitTokenIncludeWorkflowsInput(ctx, opts); includeWorkflows != "" {
		inputs[gitTokenIncludeWorkflowsInputName] = includeWorkflows
	}

	// Apply custom image settings: pre-installed runtime and fixed runs-on label.
	if customImage {
		data.UsePreinstalledRuntime = true
		data.Customization["runs-on"] = template.HTML(runnerlabels.CustomImageLabel) //nolint:gosec // label is a compile-time constant
		runsOn = runnerlabels.CustomImageLabel
		tags := a.obsv.TelemetryTags(ctx)
		a.obsv.Statter.Counter("custom_image.enabled", tags, 1)
		a.obsv.LoggerWithTelemetry(ctx).Info("using custom image for workflow")
	}

	// Apply runtime setup and entry point
	a.applyRuntimeSetup(ctx, opts, &data)

	// Apply engine mode if the feature flag is enabled and engine repo is configured
	a.applyEngineMode(ctx, opts, &data)

	// Pick the workflow template. The v2 template emits only the steps for the
	// resolved OS, eliminating the per-step `runner.os == 'X'` runtime guards
	// and the duplicated bash/pwsh bodies. We only use it when (a) the FF is
	// on and (b) the OS could be statically determined; otherwise we fall back
	// to the legacy dual-emit template, which preserves today's behavior
	// byte-for-byte.
	//
	// resolveTargetOS is called late on purpose — after setup-steps,
	// organization runner defaults, and custom-image selection have all had a
	// chance to finalize runs-on. Anything we can't statically map to a
	// concrete OS becomes targetOSUnknown (template expressions, arrays,
	// self-hosted, custom-image, multi-label runs-on) and uses the legacy
	// template regardless of the FF.
	//
	// TargetOS / ExpectedRunnerOS are populated ONLY on the v2 path so that
	// the legacy template renders byte-identically to today when the FF is
	// off (the legacy template never reads these fields, but we keep the
	// zero-values structurally unreachable from rendered legacy YAML as a
	// belt-and-braces guarantee).
	tmpl := workflowTemplate
	resolvedOS := resolveTargetOS(runsOn)
	if resolvedOS != targetOSUnknown && a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentDynamicWorkflowOSDispatch, opts) {
		tmpl = workflowTemplateV2
		data.TargetOS = string(resolvedOS)
		data.ExpectedRunnerOS = resolvedOS.expectedRunnerOS()
	}

	// Use template to create workflow yaml
	workflowContent, err := a.workflowContent(ctx, &data, tmpl, opts)
	if err != nil {
		return nil, NonRetriableLaunchError(goerrors.Errorf("failed to generate workflow content: %w", err))
	}

	ref := opts.BranchName

	workflow := &github.NewDynamicWorkflowRun{
		Ref:           gg.Ptr(ref),
		Slug:          gg.Ptr(opts.Agent.ComputeSlug()),
		WorkflowName:  gg.Ptr(opts.Agent.AppName()),
		Workflow:      gg.Ptr(workflowContent),
		Inputs:        gg.Ptr(inputs),
		PreventReruns: true,
		ActorID:       actorBotID,
	}

	useRepoID := a.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentRepoIDForDynamicWorkflows, opts)
	run, err := client.CreateDynamicWorkflowRun(ctx, opts.GitHubRepoOwner, opts.GitHubRepoName, opts.GitHubRepoID, useRepoID, workflow)
	tags := a.obsv.TelemetryTags(ctx).Merge(stats.Tags{"success": strconv.FormatBool(err == nil)})
	a.obsv.Statter.Counter("dynamic_workflow_creation", tags, 1)

	if err != nil {
		if a.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentLogInvalidUTF8Workflow, opts) {
			logWorkflowContentForDebugging(ctx, a.obsv, workflowContent, customSetupStepsUsed, err)
		}
		return nil, ClassifyLaunchError(err, "failed to create dynamic workflow run")
	}

	if run.WorkflowRunID == nil {
		return nil, NonRetriableLaunchError(goerrors.New("dynamic workflow run ID is nil, this should not happen"))
	}

	_ = requestctx.AddWorkflowRun(ctx, &requestctx.CtxWorkflowRun{ID: *run.WorkflowRunID})
	a.obsv.LoggerWithTelemetry(ctx).Info("Created dynamic workflow run")

	return &LaunchResult{
		ComputeID:        strconv.FormatInt(*run.WorkflowRunID, 10),
		CustomSetupSteps: customSetupStepsUsed,
		RunsOn:           runsOn,
	}, nil
}

type tokenSecretNames struct {
	MCP   string
	Shell string
}

func getGitHubTokenSecretNames(ctx context.Context, client featureflags.Client, launchAgentOpts *LaunchAgentOpts) tokenSecretNames {
	names := tokenSecretNames{
		MCP:   "GITHUB_COPILOT_GITHUB_TOKEN",
		Shell: "GITHUB_COPILOT_API_TOKEN",
	}
	// As a near-term mitigation until we get a git proxy implemented, we will use the read-only CAPI token as a placeholder for the real GITHUB_COPILOT_GITHUB_TOKEN
	// for the runtime/bash/powershell, while MCP servers get the real token. Using a feature flag here allows for testing with both scenarios while a git proxy is being implemented.
	if client.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentShellTokenPermissions, launchAgentOpts) {
		names.Shell = "GITHUB_COPILOT_GITHUB_TOKEN"
	}
	return names
}

// replaceFirewallTenantPlaceholders replaces tenant placeholders in firewall settings.
func replaceFirewallTenantPlaceholders(ctx context.Context, agentFirewallRequiredAllowList string) (string, error) {
	var err error
	agentFirewallRequiredAllowList, err = proxima.ReplaceTenantPlaceholder(ctx, agentFirewallRequiredAllowList)
	if err != nil {
		return "", goerrors.Errorf("failed to replace tenant placeholder in agent firewall required allow list: %w", err)
	}
	return agentFirewallRequiredAllowList, nil
}

// replaceFirewallRepoPlaceholders replaces repo placeholders in firewall settings.
// It replaces {{repo_owner}} with repoOwner and {{repo_name}} with repoName.
// The allowList parameter is the firewall allowlist string that may contain placeholders.
// Returns the modified allowList string with placeholders replaced.
func replaceFirewallRepoPlaceholders(allowList, repoOwner, repoName string) string {
	allowList = strings.ReplaceAll(allowList, "{{repo_owner}}", repoOwner)
	allowList = strings.ReplaceAll(allowList, "{{repo_name}}", repoName)
	return allowList
}

// TerminateAgent terminates an agent by cancelling the corresponding GitHub Actions workflow run.
func (a *ActionsLauncher) TerminateAgent(ctx context.Context, opts TerminateAgentOpts) error {
	ctx, span := a.obsv.Tracer.Start(ctx, "launcher.actions.TerminateAgent")
	defer span.End()

	runID, err := strconv.ParseInt(opts.ComputeID, 10, 64)
	if err != nil {
		return goerrors.Errorf("failed to parse compute ID for running job: %w", err)
	}

	if opts.Client == nil {
		app, err := a.appProvider.FindByID(ctx, opts.AgentID)
		if err != nil {
			return goerrors.Errorf("failed to find agentic app by ID: %w", err)
		}

		client, err := a.githubClientFactory.NewClientFromRepo(ctx, app, opts.RepoID, opts.OwnerID)
		if err != nil {
			return goerrors.Errorf("failed to create GitHub client: %w", err)
		}
		opts.Client = client
	}

	err = opts.Client.CancelWorkflowRunByID(ctx, opts.RepoOwner, opts.RepoName, runID)
	return err
}

// useCustomImage reports whether the custom image should be applied.
// The custom image is used by default for all agents when runsOn is empty or
// "ubuntu-latest" (see runnerlabels.UbuntuLatestLabel).
// Agents whose entry point starts with "dist-autofind-ts" additionally
// require CopilotSWEAgentUseCustomImageAutofind.
// CopilotSWEAgentDisableCustomImage can be used to opt out specific users,
// repositories, or organizations.
func (a *ActionsLauncher) useCustomImage(ctx context.Context, runsOn string, opts *LaunchAgentOpts) bool {
	if a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentDisableCustomImage, opts) && !a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentDisableCustomImageOverride, opts) {
		return false
	}
	if runsOn != "" && runsOn != runnerlabels.UbuntuLatestLabel {
		return false
	}
	if usesAutofindEntryPoint(opts.Agent) {
		return a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentUseCustomImageAutofind, opts)
	}
	return true
}

// entryPointProbe is a lightweight ComputeEnv that captures the entry point
// an agent would configure, without modifying real workflow data. All methods
// are pure in-memory string assignments with no I/O.
type entryPointProbe struct {
	entryPoint string
}

func (p *entryPointProbe) SetupAgent(string) {}

func (p *entryPointProbe) EntryPoint(cmd string) {
	p.entryPoint = cmd
}

func usesAutofindEntryPoint(agent sweagentd.AgenticApp) bool {
	if agent == nil {
		return false
	}
	var probe entryPointProbe
	agent.SetupCompute(&probe)
	return agenticapp.IsEntryPointForAutofind(probe.entryPoint)
}

// defaultRunsOnValue returns the default runs-on expression used when no org-specific runner is configured.
// It respects the COPILOT_AGENT_RUNS_ON_LABELS variable, falling back to the configured default labels.
func (a *ActionsLauncher) defaultRunsOnValue() template.HTML {
	return template.HTML(fmt.Sprintf("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || '%s' }}", a.opts.ActionsDefaultRunsOnLabels)) //nolint:gosec // This is controlled input
}

// applyOrgDefaultRunnerSettings applies the organization's configured default runner to the
// workflow's runs-on customization using already-fetched settings. This is called when no
// copilot-setup-steps.yml file is found in the repository or when the file is present but does
// not specify a runs-on value.
func (a *ActionsLauncher) applyOrgDefaultRunnerSettings(ctx context.Context, defaultRunnerSettings *sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse, data *workflowData) string {
	logger := a.obsv.LoggerWithTelemetry(ctx)

	// Restore the default runs-on expression before applying any org-configured labeled runner.
	data.Customization["runs-on"] = a.defaultRunsOnValue()

	var labeledRunner *sweagentdTwirp.LabeledRunner
	switch r := defaultRunnerSettings.GetRunner().(type) {
	case *sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse_StandardRunner:
		return ""
	case *sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse_LabeledRunner:
		labeledRunner = r.LabeledRunner
	default:
		logger.Warn("unknown organization CCA runner setting, using default",
			kvp.String("runner_type", fmt.Sprintf("%T", defaultRunnerSettings.GetRunner())),
		)
		return ""
	}

	group := labeledRunner.GetGroup()
	labels := labeledRunner.GetLabels()
	if group == "" && len(labels) == 0 {
		logger.Warn("Organization CCA runner settings had no group or labels, using default")
		return ""
	}

	var buf strings.Builder
	if group != "" {
		_, _ = buf.WriteString("\n")
		_, _ = buf.WriteString("      group: ")
		_, _ = buf.WriteString(group)
	}
	if len(labels) != 0 {
		_, _ = buf.WriteString("\n")
		_, _ = buf.WriteString("      labels: ")
		if len(labels) == 1 {
			_, _ = buf.WriteString(labels[0]) //nolint:gosec // Labels come from internal trusted API
		} else {
			_, _ = buf.WriteString("[")
			_, _ = buf.WriteString(strings.Join(labels, ", "))
			_, _ = buf.WriteString("]")
		}
	}

	logger.Info("Applying organization default runner settings")
	data.Customization["runs-on"] = template.HTML(buf.String()) //nolint:gosec // Values come from internal trusted API
	return "custom"
}

func (a *ActionsLauncher) applyRuntimeSetup(ctx context.Context, opts *LaunchAgentOpts, d *workflowData) {
	// Copilot and third-party apps run on the Copilot runtime path. Partner
	// agents define their own entry point via SetupCompute.
	if !usesCopilotRuntimeVariants(opts) {
		d.JobName = opts.Agent.ComputeSlug()
		opts.Agent.SetupCompute(d)
		return
	}

	d.JobName = opts.Agent.ComputeSlug()
	runtime := selectRuntime(ctx, a.ffClient, opts)
	d.RuntimeEntryPoint = runtime.entryPoint
	d.RuntimeSetup = runtime.setup
}

// applyEngineMode configures the workflow to run an external engine instead of the
// built-in CCA runtime. Engine mode is currently hardcoded to a dev-only repo and
// is only available in development environments with the engine mode feature flag enabled.
func (a *ActionsLauncher) applyEngineMode(ctx context.Context, opts *LaunchAgentOpts, d *workflowData) {
	if !a.opts.IsDevelopmentEnvironment {
		return
	}

	if !a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentEngineMode, opts) {
		return
	}

	engineRepoNWO := "github/agent-platform-engine-example"
	codeloadHost := "http://codeload.github.localhost"

	d.EngineEnabled = true
	d.EngineRepoNWO = engineRepoNWO
	d.EngineDownloadURL = fmt.Sprintf("%s/%s/tar.gz/main", codeloadHost, engineRepoNWO)
}

func (a *ActionsLauncher) applyMCPSettings(ctx context.Context, data *workflowData, opts *LaunchAgentOpts, customImage bool) (serverConfig, interactionID, encodedPermissions string, err error) {
	if a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "sweagentd_mcp_disable", opts) {
		// This is a FF used to meet a ProdSec requirement that we have a mechanism to disable MCP entirely for specific actors
		data.MCPEnabled = false
		return "", opts.SessionID, "", nil
	}

	// Determine the blackbird mode
	if a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "sweagentd_blackbird_initial_search", opts) {
		data.BlackbirdMode = "initial-search"
	}

	params := mcp.ConfigureParams{
		CustomAgent:  opts.CustomAgent,
		GHTwirp:      a.ghTwirp,
		RepositoryID: opts.GitHubRepoID,
		UserID:       opts.ActorID,
		FFClient:     a.ffClient,
	}

	// When using a custom image, Playwright MCP is pre-started as a systemd service
	// on port 3100. Rewrite the config to use the remote HTTP endpoint instead of launching a new process.
	if customImage {
		params.UsePreStartedPlaywright = true
		params.PreStartedPlaywrightURL = "http://localhost:3100/mcp"
	}

	resp, err := mcp.Configure(ctx, params)
	if err != nil {
		return "", opts.SessionID, "", goerrors.Errorf("failed to configure MCP: %w", err)
	}

	agentPerms := permissions.Unset
	if p, ok := opts.CustomAgent.(permissions.Provider); ok {
		agentPerms = p.Permissions()
	}

	// Enable support for repo MCP config-level permissions (set under github.permissions) if ff is set.
	repoPerms := permissions.Unset
	if a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentRepoConfigCustomPermissions, opts) {
		repoPerms = resp.Permissions
	}

	// When neither the custom agent nor the repo specifies permissions and the
	// `copilot_swe_agent_mcp_permission_gate` FF is enabled, expand the
	// default token to read-write. The runtime's PermissionGate gates each
	// non-readOnly MCP tool call behind interactive user approval, so the
	// broadened token cannot be used for unattended writes.
	//
	// Only the Copilot coding agent has the PermissionGate wired in; for
	// third-party agents (Claude, Codex, custom) the expanded write token
	// would be ungated, so we keep them on the read-only default permissions
	// until the feature parity is gained for those runtimes.
	isCopilotCodingAgent := a.appProvider != nil && a.appProvider.IsCopilotCodingAgentApp(opts.Agent.AppID())
	useExpandedDefaults := agentPerms.IsUnset() && repoPerms.IsUnset() && isCopilotCodingAgent &&
		a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentMCPPermissionGate, opts)

	perms := permissions.ResolvePermissions(agentPerms, repoPerms)
	if useExpandedDefaults {
		perms = permissions.MCPWriteDefault
	}
	if opts.IsTriggered && a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCustomAgentTriggers, opts) {
		perms = permissions.RestrictTriggeredMCPPermissions(perms)
	}

	ghp, err := perms.ToDotCom()
	if err != nil {
		return "", opts.SessionID, "", goerrors.Errorf("failed to convert resolved permissions: %w", err)
	}
	permissionsJSON, err := json.Marshal(ghp)
	if err != nil {
		return "", opts.SessionID, "", goerrors.Errorf("failed to marshal resolved permissions to JSON: %w", err)
	}
	effectivePerms := string(permissionsJSON)

	data.MCP3PEnabled = resp.Enabled
	return resp.Encoded, opts.SessionID, effectivePerms, nil
}

// environmentURLs contains the URLs needed for a specific environment.
type environmentURLs struct {
	CopilotAPIURL        string
	ActionDownloadURL    string
	AgentCallbackURL     string
	UploadURL            string
	DownloadURL          string
	SecretScanningURL    string
	CopilotAPIHost       string // Host extracted from CopilotAPIURL
	GitHubMCPURLOverride string // Development override to allow pointing to localhost w/o CAPI
}

// getURLsForEnvironment returns the action download URL and agent callback URL for the given environment
func (a *ActionsLauncher) getURLsForEnvironment(ctx context.Context, environment config.Environment, opts *LaunchAgentOpts) (environmentURLs, error) {
	urls := environmentURLs{
		CopilotAPIURL:        a.opts.CopilotAPIURL,
		GitHubMCPURLOverride: a.opts.GitHubMCPURLOverride,
	}

	// Apply subscription-based CAPI URL if feature flag is enabled
	// Only apply for production and staging environments (not Proxima/development)
	if a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWESubscriptionBasedCapiURL, opts) &&
		(environment == config.EnvironmentProduction || environment == config.EnvironmentStaging) {
		userDetails, err := a.ghTwirp.GetCopilotUserDetails(ctx, opts.ActorID)
		if err != nil {
			// Log error but don't fail - fall back to default URL
			a.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("failed to get user details for subscription-based URL, using default")
		}

		if userDetails != nil && userDetails.Skuisolation != nil && userDetails.Skuisolation.ApiHost != "" {
			// Use the API-provided subscription-based URL
			urls.CopilotAPIURL = "https://" + userDetails.Skuisolation.ApiHost
			urls.CopilotAPIHost = userDetails.Skuisolation.ApiHost
			a.obsv.LoggerWithTelemetry(ctx).Info("using subscription-based Copilot API endpoint",
				kvp.String("endpoint", urls.CopilotAPIURL))
		}
	}

	var err error
	switch environment {
	case config.EnvironmentStaging:
		urls.ActionDownloadURL = urls.CopilotAPIURL + fmt.Sprintf("/agents/swe-%s/runtime", a.opts.Environment)
		urls.AgentCallbackURL = urls.CopilotAPIURL + fmt.Sprintf("/agents/swe-%s/agent", a.opts.Environment)
		urls.UploadURL = a.opts.UploadsURL
		urls.DownloadURL = a.opts.DownloadsURL
		urls.SecretScanningURL = a.opts.SecretScanningURL
	case config.EnvironmentProxima:
		urls.CopilotAPIURL, err = proxima.ReplaceTenantPlaceholder(ctx, urls.CopilotAPIURL)
		if err != nil {
			return environmentURLs{}, goerrors.Errorf("failed to replace tenant placeholder in copilot API URL: %w", err)
		}

		urls.ActionDownloadURL = urls.CopilotAPIURL + "/agents/swe/runtime"
		urls.AgentCallbackURL, err = proxima.ReplaceTenantPlaceholder(ctx, a.opts.AgentCallbackURL)
		if err != nil {
			return environmentURLs{}, goerrors.Errorf("failed to replace tenant placeholder in agent callback URL: %w", err)
		}
		urls.UploadURL, err = proxima.ReplaceTenantPlaceholder(ctx, a.opts.UploadsURL)
		if err != nil {
			return environmentURLs{}, goerrors.Errorf("failed to replace tenant placeholder in upload URL: %w", err)
		}
		urls.DownloadURL, err = proxima.ReplaceTenantPlaceholder(ctx, a.opts.DownloadsURL)
		if err != nil {
			return environmentURLs{}, goerrors.Errorf("failed to replace tenant placeholder in downloads URL: %w", err)
		}

		urls.SecretScanningURL, err = proxima.ReplaceTenantPlaceholder(ctx, a.opts.SecretScanningURL)
		if err != nil {
			return environmentURLs{}, goerrors.Errorf("failed to replace tenant placeholder in secret scanning URL: %w", err)
		}
	case config.EnvironmentDevelopment:
		// The callback URL is different than the CopilotAPIURL if CAPI is not running in development
		if a.opts.AgentCallbackURL != "" {
			urls.AgentCallbackURL = a.opts.AgentCallbackURL
		} else {
			urls.AgentCallbackURL = urls.CopilotAPIURL + "/agents/swe/agent"
		}
		urls.UploadURL = a.opts.UploadsURL
		urls.DownloadURL = a.opts.DownloadsURL
		urls.SecretScanningURL = a.opts.SecretScanningURL
	default:
		urls.AgentCallbackURL = urls.CopilotAPIURL + "/agents/swe/agent"
		urls.UploadURL = a.opts.UploadsURL
		urls.DownloadURL = a.opts.DownloadsURL
		urls.SecretScanningURL = a.opts.SecretScanningURL
	}

	// Extract host from CopilotAPIURL if not already set
	if urls.CopilotAPIHost == "" {
		parsedURL, err := url.Parse(urls.CopilotAPIURL)
		if err == nil && parsedURL.Host != "" {
			urls.CopilotAPIHost = parsedURL.Host
		}
	}

	return urls, nil
}

//go:embed actions_workflow.yaml
var workflowTemplate string

//go:embed actions_workflow_v2.yaml
var workflowTemplateV2 string

type workflowData struct {
	RunName                              template.HTML
	Secrets                              []string
	Variables                            []string
	AgenticGitHubAppAction               string
	AgenticGitHubAppConfigVarName        string
	AgentDebug                           bool
	AgentFirewallEnabledDefault          bool
	AgentFirewallRuleSetAllowListDefault template.HTML
	AgentFirewallRequiredAllowList       template.HTML
	UseMaterializedFirewall              bool
	MaterializedFirewallEnabled          bool
	MaterializedFirewallUseDefaultRules  bool
	MaterializedFirewallAllowedRules     template.HTML
	AgentCallbackURL                     string
	UploadsURL                           string
	JobID                                string
	IsDevelopmentEnvironment             bool
	IsStagingEnvironment                 bool
	Environment                          string
	ActionDownloadURL                    string                   // Used to bootstrap the runtime from sweagentd itself
	Customization                        map[string]template.HTML // Don't want to escape this since we need to use ""
	MCPEnabled                           bool
	MCP3PEnabled                         bool
	MCPVariables                         []string
	MCPSecrets                           []string
	McpRemoteEnabled                     bool
	MCPReadOnlyMode                      bool
	PlaywrightUseFirewall                bool
	BlackbirdMode                        string
	InjectedSecretNames                  string
	AgentOnlineEvaluationDisabled        string
	FeatureFlags                         string
	Experiments                          string
	ExperimentAssignmentContext          string
	PlaywrightVersion                    string
	RuntimeEntryPoint                    string
	RuntimeSetup                         string
	JobName                              string
	TokenSecretNames                     tokenSecretNames
	CopilotTraceParent                   string
	UsePreinstalledRuntime               bool
	URLs                                 environmentURLs
	BackgroundMkcertKeygen               bool
	RepositoryOwner                      string
	UseAgentSecrets                      bool
	// Engine mode fields
	EngineEnabled     bool
	EngineRepoNWO     string // e.g. "github/agent-platform-engine-example"
	EngineDownloadURL string // codeload URL for engine tarball

	// IncludeCopilotEnvironmentInDynamicWorkflow forces the copilot environment
	// to stay attached to the generated dynamic workflow when agent secrets are enabled.
	IncludeCopilotEnvironmentInDynamicWorkflow bool

	// TargetOS is the operating system the workflow is being rendered for.
	// It is one of "linux", "windows", "macos", or "" (empty) — empty means
	// the legacy multi-OS dispatch template is in use, which emits per-step
	// `runner.os == 'X'` guards for every supported OS and does not read
	// this field. Populated in LaunchAgent only on the v2 template path
	// (FF on AND runs-on statically resolves to a concrete OS via
	// resolveTargetOS in target_os.go); zero on every other path.
	TargetOS string

	// ExpectedRunnerOS is the value GitHub Actions exposes as `runner.os`
	// for TargetOS (e.g. "Linux", "Windows", "macOS"), or "" when TargetOS
	// is "". Populated alongside TargetOS only on the v2 template path.
	// The v2 template uses this to emit a fail-fast assertion step that
	// catches the case where the workflow was rendered for one OS but
	// actually scheduled on a runner with a different OS.
	ExpectedRunnerOS string
}

func (w *workflowData) SetupAgent(cmd string) {
	w.RuntimeSetup = cmd
}

func (w *workflowData) EntryPoint(cmd string) {
	w.RuntimeEntryPoint = cmd
}

// ActionsInputNumberLimit limits the number of inputs to 10.
const ActionsInputNumberLimit = 10

// ActionsInputJSONLengthLimit limits the inputs serialized to a JSON string to 2^16 - 1 bytes, which
// is the limit for MySQL BLOB and TEXT fields.
//
//   - https://github.com/github/github/blob/17b228a224bc48b3bae6e5602b498d8500b0f1ef/app/api/actions_dynamic_workflows.rb#L23-L25
//   - https://github.com/github/github/blob/17b228a224bc48b3bae6e5602b498d8500b0f1ef/lib/github/config/mysql.rb#L236-L239
const ActionsInputJSONLengthLimit = 65535

func validateInputs(inputs map[string]string) error {
	if len(inputs) > ActionsInputNumberLimit {
		return goerrors.Errorf("number of inputs: %d exceeds maximum: %d", len(inputs), ActionsInputNumberLimit)
	}
	inputsJSON, err := json.Marshal(inputs)
	if err != nil {
		return goerrors.Errorf("failed to marshal inputs to JSON: %w", err)
	}
	if len(inputsJSON) > ActionsInputJSONLengthLimit {
		return goerrors.Errorf("length of inputs JSON: %d exceeds maximum: %d", len(inputsJSON), ActionsInputJSONLengthLimit)
	}
	return nil
}

func (a *ActionsLauncher) workflowContent(ctx context.Context, data *workflowData, workflowTmpl string, opts *LaunchAgentOpts) (string, error) {
	// Remove any secrets or variables that are explicitly called out in the workflow yaml.
	if data.Secrets != nil {
		data.Secrets = slices.DeleteFunc(data.Secrets, func(v string) bool {
			return slices.Contains(workflowDirectlyReferencedVarNames, v)
		})
		if data.IsDevelopmentEnvironment {
			data.Secrets = slices.DeleteFunc(data.Secrets, func(v string) bool {
				return slices.Contains(developmentWorkflowDirectlyReferencedVarNames, v)
			})
		}
	}
	if data.Variables != nil {
		data.Variables = slices.DeleteFunc(data.Variables, func(v string) bool {
			return slices.Contains(workflowDirectlyReferencedVarNames, v)
		})
		if data.IsDevelopmentEnvironment {
			data.Variables = slices.DeleteFunc(data.Variables, func(v string) bool {
				return slices.Contains(developmentWorkflowDirectlyReferencedVarNames, v)
			})
		}
	}
	// For secrets and variables with the same name, the secret takes precedence.
	if data.Secrets != nil && data.Variables != nil {
		data.Variables = slices.DeleteFunc(data.Variables, func(v string) bool {
			return slices.Contains(data.Secrets, v)
		})
	}

	if data.MCPEnabled {
		extractMCPVars(data)
	}

	// Generate workflow using template
	templateContent, err := a.generateWorkflowFromTemplate(data, workflowTmpl)
	if err != nil {
		return "", err
	}

	// If workflow parser validation is enabled, validate the generated workflow
	if opts != nil && a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentWorkflowParserValidation, opts) {
		validationResult := validateWorkflowYAML(templateContent)
		if !validationResult.Valid {
			// Log full error details
			fullError := validationResult.FullError()
			a.obsv.LoggerWithTelemetry(ctx).Error("workflow validation failed",
				kvp.String("validation_errors", fullError))

			// Emit telemetry counter
			tags := a.obsv.TelemetryTags(ctx).Merge(stats.Tags{"error_count": fmt.Sprintf("%d", len(validationResult.Errors))})
			a.obsv.Statter.Counter("workflowParserValidation.error", tags, 1)

			return "", goerrors.New(validationResult.FullError())
		}

		// Log success for telemetry
		tags := a.obsv.TelemetryTags(ctx)
		a.obsv.Statter.Counter("workflowParserValidation.success", tags, 1)
	}

	return templateContent, nil
}

// generateWorkflowFromTemplate generates workflow YAML using the Go template approach.
func (a *ActionsLauncher) generateWorkflowFromTemplate(data *workflowData, workflowTmpl string) (string, error) {
	funcMap := template.FuncMap{"contains": slices.Contains[[]string, string]}

	tmpl, err := template.New("workflow").Delims("<<", ">>").Funcs(funcMap).Parse(workflowTmpl)

	if err != nil {
		return "", goerrors.Errorf("failed to parse workflow template: %w", err)
	}

	var buf bytes.Buffer
	err = tmpl.Execute(&buf, data)
	if err != nil {
		return "", goerrors.Errorf("failed to execute workflow template: %w", err)
	}
	return buf.String(), nil
}

func (a *ActionsLauncher) environmentVariables(ctx context.Context, opts *LaunchAgentOpts, overrides *Variables) (map[string]string, error) {
	all := GetVariables(ctx, a.ffClient, a.opts, opts, overrides)

	// Check if required runtime variables are present
	if a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentValidateRuntimeVariables, opts) {
		err := validateRequiredVariables(all)
		if err != nil {
			return nil, goerrors.Errorf("required runtime variables validation failed: %w", err)
		}
	}

	inputs := map[string]string{}
	for k, v := range all {
		inputs[k] = v.Value
	}
	// Actions limits us to 10 inputs, so we serialize the inputs to a JSON string
	// and pass them as the value to a single COPILOT_AGENT_INPUTS input.
	inputsJSON, err := json.Marshal(inputs)
	if err != nil {
		return nil, goerrors.Errorf("failed to marshal inputs to JSON: %w", err)
	}

	a.obsv.LoggerWithTelemetry(ctx).Info(fmt.Sprintf("Using runtime version: %s\n", inputs["COPILOT_AGENT_RUNTIME_VERSION"]))
	envVars := map[string]string{
		"COPILOT_AGENT_INPUTS": string(inputsJSON),
		// When we send a dynamic workflow to Actions, the Actions service calls back
		// into dotcom to get secrets (e.g. the CAPI u2s token). We use the actor ID to
		// associate agent job with a user. This logic requires COPILOT_AGENT_ACTOR_ID
		// to be a top-level input, so we pass it here as well.
		"COPILOT_AGENT_ACTOR_ID":        inputs["COPILOT_AGENT_ACTOR_ID"],
		"COPILOT_AGENT_ACTOR_TYPE":      inputs["COPILOT_AGENT_ACTOR_TYPE"],
		"COPILOT_AGENT_RUNTIME_VERSION": inputs["COPILOT_AGENT_RUNTIME_VERSION"],
	}
	return envVars, nil
}

// We only perform this operation on items we read in from the `copilot` environment
func extractMCPVars(data *workflowData) {
	mcpVariables := []string{}
	nonMCPVariables := []string{}

	for _, variable := range data.Variables {
		if mcp.IsVar(variable) {
			mcpVariables = append(mcpVariables, variable)
		} else {
			nonMCPVariables = append(nonMCPVariables, variable)
		}
	}

	mcpSecrets := []string{}
	nonMCPSecrets := []string{}

	for _, secret := range data.Secrets {
		if mcp.IsVar(secret) {
			mcpSecrets = append(mcpSecrets, secret)
		} else {
			nonMCPSecrets = append(nonMCPSecrets, secret)
		}
	}

	data.Variables = nonMCPVariables
	data.Secrets = nonMCPSecrets
	data.MCPVariables = mcpVariables
	data.MCPSecrets = mcpSecrets
}

// GenerateRunName generates a run name for the GitHub Actions workflow run.
func GenerateRunName(opts *LaunchAgentOpts) string {
	if opts.Agent != nil && opts.Agent.WorkflowRunName(opts.PRNumber) != "" {
		return opts.Agent.WorkflowRunName(opts.PRNumber)
	}

	if opts.RunName != "" {
		// Escape single quotes as Actions YAML quote the value as `run-name: '<value>'`
		runName := strings.ReplaceAll(opts.RunName, "'", "''")
		// Shrink to one-liner to avoid multi-liner conflicting with YAML syntax (e.g. "---" indicating a new YAML document)
		runName = strings.ReplaceAll(runName, "\n", " ")
		runName = strings.ReplaceAll(runName, "\r", " ")
		runName = strings.Join(strings.Fields(runName), " ")
		if len(runName) > github.MaxRunNameLength {
			runName = runName[:github.MaxRunNameLength-3] + "..."
		}
		return runName
	}
	if opts.Action == "fix-pr-comment" && opts.PRNumber != 0 {
		return fmt.Sprintf("Addressing comment on PR #%d", opts.PRNumber)
	}
	if opts.IssueNumber != 0 {
		return fmt.Sprintf("Fixing issue #%d", opts.IssueNumber)
	}
	return fmt.Sprintf("Running %s", opts.Agent.AppName())
}

// ActionsWorkflowJobKnownSteps returns the known steps in the dynamic workflow job.
// This is used to determine if a failed step is part of the core workflow or
// a custom step defined by the user (copilot-setup-steps.yml).
func ActionsWorkflowJobKnownSteps() []string {
	return []string{
		"Initialize",
		"Set HOME environment variable (Linux)",
		"Validate runner OS",
		"Validate expected runner OS",
		"Validate firewall settings (Linux)",
		"Validate firewall settings (Windows)",
		"Pre-cache Playwright MCP server in the background (Linux)",
		"Pre-cache Playwright MCP server in the background (Windows)",
		"Use pre-installed runtime (Linux)",
		"Prepare Copilot (Linux)",
		"Prepare Copilot (Windows)",
		"Download Autofind (Linux)",
		"Download Autofind (Windows)",
		"Generate agent firewall CA (Linux)",
		"Start MCP Servers (Linux)",
		"Start MCP Servers (Windows)",
		"Setup Agent (Linux)",
		"Setup Agent (Windows)",
		"Pre-seed mkcert CA (Linux)",
		"Processing Request (Linux)",
		"Processing Request (Windows)",
		"Download and Run Engine",
		"Clean up mkcert CA (Linux)",
		"Clean Up (Linux)",
		"Clean Up (Windows)",
		"Post-Prepare Copilot (Linux)",
		"Post-Prepare Copilot (Windows)",
		"Checkout Repository for Post-Prepare",
		"[Optional] Archive Details",
	}
}

// ActionsWorkflowNotSupportedStepsWithErrorMessage returns a map of known unsupported steps.
func ActionsWorkflowNotSupportedStepsWithErrorMessage() map[string]string {
	return map[string]string{
		"Validate runner OS":                   "The `runs-on` setting in your `copilot-setup-steps.yml` file points to a GitHub Actions runner with an unsupported operating system. Only Linux and Windows runners are supported. For more information, see https://gh.io/cca-runner-os.",
		"Validate expected runner OS":          "The `runs-on` label resolved to a different operating system than the one detected on the runner. Make sure the runner labels in `copilot-setup-steps.yml` and your runner registration agree. For more information, see https://gh.io/cca-runner-os.",
		"Validate firewall settings (Linux)":   "The agent firewall is enabled, but firewall is not supported for self-hosted runners. You must disable the agent firewall in the repository's settings to use self-hosted runners. For more information, see https://gh.io/cca-self-hosted-disable-firewall.",
		"Validate firewall settings (Windows)": "The agent firewall is enabled, but firewall is not supported on Windows runners. You must disable the agent firewall in the repository's settings to use Windows runners. For more information, see https://gh.io/cca-disable-firewall.",
	}
}

// gitTokenIncludeWorkflowsInputName tells dotcom whether to include workflows:write
// when minting GITHUB_COPILOT_GIT_TOKEN. Value: "true"/"false"; absent ⇒ dotcom
// uses its legacy hardcoded permissions.
const gitTokenIncludeWorkflowsInputName = "COPILOT_AGENT_GIT_TOKEN_INCLUDE_WORKFLOWS"

// gitTokenIncludeWorkflowsInput returns the value for the
// COPILOT_AGENT_GIT_TOKEN_INCLUDE_WORKFLOWS dynamic-workflow input, or ""
// when the input should be omitted (FF off or no check was performed).
//
// Kept outside applyMCPSettings (which short-circuits when sweagentd_mcp_disable
// is on) so the scoping still applies in that case.
func (a *ActionsLauncher) gitTokenIncludeWorkflowsInput(ctx context.Context, opts *LaunchAgentOpts) string {
	if !a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentScopeGitTokenWorkflows, opts) {
		return ""
	}
	if opts.CanWriteWorkflows == nil {
		return ""
	}
	allowed := *opts.CanWriteWorkflows
	result := "denied"
	if allowed {
		result = "allowed"
	}
	a.obsv.Increment(ctx, "git_token_workflow_scope_check", stats.Tags{
		"result": result,
		"source": "launcher_emit",
	})
	return strconv.FormatBool(allowed)
}
