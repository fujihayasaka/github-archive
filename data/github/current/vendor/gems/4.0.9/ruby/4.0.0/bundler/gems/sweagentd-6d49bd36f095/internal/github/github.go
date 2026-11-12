// Package github provides a client for interacting with the GitHub Rest and GraphQL APIs.
package github

import (
	"archive/zip"
	"bytes"
	"context"
	_ "embed"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-auth/hmac"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
	"github.com/shurcooL/githubv4"
	"go.opentelemetry.io/otel/attribute"
)

// List of branch protection rules that can prevent Copilot from pushing code
const (
	RuleRequireGitHubActions     = "GitHub Actions is disabled for this repository. To learn how to enable GitHub Actions, head to the [GitHub Docs](https://gh.io/copilot-coding-agent-enable-actions)."
	RuleAgentPrefixBranchExists  = "A branch named `%s` already exists. To learn how to delete a branch, head to the [GitHub Docs](https://gh.io/copilot-coding-agent-delete-copilot-branch)."
	RuleBlockCreation            = "Branch creation is blocked"
	RuleRequirePullRequest       = "Changes must be made through a pull request"
	RuleCodeScanning             = "Code scanning results must be provided"
	RuleRequireSignatures        = "Commits must have verified signatures"
	RuleBranchNamePattern        = "Branch name restrictions apply"
	RuleCommitMessagePattern     = "Commit message restrictions apply"
	RuleCommitAuthorEmailPattern = "Commit author email restrictions apply"
	RuleCommitterEmailPattern    = "Committer email restrictions apply"
)

// Limits on field sizes
const (
	MaxRunNameLength          = 255
	MaxPullRequestTitleLength = 255
	MaxPullRequestBodyLength  = 65535 // 64 KB
)

// CopilotEnvironmentName is the name of the Copilot environment for GitHub Actions.
const CopilotEnvironmentName string = "copilot"

// maxAgentPaginationPages is the maximum number of pages to fetch when paginating agent secrets/variables endpoints.
const maxAgentPaginationPages = 10

// FeedbackTip contains the feedback tip message for Copilot.
//
//go:embed feedback_tip.md
var FeedbackTip string

// BestPracticesTip contains best practices tips for Copilot.
//
//go:embed best_practices_tip.md
var BestPracticesTip string

// AdvancedSecurityTip contains the Advanced Security tip message for Copilot.
//
//go:embed advanced_security_tip.md
var AdvancedSecurityTip string

// PlanningAndTrackingTip contains the planning and tracking tip message for Copilot.
//
//go:embed planning_and_tracking_tip.md
var PlanningAndTrackingTip string

// WorkplaceChatTip contains the workplace chat tip message for Copilot.
//
//go:embed workplace_chat_tip.md
var WorkplaceChatTip string

// MobileTip contains the mobile tip message for Copilot.
//
//go:embed mobile_tip.md
var MobileTip string

// IDETip contains the IDE integration tip message for Copilot.
//
//go:embed ide_tip.md
var IDETip string

// RaycastTip contains the Raycast extension tip message for Copilot.
//
//go:embed raycast_tip.md
var RaycastTip string

// OsweExperimentNote contains the OSWE experiment note.
//
//go:embed oswe_experiment_note.md
var OsweExperimentNote string

// ClientInterface defines the interface for GitHub API clients.
//
//nolint:interfacebloat // This interface aggregates all GitHub API operations needed by the system
type ClientInterface interface {
	Committer

	Token() string
	CreateEmptyCommit(ctx context.Context, ownerLogin, repoName, branchName string) (*gg.Commit, error)
	CreatePullRequest(ctx context.Context, ownerLogin, repoName string, opts *gg.NewPullRequest) (*gg.PullRequest, error)
	GetRepository(ctx context.Context, ownerLogin, repoName string) (*gg.Repository, error)
	GetRepositoryByID(ctx context.Context, id int64) (*gg.Repository, error)
	GetIssue(ctx context.Context, ownerLogin, repoName string, number int) (*gg.Issue, error)
	AssignToIssue(ctx context.Context, ownerLogin, repoName string, issueNumber int, assignee string) error
	GetPullRequest(ctx context.Context, repoID int64, number int) (*gg.PullRequest, error)
	ListPullRequestFiles(ctx context.Context, owner, repo string, number int) ([]*gg.CommitFile, error)
	ListPullRequestsWithCommit(ctx context.Context, owner, repo, sha string) ([]*gg.PullRequest, error)
	UpdatePullRequest(ctx context.Context, repoID int64, pr *gg.PullRequest) (*gg.PullRequest, error)
	RequestReviewers(ctx context.Context, ownerLogin, repoName string, number int, reviewers []string) error
	GetComment(ctx context.Context, owner, repo string, commentID int64) (*gg.IssueComment, error)
	CreateComment(ctx context.Context, repoID int64, issueOrPRNumber int, body string) (*gg.IssueComment, error)
	DeleteComment(ctx context.Context, repoID, commentID int64) error
	CreateCommentInReplyTo(ctx context.Context, owner, repo string, prNumber int, body string, commentID int64) (*gg.PullRequestComment, error)
	UpdateComment(ctx context.Context, owner, repo string, commentID int64, body string) (*gg.IssueComment, error)
	MinimizeComment(ctx context.Context, nodeID string, classifier GQLReportedContentClassifier) error
	UnminimizeComment(ctx context.Context, nodeID string) error
	MarkPullRequestReadyForReview(ctx context.Context, prNodeID string) error
	ConvertPullRequestToDraft(ctx context.Context, prNodeID string) error
	AddReaction(ctx context.Context, nodeID string, content GQLReactionContent) error
	RemoveReaction(ctx context.Context, nodeID string, content GQLReactionContent) error
	RemoveReactionFromIssue(ctx context.Context, owner, repo string, number int, isAgentic agenticapp.IsAgenticFunc) error
	GetWorkflowRunByID(ctx context.Context, ownerLogin, repoName string, runID int64) (*gg.WorkflowRun, error)
	CancelWorkflowRunByID(ctx context.Context, ownerLogin, repoName string, runID int64) error
	GetWorkflowRunLogs(ctx context.Context, owner, repo string, runID int64) (string, error)
	CreateDynamicWorkflowRun(ctx context.Context, owner, repo string, repoID int64, useRepoID bool, opts *NewDynamicWorkflowRun) (*DynamicWorkflowRun, error)
	ListWorkflowJobs(ctx context.Context, owner, repo string, runID int64) ([]*gg.WorkflowJob, error)
	GetWorkflowJobByID(ctx context.Context, owner, repo string, jobID int64) (*gg.WorkflowJob, error)
	ListCheckRunAnnotations(ctx context.Context, owner, repo string, jobID int64) ([]*gg.CheckRunAnnotation, error)
	AddLabelsToIssueOrPR(ctx context.Context, ownerLogin string, repoName string, issueOrPRNumber int, labels []string) error
	GetUserByID(ctx context.Context, id uint64) (*gg.User, error)
	DeleteRepo(ctx context.Context, owner, repo string) error
	CreateRepo(ctx context.Context, org, name string, autoinit bool) (*gg.Repository, error)
	CreateIssue(ctx context.Context, owner, repo, title, body string) (*gg.Issue, error)
	GetPullRequests(ctx context.Context, owner, repo string, opts *gg.PullRequestListOptions) ([]*gg.PullRequest, error)
	GetContents(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error)
	UpdateFile(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentFileOptions) (*gg.RepositoryContentResponse, error)
	GetAuthenticatedUser(ctx context.Context) (*gg.User, error)
	GetCopilotEnvironmentSecretsAndVariables(ctx context.Context, owner, repo string, repoID int64) (secrets, variables []string, err error)
	GetAgentSecretsAndVariables(ctx context.Context, owner, repo string, isRepoOwnedByOrganization bool) (secrets, variables []string, err error)
	GetAgentVariableValue(ctx context.Context, owner, repo, variableName string, isRepoOwnedByOrganization bool) (string, error)
	GetCopilotBotUser(ctx context.Context) (*gg.User, error)
	GetUserPermissionsForRepository(ctx context.Context, owner, repo, username string) (*RepositoryPermissions, error)
	GetUserPermissionsForRepositoryByID(ctx context.Context, repoID int64, username string) (*RepositoryPermissions, error)
	GetRepositoryContext(ctx context.Context, repoNodeID string) (*RepositoryContext, error)
	GetIssueContext(ctx context.Context, repoNodeID string, number int, isAgentic agenticapp.IsAgenticFunc) (*IssueContext, error)
	GetIssueUserContentEdits(ctx context.Context, issueNodeID string) ([]UserContentEdit, error)
	GetPullRequestContext(ctx context.Context, repoNodeID string, number int, isAgentic agenticapp.IsAgenticFunc) (*PullRequestContext, error)
	ReplaceActorsForAssignable(ctx context.Context, assignableID string, actorsIDs []string) error
	ListBranchProtectionRules(ctx context.Context, repoNodeID string) (*[]GQLBranchProtectionRule, error)
	ListRepositoryRulesForBranch(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error)
	GetActionsPermissions(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error)
}

