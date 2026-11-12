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
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/mcp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/proxima"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

// These are variables explicitly called out in the workflow yaml. They should not
// be passed into the actions_workflow.yaml template to avoid duplicates.
var workflowDirectlyReferencedVarNames = []string{
	"COPILOT_AGENT_RUNS_ON_LABELS",
	"COPILOT_AGENT_FIREWALL_ENABLED",
	"COPILOT_AGENT_FIREWALL_ALLOW_LIST_ADDITIONS",
	"COPILOT_AGENT_FIREWALL_ALLOW_LIST",
	"COPILOT_AGENT_DEBUG",
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
	opts ActionsLauncherOpts,
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

	urls, err := a.getURLsForEnvironment(ctx, environment, a.opts.Environment, opts.ActorID)
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

	client, err := a.githubClientFactory.NewClientFromRepo(ctx, opts.Agent, opts.GitHubRepoID, opts.GitHubRepoOwnerID)
	if err != nil {
		return nil, ClassifyLaunchError(err, "failed to create GitHub client")
	}

	secrets, variables, err := client.GetCopilotEnvironmentSecretsAndVariables(ctx, opts.GitHubRepoOwner, opts.GitHubRepoName, opts.GitHubRepoID)
	if err != nil {
		return nil, ClassifyLaunchError(err, "failed to get copilot environment secrets and variables")
	}

	// Emit Datadog metrics for Copilot environment secrets and variables counts
	metricTags := a.obsv.TelemetryTags(ctx)
	a.obsv.Statter.Distribution("agent.copilot_environment.secrets.count", metricTags, float64(len(secrets)))
	a.obsv.Statter.Distribution("agent.copilot_environment.variables.count", metricTags, float64(len(variables)))

	firewallRequiredAllowList, err := replaceFirewallTenantPlaceholders(ctx, a.opts.AgentFirewallRequiredAllowList)
	if err != nil {
		return nil, NonRetriableLaunchError(goerrors.Errorf("failed to replace firewall tenant placeholders: %w", err))
	}

	// Replace repo-specific placeholders
	if opts.GitHubRepoOwner != "" && opts.GitHubRepoName != "" {
		firewallRequiredAllowList = replaceFirewallRepoPlaceholders(firewallRequiredAllowList, opts.GitHubRepoOwner, opts.GitHubRepoName)
	}

	if urls.CopilotAPIHost != "" {
		if firewallRequiredAllowList == "" {
			firewallRequiredAllowList = urls.CopilotAPIHost
		} else {
			firewallRequiredAllowList = firewallRequiredAllowList + "," + urls.CopilotAPIHost
		}
	}

	data := workflowData{
		RunName:                        template.HTML(GenerateRunName(opts)), //nolint:gosec // This is controlled input
		JobName:                        opts.Agent.ComputeSlug(),
		Secrets:                        secrets,
		Variables:                      variables,
		AgentDebug:                     a.opts.AgentDebug,
		AgentFirewallEnabledDefault:    isFirewallEnabledByDefault(ctx, a.ffClient, &a.opts.AgentLauncherOpts),
		AgentFirewallRequiredAllowList: template.HTML(firewallRequiredAllowList), //nolint:gosec // This is controlled input
		AgentCallbackURL:               urls.AgentCallbackURL,
		UploadsURL:                     a.opts.UploadsURL,
		JobID:                          opts.JobID,
		IsDevelopmentEnvironment:       a.opts.IsDevelopmentEnvironment,
		Environment:                    a.opts.Environment,
		MCPEnabled:                     a.opts.MCPEnabled,
		MCP3PEnabled:                   true,
		McpRemoteEnabled:               a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "sweagentd_mcp_remote_enabled", opts),
		MCPVariables:                   []string{},
		MCPSecrets:                     []string{},
		WindowsOSRunnerEnabled:         a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentWindowsOSRunner, opts),
		Customization: map[string]template.HTML{
			"runs-on":         template.HTML(fmt.Sprintf("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || '%s' }}", a.opts.ActionsDefaultRunsOnLabels)), //nolint:gosec // This is controlled input
			"timeout-minutes": template.HTML(fmt.Sprintf("%d", a.opts.AgentTimeoutMin)),                                                          //nolint:gosec // This is controlled input
		},
		BlackbirdMode:                 "disabled",
		InjectedSecretNames:           strings.Join(secrets, ","),
		AgentOnlineEvaluationDisabled: "false",
		FeatureFlags: strings.Join(
			getFeatureFlags(ctx, a.ffClient, opts),
			","),
		Experiments:                 opts.Experiments,
		ExperimentAssignmentContext: opts.ExperimentAssignmentContext,
		PlaywrightVersion:           playwrightVersion,
		GitHubMCPTokenSecretName:    getGitHubMCPTokenSecretName(ctx, a.ffClient, opts),
		CopilotTraceParent:          getCopilotTraceParent(ctx, a.ffClient, opts, a.opts.TraceParentPropagator),
		ClearTempGitCredentials:     a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCleanGitConfig, opts),
	}

	switch environment {
	case config.EnvironmentStaging, config.EnvironmentProxima:
		data.ActionDownloadURL = urls.ActionDownloadURL
	default:
		// In production, we always use the public action URL
	}

	data.AgentFirewallRuleSetAllowListDefault = template.HTML(a.opts.AgentFirewallRuleSetAllowListDefault) //nolint:gosec // This is controlled input

	inputs[mcp.ServerConfigEnvVar], inputs[mcp.InteractionIDEnvVar], err = a.applyMCPSettings(ctx, &data, opts)
	if err != nil {
		return nil, ClassifyLaunchError(err, "failed to apply MCP settings")
	}

	if isOnlineEvaluationDisabled(ctx, a.ffClient, &a.opts.AgentLauncherOpts, opts) {
		data.AgentOnlineEvaluationDisabled = "true"
	}

	// Try to find a user Actions workflow steps file at ".github/workflows/copilot-setup-steps.yml/yaml" for the
	// repo and branch and then process it. Only the permissions, runs-on, and steps from the copilot-setup-steps job are used.
	setupStepsResult, err := a.applySetupSteps(ctx, client, opts, &data, urls.CopilotAPIURL)
	if err != nil {
		// If the setup steps file is not found, or there is an error processing
		// it, we create a comment on the PR to inform the user, but we do not fail
		// the workflow run.
		a.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("failed to apply setup steps")
	} else if setupStepsResult != nil {
		data.Customization = setupStepsResult.Customization
		customSetupStepsUsed = setupStepsResult.WasApplied
		runsOn = setupStepsResult.RunsOn
	}

	// Apply runtime setup and entry point
	a.applyRuntimeSetup(ctx, opts, &data)

	// Use template to create workflow yaml
	workflowContent, err := a.workflowContent(ctx, &data, workflowTemplate, opts)
	if err != nil {
		return nil, NonRetriableLaunchError(goerrors.Errorf("failed to generate workflow content: %w", err))
	}

	workflow := &github.NewDynamicWorkflowRun{
		Ref:           gg.Ptr(opts.BranchName),
		Slug:          gg.Ptr(opts.Agent.ComputeSlug()),
		WorkflowName:  gg.Ptr(opts.Agent.AppName()),
		Workflow:      gg.Ptr(workflowContent),
		Inputs:        gg.Ptr(inputs),
		PreventReruns: true,
	}

	useRepoID := a.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentRepoIDForDynamicWorkflows, opts)
	run, err := client.CreateDynamicWorkflowRun(ctx, opts.GitHubRepoOwner, opts.GitHubRepoName, opts.GitHubRepoID, useRepoID, workflow)
	tags := a.obsv.TelemetryTags(ctx).Merge(stats.Tags{"success": strconv.FormatBool(err == nil)})
	a.obsv.Statter.Counter("dynamic_workflow_creation", tags, 1)

	if err != nil {
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

func getGitHubMCPTokenSecretName(ctx context.Context, client featureflags.Client, launchAgentOpts *LaunchAgentOpts) string {
	if client.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCustomAgentPermissions, launchAgentOpts) {
		return "GITHUB_COPILOT_GITHUB_TOKEN"
	}
	return "GITHUB_COPILOT_API_TOKEN"
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
		app, err := a.appProvider.FindByID(opts.AgentID)
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

func (a *ActionsLauncher) applyRuntimeSetup(ctx context.Context, opts *LaunchAgentOpts, d *workflowData) {
	if a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentRuntimeEntryPointCCAV2, opts) {
		d.RuntimeEntryPoint = "dist-cca/index.js"
		return
	}

	if a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentRuntimeEntryPointClaude, opts) {
		d.RuntimeEntryPoint = "dist-claude/index.js"
		return
	}

	if a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentRuntimeEntryPointCodex, opts) {
		d.RuntimeEntryPoint = "dist-codex/index.js"
		d.RuntimeSetup = "npm install -g @openai/codex@0.47.0"
		return
	}

	d.JobName = opts.Agent.ComputeSlug()
	opts.Agent.SetupCompute(d)
}

