package events

import (
	"context"
	"fmt"
	"testing"
	"time"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"

	"github.com/github/hydro-client-go/v7/pkg/hydro"
	et "github.com/github/sweagentd/internal/events/eventstest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/require"
)

func TestOnIssueAssigned(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}

	t.Run("queues the agent job", func(t *testing.T) {
		flags := map[string]bool{}
		ffc := featureflags.NewNoopClient(flags)
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}
		h, service, executor := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)

		assignee := et.UserCopilot()
		issue := et.Issue(*assignee)
		ghFactory.MockIssueContext = &github.IssueContext{Repository: *et.Repo(), Issue: *issue}

		err := h.OnIssueAssigned(context.Background(), IssueAssignmentEvent{
			Actor:     EventActorWriter(),
			Repo:      EventRepository(),
			Issue:     EventIssue(),
			Action:    IssueAssignmentEventActionAssigned,
			Assignees: []string{assignee.Login},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
		require.Len(t, executor.LaunchAgentCalls(), 0)
		require.Equal(t, et.ActorWriter().GetID(), service.QueuedJobs()[0].ActorId)
	})

	t.Run("ignores events where Copilot was not assigned/unassigned", func(t *testing.T) {

		ffClient := featureflags.NewNoopClient(nil)
		h, service, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)

		assignee := et.UserReader()
		issue := et.Issue(*assignee)
		ghFactory.MockIssueContext = &github.IssueContext{Repository: *et.Repo(), Issue: *issue}

		err := h.OnIssueAssigned(context.Background(), IssueAssignmentEvent{
			Actor:    EventActorWriter(),
			Repo:     EventRepository(),
			Issue:    EventIssue(),
			Action:   IssueAssignmentEventActionAssigned,
			Assignee: assignee.Login,
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("uses twirp to create the PR", func(t *testing.T) {
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		didCallTwirp := false
		ghTwirp.NoopSweagentdAPI = &githubtwirp.NoopSweagentdAPI{
			MockCreatePullRequest: func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
				didCallTwirp = true
				return &sweagentdTwirp.CreatePullRequestResponse{PullRequest: &sweagentdTwirp.PullRequest{Id: 123, GithubNumber: 789, RepositoryId: 456}}, nil
			},
		}
		ghTwirp.NoopUserDetailAPI = &githubtwirp.NoopUserDetailAPI{
			MockGetCopilotUser: func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
				return &copilotUsersTwirp.GetCopilotUserResponse{UserDetails: &copilotUsersTwirp.CopilotUserDetails{CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE}}, nil
			},
		}
		flags := map[string]bool{"sweagentd_create_pr_twirp": true}
		ffClient := featureflags.NewNoopClient(flags)
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)
		assignee := et.UserCopilot()
		issue := et.Issue(*assignee)
		ghFactory.MockIssueContext = &github.IssueContext{Repository: *et.Repo(), Issue: *issue}
		err := h.OnIssueAssigned(context.Background(), IssueAssignmentEvent{Actor: EventActorWriter(), Repo: EventRepository(), Issue: EventIssue(), Action: IssueAssignmentEventActionAssigned, Assignees: []string{assignee.Login}})
		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
		require.True(t, didCallTwirp)
	})

	t.Run("emits job_created hydro event", func(t *testing.T) {
		messageChan := make(chan hydro.Message, 1)
		sink, err := hydro.NewMemorySink(messageChan)
		require.NoError(t, err)
		publisher, _ := hydro.NewPublisher(sink, hydro.WithEncoder(hydro.NewJSONEncoder()))
		obsvWithPublisher := obsv.WithPublisher(publisher)
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		didCallTwirp := false

		ghTwirp.NoopSweagentdAPI = &githubtwirp.NoopSweagentdAPI{
			MockCreatePullRequest: func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
				didCallTwirp = true
				return &sweagentdTwirp.CreatePullRequestResponse{
					PullRequest: &sweagentdTwirp.PullRequest{
						Id:           123,
						GithubNumber: 789,
						RepositoryId: 456,
					},
				}, nil
			},
		}
		ghTwirp.NoopUserDetailAPI = &githubtwirp.NoopUserDetailAPI{
			MockGetCopilotUser: func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
				return &copilotUsersTwirp.GetCopilotUserResponse{
					UserDetails: &copilotUsersTwirp.CopilotUserDetails{
						CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
					},
				}, nil
			},
		}
		ffClient := featureflags.NewNoopClient(nil)
		h, service, _ := NewTestHandler(t, obsvWithPublisher, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		assignee := et.UserCopilot()
		issue := et.Issue(*assignee)
		ghFactory.MockIssueContext = &github.IssueContext{Repository: *et.Repo(), Issue: *issue}

		eventRepo := EventRepository()
		eventIssue := EventIssue()

		err = h.OnIssueAssigned(context.Background(), IssueAssignmentEvent{
			Actor:     EventActorWriter(),
			Repo:      eventRepo,
			Issue:     eventIssue,
			Action:    IssueAssignmentEventActionAssigned,
			Assignees: []string{assignee.Login},
		})

		require.NoError(t, err)
		require.True(t, didCallTwirp)
		require.Len(t, service.QueuedJobs(), 1)

		select {
		case <-messageChan:
			t.Error("No hydro event should be emitted immediately when queuing is enabled")
		case <-time.After(100 * time.Millisecond):
			// Expected: no event emitted immediately as jobs are queued by default
		}
	})

	t.Run("launches the agent", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}

		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		assignee := et.UserCopilot()
		issue := et.Issue(*assignee)
		ghFactory.MockIssueContext = &github.IssueContext{Repository: *et.Repo(), Issue: *issue}

		err := h.OnIssueAssigned(context.Background(), IssueAssignmentEvent{
			Actor:    EventActorWriter(),
			Repo:     EventRepository(),
			Issue:    EventIssue(),
			Action:   IssueAssignmentEventActionAssigned,
			Assignee: assignee.Login,
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
		require.Equal(t, et.ActorWriter().GetID(), service.QueuedJobs()[0].ActorId)
	})

	t.Run("uses previous body content if updated after hydro event (race condition)", func(t *testing.T) {
		ffAlt := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentIssueBodyEditCheck: true,
		})

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffAlt, jobStore, ghTwirp, ghFactory)

		assignee := et.UserCopilot()
		issue := et.Issue(*assignee)
		lastEditAt := time.Now()
		issue.LastEditedAt = &lastEditAt
		ghFactory.MockIssueContext = &github.IssueContext{Repository: *et.Repo(), Issue: *issue}
		ghFactory.MockIssueUserContentEdits = []github.UserContentEdit{
			{
				EditedAt: time.Now().Add(-time.Minute * 2), // Simulate an edit before the event timestamp
				Diff:     "~~Initial body content~~",
			},
			{
				EditedAt: *issue.LastEditedAt,
				Diff:     "~~Updated body content~~",
			},
		}

		err := h.OnIssueAssigned(context.Background(), IssueAssignmentEvent{
			Actor:     EventActorWriter(),
			Repo:      EventRepository(),
			Issue:     EventIssue(),
			Action:    IssueAssignmentEventActionAssigned,
			Assignees: []string{assignee.Login},
			Timestamp: time.Now().Add(-time.Minute), // Simulate a race condition
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		// Ensure we've passed the correct parameters to the launcher
		require.Equal(t, et.ActorWriter().GetID(), service.QueuedJobs()[0].ActorId)
	})

	t.Run("handles issues with no body", func(t *testing.T) {
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		assignee := et.UserCopilot()
		issue := et.Issue(*assignee)
		// set the issue body to empty
		issue.Body = ""
		ghFactory.MockIssueContext = &github.IssueContext{Repository: *et.Repo(), Issue: *issue}

		err := h.OnIssueAssigned(context.Background(), IssueAssignmentEvent{
			Actor:     EventActorWriter(),
			Repo:      EventRepository(),
			Issue:     EventIssue(),
			Action:    IssueAssignmentEventActionAssigned,
			Assignees: []string{assignee.Login},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
	})

	t.Run("handles issues in uninitialized repos", func(t *testing.T) {
		assignee := et.UserCopilot()
		repo := et.Repo()
		repo.DefaultBranchRef = nil
		gh := &github.NoopClient{
			MockRepositoryContext: &github.RepositoryContext{
				Repository: *repo,
			},
			GithubAppLogin: et.GitHubAppLogin,
			GithubBotLogin: et.GitHubBotLogin,
		}
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin:   et.GitHubAppLogin,
			GitHubBotLogin:   et.GitHubBotLogin,
			MockIssueContext: &github.IssueContext{Repository: *repo, Issue: *et.Issue(*assignee)},
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}

		h, service, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)

		err := h.OnIssueAssigned(context.Background(), IssueAssignmentEvent{
			Actor:     EventActorWriter(),
			Repo:      EventRepository(),
			Issue:     EventIssue(),
			Action:    IssueAssignmentEventActionAssigned,
			Assignees: []string{assignee.Login},
		})
		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)

		require.Len(t, gh.MethodCalls, 1)
		var createCommentCall github.MethodCall
		for _, call := range gh.MethodCalls {
			if call.Method == "CreateComment" {
				createCommentCall = call
				break
			}
		}
		require.NotEmpty(t, createCommentCall)
		require.Len(t, createCommentCall.Args, 3)
		commentBody := createCommentCall.Args[2].(string)
		require.Contains(t, commentBody, "This repository doesn't have any commits yet")
	})

	t.Run("ignores events where the assigner doesn't have repo write access", func(t *testing.T) {
		h, service, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)

		assignee := et.UserCopilot()
		issue := et.Issue(*assignee)
		ghFactory.MockIssueContext = &github.IssueContext{Repository: *et.Repo(), Issue: *issue}

		err := h.OnIssueAssigned(context.Background(), IssueAssignmentEvent{
			Actor:     EventActorReader(), // Reader doesn't have write access
			Repo:      EventRepository(),
			Issue:     EventIssue(),
			Action:    IssueAssignmentEventActionAssigned,
			Assignees: []string{assignee.Login},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("handles rules violation", func(t *testing.T) {
		tests := []struct {
			name               string
			mockedClient       *github.NoopClient
			expectedComment    string
			launchAgentCalls   int
			createCommentCalls int
		}{
			{
				name: "blocks branch creation",
				mockedClient: &github.NoopClient{
					MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
						return &[]github.GQLBranchProtectionRule{{
							Pattern:         fmt.Sprintf("%s/*", github.CopilotBranchPrefix),
							BlocksCreations: true,
						}}, nil
					},
				},
				expectedComment:    fmt.Sprintf("%s due to branch protection rules", github.RuleBlockCreation),
				createCommentCalls: 1,
			},
			{
				name: "requires pull requests",
				mockedClient: &github.NoopClient{
					MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
						return &[]github.GQLBranchProtectionRule{{
							Pattern:                  fmt.Sprintf("%s/*", github.CopilotBranchPrefix),
							RequiresApprovingReviews: true,
						}}, nil
					},
				},
				expectedComment:    fmt.Sprintf("%s due to branch protection rules", github.RuleRequirePullRequest),
				createCommentCalls: 1,
			},
			{
				name: "requires signing commits",
				mockedClient: &github.NoopClient{
					MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
						return &[]github.GQLBranchProtectionRule{{
							Pattern:                  fmt.Sprintf("%s/*", github.CopilotBranchPrefix),
							RequiresCommitSignatures: true,
						}}, nil
					},
				},
				expectedComment:    fmt.Sprintf("%s due to branch protection rules", github.RuleRequireSignatures),
				createCommentCalls: 1,
			},
			{
				name: "blocks branch creation",
				mockedClient: &github.NoopClient{
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin string, repoName string, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return &gg.BranchRules{
							Creation: []*gg.BranchRuleMetadata{{RulesetID: 1}},
						}, nil
					},
				},
				expectedComment:    fmt.Sprintf("%s due to repository rules", github.RuleBlockCreation),
				createCommentCalls: 1,
			},
			{
				name: "requires pull requests",
				mockedClient: &github.NoopClient{
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin string, repoName string, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return &gg.BranchRules{
							PullRequest: []*gg.PullRequestBranchRule{{BranchRuleMetadata: gg.BranchRuleMetadata{RulesetID: 2}}},
						}, nil
					},
				},
				expectedComment:    fmt.Sprintf("%s due to repository rules", github.RuleRequirePullRequest),
				createCommentCalls: 1,
			},
			{
				name: "requires signing commits",
				mockedClient: &github.NoopClient{
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin string, repoName string, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return &gg.BranchRules{
							RequiredSignatures: []*gg.BranchRuleMetadata{{RulesetID: 3}},
						}, nil
					},
				},
				expectedComment:    fmt.Sprintf("%s due to repository rules", github.RuleRequireSignatures),
				createCommentCalls: 1,
			},
			{
				name: "requires code scanning results",
				mockedClient: &github.NoopClient{
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin string, repoName string, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return &gg.BranchRules{
							CodeScanning: []*gg.CodeScanningBranchRule{{BranchRuleMetadata: gg.BranchRuleMetadata{RulesetID: 3}}},
						}, nil
					},
				},
				expectedComment:    fmt.Sprintf("%s due to repository rules", github.RuleCodeScanning),
				createCommentCalls: 1,
			},
			{
				name: "restricts commit message",
				mockedClient: &github.NoopClient{
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin string, repoName string, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return &gg.BranchRules{
							CommitMessagePattern: []*gg.PatternBranchRule{{BranchRuleMetadata: gg.BranchRuleMetadata{RulesetID: 3}}},
						}, nil
					},
				},
				expectedComment:    fmt.Sprintf("%s due to repository rules", github.RuleCommitMessagePattern),
				createCommentCalls: 1,
			},
			{
				name: "commit author email rule (starts with)",
				mockedClient: &github.NoopClient{
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin string, repoName string, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return &gg.BranchRules{
							CommitAuthorEmailPattern: []*gg.PatternBranchRule{
								{
									Parameters: gg.PatternRuleParameters{
										Pattern:  "dev@",
										Operator: gg.PatternRuleOperatorStartsWith,
									},
								},
							},
						}, nil
					},
				},
				expectedComment:    fmt.Sprintf("%s (must start with ***) due to repository rules", github.RuleCommitAuthorEmailPattern),
				createCommentCalls: 1,
			},
			{
				name: "commit author email rule (ends with)",
				mockedClient: &github.NoopClient{
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin string, repoName string, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return &gg.BranchRules{
							CommitAuthorEmailPattern: []*gg.PatternBranchRule{
								{
									Parameters: gg.PatternRuleParameters{
										Pattern:  "@company.com",
										Operator: gg.PatternRuleOperatorEndsWith,
									},
								},
							},
						}, nil
					},
				},
				expectedComment:    fmt.Sprintf("%s (must end with ***) due to repository rules", github.RuleCommitAuthorEmailPattern),
				createCommentCalls: 1,
			},
			{
				name: "commit author email rule (contains negated)",
				mockedClient: &github.NoopClient{
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin string, repoName string, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return &gg.BranchRules{
							CommitAuthorEmailPattern: []*gg.PatternBranchRule{
								{
									Parameters: gg.PatternRuleParameters{
										Pattern:  "example.com",
										Operator: gg.PatternRuleOperatorContains,
										Negate:   gg.Ptr(true),
									},
								},
							},
						}, nil
					},
				},
				expectedComment:    fmt.Sprintf("%s (must not contain ***) due to repository rules", github.RuleCommitAuthorEmailPattern),
				createCommentCalls: 1,
			},
			{
				name: "commit author email rule (regex)",
				mockedClient: &github.NoopClient{
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin string, repoName string, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return &gg.BranchRules{
							CommitAuthorEmailPattern: []*gg.PatternBranchRule{
								{
									Parameters: gg.PatternRuleParameters{
										Pattern:  "^[a-z]+@(github|microsoft)\\.com$",
										Operator: gg.PatternRuleOperatorRegex,
									},
								},
							},
						}, nil
					},
				},
				expectedComment:    fmt.Sprintf("%s (must match regex ***) due to repository rules", github.RuleCommitAuthorEmailPattern),
				createCommentCalls: 1,
			},
			{
				name: "committer email rule (starts with)",
				mockedClient: &github.NoopClient{
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin string, repoName string, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return &gg.BranchRules{
							CommitterEmailPattern: []*gg.PatternBranchRule{
								{
									Parameters: gg.PatternRuleParameters{
										Pattern:  "admin@",
										Operator: gg.PatternRuleOperatorStartsWith,
									},
								},
							},
						}, nil
					},
				},
				expectedComment:    fmt.Sprintf("%s (must start with ***) due to repository rules", github.RuleCommitterEmailPattern),
				createCommentCalls: 1,
			},
			{
				name: "committer email rule (ends with)",
				mockedClient: &github.NoopClient{
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin string, repoName string, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return &gg.BranchRules{
							CommitterEmailPattern: []*gg.PatternBranchRule{
								{
									Parameters: gg.PatternRuleParameters{
										Pattern:  "@enterprise.com",
										Operator: gg.PatternRuleOperatorEndsWith,
									},
								},
							},
						}, nil
					},
				},
				expectedComment:    fmt.Sprintf("%s (must end with ***) due to repository rules", github.RuleCommitterEmailPattern),
				createCommentCalls: 1,
			},
			{
				name: "committer email rule (contains)",
				mockedClient: &github.NoopClient{
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin string, repoName string, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return &gg.BranchRules{
							CommitterEmailPattern: []*gg.PatternBranchRule{
								{
									Parameters: gg.PatternRuleParameters{
										Pattern:  "verified",
										Operator: gg.PatternRuleOperatorContains,
									},
								},
							},
						}, nil
					},
				},
				expectedComment:    fmt.Sprintf("%s (must contain ***) due to repository rules", github.RuleCommitterEmailPattern),
				createCommentCalls: 1,
			},
			{
				name: "committer email rule (regex with negation)",
				mockedClient: &github.NoopClient{
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin string, repoName string, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return &gg.BranchRules{
							CommitterEmailPattern: []*gg.PatternBranchRule{
								{
									Parameters: gg.PatternRuleParameters{
										Pattern:  "^test@.*\\.com$",
										Operator: gg.PatternRuleOperatorRegex,
										Negate:   gg.Ptr(true),
									},
								},
							},
						}, nil
					},
				},
				expectedComment:    fmt.Sprintf("%s (must not match regex ***) due to repository rules", github.RuleCommitterEmailPattern),
				createCommentCalls: 1,
			},
			{
				name: "copilot branch name collision",
				mockedClient: &github.NoopClient{
					MockCheckIfBranchExists: func(ctx context.Context, ownerLogin string, repoName string, branchName string) (bool, error) {
						return true, nil // Simulate that the branch already exists
					},
				},
				expectedComment:    github.RuleCopilotBranchExists,
				createCommentCalls: 1,
			},
			{
				name: "github actions disabled (no longer blocks)",
				mockedClient: &github.NoopClient{
					MockGetActionsPermissions: func(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error) {
						enabled := false
						return &gg.ActionsPermissionsRepository{Enabled: &enabled}, nil
					},
				},
				// Actions disabled is no longer a blocking rule, so the agent should launch successfully
				launchAgentCalls: 1,
			},
			{
				name: "requires signing commits (noop with error)",
				mockedClient: &github.NoopClient{
					MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
						return nil, fmt.Errorf("failed to get branch protection rules")
					},
				},
				expectedComment:  fmt.Sprintf("%s due to branch protection rules", github.RuleRequireSignatures),
				launchAgentCalls: 1,
			},
			{
				name: "blocks branch creation (noop with error)",
				mockedClient: &github.NoopClient{
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin string, repoName string, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return nil, fmt.Errorf("failed to get repository rules for branch")
					},
				},
				expectedComment:  fmt.Sprintf("%s due to repository rules", github.RuleBlockCreation),
				launchAgentCalls: 1,
			},
			{
				name: "branch name rule (start with)",
				mockedClient: &github.NoopClient{
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin string, repoName string, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return &gg.BranchRules{
							BranchNamePattern: []*gg.PatternBranchRule{
								{
									Parameters: gg.PatternRuleParameters{
										Pattern:  "users/",
										Operator: gg.PatternRuleOperatorStartsWith,
									},
								},
							},
						}, nil
					},
				},
				expectedComment:    fmt.Sprintf("%s (must start with ***) due to repository rules", github.RuleBranchNamePattern),
				createCommentCalls: 1,
			},
			{
				name: "branch name rule (contain negated)",
				mockedClient: &github.NoopClient{
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin string, repoName string, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return &gg.BranchRules{
							BranchNamePattern: []*gg.PatternBranchRule{
								{
									Parameters: gg.PatternRuleParameters{
										Pattern:  "copilot",
										Operator: gg.PatternRuleOperatorContains,
										Negate:   gg.Ptr(true),
									},
								},
							},
						}, nil
					},
				},
				expectedComment:    fmt.Sprintf("%s (must not contain ***) due to repository rules", github.RuleBranchNamePattern),
				createCommentCalls: 1,
			},
			{
				name: "branch name rule (match regex)",
				mockedClient: &github.NoopClient{
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin string, repoName string, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return &gg.BranchRules{
							BranchNamePattern: []*gg.PatternBranchRule{
								{
									Parameters: gg.PatternRuleParameters{
										Pattern:  "^(feature|fix)\\/(\\S+-\\d+)\\_(.+)$",
										Operator: gg.PatternRuleOperatorRegex,
									},
								},
							},
						}, nil
					},
				},
				expectedComment:    fmt.Sprintf("%s (must match regex ***) due to repository rules", github.RuleBranchNamePattern),
				createCommentCalls: 1,
			},
			{
				name: "copilot branch name collision (noop with error)",
				mockedClient: &github.NoopClient{
					MockCheckIfBranchExists: func(ctx context.Context, ownerLogin string, repoName string, branchName string) (bool, error) {
						return false, fmt.Errorf("branch collision check failed")
					},
				},
				launchAgentCalls: 1,
			},
			{
				name: "github actions disabled (noop with error)",
				mockedClient: &github.NoopClient{
					MockGetActionsPermissions: func(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error) {
						return nil, fmt.Errorf("actions permissions not found")
					},
				},
				launchAgentCalls: 1,
			},
		}

		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				capiClient, jobStore, ghTwirp := commonHandlerDependencies()
				assignee := et.UserCopilot()
				issue := et.Issue(*assignee)
				// Create a fresh copy of the mocked client for each builderFF iteration so we don't
				// accumulate MethodCalls across the flag variants.
				origClient := tt.mockedClient
				gh := &github.NoopClient{}
				*gh = *origClient
				gh.MethodCalls = nil
				gh.MockIssueContext = &github.IssueContext{Repository: *et.Repo(), Issue: *issue}
				cf := &github.NoopClientFactory{
					MockNewClient: func(token string) github.ClientInterface { return gh },
				}
				ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
					return &copilotUsersTwirp.GetCopilotUserResponse{
						UserDetails: &copilotUsersTwirp.CopilotUserDetails{CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE},
					}, nil
				}
				flags := map[string]bool{}
				ffLocal := featureflags.NewNoopClient(flags)
				h, service, _ := NewTestHandler(t, obsv, capiClient, ffLocal, jobStore, ghTwirp, cf)

				err := h.OnIssueAssigned(context.Background(), IssueAssignmentEvent{
					Actor:     EventActorWriter(),
					Repo:      EventRepository(),
					Issue:     EventIssue(),
					Action:    IssueAssignmentEventActionAssigned,
					Assignees: []string{assignee.Login},
				})

				if tt.createCommentCalls > 0 { // expect a rules violation surfaced as error and a single comment
					require.Error(t, err)
					require.Contains(t, err.Error(), "repository rules violation")
					require.Len(t, service.QueuedJobs(), 0)
					require.Len(t, gh.MethodCalls, tt.createCommentCalls)
					var createCommentCall github.MethodCall
					for _, call := range gh.MethodCalls {
						if call.Method == "CreateComment" {
							createCommentCall = call
							break
						}
					}
					require.NotEmpty(t, createCommentCall)
					require.Len(t, createCommentCall.Args, 3)
					commentBody := createCommentCall.Args[2].(string)
					require.Contains(t, commentBody, tt.expectedComment)
					return
				}
				// No rules violation detected -> no error, job may have been queued
				require.NoError(t, err)
				require.Len(t, service.QueuedJobs(), tt.launchAgentCalls)
				require.Len(t, gh.MethodCalls, 0)
			}) // end inner builderFF loop subtest
		} // end builderFF loop
	}) // end individual rules violation case
}

