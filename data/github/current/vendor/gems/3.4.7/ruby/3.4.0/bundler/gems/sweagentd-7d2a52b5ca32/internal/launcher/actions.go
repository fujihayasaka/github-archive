package launcher

import (
	"bytes"
	"context"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"html/template"
	"slices"
	"strconv"
	"strings"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/mcp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/proxima"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

const workflowName = "Copilot coding agent"

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
) (*ActionsLauncher, error) {
	return &ActionsLauncher{
		obsv:                obsv,
		ffClient:            ffClient,
		githubClientFactory: githubClientFactory,
		ghTwirp:             ghTwirp,
		spokes:              spokes,
		opts:                opts,
	}, nil
}

// LauncherType returns the type of launcher.
func (a *ActionsLauncher) LauncherType() LauncherType {
	return LauncherTypeActions
}

// LaunchAgent launches an agent using GitHub Actions.
func (a *ActionsLauncher) LaunchAgent(ctx context.Context, opts LaunchAgentOpts) (string, error) {
	ctx, span := a.obsv.Tracer.Start(ctx, "launcher.actions.LaunchAgent")
	defer span.End()

	environment, err := config.ParseEnvironment(a.opts.Environment)
	if err != nil {
		return "", fmt.Errorf("failed to parse environment: %w", err)
	}

	copilotAPIURL, actionDownloadURL, agentCallbackURL, uploadURL, downloadURL, err := a.getURLsForEnvironment(ctx, environment, a.opts.Environment)
	if err != nil {
		return "", fmt.Errorf("failed to generate tenant specific capi urls: %w", err)
	}

	overrides := &variables{
		// Callback URL is passed into the dynamic workflow twice, this could probably be addressed to only use the workflowData.
		"COPILOT_AGENT_CALLBACK_URL": {Value: agentCallbackURL},
		"COPILOT_API_URL":            {Value: copilotAPIURL},
		"GITHUB_UPLOADS_URL":         {Value: uploadURL},
		"GITHUB_DOWNLOADS_URL":       {Value: downloadURL},
	}

	inputs, err := a.environmentVariables(ctx, opts, overrides)
	if err != nil {
		return "", fmt.Errorf("failed to generate environment variables: %w", err)
	}

	if err := validateInputs(inputs); err != nil {
		return "", fmt.Errorf("invalid inputs: %w", err)
	}

	client, err := a.githubClientFactory.NewClientFromRepo(ctx, opts.GitHubRepoID, opts.GitHubRepoOwnerID)
	if err != nil {
		return "", fmt.Errorf("failed to create GitHub client: %w", err)
	}

	secrets, variables, err := client.GetCopilotEnvironmentSecretsAndVariables(ctx, opts.GitHubRepoOwner, opts.GitHubRepoName, opts.GitHubRepoID)
	if err != nil {
		return "", fmt.Errorf("failed to get copilot environment secrets and variables: %w", err)
	}

	a.opts, err = ReplaceFirewallTenantPlaceholders(ctx, a.opts)
	if err != nil {
		return "", fmt.Errorf("failed to replace firewall tenant placeholders: %w", err)
	}

	data := workflowData{
		WorkflowName:                   template.HTML(workflowName),
		RunName:                        template.HTML(GenerateRunName(opts)),
		Secrets:                        secrets,
		Variables:                      variables,
		AgentDebug:                     a.opts.AgentDebug,
		AgentFirewallEnabledDefault:    isFirewallEnabledByDefault(ctx, a.ffClient, a.opts.AgentLauncherOpts),
		AgentFirewallRequiredAllowList: template.HTML(a.opts.AgentFirewallRequiredAllowList),
		AgentCallbackURL:               agentCallbackURL,
		UploadsURL:                     a.opts.UploadsURL,
		JobID:                          opts.JobID,
		IsDevelopmentEnvironment:       a.opts.IsDevelopmentEnvironment,
		Environment:                    a.opts.Environment,
		MCPEnabled:                     a.opts.MCPEnabled,
		MCP3PEnabled:                   true,
		McpRemoteEnabled:               a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "sweagentd_mcp_remote_enabled", &opts),
		MCPVariables:                   []string{},
		MCPSecrets:                     []string{},
		Customization: &map[string]template.HTML{
			"runs-on":         template.HTML(fmt.Sprintf("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || '%s' }}", a.opts.ActionsDefaultRunsOnLabels)),
			"timeout-minutes": template.HTML(fmt.Sprintf("%d", a.opts.AgentTimeoutMin)),
		},
		BlackbirdMode:                 "disabled",
		InjectedSecretNames:           strings.Join(secrets, ","),
		AgentOnlineEvaluationDisabled: "false",
		FeatureFlags: strings.Join(
			getFeatureFlags(a.ffClient, ctx, &opts),
			","),
		Experiments:                 opts.Experiments,
		ExperimentAssignmentContext: opts.ExperimentAssignmentContext,
		PlaywrightVersion:           playwrightVersion,
	}

	switch environment {
	case config.EnvironmentStaging:
		fallthrough
	case config.EnvironmentProxima:
		data.ActionDownloadURL = actionDownloadURL
	}

	data.AgentFirewallRuleSetAllowListDefault = template.HTML(a.opts.AgentFirewallRuleSetAllowListDefault)

	inputs[mcp.ServerConfigEnvVar], inputs[mcp.InteractionIDEnvVar], err = a.applyMCPSettings(ctx, &data, opts)
	if err != nil {
		return "", fmt.Errorf("failed to apply MCP settings: %w", err)
	}

	if isOnlineEvaluationDisabled(ctx, a.ffClient, a.opts.AgentLauncherOpts, &opts) {
		data.AgentOnlineEvaluationDisabled = "true"
	}

	// Try to find a user Actions workflow steps file at ".github/workflows/copilot-setup-steps.yml/yaml" for the
	// repo and branch and then process it. Only the permissions, runs-on, and steps from the copilot-setup-steps job are used.
	customization, err := a.applySetupSteps(ctx, client, opts, data)
	if err != nil {
		// If the setup steps file is not found, or there is an error processing
		// it, we create a comment on the PR to inform the user, but we do not fail
		// the workflow run.
		a.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("failed to apply setup steps")
	} else if customization != nil {
		data.Customization = customization
	}

	// Apply runtime setup and entry point
	a.applyRuntimeSetup(ctx, opts.ActorID, &data)

	// Use template to create workflow yaml
	workflowContent, err := a.workflowContent(data, workflowTemplate)
	if err != nil {
		return "", fmt.Errorf("failed to generate workflow content: %w", err)
	}

	workflow := &github.NewDynamicWorkflowRun{
		Ref:           gg.Ptr(opts.BranchName),
		Slug:          gg.Ptr("copilot"),
		WorkflowName:  gg.Ptr(workflowName),
		Workflow:      gg.Ptr(workflowContent),
		Inputs:        gg.Ptr(inputs),
		PreventReruns: true,
	}

	run, err := client.CreateDynamicWorkflowRun(ctx, opts.GitHubRepoOwner, opts.GitHubRepoName, opts.GitHubRepoID, workflow)
	tags := a.obsv.TelemetryTags(ctx).Merge(stats.Tags{"success": strconv.FormatBool(err == nil)})
	a.obsv.Statter.Counter("dynamic_workflow_creation", tags, 1)

	if err != nil {
		return "", fmt.Errorf("failed to create dynamic workflow run: %w", err)
	}

	if run.WorkflowRunID == nil {
		return "", errors.New("dynamic workflow run ID is nil, this should not happen")
	}

	_ = requestctx.AddWorkflowRun(ctx, &requestctx.CtxWorkflowRun{ID: *run.WorkflowRunID})
	a.obsv.LoggerWithTelemetry(ctx).Info("Created dynamic workflow run")

	return strconv.FormatInt(*run.WorkflowRunID, 10), nil
}

