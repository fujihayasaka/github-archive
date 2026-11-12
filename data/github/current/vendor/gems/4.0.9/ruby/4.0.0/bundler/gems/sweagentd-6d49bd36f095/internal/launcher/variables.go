package launcher

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"maps"
	"reflect"
	"strconv"
	"strings"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/github/sweagentd/internal/traceparent"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

// NOTE: When updating, be sure to add any secrets or environment variable values
// that should be filtered out in /runtime/src/tools/bash.ts

// Variables is a map of variable names to their values and metadata.
type Variables map[string]struct {
	Value    string
	Secure   bool
	Required bool
}

// AgentLauncherOpts are the options that are common to all launchers.
type AgentLauncherOpts struct {
	CopilotAPIURL                        string
	AgentCallbackURL                     string
	GitHubMCPURLOverride                 string // For development to allow the GitHub MCP url to vary when not running CAPI
	GitHubCopilotAPIToken                string
	UploadsURL                           string
	RuntimeSHA                           string // The SHA used to build the runtime version tag
	RuntimeSubmoduleSHA                  string // The git SHA of the runtime submodule at build time
	DownloadsURL                         string
	SecretScanningURL                    string
	ModelOverride                        string
	AgentFirewallEnabledDefault          bool   // Indicates whether or not the firewall is enabled by default
	AgentFirewallRuleSetAllowListDefault string // gzip'd base64 set of firewall rule files see ./internal/config/default_network_rules
	AgentFirewallRequiredAllowList       string // comma-separated list of domains or URIs that are required for the agent to function
	// Flags that dictate debug or development behavior
	AgentDebug               bool
	Environment              string
	IsDevelopmentEnvironment bool
	IsProximaEnvironment     bool
	IsStagingEnvironment     bool
	MCPEnabled               bool
	OnlineEvaluationDisabled bool
	// How long until the runtime should be terminated due to timeout. It is currently up to the launcher to
	// determine how to accomplish the termination. The runtime will not terminate itself.
	AgentTimeoutMin int
	// TraceParentPropagator provides signed trace context for distributed tracing.
	// If nil, no trace context is added to launched agents.
	TraceParentPropagator traceparent.Propagator
}

// RuntimeVersion returns the runtime version tag.
// When useAppSpecific is true, returns app-specific format: runtime-{app}-{sha}
// When useAppSpecific is false, returns default format: runtime-{sha}
// Returns "latest" if SHA is empty (development mode).
func RuntimeVersion(sha, appSlug string, useAppSpecific bool) string {
	if sha == "" {
		return "latest"
	}
	if useAppSpecific {
		return fmt.Sprintf("runtime-%s-%s", appSlug, sha)
	}
	return fmt.Sprintf("runtime-%s", sha)
}