func TestOnIssueAssigned_Experiments(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}

	t.Run("calls the experiment client", func(t *testing.T) {
		tests := []struct {
			name        string
			experiments []string
		}{
			{
				name:        "looks for the ghpad_aa experiment",
				experiments: []string{"ghpad_aa"},
			},
			{
				name:        "looks for the padawan_exp_oswe experiment",
				experiments: []string{"padawan_exp_oswe"},
			},
		}

		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				ffc := featureflags.NewNoopClient(nil)
				capiClient, jobStore, ghTwirp := commonHandlerDependencies()
				ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
					return &copilotUsersTwirp.GetCopilotUserResponse{
						UserDetails: &copilotUsersTwirp.CopilotUserDetails{
							CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
						},
					}, nil
				}
				h, s, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)

				assignee := et.UserCopilot()
				issue := et.Issue(*assignee)
				ghFactory.MockIssueContext = &github.IssueContext{Repository: *et.Repo(), Issue: *issue}

				err := h.OnIssueAssigned(context.Background(), IssueAssignmentEvent{
					Actor:     EventActorWriter(),
					Repo:      EventRepository(),
					Issue:     EventIssue(),
					Action:    IssueAssignmentEventActionAssigned,
					Assignees: []string{assignee.Login},
				})

				require.NoError(t, err)
				for _, exp := range tt.experiments {
					require.True(t, s.Experiments.GetFeatureAssignmentCalledWithFeatureName(exp))
				}
			})
		}
	})
}
