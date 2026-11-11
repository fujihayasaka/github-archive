//nolint:gosec // G404: This file uses math/rand for test mocking, not for security purposes
package github

import (
	"context"
	"fmt"
	"math/rand"
	"net/url"
	"strings"
	"time"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

// NewTestClientFactory returns a new ClientFactory without needing to pass in additional env vars.
func NewTestClientFactory(
	obsv observability.Exporters,
	githubCommitLogin, githubCommitEmail, githubAppLogin, githubBotLogin string,
	flags map[string]bool,
) (ClientFactoryInterface, error) {
	url, err := url.Parse("https://api.github.com/")
	if err != nil {
		return nil, err
	}
	return &ClientFactory{
		baseURL:  url,
		ffClient: featureflags.NewNoopClient(flags),
		obsv:     obsv,
	}, nil
}

// NoopClientFactory is a mock implementation of ClientFactoryInterface for testing purposes.
type NoopClientFactory struct {
	MockNewClient                           func(token string) ClientInterface
	MockNewClientFromRepo                   func(ctx context.Context, repoId, repoOwnerId int64) (ClientInterface, error)
	MockNewClientFromRepoName               func(ctx context.Context, app sweagentd.AgenticApp, repoName, ownerName string) (ClientInterface, error)
	MockGetRepository                       func(ctx context.Context, ownerName, repoName string) (*gg.Repository, error)
	MockGetActionsPermissions               func(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error)
	MockGetUserPermissionsForRepositoryByID func(ctx context.Context, repoID int64, login string) (*RepositoryPermissions, error)
	MockCreateNewEmptyBranch                func(ctx context.Context, ownerLogin, repoName, baseBranchName, branchName string) (*gg.Reference, error)
	GitHubAppID                             int64
	GitHubAppLogin                          string
	GitHubBotLogin                          string
	MockRepositoryContext                   *RepositoryContext
	MockRepositories                        *map[string]gg.Repository // owner/name or ID to content
	MockIssueContext                        *IssueContext
	MockPullRequestList                     []*gg.PullRequest
	MockPullRequestContext                  *PullRequestContext
	MockIssueUserContentEdits               []UserContentEdit
	MockPullRequest                         *gg.PullRequest // Mocked pull request for testing purposes
	MockWorkflowRun                         *gg.WorkflowRun // Mocked workflow run for testing purposes
}

// BaseURL returns the base URL of the factory.
func (cf *NoopClientFactory) BaseURL() *url.URL {
	u, _ := url.Parse("https://api.github.com/")
	return u
}

// AppID returns the GitHub App ID.
func (cf *NoopClientFactory) AppID() int64 {
	return cf.GitHubAppID
}

// NewClient creates a new NoopClient with the given token.
func (cf *NoopClientFactory) NewClient(token string) ClientInterface {
	target := sweagentd.ClientTargetForInstallationByOwnerID(cf.AppID(), 1234)
	return cf.newClient(token, target, nil)
}

// newClient creates a new NoopClient with the given token and target.
//
//nolint:funcorder // Helper method is placed near callers for readability
func (cf *NoopClientFactory) newClient(token string, target sweagentd.ClientTarget, app sweagentd.AgenticApp) ClientInterface {
	if cf.MockNewClient != nil {
		return cf.MockNewClient(token)
	}
	return &NoopClient{
		GithubAppLogin:                          cf.GitHubAppLogin,
		GithubBotLogin:                          cf.GitHubBotLogin,
		MockRepositoryContext:                   cf.MockRepositoryContext,
		MockRepositories:                        cf.MockRepositories,
		MockIssueContext:                        cf.MockIssueContext,
		MockPullRequestList:                     cf.MockPullRequestList,
		MockPullRequestContext:                  cf.MockPullRequestContext,
		MockGetActionsPermissions:               cf.MockGetActionsPermissions,
		MockGetRepository:                       cf.MockGetRepository,
		MockGetUserPermissionsForRepositoryByID: cf.MockGetUserPermissionsForRepositoryByID,
		MockCreateNewEmptyBranch:                cf.MockCreateNewEmptyBranch,
		MockIssueUserContentEdits:               cf.MockIssueUserContentEdits,
		MockPullRequest:                         cf.MockPullRequest,
		MockWorkflowRun:                         cf.MockWorkflowRun,
	}
}

// NewClientForRepo creates a new NoopClient for the given repository.
func (cf *NoopClientFactory) NewClientForRepo(ctx context.Context, app sweagentd.AgenticApp, repo sweagentd.Repository) (ClientInterface, error) {
	if cf.MockNewClientFromRepo != nil {
		return cf.MockNewClientFromRepo(ctx, repo.GetRepositoryID(), repo.GetOwnerID())
	}
	target := sweagentd.ClientTargetForInstallationByOwnerID(cf.AppID(), repo.GetOwnerID())

	return cf.newClient("test-repo-scoped-token", target, app), nil
}

// NewClientFromRepo creates a new NoopClient from the given repository ID and owner ID.
//
//nolint:revive // Parameter names must match interface definition (repoId, not repoID)
func (cf *NoopClientFactory) NewClientFromRepo(ctx context.Context, app sweagentd.AgenticApp, repoId, repoOwnerId int64) (ClientInterface, error) {
	if cf.MockNewClientFromRepo != nil {
		return cf.MockNewClientFromRepo(ctx, repoId, repoOwnerId)
	}
	target := sweagentd.ClientTargetForInstallationByOwnerID(cf.AppID(), repoOwnerId)
	return cf.newClient("test-repo-scoped-token", target, app), nil
}

func (cf *NoopClientFactory) NewClientFromRepoName(ctx context.Context, app sweagentd.AgenticApp, repoName, ownerName string, userID uint64) (ClientInterface, error) {
	if cf.MockNewClientFromRepoName != nil {
		return cf.MockNewClientFromRepoName(ctx, app, repoName, ownerName)
	}
	target := sweagentd.ClientTargetForInstallationByOwnerName(cf.AppID(), ownerName)
	return cf.newClient("test-repo-scoped-token", target, app), nil
}

// NewClientForUser creates a new NoopClient for the given user token.
func (cf *NoopClientFactory) NewClientForUser(token string, userID uint64, app sweagentd.AgenticApp) ClientInterface {
	target := sweagentd.ClientTargetForUser(cf.AppID(), int64(userID))
	return cf.newClient(token, target, app)
}

// MethodCall represents a method call made to the NoopClient for testing purposes.
type MethodCall struct {
	Method string
	Args   []any
}

// NoopClient is a mock implementation of ClientInterface for testing purposes.
type NoopClient struct {
	ClientInterface

	GithubAppLogin                          string
	GithubBotLogin                          string
	MockRepositoryContext                   *RepositoryContext
	MockRepositories                        *map[string]gg.Repository // owner/name or ID to content
	MockIssueContext                        *IssueContext
	MockPullRequestList                     []*gg.PullRequest
	MockPullRequestContext                  *PullRequestContext
	MockListBranchProtectionRules           func(ctx context.Context, repoNodeID string) (*[]GQLBranchProtectionRule, error)
	MockListRepositoryRulesForBranch        func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error)
	MockGetActionsPermissions               func(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error)
	MockGetWorkflowJobByID                  func(ctx context.Context, owner, repo string, jobID int64) (*gg.WorkflowJob, error)
	MockListWorkflowJobs                    func(ctx context.Context, owner, repo string, runID int64) ([]*gg.WorkflowJob, error)
	MockAddLabelsToIssueOrPR                func(ctx context.Context, ownerLogin, repoName string, issueNumber int, labels []string) error
	MockListCheckRunAnnotations             func(ctx context.Context, owner, repo string, jobID int64) ([]*gg.CheckRunAnnotation, error)
	MockCreateNewEmptyBranch                func(ctx context.Context, ownerLogin, repoName, baseBranchName, branchName string) (*gg.Reference, error)
	MockGetRepository                       func(ctx context.Context, ownerName, repoName string) (*gg.Repository, error)
	MockGetUserPermissionsForRepositoryByID func(ctx context.Context, repoID int64, login string) (*RepositoryPermissions, error)
	MockListUserOrgs                        func(ctx context.Context, user string) ([]*gg.Organization, error)
	MockIssueUserContentEdits               []UserContentEdit
	MockWorkflowRun                         *gg.WorkflowRun // Mocked workflow run for testing purposes
	MockPullRequest                         *gg.PullRequest
	MethodCalls                             []MethodCall // For testing purposes - a list of all the calls made to the client
	MockGetContents                         func(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error)
}

