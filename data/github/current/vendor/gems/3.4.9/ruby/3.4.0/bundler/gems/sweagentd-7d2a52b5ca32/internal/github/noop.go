package github

import (
	"context"
	"fmt"
	"math/rand"
	"net/url"
	"strings"
	"time"

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
		baseUrl:  url,
		ffClient: featureflags.NewNoopClient(flags),
		githubApp: &GitHubApp{
			ID:       123456,
			AppLogin: githubAppLogin,
			BotLogin: githubBotLogin,
		},
		githubCommitLogin: githubCommitLogin,
		githubCommitEmail: githubCommitEmail,
		obsv:              obsv,
	}, nil
}

type NoopClientFactory struct {
	MockNewClient                           func(token string) ClientInterface
	MockNewClientFromInstallationIDAndRepo  func(ctx context.Context, installationId, repoId int64) (ClientInterface, error)
	MockNewClientFromRepo                   func(ctx context.Context, repoId, repoOwnerId int64) (ClientInterface, error)
	MockNewClientFromRepoName               func(ctx context.Context, repoName, ownerName string) (ClientInterface, error)
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

func (cf *NoopClientFactory) AppID() int64 {
	return cf.GitHubAppID
}

func (cf *NoopClientFactory) NewClient(token string) ClientInterface {
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

func (cf *NoopClientFactory) NewClientFromInstallationIDAndRepo(ctx context.Context, installationId, repoId int64) (ClientInterface, error) {
	if cf.MockNewClientFromInstallationIDAndRepo != nil {
		return cf.MockNewClientFromInstallationIDAndRepo(ctx, installationId, repoId)
	}
	return cf.NewClient("test-repo-scoped-installation-token"), nil
}

func (cf *NoopClientFactory) NewClientForRepo(ctx context.Context, repo sweagentd.Repository) (ClientInterface, error) {
	if cf.MockNewClientFromRepo != nil {
		return cf.MockNewClientFromRepo(ctx, repo.GetRepositoryID(), repo.GetOwnerID())
	}
	return cf.NewClient("test-repo-scoped-token"), nil
}

func (cf *NoopClientFactory) NewClientFromRepo(ctx context.Context, repoId, repoOwnerId int64) (ClientInterface, error) {
	if cf.MockNewClientFromRepo != nil {
		return cf.MockNewClientFromRepo(ctx, repoId, repoOwnerId)
	}
	return cf.NewClient("test-repo-scoped-token"), nil
}

func (cf *NoopClientFactory) NewClientFromRepoName(ctx context.Context, repoName, ownerName string) (ClientInterface, error) {
	if cf.MockNewClientFromRepoName != nil {
		return cf.MockNewClientFromRepoName(ctx, repoName, ownerName)
	}
	return cf.NewClient("test-repo-scoped-token"), nil
}

func (cf *NoopClientFactory) NewClientForUser(token string, userID uint64) ClientInterface {
	return cf.NewClient(token)
}

func (cf *NoopClientFactory) NewClientForTarget(token string, target string) ClientInterface {
	return cf.NewClient(token)
}

func (cf *NoopClientFactory) UserIsCopilot(login string) bool {
	return UserIsCopilot(&GitHubApp{
		AppLogin: cf.GitHubAppLogin,
		BotLogin: cf.GitHubBotLogin,
	}, login)
}

func (cf *NoopClientFactory) UserIsAllowlistedBot(login string) bool {
	return UserIsAllowlistedBot(&GitHubApp{
		AppLogin: cf.GitHubAppLogin,
		BotLogin: cf.GitHubBotLogin,
	}, login)
}

func (cf *NoopClientFactory) ContainsCopilotUser(logins []string) bool {
	return ContainsCopilotUser(&GitHubApp{
		AppLogin: cf.GitHubAppLogin,
		BotLogin: cf.GitHubBotLogin,
	}, logins)
}

func (cf *NoopClientFactory) DoesMentionCopilot(body string) bool {
	return DoesMentionCopilot(body)
}

type MethodCall struct {
	Method string
	Args   []interface{}
}

type NoopClient struct {
	ClientInterface
	GithubAppLogin                          string
	GithubBotLogin                          string
	MockRepositoryContext                   *RepositoryContext
	MockRepositories                        *map[string]gg.Repository // owner/name or ID to content
	MockIssueContext                        *IssueContext
	MockPullRequestList                     []*gg.PullRequest
	MockPullRequestContext                  *PullRequestContext
	MockCheckIfBranchExists                 func(ctx context.Context, ownerLogin, repoName, branchName string) (bool, error)
	MockCheckIfRefExists                    func(ctx context.Context, ownerLogin, repoName, ref string) (bool, error)
	MockListBranchProtectionRules           func(ctx context.Context, repoNodeID string) (*[]GQLBranchProtectionRule, error)
	MockListRepositoryRulesForBranch        func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error)
	MockGetActionsPermissions               func(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error)
	MockGetWorkflowJobByID                  func(ctx context.Context, owner, repo string, jobID int64) (*gg.WorkflowJob, error)
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
	MockEnsureUniqueBranchName              func(ctx context.Context, ownerLogin string, repoName string, branchName string) (string, error)
}

func (nc *NoopClient) HasMethodCall(method string) bool {
	for _, call := range nc.MethodCalls {
		if call.Method == method {
			return true
		}
	}
	return false
}

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

// Returns the token used in the GitHub client.
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

func (nc *NoopClient) UserIsCopilot(login string) bool {
	return UserIsCopilot(&GitHubApp{
		AppLogin: nc.GithubAppLogin,
		BotLogin: nc.GithubBotLogin,
	}, login)
}

func (nc *NoopClient) UserIsAllowlistedBot(login string) bool {
	return UserIsAllowlistedBot(&GitHubApp{
		AppLogin: nc.GithubAppLogin,
		BotLogin: nc.GithubBotLogin,
	}, login)
}

func (nc *NoopClient) ContainsCopilotUser(logins []string) bool {
	return ContainsCopilotUser(&GitHubApp{
		AppLogin: nc.GithubAppLogin,
		BotLogin: nc.GithubBotLogin,
	}, logins)
}

func (nc *NoopClient) CreateNewEmptyBranch(ctx context.Context, ownerLogin, repoName, baseBranchName, branchName string) (*gg.Reference, error) {
	if nc.MockCreateNewEmptyBranch != nil {
		return nc.MockCreateNewEmptyBranch(ctx, ownerLogin, repoName, baseBranchName, branchName)
	}
	return &gg.Reference{
		Ref: gg.Ptr("refs/heads/" + branchName),
	}, nil
}

func (nc *NoopClient) CreateEmptyCommit(ctx context.Context, ownerLogin, repoName, branchName string) (*gg.Commit, error) {
	return &gg.Commit{
		SHA: gg.Ptr("sha"),
	}, nil
}

func (nc *NoopClient) EnsureUniqueBranchName(ctx context.Context, ownerLogin string, repoName string, branchName string) (string, error) {
	if nc.MockEnsureUniqueBranchName != nil {
		return nc.MockEnsureUniqueBranchName(ctx, ownerLogin, repoName, branchName)
	}

	baseName := fmt.Sprintf("%s/%s", CopilotBranchPrefix, branchName)
	candidateName := baseName
	attemptCount := 0

	for {
		exists, err := nc.CheckIfBranchExists(ctx, ownerLogin, repoName, candidateName)
		if err != nil {
			// If we can't check if the branch exists, return the candidate name anyway
			return candidateName, nil
		}

		if !exists {
			return candidateName, nil
		}

		// Give up after maximum attempts and fall back to using a predictable suffix for testing
		if attemptCount >= maxUniqueBranchAttempts {
			// Use a predictable suffix for testing
			return fmt.Sprintf("%s-fallback", baseName), nil
		}

		candidateName = fmt.Sprintf("%s-%s", baseName, branchNameSuffixes[attemptCount])
		attemptCount++
	}
}

func (nc *NoopClient) CheckIfBranchExists(ctx context.Context, ownerLogin string, repoName string, branchName string) (bool, error) {
	if nc.MockCheckIfBranchExists != nil {
		return nc.MockCheckIfBranchExists(ctx, ownerLogin, repoName, branchName)
	}

	return false, nil
}

func (nc *NoopClient) CheckIfRefExists(ctx context.Context, ownerLogin string, repoName string, refName string) (bool, error) {
	if nc.MockCheckIfRefExists != nil {
		return nc.MockCheckIfRefExists(ctx, ownerLogin, repoName, refName)
	}

	return true, nil
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

func (nc *NoopClient) UpdatePullRequest(ctx context.Context, repoID int64, pr *gg.PullRequest) (*gg.PullRequest, error) {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "UpdatePullRequest",
			Args:   []interface{}{repoID, pr},
		})
	}()
	return pr, nil
}

