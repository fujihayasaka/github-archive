package sweagentd

// CustomAgentHandoff represents one of a list of handoffs in custom agent config for VS Code.
// https://code.visualstudio.com/docs/copilot/customization/custom-chat-modes#_header-optional
type CustomAgentHandoff struct {
	// Label is the display label for the handoff option.
	Label string `json:"label" yaml:"label"`
	// Agent is the identifier of the handoff agent.
	Agent string `json:"agent" yaml:"agent"`
	// Prompt is an optional prompt to provide context for the handoff.
	Prompt string `json:"prompt" yaml:"prompt"`
	// Send indicates whether to send the current conversation to the handoff agent.
	Send bool `json:"send" yaml:"send"`
	// Model is the language model to use when the handoff executes.
	Model string `json:"model" yaml:"model"`
}

// CustomAgentTriggers defines the events that a custom agent can respond to.
type CustomAgentTriggers struct {
	// We only want to exclude these if they are nil since non-nil but empty has
	// meaning in the Actions syntax
	Interval *CustomAgentIntervalTrigger `json:"interval,omitempty" yaml:"interval,omitempty"`
	// Issues includes the trigger for issue events
	Issues *CustomAgentTrigger `json:"issues,omitempty" yaml:"issues,omitempty"`
	// WorkflowRun includes the trigger for workflow runs
	WorkflowRun *CustomAgentWorkflowRunTrigger `json:"workflow_run,omitempty" yaml:"workflow_run,omitempty"`
	// PullRequestOpened includes the trigger for pull_request.opened activity.
	PullRequestOpened *CustomAgentPullRequestTrigger `json:"pull_request_opened,omitempty" yaml:"pull_request_opened,omitempty"`
	// PullRequestSynchronize includes the trigger for pull_request.synchronize activity.
	PullRequestSynchronize *CustomAgentPullRequestTrigger `json:"pull_request_synchronize,omitempty" yaml:"pull_request_synchronize,omitempty"`
	// PullRequestMerged includes the trigger for pull_request.merged activity.
	PullRequestMerged *CustomAgentPullRequestTrigger `json:"pull_request_merged,omitempty" yaml:"pull_request_merged,omitempty"`
}

// HasDefinedTriggers returns true when any trigger block is present.
// A non-nil trigger counts as defined even if its inner lists are empty.
func (t CustomAgentTriggers) HasDefinedTriggers() bool {
	return t.Interval != nil || t.Issues != nil || t.WorkflowRun != nil ||
		t.PullRequestOpened != nil || t.PullRequestSynchronize != nil || t.PullRequestMerged != nil
}

// CustomAgentIntervalTrigger defines the interval trigger configuration for a custom agent.
type CustomAgentIntervalTrigger struct {
	// Types is a list of interval types (e.g., "daily", "weekly").
	// Currently only the first valid type is used per agent.
	Types []string `json:"types,omitempty" yaml:"types,omitempty"`
	// HourUTC anchors daily/weekly schedules to a specific UTC hour (0..23).
	// Optional; omit for "anytime within the natural window".
	HourUTC *int `json:"hour_utc,omitempty" yaml:"hour_utc,omitempty"`
	// DayOfWeek anchors weekly schedules to a specific UTC weekday (0...6, where 0=Sunday).
	DayOfWeek *int `json:"day_of_week,omitempty" yaml:"day_of_week,omitempty"`
}

// CustomAgentTrigger is a base struct that defines a specific event type for a
// custom agent. Some events will have more properties
type CustomAgentTrigger struct {
	// Types is a list of event types that the agent should respond to.
	Types []string `json:"types,omitempty" yaml:"types,omitempty"`
	// Query is an optional GitHub search query string used to filter which
	// newly opened issues trigger the agent (e.g. "label:auto-triage -has:assignee").
	// Only applicable when Types includes "opened". When empty, all opened
	// issues will trigger the agent.
	Query string `json:"query,omitempty" yaml:"query,omitempty"`
}

// CustomAgentWorkflowRunTrigger defines the workflow run trigger configuration
// for a custom agent.
type CustomAgentWorkflowRunTrigger struct {
	// Types is a list of workflow run event types that the agent should respond to.
	Types []string `json:"types,omitempty" yaml:"types,omitempty"`
	// Workflows is an optional list of workflow names that the agent should respond to.
	Workflows []string `json:"workflows,omitempty" yaml:"workflows,omitempty"`
}

// CustomAgentPullRequestTrigger defines the pull_request trigger configuration.
type CustomAgentPullRequestTrigger struct {
	// Types is a list of pull_request activity types (currently only "opened").
	Types []string `json:"types,omitempty" yaml:"types,omitempty"`
	// Query is an optional GitHub search query (e.g. "label:dependencies -draft:true").
	Query string `json:"query,omitempty" yaml:"query,omitempty"`
	// Paths is an optional list of gitignore-style globs (e.g. "src/**", "!**/*.md").
	Paths []string `json:"paths,omitempty" yaml:"paths,omitempty"`
}

// CustomAgent represents a specialized agent with specific configurations and capabilities.
//
//nolint:interfacebloat // CustomAgent interface requires many methods to fully represent agent configuration
type CustomAgent interface {
	Name() string
	RepoOwnerID() int64
	RepoOwner() string
	RepoID() int64
	RepoName() string
	DisplayName() string
	Description() string
	Prompt() string
	Tools() []string
	Version() string
	Target() string
	ConfigError() string
	Metadata() map[string]string
	ArgumentHint() string
	InferenceEnabled() bool
	DisableModelInvocation() bool
	UserInvocable() bool
	Model() string
	Handoffs() []CustomAgentHandoff
	Triggers() CustomAgentTriggers
	GitHubMCPToolsets() []string
	Skills() []string
	// Scope returns the origin scope of the agent: "repo", "org", "enterprise", or "job".
	Scope() string
}