// ReplaceFirewallTenantPlaceholders replaces tenant placeholders in firewall settings.
func ReplaceFirewallTenantPlaceholders(ctx context.Context, opts ActionsLauncherOpts) (ActionsLauncherOpts, error) {
	var err error
	opts.AgentFirewallRequiredAllowList, err = proxima.ReplaceTenantPlaceholder(ctx, opts.AgentFirewallRequiredAllowList)
	if err != nil {
		return opts, fmt.Errorf("failed to replace tenant placeholder in agent firewall required allow list: %w", err)
	}
	return opts, nil
}

// TerminateAgent terminates an agent by cancelling the corresponding GitHub Actions workflow run.
func (a *ActionsLauncher) TerminateAgent(ctx context.Context, opts TerminateAgentOpts) error {
	ctx, span := a.obsv.Tracer.Start(ctx, "launcher.actions.TerminateAgent")
	defer span.End()

	runID, err := strconv.ParseInt(opts.ComputeID, 10, 64)
	if err != nil {
		return fmt.Errorf("failed to parse compute ID for running job: %w", err)
	}

	if opts.Client == nil {
		client, err := a.githubClientFactory.NewClientFromRepo(ctx, opts.RepoID, opts.OwnerID)
		if err != nil {
			return fmt.Errorf("failed to create GitHub client: %w", err)
		}
		opts.Client = client
	}

	err = opts.Client.CancelWorkflowRunByID(ctx, opts.RepoOwner, opts.RepoName, runID)
	return err
}