// Client is a GitHub API client that wraps the go-github library.
type Client struct {
	target                     sweagentd.ClientTarget
	client                     *gg.Client
	internalClient             *gg.Client
	gqlclient                  *githubv4.Client
	internalGqlClient          *githubv4.Client
	dynamicWorkflowsHmacSecret string
	ffClient                   featureflags.Client
	limiter                    limiter.RateLimiter
	token                      string
	tokenSource                *refreshableTokenSource
	obsv                       observability.Exporters
	environment                config.Environment
	app                        sweagentd.AgenticApp
}

// Ensure Client implements ClientInterface
var _ ClientInterface = &Client{}

// getRESTClient returns the appropriate REST API client based on the feature flag.
// When the internal API flag is enabled, returns the internal client; otherwise returns the public client.
func (ac *Client) getRESTClient(ctx context.Context) *gg.Client {
	if ac.ffClient.IsEnabled(ctx, featureflags.CopilotSWEAgentUseInternalAPI) {
		return ac.internalClient
	}
	return ac.client
}

// getGraphQLClient returns the appropriate GraphQL client based on the feature flag.
// When the internal API flag is enabled, returns the internal client; otherwise returns the public client.
func (ac *Client) getGraphQLClient(ctx context.Context) *githubv4.Client {
	if ac.ffClient.IsEnabled(ctx, featureflags.CopilotSWEAgentUseInternalAPI) {
		return ac.internalGqlClient
	}
	return ac.gqlclient
}

// Token returns the token used in the GitHub client.
func (ac *Client) Token() string {
	if ac.tokenSource != nil {
		return ac.tokenSource.Current()
	}
	return ac.token
}

// BaseURL returns the base URL of the GitHub client.
// Implements [sweagentd.GitHubAPI].
func (ac *Client) BaseURL() *url.URL {
	return ac.client.BaseURL
}

// Note: This function creates an empty commit but takes in an existing ref. We cannot reuse the CreateEmptyCommit
// function directly since this needs to look up the branch, and replication delays can cause 404s based on what we've seen in prod.
//
//nolint:funcorder // Helper method is placed near callers for readability
func (ac *Client) createEmptyCommit(ctx context.Context, ownerLogin, repoName, branchName string, ref *gg.Reference, commit *gg.Commit) (*gg.Commit, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.createEmptyCommit")
	defer span.End()

	emptyCommit, resp, err := ac.getRESTClient(ctx).Git.CreateCommit(ctx, ownerLogin, repoName, gg.Commit{
		Parents: []*gg.Commit{commit},
		Message: gg.Ptr("Initial plan"),
		Tree:    commit.Tree,
		Author: &gg.CommitAuthor{
			Name:  gg.Ptr(ac.app.CommitLogin()),
			Email: gg.Ptr(ac.app.CommitEmail()),
		},
	}, &gg.CreateCommitOptions{
		// TODO: Use a signer so commits are signed by Copilot
		Signer: nil,
	})
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to create initial empty commit for branch")
	}

	if v := emptyCommit.GetVerification(); v != nil {
		ac.obsv.LoggerWithTelemetry(ctx).Info("create commit verification",
			kvp.Bool("verified", v.GetVerified()),
			kvp.String("reason", v.GetReason()),
		)
	} else {
		ac.obsv.LoggerWithTelemetry(ctx).Warn("create commit response missing verification data")
	}

	var isRetrying bool
	user, ok := requestctx.User(ctx)
	if !ok {
		ac.obsv.LoggerWithTelemetry(ctx).Error("failed to get user from context, will not check feature state")
	} else {
		isRetrying = ac.ffClient.IsEnabledForUser(ctx, "sweagentd_retry_update_ref", int64(user.ID))
	}
	if isRetrying {
		// Update the branch to point to the empty commit with retries and backoff delays
		for i := range 3 {
			_, resp, err = ac.getRESTClient(ctx).Git.UpdateRef(ctx, ownerLogin, repoName, fmt.Sprintf("refs/heads/%s", branchName), gg.UpdateRef{
				SHA:   *emptyCommit.SHA,
				Force: gg.Ptr(true),
			})
			if err == nil {
				ac.obsv.LoggerWithTelemetry(ctx).Info("successfully updated ref to point to empty commit", kvp.Int("attempts", i))
				break
			}
			if resp != nil && resp.StatusCode == http.StatusUnprocessableEntity && strings.Contains(err.Error(), "Reference does not exist") {
				// Retry on 422 Reference does not exist
				time.Sleep(time.Duration(1<<i) * 100 * time.Millisecond) // Exponential backoff
				continue
			}
			return nil, ac.checkError(ctx, resp, err, "failed to update branch to point to empty commit")
		}
		if err != nil {
			return nil, ac.checkError(ctx, resp, err, "failed to update branch to point to empty commit after retries")
		}
	} else {
		// Update the branch to point to the empty commit
		_, resp, err = ac.getRESTClient(ctx).Git.UpdateRef(ctx, ownerLogin, repoName, fmt.Sprintf("refs/heads/%s", branchName), gg.UpdateRef{
			SHA:   *emptyCommit.SHA,
			Force: gg.Ptr(true),
		})
		if err != nil {
			return nil, ac.checkError(ctx, resp, err, "failed to update branch to point to empty commit")
		}
	}

	return emptyCommit, nil
}

// CreateEmptyCommit creates an empty commit on the specified branch.
func (ac *Client) CreateEmptyCommit(ctx context.Context, ownerLogin, repoName, branchName string) (*gg.Commit, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.CreateEmptyCommit")
	defer span.End()

	ref, resp, err := ac.getRESTClient(ctx).Git.GetRef(ctx, ownerLogin, repoName, fmt.Sprintf("refs/heads/%s", branchName))
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to get branch")
	}
	commit, resp, err := ac.getRESTClient(ctx).Git.GetCommit(ctx, ownerLogin, repoName, *ref.Object.SHA)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to get commit for branch")
	}

	return ac.createEmptyCommit(ctx, ownerLogin, repoName, branchName, ref, commit)
}