func (nc *NoopClient) RequestReviewers(ctx context.Context, ownerLogin, repoName string, number int, reviewers []string) error {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "RequestReviewers",
			Args:   []interface{}{ownerLogin, repoName, number, reviewers},
		})
	}()

	return nil
}

func (nc *NoopClient) GetComment(ctx context.Context, owner, repo string, commentID int64) (*gg.IssueComment, error) {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "GetComment",
			Args:   []interface{}{owner, repo, commentID},
		})
	}()
	return &gg.IssueComment{
		ID:   &commentID,
		Body: gg.Ptr("test-comment-body"),
	}, nil
}

func (nc *NoopClient) CreateComment(ctx context.Context, repoID int64, issueOrPRNumber int, body string) (*gg.IssueComment, error) {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "CreateComment",
			Args:   []interface{}{repoID, issueOrPRNumber, body},
		})
	}()

	id := rand.Int63n(1000000)
	return &gg.IssueComment{
		ID:   &id,
		Body: gg.Ptr(body),
	}, nil
}

func (nc *NoopClient) DeleteComment(ctx context.Context, repoID, commentID int64) error {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "DeleteComment",
			Args:   []interface{}{repoID, commentID},
		})
	}()
	return nil
}

func (nc *NoopClient) CreateCommentInReplyTo(ctx context.Context, owner, repo string, number int, body string, commentID int64) (*gg.PullRequestComment, error) {
	id := rand.Int63n(1000000)
	return &gg.PullRequestComment{
		ID:   &id,
		Body: gg.Ptr(body),
	}, nil
}