// addAgentVariables adds the Copilot Agent environment variables required by all launchers.
func addAgentVariables(ctx context.Context, ffClient featureflags.Client, vars *Variables, launchOpts *AgentLauncherOpts, opts *LaunchAgentOpts) {
	problemStatementBase64 := base64.StdEncoding.EncodeToString([]byte(opts.ProblemStatement))
	// Use model override if set, otherwise use opts.Model
	model := opts.Model
	if launchOpts.ModelOverride != "" {
		model = launchOpts.ModelOverride
	}

	// Check feature flag for app-specific runtime version format (actor-level only)
	useAppSpecific := ffClient != nil && ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentUseReleaseAssets, opts.ActorID)
	runtimeReleaseSlug := opts.Agent.EngineSlug()
	if useAppSpecific {
		runtimeReleaseSlug = selectRuntime(ctx, ffClient, opts).releaseSlug
	}

	maps.Copy(*vars, Variables{
		// Copilot Agent environment variables. We use a prefix to avoid conflicts
		// with compute sandbox environment variables, but don't use the GITHUB_
		// prefix to avoid conflicts Actions, Codespaces, local, etc.

		// COPILOT_AGENT is a stable, long-term identifier that signals the process is
		// running inside a Copilot Coding Agent (CCA) context. It is always set to
		// "true" and must never be removed or changed. Downstream consumers (e.g. tsc,
		// third-party tools) rely on it to detect CCA environments and adjust runtime
		// behavior (such as customizing error messages). Backward-compatibility is
		// guaranteed: the variable will continue to be set for the lifetime of CCA.
		"COPILOT_AGENT":                      {Value: "true"},
		"COPILOT_AGENT_ACTION":               {Value: opts.Action, Required: true},
		"COPILOT_AGENT_ACTOR":                {Value: opts.ActorLogin},
		"COPILOT_AGENT_ACTOR_ID":             {Value: strconv.FormatInt(opts.ActorID, 10)},
		"COPILOT_AGENT_ACTOR_TYPE":           {Value: opts.ActorType},
		"COPILOT_AGENT_RUNTIME_VERSION":      {Value: RuntimeVersion(launchOpts.RuntimeSHA, runtimeReleaseSlug, useAppSpecific), Required: true},
		"COPILOT_AGENT_RUNTIME_SHA":          {Value: launchOpts.RuntimeSubmoduleSHA},
		"COPILOT_AGENT_BASE_COMMIT":          {Value: opts.GitHubBaseCommit, Required: true}, // is COPILOT_AGENT_BASE_REF better?
		"COPILOT_AGENT_BRANCH_NAME":          {Value: opts.BranchName},
		"COPILOT_AGENT_CALLBACK_URL":         {Value: launchOpts.AgentCallbackURL, Required: true},
		"COPILOT_AGENT_COMMIT_LOGIN":         {Value: opts.Agent.CommitLogin(), Required: true},
		"COPILOT_AGENT_COMMIT_EMAIL":         {Value: opts.Agent.CommitEmail(), Required: true},
		"COPILOT_AGENT_ISSUE_NUMBER":         {Value: strconv.Itoa(opts.IssueNumber), Required: true},
		"COPILOT_AGENT_JOB_ID":               {Value: opts.JobID, Required: true},
		"COPILOT_AGENT_MODEL":                {Value: model},
		"COPILOT_AGENT_PROMPT":               {Value: problemStatementBase64, Required: true},
		"GITHUB_UPLOADS_URL":                 {Value: launchOpts.UploadsURL, Required: true},
		"GITHUB_DOWNLOADS_URL":               {Value: launchOpts.DownloadsURL, Required: true},
		"SECRET_SCANNING_URL":                {Value: launchOpts.SecretScanningURL, Required: true},
		"COPILOT_AGENT_CONTENT_FILTER_MODE":  {Value: opts.ContentFilterMode},
		"COPILOT_AGENT_PUSH":                 {Value: strconv.FormatBool(opts.Push)},
		"COPILOT_AGENT_PR_COMMIT_COUNT":      {Value: strconv.Itoa(opts.CommitCount)},
		"COPILOT_AGENT_SESSION_ID":           {Value: opts.SessionID},
		"COPILOT_AGENT_PREVIOUS_SESSION_IDS": {Value: strings.Join(opts.PreviousSessionIDs, ",")},
		"COPILOT_AGENT_RESUME_SESSION_ID":    {Value: opts.ResumeSessionID},
		"COPILOT_API_URL":                    {Value: launchOpts.CopilotAPIURL, Required: true},
		"COPILOT_USE_SESSIONS":               {Value: strconv.FormatBool(opts.UseSessions)},
		"COPILOT_USE_ASYNC_SESSIONS":         {Value: strconv.FormatBool(opts.UseAsyncSessions)},
		"COPILOT_MCP_ENABLED":                {Value: strconv.FormatBool(launchOpts.MCPEnabled)}, // TODO: move this out of addAgentVariables
		"COPILOT_JOB_NONCE":                  {Value: opts.Nonce, Required: true, Secure: true},  // Adding nonce to be used in callbacks
		"COPILOT_JOB_EVENT_TYPE":             {Value: opts.JobEventType, Required: false},
		"COPILOT_SNIPPY_BLOCKING_MODE":       {Value: snippyBlockingModeToString(opts.SnippyBlockingMode)},
		"COPILOT_AGENT_SIGN_COMMITS":         {Value: strconv.FormatBool(opts.SignCommits)},
		"GITHUB_VERIFICATION_TOKEN":          {Value: opts.Nonce, Secure: true},   // Needed for the gh-gpgsign to send to the signing endpoint for commit signing verification
		"GITHUB_TOKEN_VARNAME":               {Value: "GITHUB_COPILOT_API_TOKEN"}, // This is the name of the token used for auth in the signing endpoint
	})

	// Only pass validation tool settings when the feature flag is enabled.
	if ffClient != nil && ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentValidationToolSettings, opts.ActorID) {
		maps.Copy(*vars, Variables{
			"COPILOT_AGENT_USE_CODEQL":          {Value: strconv.FormatBool(opts.UseCodeQL)},
			"COPILOT_AGENT_USE_CCR":             {Value: strconv.FormatBool(opts.UseCCR)},
			"COPILOT_AGENT_USE_SECRET_SCANNING": {Value: strconv.FormatBool(opts.UseSecretScanning)},
			"COPILOT_AGENT_USE_DEPENDENCY_VULN": {Value: strconv.FormatBool(opts.UseDependencyVulnCheck)},
		})
	}
}

