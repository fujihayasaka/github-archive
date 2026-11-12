package jobapi

import (
	"encoding/json"
	"strings"
	"unicode/utf8"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	ps "github.com/github/sweagentd/internal/problemstatement"
	gg "github.com/google/go-github/v75/github"
)

// NewJobAPIRequest represents a request to create a new job via the API
type NewJobAPIRequest struct {
	ProblemStatement  string                                 `json:"problem_statement"`
	ContentFilterMode jobs.ProblemStatementContentFilterMode `json:"content_filter_mode,omitempty"`

	RunName string `json:"run_name"`

	// [Optional] Information about the triggering event
	EventType        jobs.EventType `json:"event_type,omitempty"`
	EventURL         string         `json:"event_url,omitempty"`
	EventIdentifiers []string       `json:"event_identifiers,omitempty"`
	EventContent     string         `json:"event_content,omitempty"`

	// Features contains required resources and options for the job's environment.
	Features *EnvironmentFeatures `json:"features,omitempty"`

	// If this field is set, the custom agent will be loaded from the custom agent's file
	// in the repository, i.e. .github/agents/<custom-agent>.md
	CustomAgent string `json:"custom_agent,omitempty"`

	// The GitHub App ID to use for this job. If 0, defaults to Copilot's app ID
	AgentID uint64 `json:"agent_id,omitempty"`

	// The AI model to use for this job. If empty, defaults to the default model.
	Model string `json:"model,omitempty"`
}

// UnmarshalJSON is a custom unmarshaler to handle deprecated fields.
func (r *NewJobAPIRequest) UnmarshalJSON(data []byte) error {
	// Use type aliases to avoid recursion
	type Alias NewJobAPIRequest

	aux := &struct {
		*Alias

		// this allows us to capture the pull_request field if it exists on the
		// root of the JSON object for backwards compatibility
		PullRequest *PullRequestFeature `json:"pull_request,omitempty"`
	}{
		Alias: (*Alias)(r),
	}

	err := json.Unmarshal(data, &aux)
	if err != nil {
		return err
	}

	// If the deprecated PullRequest field is set and Features.PullRequest is
	// nil, move the data over.
	if aux.PullRequest != nil && (r.Features == nil || r.Features.PullRequest == nil) {
		r.Features = &EnvironmentFeatures{
			PullRequest: aux.PullRequest,
		}
	}

	return nil
}

// validate validates the new job arguments
func (r *NewJobAPIRequest) validate(repo *gg.Repository) error {
	// The errors returned from this method are anticipated NOT to be recorded in
	// sentry since they should all represent 400 series errors.
	//
	// Therefore, it's fine to return simple errors with text that can be shown
	// to the user including high cardinality information.
	//
	// TODO (colbylwilliams): Create an actual validation error type so we can return
	// multiple validation errors at once and use proper error codes.
	// TODO (colbylwilliams): Replace the title validation for title

	if r.ProblemStatement == "" {
		return goerrors.New("problem_statement is required")
	}

	if utf8.RuneCountInString(r.ProblemStatement) > ps.MaxProblemStatementLength {
		return goerrors.Errorf("problem_statement exceeds maximum length of %d characters, actual length of %d", ps.MaxProblemStatementLength, utf8.RuneCountInString(r.ProblemStatement))
	}

	if r.Features != nil && r.Features.PullRequest != nil {
		// If a HeadRef is provided, it must start with the Copilot branch prefix
		// TODO: Support other agenticapp's branch prefixes in the future
		if r.Features.PullRequest.HeadRef != "" && !strings.HasPrefix(r.Features.PullRequest.HeadRef, agenticapp.CopilotBranchPrefix+"/") {
			return goerrors.Errorf("features.pull_request.head_ref must start with the prefix %q", agenticapp.CopilotBranchPrefix+"/")
		}

		if utf8.RuneCountInString(r.Features.PullRequest.BodyPlaceholder) > jobservice.MaxPullRequestBodyPlaceholderLength {
			return goerrors.Errorf("features.pull_request.body_placeholder exceeds maximum length of %d characters, actual length of %d", jobservice.MaxPullRequestBodyPlaceholderLength, utf8.RuneCountInString(r.Features.PullRequest.BodyPlaceholder))
		}

		if utf8.RuneCountInString(r.Features.PullRequest.BodySuffix) > jobservice.MaxPullRequestBodySuffixLength {
			return goerrors.Errorf("features.pull_request.body_suffix exceeds maximum length of %d characters, actual length of %d", jobservice.MaxPullRequestBodySuffixLength, utf8.RuneCountInString(r.Features.PullRequest.BodySuffix))
		}
	}

	if repo.GetDefaultBranch() == "" {
		return goerrors.New("repository is not initialized")
	}

	if repo.Archived != nil && *repo.Archived {
		return goerrors.New("repository is archived")
	}

	return nil
}

// EnvironmentFeatures defines the features for the job's environment,
type EnvironmentFeatures struct {
	// Branch defines the options for branch creation.
	Branch *BranchFeature `json:"branch,omitempty"`

	// PullRequest defines the options for pull request creation.
	PullRequest *PullRequestFeature `json:"pull_request,omitempty"`
}

// PullRequestFeature defines the options for pull request creation.
type PullRequestFeature struct {
	// Title is the title of the PR. If not specified, AI will generate one.
	Title string `json:"title,omitempty"`

	// BodyPlaceholder is the placeholder text for the body of the PR.
	BodyPlaceholder string `json:"body_placeholder,omitempty"`

	// BodySuffix is the suffix to always include at the end of the body of the PR.
	BodySuffix string `json:"body_suffix,omitempty"`

	// BaseRef defaults to the default branch of the repo.
	BaseRef string `json:"base_ref,omitempty"`

	// HeadRef is the branch that will be used for the PR (but still targeting
	// the BaseRef).
	// If not specified, but the branch feature is specified, the branch feature's
	// resulting branch will be used.
	// If neither is specified, a new branch will be created from the BaseRef.
	HeadRef string `json:"head_ref,omitempty"`

	// Labels are the labels to add to the PR.
	Labels []string `json:"labels,omitempty"`
}

// BranchFeature defines the options for branch creation.
type BranchFeature struct {
	// Name is the name of the branch to create. If not specified, one will be
	// generated using AI.
	Name string `json:"name,omitempty"`

	// BaseRef is the branch that the new branch will be created from.
	BaseRef string `json:"base_ref,omitempty"`
}