// HasMethodCall checks if a method with the given name was called on the NoopClient.
func (nc *NoopClient) HasMethodCall(method string) bool {
	for _, call := range nc.MethodCalls {
		if call.Method == method {
			return true
		}
	}
	return false
}

// HasNMethodCalls checks if a method with the given name was called exactly n times on the NoopClient.
func (nc *NoopClient) HasNMethodCalls(method string, n int) bool {
	count := 0
	for _, call := range nc.MethodCalls {
		if call.Method == method {
			count++
		}
	}
	return count == n
}

// Ensure NoopClient implements ClientInterface
var _ ClientFactoryInterface = &NoopClientFactory{}

// Ensure NoopClient implements ClientInterface
var _ ClientInterface = &NoopClient{}

// Token returns the token used in the GitHub client.
func (nc *NoopClient) Token() string {
	return "ghp_test_token"
}

// Committer returns a CommitAuthor with default test values.
func (nc *NoopClient) Committer() *gg.CommitAuthor {
	return &gg.CommitAuthor{
		Name:  gg.Ptr("test-committer"),
		Email: gg.Ptr("test@example.com"),
	}
}

// CreateNewEmptyBranch creates a new empty branch from a base branch.
func (nc *NoopClient) CreateNewEmptyBranch(ctx context.Context, ownerLogin, repoName, baseBranchName, branchName string) (*gg.Reference, error) {
	if nc.MockCreateNewEmptyBranch != nil {
		return nc.MockCreateNewEmptyBranch(ctx, ownerLogin, repoName, baseBranchName, branchName)
	}
	return &gg.Reference{
		Ref: gg.Ptr("refs/heads/" + branchName),
	}, nil
}

