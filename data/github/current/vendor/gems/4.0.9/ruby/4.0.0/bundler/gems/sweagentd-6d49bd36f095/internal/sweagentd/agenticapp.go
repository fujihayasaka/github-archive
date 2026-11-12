package sweagentd

const (
	// ModelVendorAnthropic is the vendor string for Anthropic models.
	ModelVendorAnthropic = "Anthropic"
	// ModelVendorOpenAI is the vendor string for OpenAI models.
	ModelVendorOpenAI = "OpenAI"
	// ModelVendorGoogle is the vendor string for Google models.
	ModelVendorGoogle = "Google"

	// MetadataCAPIIntegrationID is the Metadata key that agentic apps use to
	// declare the integration ID sent via the Copilot-Integration-Id header
	// on CAPI /models requests. When set, this overrides the default
	// integration ID so CAPI can identify the specific agent integration.
	MetadataCAPIIntegrationID = "capi_integration_id"
)

// ComputeEnv represents the compute environment for an agent.
type ComputeEnv interface {
	// SetupAgent prepares the compute environment for the agent.
	// The cmd parameter specifies the command to execute for setting up the agent.
	SetupAgent(cmd string)

	// EntryPoint defines the entry point for the agent in the compute environment.
	// The cmd parameter represents the path or command to the entry point to be executed.
	EntryPoint(cmd string)
}

// AgentSource represents the source code information for an agent.
type AgentSource struct {
	URL string // repository URL for the agent source code, e.g. a GitHub repo URL
	SHA string // the specific commit SHA that the agent source code is pinned to
}

// AgenticApp represents a GitHub App that manages an agent.
//
//nolint:interfacebloat // agents get bloated sometimes
type AgenticApp interface {
	AppID() int64
	AppName() string
	BranchPrefix() string
	BotID() int64
	BotLogin() string
	CommitLogin() string
	CommitEmail() string
	MentionableSlug() string
	ComputeSlug() string

	// EngineSlug returns the slug used to resolve the runtime/engine artifact.
	// Most apps return ComputeSlug(); apps that share a runtime with another
	// app (e.g. CodeScanning shares the autofind runtime with CopilotCodeReview)
	// override this to return the slug of the app whose artifact is published.
	EngineSlug() string

	HasSource() bool
	SourceURL() string
	AgentSource() *AgentSource

	// IsGlobalApp, IsPartnerApp, and IsThirdPartyApp are mutually exclusive.
	// Exactly one must return true for any implementation.

	// IsGlobalApp returns true if the app is a global app i.e Copilot, CopilotCodeReview, or CodeScanning.
	IsGlobalApp() bool
	// IsPartnerApp returns true if the app is a partner app i.e Codex, Claude.
	IsPartnerApp() bool
	// IsThirdPartyApp returns true if the app is a regular third-party app.
	IsThirdPartyApp() bool

	// ModelVendors returns the vendor names used for model filtering in normal
	// request flows.
	// Third-party agents typically return their vendors (e.g., ["Anthropic"],
	// ["OpenAI"], or ["Anthropic", "OpenAI"]) so that model selection is
	// limited to models from those vendors.
	// Copilot returns an empty slice to allow all supported models and
	// override vendor filtering where appropriate.
	ModelVendors() []string

	// Metadata returns app-specific key-value metadata that is surfaced to the
	// runtime via the GET /agent/jobs/{jobID} endpoint. First-party apps may
	// use this to pass operational configuration (e.g. a per-app CAPI
	// integration ID) without changing the core interface.
	Metadata() map[string]string

	SetupCompute(compute ComputeEnv)

	// WorkflowRunName will set the name of the Workflow Run in Actions, to override the default name.
	// prNumber is the pull request number associated with the job, or 0 if none.
	WorkflowRunName(prNumber int) string

	// IsQuotaExempt returns true if this app is exempt from license and quota
	// checks. Apps with their own billing model (e.g., Code Scanning) return
	// true so that sweagentd does not enforce Copilot premium quota on them.
	IsQuotaExempt() bool

	// UsesExperiments returns true if this app participates in the experiments
	// framework (i.e., experiment assignments should be looked up for its jobs).
	// Apps like Code Review and Code Scanning that have no applicable experiments
	// return false to avoid noisy log messages from missing assignments.
	UsesExperiments() bool
}