// CreatePullRequest creates a new pull request with the given options.
func (ac *Client) CreatePullRequest(ctx context.Context, ownerLogin, repoName string, opts *gg.NewPullRequest) (*gg.PullRequest, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.CreatePullRequest")
	defer span.End()

	pullRequest, resp, err := ac.getRESTClient(ctx).PullRequests.Create(ctx, ownerLogin, repoName, opts)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to create pull request")
	}

	if pullRequest != nil {
		copilot, err := ac.GetCopilotBotUser(ctx)
		if err != nil {
			return nil, err
		}

		// Use the GraphQL mutation to assign the PR to copilot
		assignees := []string{copilot.GetNodeID()}
		err = ac.ReplaceActorsForAssignable(ctx, pullRequest.GetNodeID(), assignees)
		if err != nil {
			return nil, err
		}
	}

	return pullRequest, nil
}

type pullRequestUpdate struct {
	Title               *string `json:"title,omitempty"`
	Body                *string `json:"body,omitempty"`
	State               *string `json:"state,omitempty"`
	Base                *string `json:"base,omitempty"`
	MaintainerCanModify *bool   `json:"maintainer_can_modify,omitempty"`
}

// UpdatePullRequest updates the following fields of the pull request: Title and Body.
func (ac *Client) UpdatePullRequest(ctx context.Context, repoID int64, pr *gg.PullRequest) (*gg.PullRequest, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.UpdatePullRequest")
	defer span.End()

	u := fmt.Sprintf("repositories/%d/pulls/%d", repoID, pr.GetNumber())

	update := &pullRequestUpdate{
		Title: pr.Title,
		Body:  pr.Body,
	}

	req, err := ac.getRESTClient(ctx).NewRequest(http.MethodPatch, u, update)
	if err != nil {
		return nil, err
	}

	p := new(gg.PullRequest)
	resp, err := ac.getRESTClient(ctx).Do(ctx, req, p)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to update pull request")
	}

	return p, nil
}

// RequestReviewers requests reviewers for a pull request.
func (ac *Client) RequestReviewers(ctx context.Context, owner, repo string, number int, reviewers []string) error {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.RequestReviewers")
	defer span.End()

	reviewersreq := gg.ReviewersRequest{
		Reviewers: reviewers,
	}
	_, resp, err := ac.getRESTClient(ctx).PullRequests.RequestReviewers(ctx, owner, repo, number, reviewersreq)
	if err != nil {
		return ac.checkError(ctx, resp, err, "failed to request reviewers")
	}
	return nil
}

// GetComment retrieves an issue comment by ID.
func (ac *Client) GetComment(ctx context.Context, owner, repo string, commentID int64) (*gg.IssueComment, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetComment")
	defer span.End()

	comment, resp, err := ac.getRESTClient(ctx).Issues.GetComment(ctx, owner, repo, commentID)
	if err != nil {
		if resp != nil && resp.StatusCode == http.StatusNotFound {
			return nil, nil
		}
		return nil, ac.checkError(ctx, resp, err, "failed to get pull request comment")
	}

	return comment, err
}

// CreateComment creates a new issue comment.
func (ac *Client) CreateComment(ctx context.Context, repoID int64, issueOrPRNumber int, body string) (*gg.IssueComment, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.CreateComment")
	defer span.End()

	u := fmt.Sprintf("repositories/%d/issues/%d/comments", repoID, issueOrPRNumber)
	req, err := ac.getRESTClient(ctx).NewRequest(http.MethodPost, u, &gg.IssueComment{
		Body: &body,
	})
	if err != nil {
		return nil, err
	}

	c := new(gg.IssueComment)
	resp, err := ac.getRESTClient(ctx).Do(ctx, req, c)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to create comment")
	}

	return c, nil
}

// DeleteComment deletes an issue comment.
func (ac *Client) DeleteComment(ctx context.Context, repoID, commentID int64) error {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.DeleteComment")
	defer span.End()

	u := fmt.Sprintf("repositories/%d/issues/comments/%d", repoID, commentID)
	req, err := ac.getRESTClient(ctx).NewRequest(http.MethodDelete, u, nil)
	if err != nil {
		return err
	}

	resp, err := ac.getRESTClient(ctx).Do(ctx, req, nil)
	if err != nil {
		return ac.checkError(ctx, resp, err, "failed to delete comment")
	}

	return nil
}

// CreateCommentInReplyTo creates a reply to a pull request review comment.
func (ac *Client) CreateCommentInReplyTo(ctx context.Context, owner, repo string, prNumber int, body string, commentID int64) (*gg.PullRequestComment, error) {
	// This function in go-github has a bug that uses the comments endpoint instead of reply. So we'll do a post ourselves.
	// comment, _, err := ac.getRESTClient(ctx).PullRequests.CreateCommentInReplyTo(ctx, owner, repo, prNumber, body, commentID)

	// See https://docs.github.com/en/rest/pulls/comments?apiVersion=2022-11-28#create-a-reply-for-a-review-comment

	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.CreateCommentInReplyTo")
	defer span.End()

	comment := &struct {
		Body string `json:"body"`
	}{
		Body: body,
	}
	u := fmt.Sprintf("repos/%v/%v/pulls/%d/comments/%d/replies", owner, repo, prNumber, commentID)
	req, err := ac.getRESTClient(ctx).NewRequest(http.MethodPost, u, comment)
	if err != nil {
		return nil, err
	}

	c := new(gg.PullRequestComment)
	resp, err := ac.getRESTClient(ctx).Do(ctx, req, c)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to create comment in reply to")
	}
	return c, nil
}

// UpdateComment updates an existing issue comment.
func (ac *Client) UpdateComment(ctx context.Context, owner, repo string, commentID int64, body string) (*gg.IssueComment, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.UpdateComment")
	defer span.End()

	comment, resp, err := ac.getRESTClient(ctx).Issues.EditComment(ctx, owner, repo, commentID, &gg.IssueComment{
		Body: &body,
	})
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to update comment")
	}
	return comment, err
}

// GetRepository retrieves a repository by owner and name.
func (ac *Client) GetRepository(ctx context.Context, ownerName, repoName string) (*gg.Repository, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetRepository")
	defer span.End()

	repo, resp, err := ac.getRESTClient(ctx).Repositories.Get(ctx, ownerName, repoName)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to get repository")
	}
	return repo, err
}

// GetRepositoryByID retrieves a repository by its ID. The result is memoized in the
// request context, so subsequent calls within the same request return the cached value
// without making another network round-trip.
func (ac *Client) GetRepositoryByID(ctx context.Context, id int64) (*gg.Repository, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetRepositoryByID")
	defer span.End()

	if repo, ok := requestctx.RepositoryByID(ctx, id); ok {
		span.SetAttributes(attribute.Bool("cache.hit", true))
		return repo, nil
	}
	span.SetAttributes(attribute.Bool("cache.hit", false))

	repo, resp, err := ac.getRESTClient(ctx).Repositories.GetByID(ctx, id)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to get repository by ID")
	}

	_ = requestctx.AddRepositoryByID(ctx, id, repo)
	return repo, nil
}

// GetWorkflowRunLogs retrieves the logs for a workflow run.
func (ac *Client) GetWorkflowRunLogs(ctx context.Context, owner, repo string, runID int64) (string, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetWorkflowRunLogs")
	defer span.End()

	u, resp, err := ac.getRESTClient(ctx).Actions.GetWorkflowRunLogs(ctx, owner, repo, runID, 10)
	if err != nil {
		return "", ac.checkError(ctx, resp, err, "failed to get workflow run logs URL")
	}

	req, err := ac.getRESTClient(ctx).NewRequest(http.MethodGet, u.String(), nil)
	if err != nil {
		return "", err
	}

	// Download the zip file as binary
	buff := bytes.NewBuffer([]byte{})
	resp, err = ac.getRESTClient(ctx).Do(ctx, req, buff)
	if err != nil {
		return "", ac.checkError(ctx, resp, err, "failed to get workflow run logs")
	}

	zipReader, err := zip.NewReader(bytes.NewReader(buff.Bytes()), int64(buff.Len()))
	if err != nil {
		return "", err
	}

	// Find the logs.txt file (should be at the root level)
	for _, f := range zipReader.File {
		if f.Name != "logs.txt" {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			return "", err
		}

		buf := new(strings.Builder)
		//nolint:gosec // G110: The zip file is from GitHub's API, limiting size is not necessary
		_, err = io.Copy(buf, rc)
		_ = rc.Close() // Error ignored intentionally - we already have the data
		return buf.String(), err
	}
	return "", goerrors.New("could not find logs.txt in workflow run logs zip")
}

