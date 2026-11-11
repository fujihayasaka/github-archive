package jobapi

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobutils"
	ps "github.com/github/sweagentd/internal/problemstatement"
	gg "github.com/google/go-github/v75/github"
)

// TODO (colbylwilliams): Move these constants to the jobservice package
//
// Pull Request Body Structure and Character Allocation:
//
// ┌─────────────────────────────────────────────────────────────┐
// │ PR Body Placeholder (user-provided)                         |
// |                                                             │
// │ Max: ~44,975 chars                                          │
// │ (MaxPullRequestBodyPlaceholderLength)        	             │
// |    65,535  (max PR body length)                             │
// |  - 19,570  (combined below: ~50 + ~5,070 + ~650 + 13,800)   |
// |   ---------                                                 |
// |   ~45,965  (actual max placeholder length)                  |
// └─────────────────────────────────────────────────────────────┘
// ┌─────────────────────────────────────────────────────────────┐
// │ <!-- START COPILOT CODING AGENT SUFFIX -->                  |
// |                                                             │
// │ (PullRequestBodySuffixSeparator: ~50 chars)                 │
// └─────────────────────────────────────────────────────────────┘
// ┌─────────────────────────────────────────────────────────────┐
// │ <details><summary>Original prompt</summary>                 │
// │ [Problem Statement Quote]                                   │
// │ </details>                                                  │
// │                                                             |
// | Max: ~5,070 chars total (wrapper + quote)                   │
// │ (MaxPullRequestBodyProblemStatementQuoteLengthWithWrapper)  │
// │   - Wrapper: ~70 chars                                      │
// │   - Quote: 5,000 chars max                                  │
// │   - Note: Omitted for Slack event types                     │
// └─────────────────────────────────────────────────────────────┘
// ┌─────────────────────────────────────────────────────────────┐
// │ Custom Agent details (name (100) + description (500))       |
// │                                                             |
// │ Max: ~650 chars                                             │
// │ (MaxCompiledPullRequestBodyAgentDetailsLength)              │
// └─────────────────────────────────────────────────────────────┘
// ┌─────────────────────────────────────────────────────────────┐
// │ User-provided Body Suffix (e.g., "Fixes #123")            |
// │                                                             |
// │ Max: 13,800 chars                                           │
// │ (MaxPullRequestBodySuffixLength)                            │
// └─────────────────────────────────────────────────────────────┘
// ┌─────────────────────────────────────────────────────────────┐
// │ Random Tip (optional, added if space allows)                │
// └─────────────────────────────────────────────────────────────┘
const (
	// MaxPullRequestBodyProblemStatementQuoteLength is the maximum length of the
	// problem statement quote we want to include in the PR body placeholder.
	MaxPullRequestBodyProblemStatementQuoteLength = 5000

	// MaxPullRequestBodyProblemStatementQuoteLengthWithWrapper is the maximum
	// length of the problem statement quote we want to include in the PR body
	// suffix, including the length of the wrapper.
	MaxPullRequestBodyProblemStatementQuoteLengthWithWrapper = len(PullRequestBodyProblemStatementQuoteWrapper) + MaxPullRequestBodyProblemStatementQuoteLength

	// MaxPullRequestBodyAgentNameLength is the maximum length of the agent name
	// we want to include in the PR body suffix.
	MaxPullRequestBodyAgentNameLength = 100

	// MaxPullRequestBodyAgentNameLengthWithWrapper is the maximum length of the
	// agent name we want to include in the PR body suffix, including the length
	// of the wrapper.
	MaxPullRequestBodyAgentNameLengthWithWrapper = len(PullRequestBodyAgentNameWrapper) + MaxPullRequestBodyAgentNameLength

	// MaxPullRequestBodyAgentDescriptionLength is the maximum length of the
	// agent description we want to include in the PR body suffix.
	MaxPullRequestBodyAgentDescriptionLength = 500

	// MaxCompiledPullRequestBodyAgentDetailsLength is the maximum length of the
	// compiled agent details (name + description) we want to include in the PR
	// body suffix.
	MaxCompiledPullRequestBodyAgentDetailsLength = MaxPullRequestBodyAgentNameLengthWithWrapper + MaxPullRequestBodyAgentDescriptionLength

	// MaxPullRequestBodySuffixLength is the maximum length of the user provided
	// body suffix to append to the end of the pull request body. e.g. Fixes #123
	MaxPullRequestBodySuffixLength = 13800

	// MaxCompiledPullRequestBodySuffixLength is the maximum length of the compiled
	// pull request body suffix, which includes the suffix separator, problem
	// statement quote, any user provided suffix, and optionally a tip.
	MaxCompiledPullRequestBodySuffixLength = len(jobutils.PullRequestBodySuffixSeparator) + MaxPullRequestBodyProblemStatementQuoteLengthWithWrapper + MaxCompiledPullRequestBodyAgentDetailsLength + MaxPullRequestBodySuffixLength

	// MaxPullRequestBodyPlaceholderLength is the maximum length of the body
	// placeholder that can be specified when creating a new job. This is
	// calculated to ensure that when we append the compiled body suffix, we do
	// not exceed GitHub's maximum pull request body length.
	MaxPullRequestBodyPlaceholderLength = github.MaxPullRequestBodyLength - MaxCompiledPullRequestBodySuffixLength
)