func (a *ActionsLauncher) applyRuntimeSetup(ctx context.Context, actorID int64, d *workflowData) {
	if a.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentRuntimeEntryPointClaude, actorID) {
		d.RuntimeEntryPoint = "dist-claude/index.js"
		return
	}

	if a.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentRuntimeEntryPointCodex, actorID) {
		d.RuntimeEntryPoint = "dist-codex/index.js"
		d.RuntimeSetup = "npm install -g @openai/codex"
		return
	}

	d.RuntimeEntryPoint = "dist/index.js"
}

func (a *ActionsLauncher) applyMCPSettings(ctx context.Context, data *workflowData, opts LaunchAgentOpts) (string, string, error) {
	if a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "sweagentd_mcp_disable", &opts) {
		// This is a FF used to meet a ProdSec requirement that we have a mechanism to disable MCP entirely for specific actors
		data.MCPEnabled = false
		return "", opts.SessionID, nil
	}

	// Determine the blackbird mode
	if a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "sweagentd_blackbird_initial_search", &opts) {
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
		return "", opts.SessionID, fmt.Errorf("failed to configure MCP: %w", err)
	}
	data.MCP3PEnabled = resp.Enabled
	return resp.Encoded, opts.SessionID, nil
}

// getURLsForEnvironment returns the action download URL and agent callback URL for the given environment
func (a *ActionsLauncher) getURLsForEnvironment(ctx context.Context, environment config.Environment, environmentName string) (copilotAPIURL, actionDownloadURL, agentCallbackURL, uploadURL, downloadURL string, err error) {
	copilotAPIURL = a.opts.CopilotAPIURL

	switch environment {
	case config.EnvironmentStaging:
		actionDownloadURL = a.opts.CopilotAPIURL + fmt.Sprintf("/agents/swe-%s/runtime", environmentName)
		agentCallbackURL = a.opts.AgentCallbackURL
		uploadURL = a.opts.UploadsURL
		downloadURL = a.opts.DownloadsURL
	case config.EnvironmentProxima:
		copilotAPIURL, err = proxima.ReplaceTenantPlaceholder(ctx, copilotAPIURL)
		if err != nil {
			return "", "", "", "", "", fmt.Errorf("failed to replace tenant placeholder in copilot API URL: %w", err)
		}

		actionDownloadURL = copilotAPIURL + "/agents/swe/runtime"
		agentCallbackURL, err = proxima.ReplaceTenantPlaceholder(ctx, a.opts.AgentCallbackURL)
		if err != nil {
			return "", "", "", "", "", fmt.Errorf("failed to replace tenant placeholder in agent callback URL: %w", err)
		}
		uploadURL, err = proxima.ReplaceTenantPlaceholder(ctx, a.opts.UploadsURL)
		if err != nil {
			return "", "", "", "", "", fmt.Errorf("failed to replace tenant placeholder in upload URL: %w", err)
		}
		downloadURL, err = proxima.ReplaceTenantPlaceholder(ctx, a.opts.DownloadsURL)
		if err != nil {
			return "", "", "", "", "", fmt.Errorf("failed to replace tenant placeholder in downloads URL: %w", err)
		}
	default:
		agentCallbackURL = a.opts.AgentCallbackURL
		uploadURL = a.opts.UploadsURL
		downloadURL = a.opts.DownloadsURL
	}

	return copilotAPIURL, actionDownloadURL, agentCallbackURL, uploadURL, downloadURL, nil
}

//go:embed actions_workflow.yaml
var workflowTemplate string