// GetPullRequest retrieves a pull request by repository ID and number.
func (ac *Client) GetPullRequest(ctx context.Context, repoID int64, number int) (*gg.PullRequest, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetPullRequest")
	defer span.End()

	u := fmt.Sprintf("repositories/%d/pulls/%d", repoID, number)
	req, err := ac.getRESTClient(ctx).NewRequest(http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}

	pr := new(gg.PullRequest)
	resp, err := ac.getRESTClient(ctx).Do(ctx, req, pr)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to get pull request")
	}

	return pr, nil
}

// ListPullRequestFiles returns the first page of files changed by the given PR (up to 100).
func (ac *Client) ListPullRequestFiles(ctx context.Context, owner, repo string, number int) ([]*gg.CommitFile, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.ListPullRequestFiles")
	defer span.End()

	files, resp, err := ac.getRESTClient(ctx).PullRequests.ListFiles(ctx, owner, repo, number, &gg.ListOptions{PerPage: 100})
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to list pull request files")
	}
	return files, nil
}

// ListPullRequestsWithCommit returns pull requests associated with a commit SHA.
func (ac *Client) ListPullRequestsWithCommit(ctx context.Context, owner, repo, sha string) ([]*gg.PullRequest, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.ListPullRequestsWithCommit")
	defer span.End()

	prs, resp, err := ac.getRESTClient(ctx).PullRequests.ListPullRequestsWithCommit(ctx, owner, repo, sha, nil)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to list pull requests with commit")
	}

	return prs, nil
}

// GetIssue retrieves an issue by owner, repo, and number.
func (ac *Client) GetIssue(ctx context.Context, ownerLogin, repoName string, number int) (*gg.Issue, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetIssue")
	defer span.End()

	issue, resp, err := ac.getRESTClient(ctx).Issues.Get(ctx, ownerLogin, repoName, number)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to get issue")
	}
	return issue, nil
}

// AssignToIssue assigns a user to an issue.
func (ac *Client) AssignToIssue(ctx context.Context, ownerLogin, repoName string, issueNumber int, assignee string) error {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.AssignToIssue")
	defer span.End()

	_, resp, err := ac.getRESTClient(ctx).Issues.AddAssignees(ctx, ownerLogin, repoName, issueNumber, []string{assignee})
	if err != nil {
		return ac.checkError(ctx, resp, err, "failed to assign issue")
	}
	return nil
}

// RemoveReactionFromIssue removes a reaction from an issue.
func (ac *Client) RemoveReactionFromIssue(ctx context.Context, owner, repo string, number int, isAgentic agenticapp.IsAgenticFunc) error {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.RemoveReactionFromIssue")
	defer span.End()

	opts := &gg.ListReactionOptions{Content: "eyes"}
	reactions, resp, err := ac.getRESTClient(ctx).Reactions.ListIssueReactions(ctx, owner, repo, number, opts)
	if err != nil {
		return ac.checkError(ctx, resp, err, "failed to list reactions")
	}

	var reaction *gg.Reaction
	for _, r := range reactions {
		_, isAgenticUser := isAgentic(r.User)
		if r.User.GetLogin() != "" && isAgenticUser {
			reaction = r
			break
		}
	}
	if reaction != nil {
		resp, err = ac.getRESTClient(ctx).Reactions.DeleteIssueReaction(ctx, owner, repo, number, reaction.GetID())
		if err != nil {
			return ac.checkError(ctx, resp, err, "failed to delete reaction")
		}
	}

	return nil
}

// GetWorkflowRunByID retrieves a workflow run by ID.
func (ac *Client) GetWorkflowRunByID(ctx context.Context, ownerLogin, repoName string, runID int64) (*gg.WorkflowRun, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetWorkflowRunByID")
	defer span.End()

	run, resp, err := ac.getRESTClient(ctx).Actions.GetWorkflowRunByID(ctx, ownerLogin, repoName, runID)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to get workflow run")
	}
	return run, nil
}

// ErrWorkflowRunAlreadyCompleted is returned when a cancel request receives a 409,
// indicating the workflow run is already in a terminal state. Callers should handle
// this by finalizing the job directly rather than waiting for a workflow_run_completed event.
var ErrWorkflowRunAlreadyCompleted = goerrors.New("workflow run is already completed")

// CancelWorkflowRunByID cancels a workflow run by ID.
func (ac *Client) CancelWorkflowRunByID(ctx context.Context, ownerLogin, repoName string, runID int64) error {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.CancelWorkflowRunByID")
	defer span.End()

	// TODO (houndie): Once actions fixes
	// https://github.com/github/actions-dispatch/issues/370, retrying here should
	// no longer be necessary.  We're doing retries to try and work around this and
	// avoid random 500s on our end.
	resp, err := ac.getRESTClient(ctx).Actions.CancelWorkflowRunByID(withRetryableEndpoint(ctx), ownerLogin, repoName, runID)
	if err != nil {
		// This call can result in an "accepted error" that says that the cancellation has been queued,
		// but it comes back as an error saying its fully cancelled. Since we do not need to wait for
		// the cancellation to actually be complete, treat this as a success condition instead.
		var acceptedErr *gg.AcceptedError
		if errors.As(err, &acceptedErr) && resp.StatusCode == http.StatusAccepted {
			return nil
		}
		// The Cancel endpoint returns 409 Conflict if the workflow run is already completed.
		// Return a sentinel error so callers can finalize the job directly instead of waiting
		// for a workflow_run_completed event that will never arrive.
		if resp != nil && resp.StatusCode == http.StatusConflict {
			return ErrWorkflowRunAlreadyCompleted
		}
		return ac.checkError(ctx, resp, err, "failed to cancel workflow run")
	}
	return nil
}

// AddLabelsToIssueOrPR adds labels to an issue or pull request.
func (ac *Client) AddLabelsToIssueOrPR(ctx context.Context, ownerLogin, repoName string, issueOrPRNumber int, labels []string) error {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.AddLabelsToIssueOrPR")
	defer span.End()

	_, resp, err := ac.getRESTClient(ctx).Issues.AddLabelsToIssue(ctx, ownerLogin, repoName, issueOrPRNumber, labels)
	if err != nil {
		return ac.checkError(ctx, resp, err, "failed to add labels to issue or PR")
	}
	return nil
}

// DynamicWorkflowRun represents a dynamic workflow run response.
type DynamicWorkflowRun struct {
	ExecutionID   *string        `json:"execution_id"`
	WorkflowRunID *int64         `json:"workflow_run_id"`
	Repository    *gg.Repository `json:"repository"`
	Ref           *string        `json:"ref"`
	Slug          *string        `json:"slug"`
	WorkflowName  *string        `json:"workflow_name"`
	Workflow      *string        `json:"workflow"`
}

// NewDynamicWorkflowRun represents the options for creating a dynamic workflow run.
type NewDynamicWorkflowRun struct {
	Ref           *string            `json:"ref"`
	Slug          *string            `json:"slug"`
	WorkflowName  *string            `json:"workflow_name"`
	Workflow      *string            `json:"workflow"`
	Inputs        *map[string]string `json:"inputs"`
	PreventReruns bool               `json:"prevent_reruns,omitempty"`
	// ActorID is the bot ID of the third-party agent to use as the actor for the workflow run.
	// When set, the workflow runs on behalf of this actor instead of the authenticated app.
	// This is used for third-party agents where we authenticate as Copilot but act as the 3P agent.
	ActorID *int64 `json:"actor_id,omitempty"`
}

