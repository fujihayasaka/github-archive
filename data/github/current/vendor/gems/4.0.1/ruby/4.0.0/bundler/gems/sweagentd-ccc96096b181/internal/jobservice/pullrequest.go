package jobservice

import (
	"context"
	"errors"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/requestctx"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/twitchtv/twirp"
)

// Pull Request Body Structure and Character Allocation:
//
// ┌─────────────────────────────────────────────────────────────┐
// │ PR Body Placeholder (user-provided)                         |
// |                                                             │
// │ Max: ~44,927 chars                                          │
// │ (MaxPullRequestBodyPlaceholderLength)        	             │
// |    65,535  (max PR body length)                             │
// |  - 19,608  (combined below: 88 + ~5,070 + ~650 + 13,800)    |
// |   ---------                                                 |
// |   ~45,927  (actual max placeholder length)                  |
// └─────────────────────────────────────────────────────────────┘
// ┌─────────────────────────────────────────────────────────────┐
// │ <!-- START COPILOT ORIGINAL PROMPT -->                      |
// |                                                             │
// │ (PullRequestBodyOriginalPromptSeparator: 42 chars)          │
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
// │ <!-- START COPILOT CODING AGENT SUFFIX -->                  |
// |                                                             │
// │ (PullRequestBodySuffixSeparator: 46 chars)                  │
// └─────────────────────────────────────────────────────────────┘
// ┌─────────────────────────────────────────────────────────────┐
// │ User-provided Body Suffix (e.g., "Fixes #123")              |
// │                                                             |
// │ Max: 13,800 chars                                           │
// │ (MaxPullRequestBodySuffixLength)                            │
// └─────────────────────────────────────────────────────────────┘
// ┌─────────────────────────────────────────────────────────────┐
// │ Random Tip (optional, added if space allows)                │
// └─────────────────────────────────────────────────────────────┘
const (
	// PullRequestBodyOriginalPromptSeparator marks the start of the original prompt section in PR bodies.
	// This section contains the original problem statement and custom agent details that should be
	// included when building the problem statement for the model.
	PullRequestBodyOriginalPromptSeparator string = "\n\n<!-- START COPILOT ORIGINAL PROMPT -->\n\n"

	// PullRequestBodySuffixSeparator marks the start of user-provided suffix content in PR bodies.
	// This section contains user-provided content like "Fixes #123" that should NOT be included
	// when building the problem statement for the model to avoid hallucinations.
	PullRequestBodySuffixSeparator string = "\n\n<!-- START COPILOT CODING AGENT SUFFIX -->\n\n"

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
	// pull request body suffix, which includes both the original prompt separator,
	// problem statement quote, custom agent details, the user suffix separator,
	// user provided suffix, and optionally a tip.
	MaxCompiledPullRequestBodySuffixLength = len(PullRequestBodyOriginalPromptSeparator) + MaxPullRequestBodyProblemStatementQuoteLengthWithWrapper + MaxCompiledPullRequestBodyAgentDetailsLength + len(PullRequestBodySuffixSeparator) + MaxPullRequestBodySuffixLength

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
const PullRequestBodyAgentNameWrapper = "\n> **Custom agent used: %s**\n" // ~31 chars

// PRBodyPrefix is the prefix text added to pull request descriptions
const PRBodyPrefix = "Thanks for asking me to work on this. I will get started on it and keep this PR's description up to date as I form a plan and make progress.\n"

var (
	// ErrPullRequestExists is returned when attempting to create a pull request
	// that already exists.
	ErrPullRequestExists = errors.New("pull request already exists")
)

// PullRequestCreator defines the interface for creating pull requests.
type PullRequestCreator interface {
	CreatePullRequest(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error)
}

// OpenPullRequest creates a pull request for the given job using the provided PullRequestCreator.
func (s *Service) OpenPullRequest(ctx context.Context, gh PullRequestCreator, assignment *jobs.Assignment, job *jobs.Job, title, body string) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.OpenPullRequest")
	defer span.End()

	req := &sweagentdTwirp.CreatePullRequestRequest{
		RepositoryId:      uint64(job.RepoID),
		PrName:            title,
		PrDescription:     body,
		HeadBranchName:    job.BranchName,
		BaseBranchName:    job.BaseCommit,
		Draft:             true,
		AttributionUserId: uint64(job.ActorID),
		SessionId:         job.SessionID,
		AgentId:           job.AgentID,
	}

	s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Int64("pull_request.repository_id", job.RepoID),
		kvp.String("pull_request.title", title),
		kvp.String("pull_request.head_branch_name", job.BranchName),
		kvp.String("pull_request.base_branch_name", job.BaseCommit),
	).Info("Creating PR")

	pr, err := gh.CreatePullRequest(ctx, req)
	if err != nil {
		var twirpErr twirp.Error
		if errors.As(err, &twirpErr) && twirpErr.Code() == twirp.AlreadyExists {
			s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("pull request already exists")
			if job.Features.PullRequest != nil && job.Features.PullRequest.HeadRef != "" {
				return newErrPullRequestExists()
			}

			return goerrors.Errorf("error creating pull request: pull request exists but head ref was provided by us: %w", err)
		}
		return goerrors.Errorf("failed to create pull request: %w", err)
	}

	id := int64(pr.PullRequest.Id)
	number := int(pr.PullRequest.GithubNumber)

	assignment.PullRequestID = id
	assignment.PullRequestNumber = number

	job.PullRequestID = id
	job.PullRequestNumber = number

	s.updateRequestContextJob(ctx, job)

	_ = requestctx.AddPullRequest(ctx, requestctx.CtxPullRequest{
		ID:     &id,
		Number: number,
	})

	return nil
}

func newErrPullRequestExists() error {
	return goerrors.WithStackOffset(ErrPullRequestExists, 1)
}