// snippyBlockingModeToString converts the SnippyBlockingMode enum to a string value
// that can be passed as an environment variable to copilot-agent-runtime.
//
// This passes only the Copilot policy state (allowed/blocked). The runtime owns
// the behavioral decision (soft vs hard blocking) via feature flags.
func snippyBlockingModeToString(mode sweagentdTwirp.SnippyBlockingMode) string {
	switch mode {
	case sweagentdTwirp.SnippyBlockingMode_SNIPPY_BLOCKING_MODE_ALLOWED:
		return "allowed"
	default:
		// BLOCKED, INVALID, or unknown: fail-safe to blocked
		return "blocked"
	}
}

// ExternalLauncherOpts are the options that are common to all container launchers
// including Azure and Docker (outside of GitHub Actions).
type ExternalLauncherOpts struct {
	AgentLauncherOpts

	// Actions should use the automatically set GITHUB_SERVER_URL
	GitHubServerURL string
	// CAPI Auth
	CAPIHMACKey          string
	CopilotIntegrationID string
}

// addGitHubVariables returns the GitHub environment variables required by launchers running outside of GitHub.
func addGitHubVariables(_ context.Context, _ featureflags.Client, vars *Variables, extOpts *ExternalLauncherOpts, opts *LaunchAgentOpts) {
	maps.Copy(*vars, Variables{
		// GitHub Actions default environment variables. We set these to mimic
		// Actions compute to standardize the agent environment across computes.
		"GITHUB_REPOSITORY":          {Value: opts.GitHubRepo},
		"GITHUB_REPOSITORY_ID":       {Value: strconv.FormatInt(opts.GitHubRepoID, 10)},
		"GITHUB_REPOSITORY_OWNER":    {Value: opts.GitHubRepoOwner},
		"GITHUB_REPOSITORY_OWNER_ID": {Value: strconv.FormatInt(opts.GitHubRepoOwnerID, 10)},

		// ADDITIONAL_GITHUB_REPOSITORIES is a JSON-encoded array of additional
		// repositories that the agent has access to in a multi-repo job. The
		// primary repository is conveyed via the GITHUB_REPOSITORY* variables
		// above and is not included here.
		"ADDITIONAL_GITHUB_REPOSITORIES": {Value: addAdditionalRepositoryVariables(opts)},

		"GITHUB_SERVER_URL":             {Value: extOpts.GitHubServerURL},
		"GITHUB_TOKEN":                  {Value: opts.GitHubToken, Secure: true},
		"CAPI_HMAC_KEY":                 {Value: extOpts.CAPIHMACKey, Secure: true},
		"GITHUB_COPILOT_INTEGRATION_ID": {Value: extOpts.CopilotIntegrationID, Secure: true}, // must include GITHUB_ prefix
	})
}