// CreateEmptyCommit creates an empty commit with default test values.
func (nc *NoopClient) CreateEmptyCommit(ctx context.Context, ownerLogin, repoName, branchName string) (*gg.Commit, error) {
	return &gg.Commit{
		SHA: gg.Ptr("sha"),
	}, nil
}

// CreatePullRequest creates a new pull request with the given options.
func (nc *NoopClient) CreatePullRequest(ctx context.Context, ownerLogin, repoName string, opts *gg.NewPullRequest) (*gg.PullRequest, error) {
	id := rand.Int63n(1000000)
	return &gg.PullRequest{
		ID:     &id,
		NodeID: gg.Ptr(fmt.Sprintf("test-pull-request-node-id-%d", id)),
		Title:  opts.Title,
		Body:   opts.Body,
		Number: gg.Ptr(2),
		Base: &gg.PullRequestBranch{
			SHA: gg.Ptr("base-sha"),
		},
		Head: &gg.PullRequestBranch{
			Ref: gg.Ptr("head-ref"),
		},
	}, nil
}

// UpdatePullRequest updates a pull request with the given options.
func (nc *NoopClient) UpdatePullRequest(ctx context.Context, repoID int64, pr *gg.PullRequest) (*gg.PullRequest, error) {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "UpdatePullRequest",
			Args:   []any{repoID, pr},
		})
	}()
	return pr, nil
}

// RequestReviewers requests reviewers for a pull request.
func (nc *NoopClient) RequestReviewers(ctx context.Context, ownerLogin, repoName string, number int, reviewers []string) error {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "RequestReviewers",
			Args:   []any{ownerLogin, repoName, number, reviewers},
		})
	}()

	return nil
}

// GetComment gets a comment by ID.
func (nc *NoopClient) GetComment(ctx context.Context, owner, repo string, commentID int64) (*gg.IssueComment, error) {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "GetComment",
			Args:   []any{owner, repo, commentID},
		})
	}()
	return &gg.IssueComment{
		ID:   &commentID,
		Body: gg.Ptr("test-comment-body"),
	}, nil
}

// CreateComment creates a new comment on an issue or PR.
func (nc *NoopClient) CreateComment(ctx context.Context, repoID int64, issueOrPRNumber int, body string) (*gg.IssueComment, error) {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "CreateComment",
			Args:   []any{repoID, issueOrPRNumber, body},
		})
	}()

	id := rand.Int63n(1000000)
	return &gg.IssueComment{
		ID:   &id,
		Body: gg.Ptr(body),
	}, nil
}

// DeleteComment deletes a comment by ID.
func (nc *NoopClient) DeleteComment(ctx context.Context, repoID, commentID int64) error {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "DeleteComment",
			Args:   []any{repoID, commentID},
		})
	}()
	return nil
}

// CreateCommentInReplyTo creates a new comment in reply to an existing PR comment.
func (nc *NoopClient) CreateCommentInReplyTo(ctx context.Context, owner, repo string, number int, body string, commentID int64) (*gg.PullRequestComment, error) {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "CreateCommentInReplyTo",
			Args:   []any{owner, repo, number, body, commentID},
		})
	}()

	id := rand.Int63n(1000000)
	return &gg.PullRequestComment{
		ID:   &id,
		Body: gg.Ptr(body),
	}, nil
}

// UpdateComment updates an existing comment.
func (nc *NoopClient) UpdateComment(ctx context.Context, owner, repo string, commentID int64, body string) (*gg.IssueComment, error) {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "UpdateComment",
			Args:   []any{owner, repo, commentID, body},
		})
	}()

	return &gg.IssueComment{
		ID:   &commentID,
		Body: gg.Ptr(body),
	}, nil
}

// UpdatePullRequestReviewComment updates an existing PR review comment.
func (nc *NoopClient) UpdatePullRequestReviewComment(ctx context.Context, owner, repo string, prNumber int, commentID int64, body string) (*gg.PullRequestComment, error) {
	return &gg.PullRequestComment{
		ID:   &commentID,
		Body: gg.Ptr(body),
	}, nil
}

// MarkPullRequestReadyForReview marks a PR as ready for review.
func (nc *NoopClient) MarkPullRequestReadyForReview(ctx context.Context, prNodeID string) error {
	return nil
}