// CreateDynamicWorkflowRun creates a new dynamic workflow run.
// Note: This method always uses the internal API client because it calls an internal-only endpoint.
func (ac *Client) CreateDynamicWorkflowRun(ctx context.Context, owner, repo string, repoID int64, useRepoID bool, opts *NewDynamicWorkflowRun) (*DynamicWorkflowRun, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.CreateDynamicWorkflowRun")
	defer span.End()

	var url string
	if useRepoID {
		url = fmt.Sprintf("internal/repositories/%d/actions/dynamic", repoID)
	} else {
		url = fmt.Sprintf("internal/repos/%s/%s/actions/dynamic", owner, repo)
	}
	// Always use internal client for internal API endpoints
	client := ac.internalClient

	requestOpts := []gg.RequestOption{
		func(req *http.Request) {
			req.Header.Add(hmac.RequestHeader, hmac.NewRequestHMAC(ac.dynamicWorkflowsHmacSecret).String())
		},
	}

	req, err := client.NewRequest(http.MethodPost, url, opts, requestOpts...)
	if err != nil {
		return nil, err
	}

	run := new(DynamicWorkflowRun)
	resp, err := client.Do(ctx, req, run)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to create dynamic workflow run")
	}

	return run, nil
}

// ListWorkflowJobs lists jobs for a workflow run.
func (ac *Client) ListWorkflowJobs(ctx context.Context, owner, repo string, runID int64) ([]*gg.WorkflowJob, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.ListWorkflowJobs")
	defer span.End()

	jobs, resp, err := ac.getRESTClient(ctx).Actions.ListWorkflowJobs(ctx, owner, repo, runID, nil)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to list workflow jobs")
	}
	return jobs.Jobs, err
}

// GetWorkflowJobByID retrieves a workflow job by ID.
func (ac *Client) GetWorkflowJobByID(ctx context.Context, owner, repo string, jobID int64) (*gg.WorkflowJob, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetWorkflowJobByID")
	defer span.End()

	job, resp, err := ac.getRESTClient(ctx).Actions.GetWorkflowJobByID(ctx, owner, repo, jobID)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to get workflow job by ID")
	}
	return job, nil
}

// ListCheckRunAnnotations lists annotations for a check run.
func (ac *Client) ListCheckRunAnnotations(ctx context.Context, owner, repo string, jobID int64) ([]*gg.CheckRunAnnotation, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.ListCheckRunAnnotations")
	defer span.End()

	annotations, resp, err := ac.getRESTClient(ctx).Checks.ListCheckRunAnnotations(ctx, owner, repo, jobID, &gg.ListOptions{PerPage: 100})
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to list check run annotations")
	}
	return annotations, nil
}

// GetUserByID retrieves a user by their ID.
func (ac *Client) GetUserByID(ctx context.Context, id uint64) (*gg.User, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetUserByID")
	defer span.End()

	user, resp, err := ac.getRESTClient(ctx).Users.GetByID(ctx, int64(id))
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to get user by ID")
	}
	return user, nil
}

// DeleteRepo deletes a repository.
func (ac *Client) DeleteRepo(ctx context.Context, owner, repo string) error {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.DeleteRepo")
	defer span.End()

	resp, err := ac.getRESTClient(ctx).Repositories.Delete(ctx, owner, repo)
	if err != nil {
		return ac.checkError(ctx, resp, err, "failed to delete repository")
	}
	return nil
}

// CreateRepo creates a new repository in an organization.
func (ac *Client) CreateRepo(ctx context.Context, org, name string, autoinit bool) (*gg.Repository, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.CreateRepo")
	defer span.End()

	repo := &gg.Repository{
		Name:     gg.Ptr(name),
		AutoInit: gg.Ptr(autoinit),
	}
	repo, resp, err := ac.getRESTClient(ctx).Repositories.Create(ctx, org, repo)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to create repository")
	}
	return repo, nil
}

// CreateIssue creates a new issue in a repository.
func (ac *Client) CreateIssue(ctx context.Context, owner, repo, title, body string) (*gg.Issue, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.CreateIssue")
	defer span.End()

	req := &gg.IssueRequest{
		Title: gg.Ptr(title),
		Body:  gg.Ptr(body),
	}
	issue, resp, err := ac.getRESTClient(ctx).Issues.Create(ctx, owner, repo, req)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to create issue")
	}
	return issue, nil
}

// GetPullRequests retrieves pull requests from a repository.
func (ac *Client) GetPullRequests(ctx context.Context, owner, repo string, opts *gg.PullRequestListOptions) ([]*gg.PullRequest, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetPullRequests")
	defer span.End()

	prs, resp, err := ac.getRESTClient(ctx).PullRequests.List(ctx, owner, repo, opts)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to list pull requests")
	}
	return prs, nil
}

// GetContents retrieves the contents of a file or directory in a repository.
func (ac *Client) GetContents(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetContents")
	defer span.End()

	fileContent, dirContent, resp, err := ac.getRESTClient(ctx).Repositories.GetContents(ctx, owner, repo, path, opts)
	if err != nil {
		return nil, nil, ac.checkError(ctx, resp, err, "failed to get contents")
	}
	return fileContent, dirContent, nil
}

// UpdateFile updates a file in a repository.
func (ac *Client) UpdateFile(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentFileOptions) (*gg.RepositoryContentResponse, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.UpdateFile")
	defer span.End()

	content, resp, err := ac.getRESTClient(ctx).Repositories.UpdateFile(ctx, owner, repo, path, opts)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to update file")
	}
	return content, nil
}

// GetAuthenticatedUser retrieves the currently authenticated user.
func (ac *Client) GetAuthenticatedUser(ctx context.Context) (*gg.User, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetAuthenticatedUser")
	defer span.End()

	user, resp, err := ac.getRESTClient(ctx).Users.Get(ctx, "")
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to get authenticated user")
	}
	return user, nil
}

// GetCopilotEnvironmentSecretsAndVariables retrieves secrets and variables from the Copilot environment.
func (ac *Client) GetCopilotEnvironmentSecretsAndVariables(ctx context.Context, owner, repo string, repoID int64) (secrets, variables []string, err error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetCopilotEnvironmentSecretsAndVariables")
	defer span.End()

	_, resp, err := ac.getRESTClient(ctx).Repositories.GetEnvironment(ctx, owner, repo, CopilotEnvironmentName)
	if err != nil {
		if resp != nil && resp.StatusCode == http.StatusNotFound {
			ac.obsv.LoggerWithTelemetry(ctx).Warn("Copilot environment not found")
			return []string{}, []string{}, nil
		}
		ac.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("Failed to get Copilot environment")
		return nil, nil, ac.checkError(ctx, resp, err, "failed to get Copilot environment")
	}

	listOpts := &gg.ListOptions{PerPage: 100}

	secs, resp, err := ac.getRESTClient(ctx).Actions.ListEnvSecrets(ctx, int(repoID), CopilotEnvironmentName, listOpts)
	if err != nil {
		return nil, nil, ac.checkError(ctx, resp, err, "failed to list Copilot environment secrets")
	}
	for _, s := range secs.Secrets {
		secrets = append(secrets, s.Name)
	}

	vars, resp, err := ac.getRESTClient(ctx).Actions.ListEnvVariables(ctx, owner, repo, CopilotEnvironmentName, listOpts)
	if err != nil {
		return nil, nil, ac.checkError(ctx, resp, err, "failed to list Copilot environment variables")
	}
	for _, v := range vars.Variables {
		variables = append(variables, v.Name)
	}

	return secrets, variables, nil
}