func (nc *NoopClient) UpdateComment(ctx context.Context, owner, repo string, commentID int64, body string) (*gg.IssueComment, error) {

	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "UpdateComment",
			Args:   []interface{}{owner, repo, commentID, body},
		})
	}()

	return &gg.IssueComment{
		ID:   &commentID,
		Body: gg.Ptr(body),
	}, nil
}

func (nc *NoopClient) UpdatePullRequestReviewComment(ctx context.Context, owner, repo string, prNumber int, commentID int64, body string) (*gg.PullRequestComment, error) {
	return &gg.PullRequestComment{
		ID:   &commentID,
		Body: gg.Ptr(body),
	}, nil
}

func (nc *NoopClient) MarkPullRequestReadyForReview(ctx context.Context, prNodeID string) error {
	return nil
}

func (nc *NoopClient) ConvertPullRequestToDraft(ctx context.Context, prNodeID string) error {
	return nil
}

func (ac *NoopClient) GetRepository(ctx context.Context, ownerName, repoName string) (*gg.Repository, error) {
	if ac.MockGetRepository != nil {
		return ac.MockGetRepository(ctx, ownerName, repoName)
	}
	if ac.MockRepositories != nil {
		repo := (*ac.MockRepositories)[fmt.Sprintf("%s/%s", ownerName, repoName)]
		return &repo, nil
	}
	return &gg.Repository{
		ID:   gg.Ptr(int64(1)),
		Name: gg.Ptr(repoName),
		Owner: &gg.User{
			Login: gg.Ptr(ownerName),
		},
	}, nil
}

func (nc *NoopClient) GetRepositoryById(ctx context.Context, id int64) (*gg.Repository, error) {
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

func (nc *NoopClient) AddReaction(ctx context.Context, nodeID string, content GQLReactionContent) error {
	return nil
}

func (nc *NoopClient) RemoveReaction(ctx context.Context, nodeID string, content GQLReactionContent) error {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "RemoveReaction",
			Args:   []interface{}{nodeID, content},
		})
	}()
	return nil
}

func (nc *NoopClient) MinimizeComment(ctx context.Context, nodeID string, classifier GQLReportedContentClassifier) error {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "MinimizeComment",
			Args:   []interface{}{nodeID, classifier},
		})
	}()
	return nil
}

func (nc *NoopClient) UnminimizeComment(ctx context.Context, nodeID string) error {
	return nil
}

func (nc *NoopClient) GetWorkflowRunLogs(ctx context.Context, owner, repo string, runID int64) (string, error) {
	return "logs", nil
}

func (nc *NoopClient) GetPullRequest(ctx context.Context, repoID int64, number int) (*gg.PullRequest, error) {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "GetPullRequest",
			Args:   []interface{}{repoID, number},
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

func (nc *NoopClient) GetIssue(ctx context.Context, ownerLogin, repoName string, number int) (*gg.Issue, error) {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "GetIssue",
			Args:   []interface{}{ownerLogin, repoName, number},
		})
	}()
	return &gg.Issue{
		Title:  gg.Ptr("test-issue"),
		Body:   gg.Ptr("test-issue-body"),
		Number: gg.Ptr(1),
		NodeID: gg.Ptr("test-issue-node-id"),
	}, nil
}

func (nc *NoopClient) AssignToIssue(ctx context.Context, ownerLogin, repoName string, issueNumber int, assignee string) error {
	return nil
}