// addAdditionalRepositoryVariables serializes the additional repositories on
// the launch options as a JSON array. Returns an empty string when no
// additional repositories are configured so the resulting environment variable
// stays empty (rather than the JSON literal "null") for the default case.
func addAdditionalRepositoryVariables(opts *LaunchAgentOpts) string {
	if opts == nil || len(opts.AdditionalRepositories) == 0 {
		return ""
	}
	b, err := json.Marshal(opts.AdditionalRepositories)
	if err != nil {
		// json.Marshal of a slice of structs with primitive fields cannot fail
		// in practice, but fall back to an empty string if it ever does so we
		// don't propagate a malformed value to the runtime.
		return ""
	}
	return string(b)
}

// AnthropicKeyOpts are a special case where we need to pass the Anthropic API key to the agent.
type AnthropicKeyOpts struct {
	AnthropicAPIKey string
}

func addAnthropicKeyVariables(_ context.Context, _ featureflags.Client, vars *Variables, anthropic *AnthropicKeyOpts, _ *LaunchAgentOpts) {
	maps.Copy(*vars, Variables{"ANTHROPIC_API_KEY": {
		Value: anthropic.AnthropicAPIKey, Secure: true},
	})
}

// GetVariables returns a map of all variables required by a launcher.
func GetVariables(ctx context.Context, ffClient featureflags.Client, launcherOpts any, agentOpts *LaunchAgentOpts, vars *Variables) Variables {
	all := &Variables{}

	launcherOptsValue := reflect.ValueOf(launcherOpts)
	addVars(ctx, ffClient, all, agentOpts, launcherOptsValue, addAgentVariables)
	addVars(ctx, ffClient, all, agentOpts, launcherOptsValue, addGitHubVariables)
	addVars(ctx, ffClient, all, agentOpts, launcherOptsValue, addAnthropicKeyVariables)

	// copy the existing vars last to ensure they take precedence
	if vars != nil {
		maps.Copy(*all, *vars)
	}

	return *all
}

// GetVariablesStrings returns a list of key=value strings for all variables.
func GetVariablesStrings(ctx context.Context, ffClient featureflags.Client, launcherOpts any, agentOpts *LaunchAgentOpts, vars *Variables) []string {
	all := GetVariables(ctx, ffClient, launcherOpts, agentOpts, vars)
	kvs := []string{}
	for k, v := range all {
		kvs = append(kvs, fmt.Sprintf("%s=%s", k, v.Value))
	}
	return kvs
}

type addVarsFunc[T any] func(ctx context.Context, ffClient featureflags.Client, vars *Variables, launchOpts *T, agentOpts *LaunchAgentOpts)

// addVars adds variables to the map based on the type of the launcherOpts.
func addVars[T any](ctx context.Context, ffClient featureflags.Client, vars *Variables, agentOpts *LaunchAgentOpts, launcherOptsValue reflect.Value, f addVarsFunc[T]) {
	optsType := reflect.TypeFor[T]()
	// first check if the obj itself is of the type we care about
	if launcherOptsValue.IsValid() && launcherOptsValue.Type() == optsType {
		if launcherOptsValue.CanAddr() {
			if typedValue, ok := launcherOptsValue.Addr().Interface().(*T); ok {
				f(ctx, ffClient, vars, typedValue, agentOpts)
			}
		} else {
			// Value is not addressable, create an addressable copy
			if typedValue, ok := launcherOptsValue.Interface().(T); ok {
				f(ctx, ffClient, vars, &typedValue, agentOpts)
			}
		}
		return
	}
	// otherwise check if the obj has a field of the type we care about
	launcherOptsField := launcherOptsValue.FieldByName(optsType.Name())
	if launcherOptsField.IsValid() && launcherOptsField.Type() == optsType {
		if launcherOptsField.CanAddr() {
			if typedValue, ok := launcherOptsField.Addr().Interface().(*T); ok {
				f(ctx, ffClient, vars, typedValue, agentOpts)
			}
		} else {
			// Value is not addressable, create an addressable copy
			if typedValue, ok := launcherOptsField.Interface().(T); ok {
				f(ctx, ffClient, vars, &typedValue, agentOpts)
			}
		}
	}
}