// ConvertPullRequestToDraft converts a PR from ready to draft state.
func (nc *NoopClient) ConvertPullRequestToDraft(ctx context.Context, prNodeID string) error {
	return nil
}

// GetRepository gets a repository by owner and name.
func (nc *NoopClient) GetRepository(ctx context.Context, ownerName, repoName string) (*gg.Repository, error) {
	if nc.MockGetRepository != nil {
		return nc.MockGetRepository(ctx, ownerName, repoName)
	}
	if nc.MockRepositories != nil {
		key := fmt.Sprintf("%s/%s", ownerName, repoName)
		if repo, ok := (*nc.MockRepositories)[key]; ok {
			return &repo, nil
		}
		// Key not found in mock repositories, fall through to default
	}
	return &gg.Repository{
		ID:   gg.Ptr(int64(1)),
		Name: gg.Ptr(repoName),
		Owner: &gg.User{
			Login: gg.Ptr(ownerName),
		},
	}, nil
}

// GetRepositoryByID gets a repository by ID.
func (nc *NoopClient) GetRepositoryByID(ctx context.Context, id int64) (*gg.Repository, error) {
	return &gg.Repository{
		ID:            &id,
		Name:          gg.Ptr("test-repo"),
		NodeID:        gg.Ptr("test-repo-node-id"),
		DefaultBranch: gg.Ptr("main"),
		Owner: &gg.User{
			ID:     gg.Ptr(int64(1)),
			Login:  gg.Ptr("test-owner"),
			NodeID: gg.Ptr("test-owner-node-id"),
		},
	}, nil
}

// AddReaction adds a reaction to a GitHub entity.
func (nc *NoopClient) AddReaction(ctx context.Context, nodeID string, content GQLReactionContent) error {
	return nil
}

// RemoveReaction removes a reaction from a GitHub entity.
func (nc *NoopClient) RemoveReaction(ctx context.Context, nodeID string, content GQLReactionContent) error {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "RemoveReaction",
			Args:   []any{nodeID, content},
		})
	}()
	return nil
}

// MinimizeComment minimizes (hides) a comment.
func (nc *NoopClient) MinimizeComment(ctx context.Context, nodeID string, classifier GQLReportedContentClassifier) error {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "MinimizeComment",
			Args:   []any{nodeID, classifier},
		})
	}()
	return nil
}

// UnminimizeComment unminimizes (unhides) a comment.
func (nc *NoopClient) UnminimizeComment(ctx context.Context, nodeID string) error {
	return nil
}

// GetWorkflowRunLogs gets the logs for a workflow run.
func (nc *NoopClient) GetWorkflowRunLogs(ctx context.Context, owner, repo string, runID int64) (string, error) {
	return "logs", nil
}

// GetPullRequest gets a pull request by repository ID and number.
func (nc *NoopClient) GetPullRequest(ctx context.Context, repoID int64, number int) (*gg.PullRequest, error) {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "GetPullRequest",
			Args:   []any{repoID, number},
		})
	}()
	if nc.MockPullRequest != nil {
		return nc.MockPullRequest, nil
	}
	return &gg.PullRequest{
		ID:     gg.Ptr(int64(1)),
		Number: gg.Ptr(number),
		Draft:  gg.Ptr(true),
		URL:    gg.Ptr("test-pull-request-url"),
		Title:  gg.Ptr("test-pull-request"),
		Body:   gg.Ptr("test-pull-request-body"),
		Base: &gg.PullRequestBranch{
			SHA: gg.Ptr("base-sha"),
		},
		Head: &gg.PullRequestBranch{
			Ref: gg.Ptr("head-ref"),
		},
	}, nil
}

// GetIssue gets an issue by repository and issue number.
func (nc *NoopClient) GetIssue(ctx context.Context, ownerLogin, repoName string, number int) (*gg.Issue, error) {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "GetIssue",
			Args:   []any{ownerLogin, repoName, number},
		})
	}()
	return &gg.Issue{
		Title:  gg.Ptr("test-issue"),
		Body:   gg.Ptr("test-issue-body"),
		Number: gg.Ptr(1),
		NodeID: gg.Ptr("test-issue-node-id"),
	}, nil
}

// AssignToIssue assigns an issue to a user.
func (nc *NoopClient) AssignToIssue(ctx context.Context, ownerLogin, repoName string, issueNumber int, assignee string) error {
	return nil
}

// RemoveReactionFromIssue removes a reaction from an issue.
func (nc *NoopClient) RemoveReactionFromIssue(ctx context.Context, owner, repo string, number int, isAgentic agenticapp.IsAgenticFunc) error {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "RemoveReactionFromIssue",
			Args:   []any{owner, repo, number},
		})
	}()
	return nil
}