func (nc *NoopClient) RemoveReactionFromIssue(ctx context.Context, owner, repo string, number int) error {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "RemoveReactionFromIssue",
			Args:   []interface{}{owner, repo, number},
		})
	}()
	return nil
}

func (nc *NoopClient) GetWorkflowRunByID(ctx context.Context, ownerLogin, repoName string, runID int64) (*gg.WorkflowRun, error) {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "GetWorkflowRunByID",
			Args:   []interface{}{ownerLogin, repoName, runID},
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

func (nc *NoopClient) CancelWorkflowRunByID(ctx context.Context, ownerLogin, repoName string, runID int64) error {
	return nil
}

func (nc *NoopClient) CreateDynamicWorkflowRun(ctx context.Context, owner, repo string, repoID int64, opts *NewDynamicWorkflowRun) (*DynamicWorkflowRun, error) {
	return &DynamicWorkflowRun{
		ExecutionID:   gg.Ptr("test-execution-id"),
		Slug:          gg.Ptr("test-workflow"),
		WorkflowName:  gg.Ptr("Test Workflow"),
		WorkflowRunID: gg.Ptr((int64)(1)),
	}, nil
}

func (ac *NoopClient) ListWorkflowJobs(ctx context.Context, owner, repo string, runID int64) ([]*gg.WorkflowJob, error) {
	return []*gg.WorkflowJob{
		{
			RunID:  gg.Ptr(runID),
			Name:   gg.Ptr("test-job"),
			Status: gg.Ptr("in_progress"),
		},
	}, nil
}

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

func (nc *NoopClient) ListCheckRunAnnotations(ctx context.Context, owner, repo string, jobID int64) ([]*gg.CheckRunAnnotation, error) {
	if nc.MockListCheckRunAnnotations != nil {
		return nc.MockListCheckRunAnnotations(ctx, owner, repo, jobID)
	}
	return []*gg.CheckRunAnnotation{}, nil
}

func (ac *NoopClient) AddLabelsToIssueOrPR(ctx context.Context, ownerLogin, repoName string, issueNumber int, labels []string) error {
	if ac.MockAddLabelsToIssueOrPR != nil {
		return ac.MockAddLabelsToIssueOrPR(ctx, ownerLogin, repoName, issueNumber, labels)
	}

	return nil
}

func (ac *NoopClient) GetUserById(ctx context.Context, id uint64) (*gg.User, error) {
	return &gg.User{
		ID:    gg.Ptr(int64(id)),
		Login: gg.Ptr("test-user"),
	}, nil
}

func (ac *NoopClient) GetCopilotBotUser(ctx context.Context) (*gg.User, error) {
	return &gg.User{
		NodeID: gg.Ptr(ac.GithubBotLogin),
		Login:  gg.Ptr(ac.GithubBotLogin),
	}, nil
}

func (ac *NoopClient) AssignParticipantToIssueOrPR(ctx context.Context, assignableID string, ActorsIDs []string) error {
	return nil
}

func (ac *NoopClient) GetRepositoryContext(ctx context.Context, repoNodeID string) (*RepositoryContext, error) {
	var c *RepositoryContext

	if ac.MockRepositoryContext != nil {
		c = ac.MockRepositoryContext
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

func (ac *NoopClient) GetIssueContext(ctx context.Context, repoNodeID string, number int) (*IssueContext, error) {
	var c *IssueContext

	if ac.MockIssueContext != nil {
		c = ac.MockIssueContext
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

	actors, err := ac.getContextParticipants(ctx, c.Repository, c.Issue.GetParticipants())
	if err != nil {
		return nil, err
	}
	c.Participants = actors

	return c, nil
}

func (ac *NoopClient) GetIssueUserContentEdits(ctx context.Context, issueNodeID string) ([]UserContentEdit, error) {
	defer func() {
		ac.MethodCalls = append(ac.MethodCalls, MethodCall{
			Method: "GetIssueUserContentEdits",
			Args:   []interface{}{issueNodeID},
		})
	}()
	if ac.MockIssueUserContentEdits != nil {
		return ac.MockIssueUserContentEdits, nil
	}
	return []UserContentEdit{}, nil
}

func (ac *NoopClient) GetPullRequestContext(ctx context.Context, repoNodeID string, number int) (*PullRequestContext, error) {
	var c *PullRequestContext
	if ac.MockPullRequestContext != nil {
		c = ac.MockPullRequestContext
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

	actors, err := ac.getContextParticipants(ctx, c.Repository, c.PullRequest.GetParticipants())
	if err != nil {
		return nil, err
	}
	c.Participants = actors

	return c, nil

}

func (nc *NoopClient) DeleteRepo(ctx context.Context, owner, repo string) error {
	return nil
}

func (nc *NoopClient) CreateRepo(ctx context.Context, org, name string, autoinit bool) (*gg.Repository, error) {
	return &gg.Repository{
		Name:     gg.Ptr(name),
		AutoInit: gg.Ptr(autoinit),
	}, nil
}

func (nc *NoopClient) CreateIssue(ctx context.Context, owner, repo, title, body string) (*gg.Issue, error) {
	return &gg.Issue{
		Title:  gg.Ptr(title),
		Body:   gg.Ptr(body),
		Number: gg.Ptr(1),
	}, nil
}

func (nc *NoopClient) GetPullRequests(ctx context.Context, owner, repo string, opts *gg.PullRequestListOptions) ([]*gg.PullRequest, error) {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "GetPullRequests",
			Args:   []interface{}{owner, repo, opts},
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

func (nc *NoopClient) UpdateFile(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentFileOptions) (*gg.RepositoryContentResponse, error) {
	return &gg.RepositoryContentResponse{
		Content: &gg.RepositoryContent{
			Name:    gg.Ptr("test-file"),
			Content: gg.Ptr("test-content"),
		},
	}, nil
}

func (nc *NoopClient) GetAuthenticatedUser(ctx context.Context) (*gg.User, error) {
	return &gg.User{
		Login: gg.Ptr("test-user"),
	}, nil
}

func (nc *NoopClient) GetCopilotEnvironmentSecretsAndVariables(ctx context.Context, owner, repo string, repoID int64) (secrets []string, variables []string, err error) {
	return []string{
			"TEST_SECRET_ONE",
			"TEST_SECRET_TWO",
		}, []string{
			"TEST_VARIABLE_ONE",
			"TEST_VARIABLE_TWO",
		}, nil
}

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

func (nc *NoopClient) GetUserPermissionsForRepositoryByID(ctx context.Context, repoID int64, username string) (*RepositoryPermissions, error) {
	if nc.MockGetUserPermissionsForRepositoryByID != nil {
		return nc.MockGetUserPermissionsForRepositoryByID(ctx, repoID, username)
	}
	return nc.GetUserPermissionsForRepository(ctx, "test-owner", "test-repo", username)
}

func (ac *NoopClient) getContextParticipants(ctx context.Context, repo GQLRepository, participants []GQLActor) ([]ContextParticipant, error) {
	// get a list of unique participants and fetch repo permissions for each
	actors := []ContextParticipant{}
	for _, actor := range uniqueParticipants(participants) {
		var err error
		var permissions *RepositoryPermissions
		if actor.IsUser() {
			// bots don't return permissions from the collaborators API, so only get them for users
			permissions, err = ac.GetUserPermissionsForRepository(ctx, repo.Owner.Login, repo.Name, actor.GetLogin())
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

func (nc *NoopClient) RevokeUserToken(ctx context.Context, token string) error {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "RevokeUserToken",
			Args:   []interface{}{token},
		})
	}()
	return nil
}

func (nc *NoopClient) RevokeInstallationToken(ctx context.Context, token string) error {
	defer func() {
		nc.MethodCalls = append(nc.MethodCalls, MethodCall{
			Method: "RevokeInstallationToken",
			Args:   []interface{}{token},
		})
	}()
	return nil
}

func (nc *NoopClient) ListBranchProtectionRules(ctx context.Context, repoNodeID string) (*[]GQLBranchProtectionRule, error) {
	if nc.MockListBranchProtectionRules != nil {
		return nc.MockListBranchProtectionRules(ctx, repoNodeID)
	}
	return &[]GQLBranchProtectionRule{}, nil
}

func (nc *NoopClient) ListRepositoryRulesForBranch(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
	if nc.MockListRepositoryRulesForBranch != nil {
		return nc.MockListRepositoryRulesForBranch(ctx, ownerLogin, repoName, branchName, excludeRulesetIDs)
	}
	return &gg.BranchRules{}, nil
}

func (nc *NoopClient) GetActionsPermissions(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error) {
	if nc.MockGetActionsPermissions != nil {
		return nc.MockGetActionsPermissions(ctx, ownerLogin, repoName)
	}

	return &gg.ActionsPermissionsRepository{
		Enabled: gg.Ptr(true),
	}, nil
}

func (nc *NoopClient) ListUserOrgs(ctx context.Context, user string) ([]*gg.Organization, error) {
	if nc.MockListUserOrgs != nil {
		return nc.MockListUserOrgs(ctx, user)
	}
	return []*gg.Organization{}, nil
}