// AgenticAppModelPassthrough is an optional interface that AgenticApp implementations can
// satisfy to indicate they manage their own model selection externally.
// When SkipModelValidation returns true, DetermineModel will pass the requested
// model string through without querying CAPI or validating against the user's
// available models.
type AgenticAppModelPassthrough interface {
	SkipModelValidation() bool
}

// AgenticAppReviewerAssignment is an optional interface that AgenticApp
// implementations can satisfy to control whether sweagentd assigns the
// triggering actor as a PR reviewer when a job completes.
//
// By default (when this interface is not implemented), sweagentd adds the actor
// as a PR reviewer. Apps like Copilot Code Review should return false because
// the actor requests a Copilot review of someone else's PR and should not be
// assigned as a human reviewer.
type AgenticAppReviewerAssignment interface {
	AssignActorAsReviewer() bool
}

// AgenticAppBranchlessMode is an optional interface that AgenticApp
// implementations can satisfy to indicate the app never needs sweagentd to
// create branches or pull requests.
//
// Apps like Copilot Code Review operate on an existing PR: the caller provides
// HeadRef/BaseRef so the workflow checks out the right branch, but sweagentd
// should not create a new branch or open a new PR.
type AgenticAppBranchlessMode interface {
	SkipBranchAndPRCreation() bool
}

// AgenticAppSkipPRCloseCancel is an optional interface that AgenticApp
// implementations can satisfy to opt out of the automatic job cancellation
// that fires when the source pull request is closed or merged.
//
// By default, sweagentd cancels every running job for a PR when the PR
// transitions to closed/merged (see internal/events/on_pull_request_state_change.go).
// Apps like Copilot Code Review prefer to let the in-flight review complete
// so the user does not see a "Copilot encountered an error" review on a
// PR that was merged moments before the review finished.
type AgenticAppSkipPRCloseCancel interface {
	SkipPRCloseCancel() bool
}

// AgenticAppJobLimitExempt is an optional interface that AgenticApp
// implementations can satisfy to indicate they are exempt from actor-level
// job concurrency limits.
//
// Apps that manage their own concurrency (e.g., Copilot Code Review, which
// caps reviews via PR creation limits) return true so sweagentd skips the
// per-actor cap for their jobs.
type AgenticAppJobLimitExempt interface {
	IsJobLimitExempt() bool
}

// AgenticAppEnablementExempt is an optional interface that AgenticApp
// implementations can satisfy to indicate they manage their own enablement
// checks and should not be gated by the monolith's IsAgentEnabled response
// (which evaluates flags like copilot_swe_agent_disallow).
//
// First-party external agents (e.g., Copilot Code Review) evaluate disallow
// flags independently before calling sweagentd, so the monolith check should
// not block job creation for them.
type AgenticAppEnablementExempt interface {
	SkipEnablementCheck() bool
}

// AgenticAppSetupStepFailureNotifier is an optional interface that AgenticApp
// implementations can satisfy to opt in to posting a PR comment when a
// user-defined step in copilot-setup-steps.yml fails at runtime.
//
// Apps that do not implement this interface stay silent.
type AgenticAppSetupStepFailureNotifier interface {
	NotifyOnSetupStepFailure() bool
}

// AgenticAppFirewallExempt is an optional interface that AgenticApp
// implementations can satisfy to indicate the agent firewall must not be
// enforced for their jobs.
//
// Apps like Copilot Code Review have a narrow, well-known egress profile and
// their legacy workflow never enforced an agent firewall. They opt in here so
// sweagentd renders the workflow with the firewall fully off, regardless of
// repo-level CCA firewall settings.
type AgenticAppFirewallExempt interface {
	SkipAgentFirewall() bool
}