// GetWorkflowRunByID gets a workflow run by ID.
func (nc *NoopClient) GetWorkflowRunByID(ctx context.Context, ownerLogin, repoName string, runID int64) (*gg.WorkflowRun, error) {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "GetWorkflowRunByID",
			Args:   []any{ownerLogin, repoName, runID},
		})
	}()
	if nc.MockWorkflowRun != nil {
		return nc.MockWorkflowRun, nil
	}
	return &gg.WorkflowRun{
		ID:     gg.Ptr(runID),
		Status: gg.Ptr("in_progress"),
		PullRequests: []*gg.PullRequest{
			{
				Number: gg.Ptr(1),
			},
		},
	}, nil
}

// CancelWorkflowRunByID cancels a workflow run by ID.
func (nc *NoopClient) CancelWorkflowRunByID(ctx context.Context, ownerLogin, repoName string, runID int64) error {
	return nil
}

// CreateDynamicWorkflowRun creates a dynamic workflow run.
func (nc *NoopClient) CreateDynamicWorkflowRun(ctx context.Context, owner, repo string, repoID int64, useRepoID bool, opts *NewDynamicWorkflowRun) (*DynamicWorkflowRun, error) {
	nc.MethodCalls = append(nc.MethodCalls, MethodCall{
		Method: "CreateDynamicWorkflowRun",
		Args:   []any{owner, repo, repoID, useRepoID, opts},
	})
	return &DynamicWorkflowRun{
		ExecutionID:   gg.Ptr("test-execution-id"),
		Slug:          gg.Ptr("test-workflow"),
		WorkflowName:  gg.Ptr("Test Workflow"),
		WorkflowRunID: gg.Ptr(int64(1)),
	}, nil
}

// ListWorkflowJobs lists all jobs in a workflow run.
func (nc *NoopClient) ListWorkflowJobs(ctx context.Context, owner, repo string, runID int64) ([]*gg.WorkflowJob, error) {
	if nc.MockListWorkflowJobs != nil {
		return nc.MockListWorkflowJobs(ctx, owner, repo, runID)
	}
	return []*gg.WorkflowJob{
		{
			RunID:  gg.Ptr(runID),
			Name:   gg.Ptr("test-job"),
			Status: gg.Ptr("in_progress"),
		},
	}, nil
}

// GetWorkflowJobByID gets a workflow job by ID.
func (nc *NoopClient) GetWorkflowJobByID(ctx context.Context, owner, repo string, jobID int64) (*gg.WorkflowJob, error) {
	if nc.MockGetWorkflowJobByID != nil {
		return nc.MockGetWorkflowJobByID(ctx, owner, repo, jobID)
	}
	return &gg.WorkflowJob{
		ID:     gg.Ptr(jobID),
		Name:   gg.Ptr("test-job"),
		Status: gg.Ptr("in_progress"),
	}, nil
}

// ListCheckRunAnnotations lists annotations for a check run.
func (nc *NoopClient) ListCheckRunAnnotations(ctx context.Context, owner, repo string, jobID int64) ([]*gg.CheckRunAnnotation, error) {
	if nc.MockListCheckRunAnnotations != nil {
		return nc.MockListCheckRunAnnotations(ctx, owner, repo, jobID)
	}
	return []*gg.CheckRunAnnotation{}, nil
}

// AddLabelsToIssueOrPR adds labels to an issue or PR.
func (nc *NoopClient) AddLabelsToIssueOrPR(ctx context.Context, ownerLogin, repoName string, issueNumber int, labels []string) error {
	if nc.MockAddLabelsToIssueOrPR != nil {
		return nc.MockAddLabelsToIssueOrPR(ctx, ownerLogin, repoName, issueNumber, labels)
	}

	return nil
}

// GetUserByID gets a user by ID.
func (nc *NoopClient) GetUserByID(ctx context.Context, id uint64) (*gg.User, error) {
	return &gg.User{
		ID:    gg.Ptr(int64(id)),
		Login: gg.Ptr("test-user"),
	}, nil
}

// GetCopilotBotUser gets the Copilot bot user.
func (nc *NoopClient) GetCopilotBotUser(ctx context.Context) (*gg.User, error) {
	return &gg.User{
		NodeID: gg.Ptr(nc.GithubBotLogin),
		Login:  gg.Ptr(nc.GithubBotLogin),
	}, nil
}

// ReplaceActorsForAssignable replaces the list of actors assigned to an assignable entity.
//
//nolint:revive,gocritic // Parameter name must match interface definition (ActorsIDs, not actorsIDs)
func (nc *NoopClient) ReplaceActorsForAssignable(ctx context.Context, assignableID string, ActorsIDs []string) error {
	return nil
}