// agentSecretsResponse represents the response from the agent secrets API.
type agentSecretsResponse struct {
	Secrets []struct {
		Name string `json:"name"`
	} `json:"secrets"`
}

// agentVariablesResponse represents the response from the agent variables API.
type agentVariablesResponse struct {
	Variables []struct {
		Name string `json:"name"`
	} `json:"variables"`
}

// GetAgentSecretsAndVariables retrieves secrets and variables from the agent secrets API.
// If isRepoOwnedByOrganization is true, it also fetches organization-level secrets and variables.
func (ac *Client) GetAgentSecretsAndVariables(ctx context.Context, owner, repo string, isRepoOwnedByOrganization bool) (secrets, variables []string, err error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetAgentSecretsAndVariables")
	defer span.End()

	logger := ac.obsv.LoggerWithTelemetry(ctx)

	// Fetch repo-level agent secrets (paginated)
	repoSecrets, err := ac.fetchAllAgentSecrets(ctx, fmt.Sprintf("repos/%s/%s/agents/secrets", owner, repo))
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to list agent secrets: %w", err)
	}
	secrets = append(secrets, repoSecrets...)

	// Fetch repo-level agent variables (paginated)
	repoVars, err := ac.fetchAllAgentVariables(ctx, fmt.Sprintf("repos/%s/%s/agents/variables", owner, repo))
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to list agent variables: %w", err)
	}
	variables = append(variables, repoVars...)

	var orgSecrets, orgVars []string
	if isRepoOwnedByOrganization {
		orgSecrets, err = ac.fetchAllAgentSecrets(ctx, fmt.Sprintf("repos/%s/%s/agents/organization-secrets", owner, repo))
		if err != nil {
			return nil, nil, goerrors.Errorf("failed to list org agent secrets: %w", err)
		}
		secrets = append(secrets, orgSecrets...)

		orgVars, err = ac.fetchAllAgentVariables(ctx, fmt.Sprintf("repos/%s/%s/agents/organization-variables", owner, repo))
		if err != nil {
			return nil, nil, goerrors.Errorf("failed to list org agent variables: %w", err)
		}
		variables = append(variables, orgVars...)
	}

	logger.Info("fetched agent secrets and variables",
		kvp.Int("repo_secrets", len(repoSecrets)),
		kvp.Int("repo_variables", len(repoVars)),
		kvp.Int("org_secrets", len(orgSecrets)),
		kvp.Int("org_variables", len(orgVars)))

	return secrets, variables, nil
}

// fetchAllAgentSecrets fetches all agent secrets from the given endpoint URL, handling pagination.
// Returns an empty slice (not an error) if the endpoint returns 404.
// Fetches at most maxAgentPaginationPages pages to avoid unbounded iteration.
func (ac *Client) fetchAllAgentSecrets(ctx context.Context, endpointURL string) ([]string, error) {
	var allSecrets []string
	page := 1
	for range maxAgentPaginationPages {
		url := fmt.Sprintf("%s?per_page=100&page=%d", endpointURL, page)
		req, err := ac.getRESTClient(ctx).NewRequest(http.MethodGet, url, nil)
		if err != nil {
			return nil, goerrors.Errorf("failed to create request: %w", err)
		}
		var result agentSecretsResponse
		resp, err := ac.getRESTClient(ctx).Do(ctx, req, &result)
		if err != nil {
			if resp != nil && resp.StatusCode == http.StatusNotFound {
				return nil, nil
			}
			return nil, ac.checkError(ctx, resp, err, "failed to fetch agent secrets")
		}
		for _, s := range result.Secrets {
			allSecrets = append(allSecrets, s.Name)
		}
		if resp == nil || resp.NextPage == 0 {
			break
		}
		page = resp.NextPage
	}
	return allSecrets, nil
}

// fetchAllAgentVariables fetches all agent variables from the given endpoint URL, handling pagination.
// Returns an empty slice (not an error) if the endpoint returns 404.
// Fetches at most maxAgentPaginationPages pages to avoid unbounded iteration.
func (ac *Client) fetchAllAgentVariables(ctx context.Context, endpointURL string) ([]string, error) {
	var allVariables []string
	page := 1
	for range maxAgentPaginationPages {
		url := fmt.Sprintf("%s?per_page=100&page=%d", endpointURL, page)
		req, err := ac.getRESTClient(ctx).NewRequest(http.MethodGet, url, nil)
		if err != nil {
			return nil, goerrors.Errorf("failed to create request: %w", err)
		}
		var result agentVariablesResponse
		resp, err := ac.getRESTClient(ctx).Do(ctx, req, &result)
		if err != nil {
			if resp != nil && resp.StatusCode == http.StatusNotFound {
				return nil, nil
			}
			return nil, ac.checkError(ctx, resp, err, "failed to fetch agent variables")
		}
		for _, v := range result.Variables {
			allVariables = append(allVariables, v.Name)
		}
		if resp == nil || resp.NextPage == 0 {
			break
		}
		page = resp.NextPage
	}
	return allVariables, nil
}

type agentVariableValueResponse struct {
	Name  string `json:"name"`
	Value string `json:"value"`
}

// GetAgentVariableValue retrieves the value of a specific agent variable from the agent variables API.
// If isRepoOwnedByOrganization is true, it will also try an organization-level variable if no repo-level value is found.
func (ac *Client) GetAgentVariableValue(ctx context.Context, owner, repo, variableName string, isRepoOwnedByOrganization bool) (string, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetAgentVariableValue")
	defer span.End()

	logger := ac.obsv.LoggerWithTelemetry(ctx)

	// Fetch repo-level agent variable value
	val, err := ac.fetchAgentVariableValue(ctx, fmt.Sprintf("repos/%s/%s/agents/variables/%s", owner, repo, variableName))
	if err != nil {
		return "", goerrors.Errorf("failed to get agent variable: %w", err)
	}
	if val != "" {
		return val, nil
	}
	if !isRepoOwnedByOrganization {
		logger.Info("no repo-level value for variable found", kvp.String("variable_name", variableName))
		return "", nil
	}

	// Fetch org-level agent variable value
	val, err = ac.fetchAgentVariableValue(ctx, fmt.Sprintf("orgs/%s/agents/variables/%s", owner, variableName))
	if err != nil {
		return "", goerrors.Errorf("failed to get agent variable: %w", err)
	}
	if val != "" {
		return val, nil
	}

	logger.Info("no repo or org-level value for variable found", kvp.String("variable_name", variableName))
	return "", nil
}

// fetchAgentVariableValue fetches a specific agent variable from the given endpoint URL.
// Returns an empty string (not an error) if the endpoint returns 404.
func (ac *Client) fetchAgentVariableValue(ctx context.Context, endpointURL string) (string, error) {
	req, err := ac.getRESTClient(ctx).NewRequest(http.MethodGet, endpointURL, nil)
	if err != nil {
		return "", goerrors.Errorf("failed to create request: %w", err)
	}
	var result agentVariableValueResponse
	resp, err := ac.getRESTClient(ctx).Do(ctx, req, &result)
	if err != nil {
		if resp != nil && resp.StatusCode == http.StatusNotFound {
			return "", nil
		}
		return "", ac.checkError(ctx, resp, err, "failed to fetch agent variable")
	}
	return result.Value, nil
}

// GetCopilotBotUser retrieves the bot user associated with the Copilot app.
func (ac *Client) GetCopilotBotUser(ctx context.Context) (*gg.User, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetCopilotBotUser")
	defer span.End()

	user, resp, err := ac.getRESTClient(ctx).Users.Get(ctx, ac.app.BotLogin())
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to get Copilot bot user")
	}
	return user, nil
}