type workflowData struct {
	WorkflowName                         template.HTML
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
	ActionDownloadURL                    string                    // Used to bootstrap the runtime from sweagentd itself
	RuntimeVersion                       string                    // Used to pin the runtime version
	Customization                        *map[string]template.HTML // Don't want to escape this since we need to use ""
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
		return fmt.Errorf("number of inputs: %d exceeds maximum: %d", len(inputs), ActionsInputNumberLimit)
	}
	inputsJson, err := json.Marshal(inputs)
	if err != nil {
		return fmt.Errorf("failed to marshal inputs to JSON: %w", err)
	}
	if len(inputsJson) > ActionsInputJSONLengthLimit {
		return fmt.Errorf("length of inputs JSON: %d exceeds maximum: %d", len(inputsJson), ActionsInputJSONLengthLimit)
	}
	return nil
}

func (a *ActionsLauncher) workflowContent(data workflowData, workflowTmpl string) (string, error) {
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
		extractMCPVars(&data)
	}

	tmpl, err := template.New("workflow").Delims("<<", ">>").Parse(workflowTmpl)
	if err != nil {
		return "", fmt.Errorf("failed to parse workflow template: %w", err)
	}

	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, data); err != nil {
		return "", fmt.Errorf("failed to execute workflow template: %w", err)
	}
	return buf.String(), nil
}

func (a *ActionsLauncher) environmentVariables(ctx context.Context, opts LaunchAgentOpts, overrides *variables) (map[string]string, error) {
	gzip := a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentGZipProblemStatement, &opts)
	all := GetVariables(a.opts, opts, overrides, gzip)

	// Check if required runtime variables are present
	if a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentValidateRuntimeVariables, &opts) {
		if err := validateRequiredVariables(all); err != nil {
			return nil, fmt.Errorf("required runtime variables validation failed: %w", err)
		}
	}

	inputs := map[string]string{}
	for k, v := range all {
		inputs[k] = v.Value
	}
	// Actions limits us to 10 inputs, so we serialize the inputs to a JSON string
	// and pass them as the value to a single COPILOT_AGENT_INPUTS input.
	inputsJson, err := json.Marshal(inputs)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal inputs to JSON: %w", err)
	}

	envVars := map[string]string{
		"COPILOT_AGENT_INPUTS": string(inputsJson),
		// When we send a dynamic workflow to Actions, the Actions service calls back
		// into dotcom to get secrets (e.g. the CAPI u2s token). We use the actor ID to
		// to associate agent job with a user. This logic requires COPILOT_AGENT_ACTOR_ID
		// to be a top-level input, so we pass it here as well.
		"COPILOT_AGENT_ACTOR_ID": inputs["COPILOT_AGENT_ACTOR_ID"],
	}

	if a.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentSafeRuntimeDeploy, &opts) {
		a.obsv.LoggerWithTelemetry(ctx).Info(fmt.Sprintf("Using runtime version: %s\n", a.opts.RuntimeVersion))
		envVars["COPILOT_AGENT_RUNTIME_VERSION"] = inputs["COPILOT_AGENT_RUNTIME_VERSION"]
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
func GenerateRunName(opts LaunchAgentOpts) string {
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
	return "Running Copilot"
}

// ActionsWorkflowJobKnownSteps returns the known steps in the dynamic workflow job.
// This is used to determine if a failed step is part of the core workflow or
// a custom step defined by the user (copilot-setup-steps.yml).
func ActionsWorkflowJobKnownSteps() []string {
	return []string{
		"Validate runner OS",
		"Validate firewall settings",
		"Start downloading Playwright MCP server in the background",
		"Prepare Copilot",
		"Start MCP Servers",
		"Processing Request",
		"Clean Up",
		"Save Data",
		"[Optional] Archive Details",
	}
}

// ActionsWorkflowNotSupportedStepsWithErrorMessage returns a map of known unsupported steps.
func ActionsWorkflowNotSupportedStepsWithErrorMessage() map[string]string {
	return map[string]string{
		"Validate runner OS":         "The `runs-on` setting in your `copilot-setup-steps.yml` file points to a GitHub Actions runner with an unsupported operating system. Only Linux runners are supported. For more information, see https://gh.io/cca-runner-os.",
		"Validate firewall settings": "You have configured Copilot coding agent to use self-hosted GitHub Actions runners in `copilot-setup-steps.yml`, but the agent firewall is enabled. You must disable the agent firewall in the repository's settings to use self-hosted runners. For more information, see https://gh.io/cca-self-hosted-disable-firewall.",
	}
}