// GetRepositoryContext gets the repository context for a given repository node ID.
func (nc *NoopClient) GetRepositoryContext(ctx context.Context, repoNodeID string) (*RepositoryContext, error) {
	var c *RepositoryContext

	if nc.MockRepositoryContext != nil {
		c = nc.MockRepositoryContext
	} else {
		c = &RepositoryContext{
			Repository: GQLRepository{
				ID:               1,
				NodeID:           fmt.Sprintf("%d", rand.Int63n(1000000)),
				Name:             "test-repo",
				NameWithOwner:    fmt.Sprintf("%s/%s", "test-owner", "test-repo"),
				HasIssuesEnabled: true,
				IsPrivate:        true,
				Owner:            NewGQLRepositoryOwner(1, fmt.Sprintf("%d", rand.Int63n(1000000)), "test-owner", GQLRepositoryOwnerTypeOrganization, "test-owner"),
			},
		}
	}

	return c, nil
}

// GetIssueContext gets the issue context for a given issue.
func (nc *NoopClient) GetIssueContext(ctx context.Context, repoNodeID string, number int, isAgentic agenticapp.IsAgenticFunc) (*IssueContext, error) {
	var c *IssueContext

	if nc.MockIssueContext != nil {
		c = nc.MockIssueContext
	} else {
		c = &IssueContext{
			Repository: GQLRepository{
				ID:               1,
				NodeID:           fmt.Sprintf("%d", rand.Int63n(1000000)),
				Name:             "test-repo",
				NameWithOwner:    fmt.Sprintf("%s/%s", "test-owner", "test-repo"),
				HasIssuesEnabled: true,
				IsPrivate:        true,
				Owner:            NewGQLRepositoryOwner(1, fmt.Sprintf("%d", rand.Int63n(1000000)), "test-owner", GQLRepositoryOwnerTypeOrganization, "test-owner"),
			},
			Issue: GQLIssue{
				GQLComment: GQLComment{
					ID:     1,
					NodeID: fmt.Sprintf("%d", rand.Int63n(1000000)),
					Author: NewGQLActor(1, fmt.Sprintf("%d", rand.Int63n(1000000)), "test-user", GQLActorTypeUser, "test-user"),
					Body:   "This is a test issue.",
				},
				Title:  "Test Issue.",
				Number: number,
				State:  GQLIssueStateOpen,
				Comments: GQLConnection[GQLIssueComment]{
					TotalCount: 1,
					Nodes: []GQLIssueComment{
						{
							GQLComment: GQLComment{
								NodeID:    fmt.Sprintf("%d", rand.Int63n(1000000)),
								Body:      "This is a test comment.",
								Author:    NewGQLActor(1, fmt.Sprintf("%d", rand.Int63n(1000000)), "test-user", GQLActorTypeUser, "test-user"),
								CreatedAt: time.Time{},
							},
							GQLMinimizable: GQLMinimizable{
								IsMinimized:     false,
								MinimizedReason: "",
							},
						},
					},
				},
			},
		}
	}

	actors, err := nc.getContextParticipants(ctx, c.Repository, c.Issue.GetParticipants())
	if err != nil {
		return nil, err
	}
	c.Participants = actors

	return c, nil
}

// GetIssueUserContentEdits gets the user content edits for an issue.
func (nc *NoopClient) GetIssueUserContentEdits(ctx context.Context, issueNodeID string) ([]UserContentEdit, error) {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "GetIssueUserContentEdits",
			Args:   []any{issueNodeID},
		})
	}()
	if nc.MockIssueUserContentEdits != nil {
		return nc.MockIssueUserContentEdits, nil
	}
	return []UserContentEdit{}, nil
}