// PullRequestBodyProblemStatementQuoteWrapper is the HTML details/summary container
// used to wrap the original problem statement in the pull request body.
const PullRequestBodyProblemStatementQuoteWrapper = "\n\n<details>\n\n<summary>Original prompt</summary>\n\n%s\n\n</details>\n\n"

// PullRequestBodyAgentNameWrapper is the markdown wrapper used to highlight
// the custom agent name in the pull request body.
const PullRequestBodyAgentNameWrapper = "\n> [!NOTE] \n> **Custom agent used: %s**\n" // ~50 chars

// PRBodyPrefix is the prefix text added to pull request descriptions
const PRBodyPrefix = "Thanks for asking me to work on this. I will get started on it and keep this PR's description up to date as I form a plan and make progress.\n"

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
	Features EnvironmentFeatures `json:"features"`

	// If this field is set, the custom agent will be loaded from the custom agent's file
	// in the repository, i.e. .github/agents/<custom-agent>.md
	CustomAgent string `json:"custom_agent,omitempty"`

	// CustomAgentAttributes is used to specify a custom agent configuration
	// at runtime without the need to have the custom agent created in the repository.
	// These values more or less map to the domain Config object of the custom agent package.
	CustomAgentAttributes *CustomAgentRequestAttributes `json:"custom_agent_attributes,omitempty"`

	// The GitHub App ID to use for this job. If 0, defaults to Copilot's app ID
	AgentID uint64 `json:"agent_id,omitempty"`
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
	if aux.PullRequest != nil && r.Features.PullRequest == nil {
		r.Features.PullRequest = aux.PullRequest
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
		return errors.New("problem_statement is required")
	}

	if utf8.RuneCountInString(r.ProblemStatement) > ps.MaxProblemStatementLength {
		return fmt.Errorf("problem_statement exceeds maximum length of %d characters, actual length of %d", ps.MaxProblemStatementLength, utf8.RuneCountInString(r.ProblemStatement))
	}

	if r.Features.PullRequest != nil {
		// If a HeadRef is provided, it must start with the Copilot branch prefix
		if r.Features.PullRequest.HeadRef != "" && !strings.HasPrefix(r.Features.PullRequest.HeadRef, github.CopilotBranchPrefix+"/") {
			return fmt.Errorf("features.pull_request.head_ref must start with the prefix %q", github.CopilotBranchPrefix+"/")
		}

		if utf8.RuneCountInString(r.Features.PullRequest.BodyPlaceholder) > MaxPullRequestBodyPlaceholderLength {
			return fmt.Errorf("features.pull_request.body_placeholder exceeds maximum length of %d characters, actual length of %d", MaxPullRequestBodyPlaceholderLength, utf8.RuneCountInString(r.Features.PullRequest.BodyPlaceholder))
		}

		if utf8.RuneCountInString(r.Features.PullRequest.BodySuffix) > MaxPullRequestBodySuffixLength {
			return fmt.Errorf("features.pull_request.body_suffix exceeds maximum length of %d characters, actual length of %d", MaxPullRequestBodySuffixLength, utf8.RuneCountInString(r.Features.PullRequest.BodySuffix))
		}
	}

	if repo.GetDefaultBranch() == "" {
		return errors.New("repository is not initialized")
	}

	if repo.Archived != nil && *repo.Archived {
		return errors.New("repository is archived")
	}

	return nil
}

// CustomAgentRequestAttributes contains attributes for configuring a custom agent
type CustomAgentRequestAttributes struct {
	DisplayName string   `json:"name,omitempty"`
	Description string   `json:"description,omitempty"`
	Prompt      string   `json:"prompt,omitempty"`
	Tools       []string `json:"tools,omitempty"`
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