// GetRepositoryPermissionLevel retrieves the permission level of a user for a repository by repository ID.
func (ac *Client) GetRepositoryPermissionLevel(ctx context.Context, repoID int64, username string) (*gg.RepositoryPermissionLevel, *gg.Response, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetRepositoryPermissionLevel")
	defer span.End()

	u := fmt.Sprintf("repositories/%d/collaborators/%s/permission", repoID, username)
	req, err := ac.getRESTClient(ctx).NewRequest(http.MethodGet, u, nil)
	if err != nil {
		return nil, nil, err
	}

	rpl := new(gg.RepositoryPermissionLevel)
	resp, err := ac.getRESTClient(ctx).Do(ctx, req, rpl)
	if err != nil {
		return nil, resp, ac.checkError(ctx, resp, err, "failed to get repository permission level")
	}

	return rpl, resp, nil
}

// RepositoryPermissions represents the permissions of an actor on a repository.
// [Client.GetUserPermissionsForRepository] returns some of these as a map[string]bool,
// this struct flattens them out for easier access.
type RepositoryPermissions struct {
	// Permission provides the legacy base roles of admin, write, read, and none,
	// where the maintain role is mapped to write and the triage role is mapped to read.
	Permission string `json:"permission,omitempty"`
	// Role provides the full role name, including custom roles.
	Role     string `json:"role_name,omitempty"`
	Pull     bool   `json:"pull"`
	Triage   bool   `json:"triage"`
	Push     bool   `json:"push"`
	Maintain bool   `json:"maintain"`
	Admin    bool   `json:"admin"`
}

// GetUserPermissionsForRepository retrieves the permissions of a user for a repository.
func (ac *Client) GetUserPermissionsForRepository(ctx context.Context, owner, repo, username string) (*RepositoryPermissions, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetUserPermissionsForRepository")
	defer span.End()

	perm, resp, err := ac.getRESTClient(ctx).Repositories.GetPermissionLevel(ctx, owner, repo, username)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to get user permissions for repository")
	}

	permissions := getRepositoryPermissions(perm)

	return permissions, nil
}

// GetUserPermissionsForRepositoryByID retrieves the permissions of a user for a repository by repository ID.
func (ac *Client) GetUserPermissionsForRepositoryByID(ctx context.Context, repoID int64, username string) (*RepositoryPermissions, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetUserPermissionsForRepositoryByID")
	defer span.End()

	perm, resp, err := ac.GetRepositoryPermissionLevel(ctx, repoID, username)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to get user permissions for repository by ID")
	}

	permissions := getRepositoryPermissions(perm)

	return permissions, nil
}

func getRepositoryPermissions(perm *gg.RepositoryPermissionLevel) *RepositoryPermissions {
	permissions := perm.User.GetPermissions()

	return &RepositoryPermissions{
		Permission: perm.GetPermission(),
		Role:       perm.GetRoleName(),
		Admin:      permissions["admin"],
		Maintain:   permissions["maintain"],
		Push:       permissions["push"],
		Triage:     permissions["triage"],
		Pull:       permissions["pull"],
	}
}

// IsBranchRulesRequiresProOrPublic checks if an error indicates that branch rules
// require a GitHub Pro subscription or public repository.
func IsBranchRulesRequiresProOrPublic(err error) bool {
	if err == nil {
		return false
	}
	var e *gg.ErrorResponse
	if errors.As(err, &e) && e.Response != nil {
		return e.Response.StatusCode == http.StatusForbidden &&
			// go-github uses this approach to identify specific errors
			strings.HasSuffix(e.DocumentationURL, "#get-rules-for-a-branch") &&
			// full message will be:
			// "Upgrade to GitHub Pro or make this repository public to enable this feature."
			strings.Contains(e.Message, "Upgrade to GitHub Pro or make this repository public to enable this feature")
	}
	return false
}

// ListRepositoryRulesForBranch retrieves repository rules for a specific branch.
func (ac *Client) ListRepositoryRulesForBranch(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.ListRepositoryRulesForBranch")
	defer span.End()

	var allRules *gg.BranchRules
	// Using max for page size https://docs.github.com/en/rest/repos/rules?apiVersion=2022-11-28#get-all-repository-rulesets
	opts := &gg.ListOptions{PerPage: 100}
	for {
		rules, resp, err := ac.getRESTClient(ctx).Repositories.GetRulesForBranch(ctx, ownerLogin, repoName, branchName, opts)
		if err != nil {
			// If we get a 403 error, it may be because the repository is private
			// and the feature isn't available for private repo on the user's plan.
			// This at least tells us that there are no rules we need to worry about.
			if IsBranchRulesRequiresProOrPublic(err) {
				ac.obsv.LoggerWithTelemetry(ctx).Warn("Branch rules require GitHub Pro or Public repository")
				return nil, nil
			}
			return nil, ac.checkError(ctx, resp, err, "failed to list repository rules for branch")
		}
		if rules != nil {
			// Filter out rules from excluded rulesets before merging
			filteredRules := filterBranchRulesByRulesetID(rules, excludeRulesetIDs)
			allRules = mergeBranchRules(allRules, filteredRules)
		}
		if resp == nil || resp.NextPage == 0 {
			break
		}
		opts.Page = resp.NextPage
	}

	return allRules, nil
}

func mergeBranchRules(rules1, rules2 *gg.BranchRules) *gg.BranchRules {
	if rules2 == nil {
		return rules1
	}
	if rules1 == nil {
		return rules2
	}
	mergedRules := &gg.BranchRules{
		Creation:                 append(rules1.Creation, rules2.Creation...),
		Update:                   append(rules1.Update, rules2.Update...),
		Deletion:                 append(rules1.Deletion, rules2.Deletion...),
		RequiredLinearHistory:    append(rules1.RequiredLinearHistory, rules2.RequiredLinearHistory...),
		MergeQueue:               append(rules1.MergeQueue, rules2.MergeQueue...),
		RequiredDeployments:      append(rules1.RequiredDeployments, rules2.RequiredDeployments...),
		RequiredSignatures:       append(rules1.RequiredSignatures, rules2.RequiredSignatures...),
		PullRequest:              append(rules1.PullRequest, rules2.PullRequest...),
		RequiredStatusChecks:     append(rules1.RequiredStatusChecks, rules2.RequiredStatusChecks...),
		NonFastForward:           append(rules1.NonFastForward, rules2.NonFastForward...),
		CommitMessagePattern:     append(rules1.CommitMessagePattern, rules2.CommitMessagePattern...),
		CommitAuthorEmailPattern: append(rules1.CommitAuthorEmailPattern, rules2.CommitAuthorEmailPattern...),
		CommitterEmailPattern:    append(rules1.CommitterEmailPattern, rules2.CommitterEmailPattern...),
		BranchNamePattern:        append(rules1.BranchNamePattern, rules2.BranchNamePattern...),
		TagNamePattern:           append(rules1.TagNamePattern, rules2.TagNamePattern...),
		FilePathRestriction:      append(rules1.FilePathRestriction, rules2.FilePathRestriction...),
		MaxFilePathLength:        append(rules1.MaxFilePathLength, rules2.MaxFilePathLength...),
		FileExtensionRestriction: append(rules1.FileExtensionRestriction, rules2.FileExtensionRestriction...),
		MaxFileSize:              append(rules1.MaxFileSize, rules2.MaxFileSize...),
		Workflows:                append(rules1.Workflows, rules2.Workflows...),
		CodeScanning:             append(rules1.CodeScanning, rules2.CodeScanning...),
	}
	return mergedRules
}