// GetPullRequestContext gets the pull request context for a given pull request.
func (nc *NoopClient) GetPullRequestContext(ctx context.Context, repoNodeID string, number int, isAgentic agenticapp.IsAgenticFunc) (*PullRequestContext, error) {
	var c *PullRequestContext
	if nc.MockPullRequestContext != nil {
		c = nc.MockPullRequestContext
	} else {
		c = &PullRequestContext{
			Repository: GQLRepository{
				ID:               1,
				NodeID:           fmt.Sprintf("%d", rand.Int63n(1000000)),
				Name:             "test-repo",
				NameWithOwner:    fmt.Sprintf("%s/%s", "test-owner", "test-repo"),
				HasIssuesEnabled: true,
				IsPrivate:        true,
				Owner:            NewGQLRepositoryOwner(1, fmt.Sprintf("%d", rand.Int63n(1000000)), "test-owner", GQLRepositoryOwnerTypeOrganization, "test-owner"),
			},
			PullRequest: GQLPullRequest{
				GQLComment: GQLComment{
					ID:     1,
					NodeID: fmt.Sprintf("%d", rand.Int63n(1000000)),
					Author: NewGQLActor(1, fmt.Sprintf("%d", rand.Int63n(1000000)), "test-user", GQLActorTypeUser, "test-user"),
					Body:   "This is a test pull request.",
				},
				Title:  "Test Pull Request.",
				Number: number,
				Commits: struct {
					TotalCount int `json:"total_count"`
				}{
					TotalCount: 5,
				},
				Reviews: GQLConnection[GQLPullRequestReview]{
					TotalCount: 1,
					Nodes: []GQLPullRequestReview{
						{
							GQLComment: GQLComment{
								Body:      "This is a test review.",
								Author:    NewGQLActor(1, fmt.Sprintf("%d", rand.Int63n(1000000)), "test-user", GQLActorTypeUser, "test-user"),
								CreatedAt: time.Time{},
							},
							Comments: GQLConnection[GQLPullRequestReviewComment]{
								TotalCount: 1,
								Nodes: []GQLPullRequestReviewComment{
									{
										GQLComment: GQLComment{
											NodeID:    fmt.Sprintf("%d", rand.Int63n(1000000)),
											Body:      "This is a test comment.",
											Author:    NewGQLActor(1, fmt.Sprintf("%d", rand.Int63n(1000000)), "test-user", GQLActorTypeUser, "test-user"),
											CreatedAt: time.Time{},
										},
										GQLMinimizable: GQLMinimizable{
											IsMinimized:     false,
											MinimizedReason: "",
										},
										ReplyTo: &GQLReplyTo{
											NodeID: fmt.Sprintf("%d", rand.Int63n(1000000)),
										},
										Commit: GQLGitObject{
											OID: "test-commit",
										},
										OriginalCommit: GQLGitObject{
											OID: "test-commit",
										},
										Line:              1,
										StartLine:         1,
										OriginalLine:      1,
										OriginalStartLine: 1,
									},
								},
							},
						},
					},
				},
				Comments: GQLConnection[GQLIssueComment]{
					TotalCount: 1,
					Nodes: []GQLIssueComment{
						{
							GQLComment: GQLComment{
								Body:      "This is a test comment.",
								Author:    NewGQLActor(1, fmt.Sprintf("%d", rand.Int63n(1000000)), "test-user", GQLActorTypeUser, "test-user"),
								CreatedAt: time.Time{},
							},
						},
					},
				},
			},
		}
	}

	actors, err := nc.getContextParticipants(ctx, c.Repository, c.PullRequest.GetParticipants())
	if err != nil {
		return nil, err
	}
	c.Participants = actors

	return c, nil
}

// DeleteRepo deletes a repository.
func (nc *NoopClient) DeleteRepo(ctx context.Context, owner, repo string) error {
	return nil
}

// CreateRepo creates a new repository.
func (nc *NoopClient) CreateRepo(ctx context.Context, org, name string, autoinit bool) (*gg.Repository, error) {
	return &gg.Repository{
		Name:     gg.Ptr(name),
		AutoInit: gg.Ptr(autoinit),
	}, nil
}

// CreateIssue creates a new issue.
func (nc *NoopClient) CreateIssue(ctx context.Context, owner, repo, title, body string) (*gg.Issue, error) {
	return &gg.Issue{
		Title:  gg.Ptr(title),
		Body:   gg.Ptr(body),
		Number: gg.Ptr(1),
	}, nil
}

// GetPullRequests gets a list of pull requests for a repository.
func (nc *NoopClient) GetPullRequests(ctx context.Context, owner, repo string, opts *gg.PullRequestListOptions) ([]*gg.PullRequest, error) {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "GetPullRequests",
			Args:   []any{owner, repo, opts},
		})
	}()
	if nc.MockPullRequestList != nil {
		return nc.MockPullRequestList, nil
	}
	return []*gg.PullRequest{
		{
			Number: gg.Ptr(1),
			Draft:  gg.Ptr(false),
			URL:    gg.Ptr("test-pull-request-url"),
			Title:  gg.Ptr("test-pull-request"),
			Body:   gg.Ptr("test-pull-request-body"),
		},
	}, nil
}

// GetContents gets the contents of a file or directory.
func (nc *NoopClient) GetContents(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error) {
	if nc.MockGetContents != nil {
		return nc.MockGetContents(ctx, owner, repo, path, opts)
	}

	fileContent = &gg.RepositoryContent{
		Name:    gg.Ptr("test-file"),
		Content: gg.Ptr("test-content"),
	}
	return fileContent, nil, nil
}

// UpdateFile updates the contents of a file.
func (nc *NoopClient) UpdateFile(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentFileOptions) (*gg.RepositoryContentResponse, error) {
	return &gg.RepositoryContentResponse{
		Content: &gg.RepositoryContent{
			Name:    gg.Ptr("test-file"),
			Content: gg.Ptr("test-content"),
		},
	}, nil
}

// GetAuthenticatedUser gets the authenticated user.
func (nc *NoopClient) GetAuthenticatedUser(ctx context.Context) (*gg.User, error) {
	return &gg.User{
		Login: gg.Ptr("test-user"),
	}, nil
}

// GetCopilotEnvironmentSecretsAndVariables gets the Copilot environment secrets and variables.
func (nc *NoopClient) GetCopilotEnvironmentSecretsAndVariables(ctx context.Context, owner, repo string, repoID int64) (secrets, variables []string, err error) {
	return []string{
			"TEST_SECRET_ONE",
			"TEST_SECRET_TWO",
		}, []string{
			"TEST_VARIABLE_ONE",
			"TEST_VARIABLE_TWO",
		}, nil
}

