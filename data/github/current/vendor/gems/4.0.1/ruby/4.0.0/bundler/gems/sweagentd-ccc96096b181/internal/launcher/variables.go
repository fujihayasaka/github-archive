package launcher

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/base64"
	"fmt"
	"maps"
	"reflect"
	"strconv"
	"strings"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/github/sweagentd/internal/traceparent"
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
	GitHubCopilotAPIToken                string
	UploadsURL                           string
	RuntimeSHA                           string // The SHA used to build the runtime version tag
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
func addAgentVariables(ctx context.Context, ffClient featureflags.Client, vars *Variables, launchOpts *AgentLauncherOpts, opts *LaunchAgentOpts, gzip bool) {
	var problemStatementBase64 string
	if gzip {
		// If we hit an error, we'll fall back to straight base64 encoding instead
		problemStatementBase64, _ = gzipAndBase64Encode(opts.ProblemStatement)
	}
	// If gzipping fails or is not enabled, just do base64 encoding
	if problemStatementBase64 == "" {
		problemStatementBase64 = base64.StdEncoding.EncodeToString([]byte(opts.ProblemStatement))
	}

	// Use model override if set, otherwise use opts.Model
	model := opts.Model
	if launchOpts.ModelOverride != "" {
		model = launchOpts.ModelOverride
	}

	// Check feature flag for app-specific runtime version format (actor-level only)
	useAppSpecific := ffClient != nil && ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentUseReleaseAssets, opts.ActorID)

	maps.Copy(*vars, Variables{
		// Copilot Agent environment variables. We use a prefix to avoid conflicts
		// with compute sandbox environment variables, but don't use the GITHUB_
		// prefix to avoid conflicts Actions, Codespaces, local, etc.
		"COPILOT_AGENT_ACTION":               {Value: opts.Action, Required: true},
		"COPILOT_AGENT_ACTOR":                {Value: opts.ActorLogin},
		"COPILOT_AGENT_ACTOR_ID":             {Value: strconv.FormatInt(opts.ActorID, 10)},
		"COPILOT_AGENT_RUNTIME_VERSION":      {Value: RuntimeVersion(launchOpts.RuntimeSHA, opts.Agent.ComputeSlug(), useAppSpecific), Required: true},
		"COPILOT_AGENT_BASE_COMMIT":          {Value: opts.GitHubBaseCommit, Required: true}, // is COPILOT_AGENT_BASE_REF better?
		"COPILOT_AGENT_BRANCH_NAME":          {Value: opts.BranchName, Required: true},       // is COPILOT_AGENT_HEAD_REF better?
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
		"COPILOT_API_URL":                    {Value: launchOpts.CopilotAPIURL, Required: true},
		"COPILOT_USE_SESSIONS":               {Value: strconv.FormatBool(opts.UseSessions)},
		"COPILOT_USE_ASYNC_SESSIONS":         {Value: strconv.FormatBool(opts.UseAsyncSessions)},
		"COPILOT_MCP_ENABLED":                {Value: strconv.FormatBool(launchOpts.MCPEnabled)}, // TODO: move this out of addAgentVariables
		"COPILOT_JOB_NONCE":                  {Value: opts.Nonce, Required: true},                // Adding nonce to be used in callbacks
		"COPILOT_JOB_EVENT_TYPE":             {Value: opts.JobEventType, Required: false},
	})
}