func isFirewallEnabledByDefault(ctx context.Context, ffClient featureflags.Client, launcherOpts *AgentLauncherOpts) bool {
	// Check if the firewall "enable by default" feature flag is set if config defaults to false. Long term
	// when we don't need the ff anymore we can just update the config that way and it makes testing easier.
	firewallEnabledDefault := launcherOpts.AgentFirewallEnabledDefault
	if !firewallEnabledDefault {
		firewallEnabledDefault = ffClient.IsEnabled(ctx, copilotSWEAgentFirewallFFName)
	}
	return firewallEnabledDefault
}

// isFirewallDisabled returns true when the agent implements
// AgenticAppFirewallExempt, opts into skipping the firewall, and the
// corresponding feature flag for the specific agent type is enabled. For CCR,
// the targeted enable flag takes precedence over the broad disable flag.
func isFirewallDisabled(ctx context.Context, ffClient featureflags.Client, agent sweagentd.AgenticApp, actors sweagentd.RepositoryWithActor, appProvider *agenticapp.Provider) bool {
	firewallExempt, ok := agent.(sweagentd.AgenticAppFirewallExempt)
	if !ok || !firewallExempt.SkipAgentFirewall() {
		return false
	}
	if appProvider.IsCopilotCodeReviewApp(agent.AppID()) {
		if ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCCREnableFirewall, actors) {
			return false
		}
		return ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCCRDisableFirewall, actors)
	}
	if appProvider.IsCodeScanningApp(agent.AppID()) {
		return ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCodeScanningDisableFirewall, actors)
	}
	return false
}

// disableAgentFirewall overrides workflowData so the rendered workflow runs with
// the agent firewall fully off. Used for agents that implement
// sweagentd.AgenticAppFirewallExempt.
func disableAgentFirewall(data *workflowData) {
	data.UseMaterializedFirewall = true
	data.MaterializedFirewallEnabled = false
	data.MaterializedFirewallUseDefaultRules = false
	data.MaterializedFirewallAllowedRules = ""
	data.AgentFirewallEnabledDefault = false
}

func isOnlineEvaluationDisabled(ctx context.Context, ffClient featureflags.Client, launcherOpts *AgentLauncherOpts, actors sweagentd.RepositoryWithActor) bool {
	// Check if online evaluation is disabled feature flag is set.
	// defaults to false (meaning online evaluation is enabled).
	// Setting the FF to true will disable online evaluation for the agent.
	onlineEvaluationDisabled := launcherOpts.OnlineEvaluationDisabled
	if !onlineEvaluationDisabled {
		onlineEvaluationDisabled = ffClient.IsEnabledForUserOrRepoOrOwner(ctx, copilotSWEAgentOnlineEvalDisabledFFName, actors)
	}
	return onlineEvaluationDisabled
}

// getEngineVariables returns the environment variables needed by an external engine.
// Engines use a standardized set of PLATFORM_* variables instead of COPILOT_AGENT_* variables.
func getEngineVariables(launcherOpts *DockerLauncherOpts, opts *LaunchAgentOpts) []string {
	inferenceToken := launcherOpts.EngineInferenceToken
	if inferenceToken == "" {
		inferenceToken = launcherOpts.GitHubCopilotAPIToken
	}

	return []string{
		fmt.Sprintf("GITHUB_JOB_ID=%s", opts.JobID),
		fmt.Sprintf("GITHUB_PLATFORM_API_TOKEN=%s", launcherOpts.GitHubCopilotAPIToken),
		fmt.Sprintf("GITHUB_PLATFORM_API_URL=%s", launcherOpts.AgentCallbackURL),
		fmt.Sprintf("GITHUB_JOB_NONCE=%s", opts.Nonce),
		fmt.Sprintf("GITHUB_INFERENCE_TOKEN=%s", inferenceToken),
		fmt.Sprintf("GITHUB_GIT_TOKEN=%s", opts.GitHubToken),
	}
}

// validateRequiredVariables checks that all required runtime variables are present in the Variables map.
// Returns an error if any required variable is missing or has an empty value.
func validateRequiredVariables(vars Variables) error {
	var missing []string

	for name, variable := range vars {
		if variable.Required && variable.Value == "" {
			missing = append(missing, name)
		}
	}

	if len(missing) > 0 {
		return goerrors.Errorf("missing required runtime variables: %v", missing)
	}

	return nil
}