// GetUserPermissionsForRepository gets user permissions for a repository.
func (nc *NoopClient) GetUserPermissionsForRepository(ctx context.Context, owner, repo, username string) (*RepositoryPermissions, error) {
	write := &RepositoryPermissions{
		Permission: "write",
		Role:       "write",
		Admin:      false,
		Maintain:   false,
		Push:       true,
		Triage:     true,
		Pull:       true,
	}

	switch {
	case strings.HasSuffix(username, "-admin"):
		return &RepositoryPermissions{
			Permission: "admin",
			Role:       "admin",
			Admin:      true,
			Maintain:   true,
			Push:       true,
			Triage:     true,
			Pull:       true,
		}, nil
	case strings.HasSuffix(username, "-write"):
		return write, nil
	case strings.HasSuffix(username, "-read"):
		return &RepositoryPermissions{
			Permission: "read",
			Role:       "read",
			Admin:      false,
			Maintain:   false,
			Push:       false,
			Triage:     false,
			Pull:       true,
		}, nil
	case strings.HasSuffix(username, "-none"):
		return &RepositoryPermissions{
			Permission: "none",
			Role:       "none",
			Admin:      false,
			Maintain:   false,
			Push:       false,
			Triage:     false,
			Pull:       false,
		}, nil
	default:
		return write, nil
	}
}

// GetUserPermissionsForRepositoryByID gets user permissions for a repository by ID.
func (nc *NoopClient) GetUserPermissionsForRepositoryByID(ctx context.Context, repoID int64, username string) (*RepositoryPermissions, error) {
	if nc.MockGetUserPermissionsForRepositoryByID != nil {
		return nc.MockGetUserPermissionsForRepositoryByID(ctx, repoID, username)
	}
	return nc.GetUserPermissionsForRepository(ctx, "test-owner", "test-repo", username)
}

// getContextParticipants gets the list of context participants for a repository.
//
//nolint:funcorder // Helper method is placed near callers for readability
func (nc *NoopClient) getContextParticipants(ctx context.Context, repo GQLRepository, participants []GQLActor) ([]ContextParticipant, error) {
	// get a list of unique participants and fetch repo permissions for each
	actors := []ContextParticipant{}
	for _, actor := range uniqueParticipants(participants) {
		var err error
		var permissions *RepositoryPermissions
		if actor.IsUser() {
			// bots don't return permissions from the collaborators API, so only get them for users
			permissions, err = nc.GetUserPermissionsForRepository(ctx, repo.Owner.Login, repo.Name, actor.GetLogin())
			if err != nil {
				return actors, err
			}
		}
		actors = append(actors, ContextParticipant{
			Actor:       actor,
			Permissions: permissions,
		})
	}
	return actors, nil
}

// RevokeUserToken revokes a user token.
func (nc *NoopClient) RevokeUserToken(ctx context.Context, token string) error {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "RevokeUserToken",
			Args:   []any{token},
		})
	}()
	return nil
}

// RevokeInstallationToken revokes an installation token.
func (nc *NoopClient) RevokeInstallationToken(ctx context.Context, token string) error {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "RevokeInstallationToken",
			Args:   []any{token},
		})
	}()
	return nil
}

// ListBranchProtectionRules lists branch protection rules for a repository.
func (nc *NoopClient) ListBranchProtectionRules(ctx context.Context, repoNodeID string) (*[]GQLBranchProtectionRule, error) {
	if nc.MockListBranchProtectionRules != nil {
		return nc.MockListBranchProtectionRules(ctx, repoNodeID)
	}
	return &[]GQLBranchProtectionRule{}, nil
}

// ListRepositoryRulesForBranch lists repository rules for a branch.
func (nc *NoopClient) ListRepositoryRulesForBranch(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
	if nc.MockListRepositoryRulesForBranch != nil {
		return nc.MockListRepositoryRulesForBranch(ctx, ownerLogin, repoName, branchName, excludeRulesetIDs)
	}
	return &gg.BranchRules{}, nil
}

// GetActionsPermissions gets the actions permissions for a repository.
func (nc *NoopClient) GetActionsPermissions(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error) {
	if nc.MockGetActionsPermissions != nil {
		return nc.MockGetActionsPermissions(ctx, ownerLogin, repoName)
	}

	return &gg.ActionsPermissionsRepository{
		Enabled: gg.Ptr(true),
	}, nil
}

// ListUserOrgs lists the organizations for a user.
func (nc *NoopClient) ListUserOrgs(ctx context.Context, user string) ([]*gg.Organization, error) {
	if nc.MockListUserOrgs != nil {
		return nc.MockListUserOrgs(ctx, user)
	}
	return []*gg.Organization{}, nil
}