func (a *ActionsLauncher) applyMCPSettings(ctx context.Context, data *workflowData, opts *LaunchAgentOpts) (serverConfig, interactionID string, err error) {
	if a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "sweagentd_mcp_disable", opts) {
		// This is a FF used to meet a ProdSec requirement that we have a mechanism to disable MCP entirely for specific actors
		data.MCPEnabled = false
		return "", opts.SessionID, nil
	}

	// Determine the blackbird mode
	if a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "sweagentd_blackbird_initial_search", opts) {
		data.BlackbirdMode = "initial-search"
	}

	params := mcp.ConfigureParams{
		GHTwirp:      a.ghTwirp,
		RepositoryID: opts.GitHubRepoID,
		UserID:       opts.ActorID,
		CustomAgent:  opts.CustomAgent,
	}
	resp, err := mcp.Configure(ctx, params)
	if err != nil {
		return "", opts.SessionID, goerrors.Errorf("failed to configure MCP: %w", err)
	}
	data.MCP3PEnabled = resp.Enabled
	return resp.Encoded, opts.SessionID, nil
}

// environmentURLs contains the URLs needed for a specific environment.
type environmentURLs struct {
	CopilotAPIURL     string
	ActionDownloadURL string
	AgentCallbackURL  string
	UploadURL         string
	DownloadURL       string
	SecretScanningURL string
	CopilotAPIHost    string // Host extracted from CopilotAPIURL
}