func gzipAndBase64Encode(input string) (string, error) {
	var buf bytes.Buffer
	gzipWriter := gzip.NewWriter(&buf)
	_, err := gzipWriter.Write([]byte(input))
	if err != nil {
		return "", goerrors.Errorf("failed to gzip input: %w", err)
	}
	err = gzipWriter.Close()
	if err != nil {
		return "", goerrors.Errorf("failed to close gzip writer: %w", err)
	}
	// Base64 encode the gzipped content
	encoded := base64.StdEncoding.EncodeToString(buf.Bytes())
	return fmt.Sprintf("gz:%s", encoded), nil
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
func addGitHubVariables(_ context.Context, _ featureflags.Client, vars *Variables, extOpts *ExternalLauncherOpts, opts *LaunchAgentOpts, _ bool) {
	maps.Copy(*vars, Variables{
		// GitHub Actions default environment variables. We set these to mimic
		// Actions compute to standardize the agent environment across computes.
		"GITHUB_REPOSITORY":          {Value: opts.GitHubRepo},
		"GITHUB_REPOSITORY_ID":       {Value: strconv.FormatInt(opts.GitHubRepoID, 10)},
		"GITHUB_REPOSITORY_OWNER":    {Value: opts.GitHubRepoOwner},
		"GITHUB_REPOSITORY_OWNER_ID": {Value: strconv.FormatInt(opts.GitHubRepoOwnerID, 10)},

		"GITHUB_SERVER_URL":             {Value: extOpts.GitHubServerURL},
		"GITHUB_TOKEN":                  {Value: opts.GitHubToken, Secure: true},
		"CAPI_HMAC_KEY":                 {Value: extOpts.CAPIHMACKey, Secure: true},
		"GITHUB_COPILOT_INTEGRATION_ID": {Value: extOpts.CopilotIntegrationID, Secure: true}, // must include GITHUB_ prefix
	})
}

// AnthropicKeyOpts are a special case where we need to pass the Anthropic API key to the agent.
type AnthropicKeyOpts struct {
	AnthropicAPIKey string
}

func addAnthropicKeyVariables(_ context.Context, _ featureflags.Client, vars *Variables, anthropic *AnthropicKeyOpts, _ *LaunchAgentOpts, _ bool) {
	maps.Copy(*vars, Variables{"ANTHROPIC_API_KEY": {
		Value: anthropic.AnthropicAPIKey, Secure: true},
	})
}

// GetVariables returns a map of all variables required by a launcher.
func GetVariables(ctx context.Context, ffClient featureflags.Client, launcherOpts any, agentOpts *LaunchAgentOpts, vars *Variables, gzip bool) Variables {
	all := &Variables{}

	launcherOptsValue := reflect.ValueOf(launcherOpts)
	addVars(ctx, ffClient, all, agentOpts, launcherOptsValue, gzip, addAgentVariables)
	addVars(ctx, ffClient, all, agentOpts, launcherOptsValue, gzip, addGitHubVariables)
	addVars(ctx, ffClient, all, agentOpts, launcherOptsValue, gzip, addAnthropicKeyVariables)

	// copy the existing vars last to ensure they take precedence
	if vars != nil {
		maps.Copy(*all, *vars)
	}

	return *all
}

// GetVariablesStrings returns a list of key=value strings for all variables.
func GetVariablesStrings(ctx context.Context, ffClient featureflags.Client, launcherOpts any, agentOpts *LaunchAgentOpts, vars *Variables, gzip bool) []string {
	all := GetVariables(ctx, ffClient, launcherOpts, agentOpts, vars, gzip)
	kvs := []string{}
	for k, v := range all {
		kvs = append(kvs, fmt.Sprintf("%s=%s", k, v.Value))
	}
	return kvs
}

type addVarsFunc[T any] func(ctx context.Context, ffClient featureflags.Client, vars *Variables, launchOpts *T, agentOpts *LaunchAgentOpts, gzip bool)

// addVars adds variables to the map based on the type of the launcherOpts.
func addVars[T any](ctx context.Context, ffClient featureflags.Client, vars *Variables, agentOpts *LaunchAgentOpts, launcherOptsValue reflect.Value, gzip bool, f addVarsFunc[T]) {
	optsType := reflect.TypeFor[T]()
	// first check if the obj itself is of the type we care about
	if launcherOptsValue.IsValid() && launcherOptsValue.Type() == optsType {
		if launcherOptsValue.CanAddr() {
			if typedValue, ok := launcherOptsValue.Addr().Interface().(*T); ok {
				f(ctx, ffClient, vars, typedValue, agentOpts, gzip)
			}
		} else {
			// Value is not addressable, create an addressable copy
			if typedValue, ok := launcherOptsValue.Interface().(T); ok {
				f(ctx, ffClient, vars, &typedValue, agentOpts, gzip)
			}
		}
		return
	}
	// otherwise check if the obj has a field of the type we care about
	launcherOptsField := launcherOptsValue.FieldByName(optsType.Name())
	if launcherOptsField.IsValid() && launcherOptsField.Type() == optsType {
		if launcherOptsField.CanAddr() {
			if typedValue, ok := launcherOptsField.Addr().Interface().(*T); ok {
				f(ctx, ffClient, vars, typedValue, agentOpts, gzip)
			}
		} else {
			// Value is not addressable, create an addressable copy
			if typedValue, ok := launcherOptsField.Interface().(T); ok {
				f(ctx, ffClient, vars, &typedValue, agentOpts, gzip)
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