// ruleWithRulesetID is an interface for any rule type that has a RulesetID field
type ruleWithRulesetID interface {
	*gg.BranchRuleMetadata |
		*gg.UpdateBranchRule |
		*gg.PullRequestBranchRule |
		*gg.CodeScanningBranchRule |
		*gg.PatternBranchRule |
		*gg.MergeQueueBranchRule |
		*gg.RequiredDeploymentsBranchRule |
		*gg.RequiredStatusChecksBranchRule |
		*gg.FilePathRestrictionBranchRule |
		*gg.MaxFilePathLengthBranchRule |
		*gg.FileExtensionRestrictionBranchRule |
		*gg.MaxFileSizeBranchRule |
		*gg.WorkflowsBranchRule
}

// filterRules filters out rules that belong to excluded rulesets
func filterRules[T ruleWithRulesetID](rules []T, shouldExclude func(int64) bool) []T {
	filtered := make([]T, 0, len(rules))
	for _, rule := range rules {
		var rulesetID int64
		switch r := any(rule).(type) {
		case *gg.BranchRuleMetadata:
			rulesetID = r.RulesetID
		case *gg.UpdateBranchRule:
			rulesetID = r.RulesetID
		case *gg.PullRequestBranchRule:
			rulesetID = r.RulesetID
		case *gg.CodeScanningBranchRule:
			rulesetID = r.RulesetID
		case *gg.PatternBranchRule:
			rulesetID = r.RulesetID
		case *gg.MergeQueueBranchRule:
			rulesetID = r.RulesetID
		case *gg.RequiredDeploymentsBranchRule:
			rulesetID = r.RulesetID
		case *gg.RequiredStatusChecksBranchRule:
			rulesetID = r.RulesetID
		case *gg.FilePathRestrictionBranchRule:
			rulesetID = r.RulesetID
		case *gg.MaxFilePathLengthBranchRule:
			rulesetID = r.RulesetID
		case *gg.FileExtensionRestrictionBranchRule:
			rulesetID = r.RulesetID
		case *gg.MaxFileSizeBranchRule:
			rulesetID = r.RulesetID
		case *gg.WorkflowsBranchRule:
			rulesetID = r.RulesetID
		}
		if !shouldExclude(rulesetID) {
			filtered = append(filtered, rule)
		}
	}
	return filtered
}

// filterBranchRulesByRulesetID filters out rules that belong to excluded rulesets
func filterBranchRulesByRulesetID(rules *gg.BranchRules, excludeRulesetIDs []uint64) *gg.BranchRules {
	if rules == nil || len(excludeRulesetIDs) == 0 {
		return rules
	}

	shouldExclude := func(rulesetID int64) bool {
		return slices.Contains(excludeRulesetIDs, uint64(rulesetID))
	}

	filtered := &gg.BranchRules{}

	// Filter each rule type using the generic helper
	filtered.Creation = filterRules(rules.Creation, shouldExclude)
	filtered.Update = filterRules(rules.Update, shouldExclude)
	filtered.Deletion = filterRules(rules.Deletion, shouldExclude)
	filtered.RequiredLinearHistory = filterRules(rules.RequiredLinearHistory, shouldExclude)
	filtered.MergeQueue = filterRules(rules.MergeQueue, shouldExclude)
	filtered.RequiredDeployments = filterRules(rules.RequiredDeployments, shouldExclude)
	filtered.RequiredSignatures = filterRules(rules.RequiredSignatures, shouldExclude)
	filtered.PullRequest = filterRules(rules.PullRequest, shouldExclude)
	filtered.RequiredStatusChecks = filterRules(rules.RequiredStatusChecks, shouldExclude)
	filtered.NonFastForward = filterRules(rules.NonFastForward, shouldExclude)
	filtered.CommitMessagePattern = filterRules(rules.CommitMessagePattern, shouldExclude)
	filtered.CommitAuthorEmailPattern = filterRules(rules.CommitAuthorEmailPattern, shouldExclude)
	filtered.CommitterEmailPattern = filterRules(rules.CommitterEmailPattern, shouldExclude)
	filtered.BranchNamePattern = filterRules(rules.BranchNamePattern, shouldExclude)
	filtered.TagNamePattern = filterRules(rules.TagNamePattern, shouldExclude)
	filtered.FilePathRestriction = filterRules(rules.FilePathRestriction, shouldExclude)
	filtered.MaxFilePathLength = filterRules(rules.MaxFilePathLength, shouldExclude)
	filtered.FileExtensionRestriction = filterRules(rules.FileExtensionRestriction, shouldExclude)
	filtered.MaxFileSize = filterRules(rules.MaxFileSize, shouldExclude)
	filtered.Workflows = filterRules(rules.Workflows, shouldExclude)
	filtered.CodeScanning = filterRules(rules.CodeScanning, shouldExclude)

	return filtered
}

// GetActionsPermissions retrieves the GitHub Actions permissions for a repository.
func (ac *Client) GetActionsPermissions(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetActionsPermissions")
	defer span.End()

	permissions, resp, err := ac.getRESTClient(ctx).Repositories.GetActionsPermissions(ctx, ownerLogin, repoName)
	if err != nil {
		return nil, ac.checkError(ctx, resp, err, "failed to get actions permissions for repository")
	}
	return permissions, nil
}

// BranchNameFromHeadRef extracts the bare branch name from a HeadRef that
// may contain an "owner:" prefix (used for fork PRs). For example,
// "john:feature-x" returns "feature-x", while "feature-branch" is returned
// as-is. If the branch part after ":" is empty (e.g. "owner:"), the original
// headRef is returned unchanged.
func BranchNameFromHeadRef(headRef string) string {
	if owner, branch, ok := strings.Cut(headRef, ":"); ok && owner != "" && branch != "" {
		return branch
	}
	return headRef
}

// isForkHeadRef returns true if headRef is in "owner:branch" format with both
// parts non-empty, indicating a fork PR.
func isForkHeadRef(headRef string) bool {
	owner, branch, ok := strings.Cut(headRef, ":")
	return ok && owner != "" && branch != ""
}

// LookupExistingPRForHeadRef finds an open pull request whose head branch
// matches the given headRef and whose base branch matches baseRef.
//
// headRef may be either a plain branch name (e.g. "feature-branch") for
// same-repo PRs, or an "owner:branch" qualified ref (e.g. "john:feature-x")
// for fork PRs. For plain branch names the base repo owner is prepended
// automatically; for qualified refs the value is passed directly to the
// GitHub API Head filter.
//
// When multiple PRs share the same head branch (e.g. targeting different
// base branches), or the single matching PR targets a different base, it
// returns nil to avoid linking the job to an unintended PR. The second
// return value indicates whether a mismatch or ambiguity was detected.
// Callers are responsible for logging and error handling policy (e.g.
// whether to clear HeadRef on failure).
func LookupExistingPRForHeadRef(ctx context.Context, gh ClientInterface, owner, repo, headRef, baseRef string) (*gg.PullRequest, bool, error) {
	// If headRef already contains "owner:branch" (fork PR), use it directly as the Head filter.
	// Otherwise, prepend the base repo owner for same-repo PRs.
	var head string
	if isForkHeadRef(headRef) {
		head = headRef
	} else {
		head = owner + ":" + headRef
	}

	prs, err := gh.GetPullRequests(ctx, owner, repo, &gg.PullRequestListOptions{
		Head:  head,
		State: "open",
	})
	if err != nil {
		return nil, false, err
	}
	if len(prs) == 0 {
		return nil, false, nil
	}
	// Normalize the base ref for comparison — the GitHub API returns bare
	// branch names (e.g. "main") while callers may pass qualified refs
	// (e.g. "refs/heads/main").
	normalizedBase := strings.TrimPrefix(baseRef, "refs/heads/")
	// Find the PR whose base matches the requested base ref. If none match,
	// return nil rather than guessing, to avoid linking the job to a PR
	// targeting an unexpected branch.
	for _, pr := range prs {
		if pr.GetBase().GetRef() == normalizedBase {
			return pr, len(prs) > 1, nil
		}
	}
	return nil, true, nil
}