// getURLsForEnvironment returns the action download URL and agent callback URL for the given environment
func (a *ActionsLauncher) getURLsForEnvironment(ctx context.Context, environment config.Environment, environmentName string, actorID int64) (environmentURLs, error) {
	urls := environmentURLs{
		CopilotAPIURL: a.opts.CopilotAPIURL,
	}

	// Apply subscription-based CAPI URL if feature flag is enabled
	// Only apply for production and staging environments (not Proxima/development)
	if a.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWESubscriptionBasedCapiURL, actorID) &&
		(environment == config.EnvironmentProduction || environment == config.EnvironmentStaging) {
		userDetails, err := a.ghTwirp.GetCopilotUserDetails(ctx, actorID)
		if err != nil {
			// Log error but don't fail - fall back to default URL
			a.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("failed to get user details for subscription-based URL, using default")
		}

		if userDetails != nil && userDetails.Skuisolation != nil && userDetails.Skuisolation.ApiHost != "" {
			// Use the API-provided subscription-based URL
			urls.CopilotAPIURL = "https://" + userDetails.Skuisolation.ApiHost
			urls.CopilotAPIHost = userDetails.Skuisolation.ApiHost
		}
	}

	var err error
	switch environment {
	case config.EnvironmentStaging:
		urls.ActionDownloadURL = urls.CopilotAPIURL + fmt.Sprintf("/agents/swe-%s/runtime", environmentName)
		urls.AgentCallbackURL = urls.CopilotAPIURL + fmt.Sprintf("/agents/swe-%s/agent", environmentName)
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
	AgentCallbackURL                     string
	UploadsURL                           string
	JobID                                string
	IsDevelopmentEnvironment             bool
	Environment                          string
	ActionDownloadURL                    string                   // Used to bootstrap the runtime from sweagentd itself
	Customization                        map[string]template.HTML // Don't want to escape this since we need to use ""
	MCPEnabled                           bool
	MCP3PEnabled                         bool
	MCPVariables                         []string
	MCPSecrets                           []string
	McpRemoteEnabled                     bool
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
	WindowsOSRunnerEnabled               bool
	GitHubMCPTokenSecretName             string
	CopilotTraceParent                   string
	ClearTempGitCredentials              bool
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
	gzip := a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentGZipProblemStatement, opts)
	all := GetVariables(ctx, a.ffClient, a.opts, opts, overrides, gzip)

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
		"COPILOT_AGENT_RUNTIME_VERSION": inputs["COPILOT_AGENT_RUNTIME_VERSION"],
	}

	// Determine permission scopes and add to inputs if CopilotSWEAgentCustomAgentPermissions is set
	if a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCustomAgentPermissions, opts) {
		var p map[string]string
		if opts.CustomAgent != nil {
			p, err = customagent.PermissionsToDotComPermissions(opts.CustomAgent.Permissions())
		} else {
			p, err = customagent.PermissionsToDotComPermissions(customagent.DefaultPermissions)
		}
		if err != nil {
			return nil, goerrors.Errorf("failed to convert custom agent permissions: %w", err)
		}
		permissionsJSON, err := json.Marshal(p)
		if err != nil {
			return nil, goerrors.Errorf("failed to marshal custom agent permissions to JSON: %w", err)
		}
		envVars["COPILOT_AGENT_PERMISSIONS"] = string(permissionsJSON)
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
		"Validate runner OS",
		"Validate firewall settings (Linux)",
		"Validate firewall settings (Windows)",
		"Start downloading Playwright MCP server in the background (Linux)",
		"Start downloading Playwright MCP server in the background (Windows)",
		"Prepare Copilot (Linux)",
		"Prepare Copilot (Windows)",
		"Start MCP Servers (Linux)",
		"Start MCP Servers (Windows)",
		"Processing Request (Linux)",
		"Processing Request (Windows)",
		"Clean Up (Linux)",
		"Clean Up (Windows)",
		"[Optional] Archive Details",
	}
}

// ActionsWorkflowNotSupportedStepsWithErrorMessage returns a map of known unsupported steps.
func ActionsWorkflowNotSupportedStepsWithErrorMessage() map[string]string {
	return map[string]string{
		"Validate runner OS":                   "The `runs-on` setting in your `copilot-setup-steps.yml` file points to a GitHub Actions runner with an unsupported operating system. Only Linux and Windows runners are supported. For more information, see https://gh.io/cca-runner-os.",
		"Validate firewall settings (Linux)":   "The agent firewall is enabled, but firewall is not supported for self-hosted runners. You must disable the agent firewall in the repository's settings to use self-hosted runners. For more information, see https://gh.io/cca-self-hosted-disable-firewall.",
		"Validate firewall settings (Windows)": "The agent firewall is enabled, but firewall is not supported on Windows runners. You must disable the agent firewall in the repository's settings to use Windows runners. For more information, see https://gh.io/cca-disable-firewall.",
	}
}
