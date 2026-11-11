package automations

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/observability"
	cmcautomationsv1 "github.com/github/sweagentd/internal/proto/twirp/automations/v1"
	"github.com/stretchr/testify/require"
)

type fakeCMCAutomationsClient struct {
	hasReqs  []*cmcautomationsv1.HasRepositoryAutomationRequest
	listReqs []*cmcautomationsv1.ListRepositoryAutomationsRequest
	getReqs  []*cmcautomationsv1.GetAutomationByIDRequest
	hasResp  *cmcautomationsv1.HasRepositoryAutomationResponse
	listResp []*cmcautomationsv1.ListRepositoryAutomationsResponse
	getResp  *cmcautomationsv1.GetAutomationByIDResponse
	hasErr   error
	listErr  error
	getErr   error
}

func newTestCMCLookup(client *fakeCMCAutomationsClient) Lookup {
	return NewCMCLookup(client, nil, observability.NewNoopExporters(), time.Second)
}

func (f *fakeCMCAutomationsClient) HasRepositoryAutomation(_ context.Context, req *cmcautomationsv1.HasRepositoryAutomationRequest) (*cmcautomationsv1.HasRepositoryAutomationResponse, error) {
	f.hasReqs = append(f.hasReqs, req)
	if f.hasErr != nil {
		return nil, f.hasErr
	}
	return f.hasResp, nil
}

func (f *fakeCMCAutomationsClient) ListRepositoryAutomations(_ context.Context, req *cmcautomationsv1.ListRepositoryAutomationsRequest) (*cmcautomationsv1.ListRepositoryAutomationsResponse, error) {
	f.listReqs = append(f.listReqs, req)
	if f.listErr != nil {
		return nil, f.listErr
	}
	if len(f.listReqs) > len(f.listResp) {
		return nil, errors.New("test fake ran out of configured list responses")
	}
	resp := f.listResp[len(f.listReqs)-1]
	return resp, nil
}

func (f *fakeCMCAutomationsClient) GetAutomationByID(_ context.Context, req *cmcautomationsv1.GetAutomationByIDRequest) (*cmcautomationsv1.GetAutomationByIDResponse, error) {
	f.getReqs = append(f.getReqs, req)
	if f.getErr != nil {
		return nil, f.getErr
	}
	return f.getResp, nil
}

func TestCMCLookupHasActiveForEventMapsIssueCreated(t *testing.T) {
	client := &fakeCMCAutomationsClient{
		hasResp: &cmcautomationsv1.HasRepositoryAutomationResponse{HasAutomation: true},
	}
	lookup := newTestCMCLookup(client)

	hasActive, err := lookup.HasActiveForEvent(context.Background(), EventMatchRequest{
		OwnerID:      1,
		RepoID:       2,
		EventName:    EventIssues,
		ActivityType: ActivityIssueOpened,
	})

	require.NoError(t, err)
	require.True(t, hasActive)
	require.Len(t, client.hasReqs, 1)
	require.Equal(t, uint64(1), client.hasReqs[0].GetOwnerId())
	require.Equal(t, uint64(2), client.hasReqs[0].GetRepoId())
	require.Equal(t, "issues", client.hasReqs[0].GetEvent())
	require.Equal(t, []string{"opened"}, client.hasReqs[0].GetTypes())
}

func TestCMCLookupHasActiveForEventUnsupportedEventReturnsErrorWithoutCallingCMC(t *testing.T) {
	client := &fakeCMCAutomationsClient{}
	lookup := newTestCMCLookup(client)

	hasActive, err := lookup.HasActiveForEvent(context.Background(), EventMatchRequest{
		OwnerID:      1,
		RepoID:       2,
		EventName:    EventName("discussion"),
		ActivityType: "created",
	})

	require.ErrorContains(t, err, "unsupported automation event lookup: discussion.created")
	require.False(t, hasActive)
	require.Empty(t, client.hasReqs)
}

func TestCMCLookupHasActiveForEventWorkflowRunNonFailureSkipsCMC(t *testing.T) {
	client := &fakeCMCAutomationsClient{}
	lookup := newTestCMCLookup(client)

	hasActive, err := lookup.HasActiveForEvent(context.Background(), EventMatchRequest{
		OwnerID:            1,
		RepoID:             2,
		EventName:          EventWorkflowRun,
		ActivityType:       ActivityWorkflowRunFailed,
		WorkflowConclusion: WorkflowConclusion("success"),
	})

	require.NoError(t, err)
	require.False(t, hasActive)
	require.Empty(t, client.hasReqs)
}

func TestCMCLookupHasActiveForEventPropagatesClientError(t *testing.T) {
	client := &fakeCMCAutomationsClient{
		hasErr: errors.New("cmc unavailable"),
	}
	lookup := newTestCMCLookup(client)

	hasActive, err := lookup.HasActiveForEvent(context.Background(), EventMatchRequest{
		OwnerID:      1,
		RepoID:       2,
		EventName:    EventIssues,
		ActivityType: ActivityIssueOpened,
	})

	require.ErrorContains(t, err, "failed to query CMC automation presence")
	require.ErrorContains(t, err, "cmc unavailable")
	require.False(t, hasActive)
}

func TestCMCLookupWorkflowRunHasActiveUsesCompletedType(t *testing.T) {
	client := &fakeCMCAutomationsClient{
		hasResp: &cmcautomationsv1.HasRepositoryAutomationResponse{HasAutomation: true},
	}
	lookup := newTestCMCLookup(client)

	hasActive, err := lookup.HasActiveForEvent(context.Background(), EventMatchRequest{
		OwnerID:            1,
		RepoID:             2,
		EventName:          EventWorkflowRun,
		ActivityType:       ActivityWorkflowRunFailed,
		WorkflowConclusion: WorkflowConclusionFailure,
	})

	require.NoError(t, err)
	require.True(t, hasActive)
	require.Len(t, client.hasReqs, 1)
	require.Equal(t, "workflow_run", client.hasReqs[0].GetEvent())
	require.Equal(t, []string{"completed"}, client.hasReqs[0].GetTypes())
}

func TestCMCLookupHasActiveForEventMapsInterval(t *testing.T) {
	client := &fakeCMCAutomationsClient{
		hasResp: &cmcautomationsv1.HasRepositoryAutomationResponse{HasAutomation: true},
	}
	lookup := newTestCMCLookup(client)

	hasActive, err := lookup.HasActiveForEvent(context.Background(), EventMatchRequest{
		OwnerID:   1,
		RepoID:    2,
		EventName: EventInterval,
	})

	require.NoError(t, err)
	require.True(t, hasActive)
	require.Len(t, client.hasReqs, 1)
	require.Equal(t, "interval", client.hasReqs[0].GetEvent())
	require.Empty(t, client.hasReqs[0].GetTypes())
}

func TestCMCLookupHasActiveForEventMapsPullRequestOpened(t *testing.T) {
	client := &fakeCMCAutomationsClient{
		hasResp: &cmcautomationsv1.HasRepositoryAutomationResponse{HasAutomation: true},
	}
	lookup := newTestCMCLookup(client)

	hasActive, err := lookup.HasActiveForEvent(context.Background(), EventMatchRequest{
		OwnerID:      1,
		RepoID:       2,
		EventName:    EventPullRequest,
		ActivityType: ActivityPullRequestOpened,
	})

	require.NoError(t, err)
	require.True(t, hasActive)
	require.Len(t, client.hasReqs, 1)
	require.Equal(t, uint64(1), client.hasReqs[0].GetOwnerId())
	require.Equal(t, uint64(2), client.hasReqs[0].GetRepoId())
	require.Equal(t, "pull_request_opened", client.hasReqs[0].GetEvent())
	require.Equal(t, []string{"opened"}, client.hasReqs[0].GetTypes())
}

func TestCMCLookupHasActiveForEventPullRequestSynchronize(t *testing.T) {
	client := &fakeCMCAutomationsClient{}
	lookup := newTestCMCLookup(client)

	_, err := lookup.HasActiveForEvent(context.Background(), EventMatchRequest{
		OwnerID:      1,
		RepoID:       2,
		EventName:    EventPullRequest,
		ActivityType: "synchronize",
	})

	require.NoError(t, err)
	require.Len(t, client.hasReqs, 1)
	require.Equal(t, "pull_request_synchronize", client.hasReqs[0].GetEvent())
	require.Equal(t, []string{"synchronize"}, client.hasReqs[0].GetTypes())
}

func TestCMCLookupHasActiveForEventPullRequestUnknownActivityIsUnsupported(t *testing.T) {
	client := &fakeCMCAutomationsClient{}
	lookup := newTestCMCLookup(client)

	hasActive, err := lookup.HasActiveForEvent(context.Background(), EventMatchRequest{
		OwnerID:      1,
		RepoID:       2,
		EventName:    EventPullRequest,
		ActivityType: "unsupported_activity",
	})

	require.ErrorContains(t, err, "unsupported automation event lookup: pull_request.unsupported_activity")
	require.False(t, hasActive)
	require.Empty(t, client.hasReqs)
}

func TestCMCLookupListForWorkflowRunFiltersByWorkflowAndConclusion(t *testing.T) {
	client := &fakeCMCAutomationsClient{
		listResp: []*cmcautomationsv1.ListRepositoryAutomationsResponse{{
			Automations: []*cmcautomationsv1.Automation{
				{
					Id: "automation-1",
					Triggers: []*cmcautomationsv1.AutomationTrigger{{
						Event:       "workflow_run",
						Types:       []string{"completed"},
						Workflows:   []string{"CI"},
						Conclusions: []string{"failure"},
					}},
					Name:    "fix-ci",
					OwnerId: 1,
					RepoId:  2,
					UserId:  9001,
				},
				{
					Id: "automation-2",
					Triggers: []*cmcautomationsv1.AutomationTrigger{{
						Event:       "workflow_run",
						Types:       []string{"completed"},
						Workflows:   []string{"Deploy"},
						Conclusions: []string{"failure"},
					}},
					Name:    "fix-deploy",
					OwnerId: 1,
					RepoId:  2,
				},
				{
					Id: "automation-3",
					Triggers: []*cmcautomationsv1.AutomationTrigger{{
						Event:       "workflow_run",
						Types:       []string{"completed"},
						Workflows:   []string{"CI"},
						Conclusions: []string{"success"},
					}},
					Name:    "celebrate-ci",
					OwnerId: 1,
					RepoId:  2,
				},
			},
		}},
	}
	lookup := newTestCMCLookup(client)

	configs, err := lookup.ListForEvent(context.Background(), ListForEventRequest{
		Event: EventMatchRequest{
			OwnerID:            1,
			RepoID:             2,
			EventName:          EventWorkflowRun,
			ActivityType:       ActivityWorkflowRunFailed,
			WorkflowConclusion: WorkflowConclusionFailure,
			WorkflowName:       "CI",
		},
	})

	require.NoError(t, err)
	require.Len(t, configs, 1)
	require.Equal(t, "fix-ci", configs[0].CustomAgent.Name())
	require.Equal(t, "automation-1", configs[0].AutomationID)
	require.Equal(t, int64(9001), configs[0].AutomationOwnerID)
	require.Len(t, client.listReqs, 1)
	require.Equal(t, "workflow_run", client.listReqs[0].GetEvent())
	require.Equal(t, []string{"completed"}, client.listReqs[0].GetTypes())
}

func TestCMCLookupListForWorkflowRunRequiresWorkflowFilter(t *testing.T) {
	client := &fakeCMCAutomationsClient{
		listResp: []*cmcautomationsv1.ListRepositoryAutomationsResponse{{
			Automations: []*cmcautomationsv1.Automation{{
				Id: "automation-1",
				Triggers: []*cmcautomationsv1.AutomationTrigger{{
					Event:       "workflow_run",
					Types:       []string{"completed"},
					Conclusions: []string{"failure"},
				}},
				Name:    "fix-ci",
				OwnerId: 1,
				RepoId:  2,
			}},
		}},
	}
	lookup := newTestCMCLookup(client)

	configs, err := lookup.ListForEvent(context.Background(), ListForEventRequest{
		Event: EventMatchRequest{
			OwnerID:            1,
			RepoID:             2,
			EventName:          EventWorkflowRun,
			ActivityType:       ActivityWorkflowRunFailed,
			WorkflowConclusion: WorkflowConclusionFailure,
			WorkflowName:       "CI",
		},
	})

	require.NoError(t, err)
	require.Empty(t, configs)
}

func TestCMCLookupListForIntervalMatchesByEventOnly(t *testing.T) {
	client := &fakeCMCAutomationsClient{
		listResp: []*cmcautomationsv1.ListRepositoryAutomationsResponse{{
			Automations: []*cmcautomationsv1.Automation{
				{
					Id: "automation-1",
					Triggers: []*cmcautomationsv1.AutomationTrigger{{
						Event: "interval",
					}},
					Name:    "hourly-maintenance",
					OwnerId: 1,
					RepoId:  2,
				},
				{
					Id: "automation-2",
					Triggers: []*cmcautomationsv1.AutomationTrigger{{
						Event: "issues",
						Types: []string{"opened"},
					}},
					Name:    "issue-triage",
					OwnerId: 1,
					RepoId:  2,
				},
			},
		}},
	}
	lookup := newTestCMCLookup(client)

	configs, err := lookup.ListForEvent(context.Background(), ListForEventRequest{
		Event: EventMatchRequest{
			OwnerID:   1,
			RepoID:    2,
			EventName: EventInterval,
		},
	})

	require.NoError(t, err)
	require.Len(t, configs, 1)
	require.Equal(t, "automation-1", configs[0].AutomationID)
	require.Equal(t, "hourly-maintenance", configs[0].CustomAgent.Name())
	require.NotNil(t, configs[0].CustomAgent.Triggers().Interval)
	require.Len(t, client.listReqs, 1)
	require.Equal(t, "interval", client.listReqs[0].GetEvent())
	require.Empty(t, client.listReqs[0].GetTypes())
}

func TestCMCLookupListForIssueIgnoresQuery(t *testing.T) {
	client := &fakeCMCAutomationsClient{
		listResp: []*cmcautomationsv1.ListRepositoryAutomationsResponse{{
			Automations: []*cmcautomationsv1.Automation{
				{
					Id: "automation-1",
					Triggers: []*cmcautomationsv1.AutomationTrigger{{
						Event: "issues",
						Types: []string{"opened"},
						Query: "label:auto-triage",
					}},
					Name:                        "triage-labeled",
					OwnerId:                     1,
					RepoId:                      2,
					UserId:                      9001,
					RequireActorWritePermission: true,
				},
				{
					Id: "automation-2",
					Triggers: []*cmcautomationsv1.AutomationTrigger{{
						Event: "issues",
						Types: []string{"opened"},
					}},
					Name:    "triage-any",
					OwnerId: 1,
					RepoId:  2,
					UserId:  9002,
				},
			},
		}},
	}
	lookup := newTestCMCLookup(client)

	configs, err := lookup.ListForEvent(context.Background(), ListForEventRequest{
		Event: EventMatchRequest{
			OwnerID:      1,
			RepoID:       2,
			EventName:    EventIssues,
			ActivityType: ActivityIssueOpened,
		},
	})

	require.NoError(t, err)
	require.Len(t, configs, 2)
	require.Equal(t, "triage-labeled", configs[0].CustomAgent.Name())
	require.Equal(t, "automation-1", configs[0].AutomationID)
	require.Equal(t, int64(9001), configs[0].AutomationOwnerID)
	require.True(t, configs[0].RequireActorWritePermission)
	require.NotNil(t, configs[0].CustomAgent.Triggers().Issues)
	require.Equal(t, "label:auto-triage", configs[0].CustomAgent.Triggers().Issues.Query)
	require.Equal(t, "triage-any", configs[1].CustomAgent.Name())
	require.Equal(t, "automation-2", configs[1].AutomationID)
	require.Equal(t, int64(9002), configs[1].AutomationOwnerID)
	require.False(t, configs[1].RequireActorWritePermission)
	require.NotNil(t, configs[1].CustomAgent.Triggers().Issues)
	require.Empty(t, configs[1].CustomAgent.Triggers().Issues.Query)
}

func TestCMCLookupListForPullRequestOpenedReturnsMatchingAutomations(t *testing.T) {
	client := &fakeCMCAutomationsClient{
		listResp: []*cmcautomationsv1.ListRepositoryAutomationsResponse{{
			Automations: []*cmcautomationsv1.Automation{
				{
					Id: "automation-1",
					Triggers: []*cmcautomationsv1.AutomationTrigger{{
						Event: "pull_request_opened",
						Types: []string{"opened"},
						Query: "label:dependencies -draft:true",
						Paths: []string{"src/**", "!**/*.md"},
					}},
					Name:    "pr-greeter",
					OwnerId: 1,
					RepoId:  2,
					UserId:  9001,
				},
				{
					Id: "automation-issues",
					Triggers: []*cmcautomationsv1.AutomationTrigger{{
						Event: "issues",
						Types: []string{"opened"},
					}},
					Name:    "issue-triage",
					OwnerId: 1,
					RepoId:  2,
					UserId:  9002,
				},
				{
					Id: "automation-pr-merged",
					Triggers: []*cmcautomationsv1.AutomationTrigger{{
						Event: "pull_request_merged",
						Types: []string{"merged"},
					}},
					Name:    "pr-merged-handler",
					OwnerId: 1,
					RepoId:  2,
					UserId:  9003,
				},
			},
		}},
	}
	lookup := newTestCMCLookup(client)

	configs, err := lookup.ListForEvent(context.Background(), ListForEventRequest{
		Event: EventMatchRequest{
			OwnerID:      1,
			RepoID:       2,
			EventName:    EventPullRequest,
			ActivityType: ActivityPullRequestOpened,
		},
	})

	require.NoError(t, err)
	require.Len(t, configs, 1)
	require.Equal(t, "pr-greeter", configs[0].CustomAgent.Name())
	require.Equal(t, "automation-1", configs[0].AutomationID)
	require.Equal(t, int64(9001), configs[0].AutomationOwnerID)
	require.NotNil(t, configs[0].CustomAgent.Triggers().PullRequestOpened)
	require.Equal(t, []string{"opened"}, configs[0].CustomAgent.Triggers().PullRequestOpened.Types)
	require.Equal(t, "label:dependencies -draft:true", configs[0].CustomAgent.Triggers().PullRequestOpened.Query)
	require.Equal(t, []string{"src/**", "!**/*.md"}, configs[0].CustomAgent.Triggers().PullRequestOpened.Paths)
}

func TestCMCLookupListForPullRequestSynchronizeRoutesToSynchronizeField(t *testing.T) {
	client := &fakeCMCAutomationsClient{
		listResp: []*cmcautomationsv1.ListRepositoryAutomationsResponse{{
			Automations: []*cmcautomationsv1.Automation{{
				Id: "automation-sync",
				Triggers: []*cmcautomationsv1.AutomationTrigger{{
					Event: "pull_request_synchronize",
					Types: []string{"synchronize"},
					Query: "draft:false",
					Paths: []string{"app/**"},
				}},
				Name:    "pr-sync",
				OwnerId: 1,
				RepoId:  2,
				UserId:  9001,
			}},
		}},
	}
	lookup := newTestCMCLookup(client)

	configs, err := lookup.ListForEvent(context.Background(), ListForEventRequest{
		Event: EventMatchRequest{
			OwnerID:      1,
			RepoID:       2,
			EventName:    EventPullRequest,
			ActivityType: ActivityPullRequestSynchronize,
		},
	})

	require.NoError(t, err)
	require.Len(t, configs, 1)
	triggers := configs[0].CustomAgent.Triggers()
	require.NotNil(t, triggers.PullRequestSynchronize)
	require.Nil(t, triggers.PullRequestOpened)
	require.Nil(t, triggers.PullRequestMerged)
	require.Equal(t, []string{"synchronize"}, triggers.PullRequestSynchronize.Types)
	require.Equal(t, "draft:false", triggers.PullRequestSynchronize.Query)
	require.Equal(t, []string{"app/**"}, triggers.PullRequestSynchronize.Paths)
}

func TestCMCLookupListForPullRequestMergedRoutesToMergedField(t *testing.T) {
	client := &fakeCMCAutomationsClient{
		listResp: []*cmcautomationsv1.ListRepositoryAutomationsResponse{{
			Automations: []*cmcautomationsv1.Automation{{
				Id: "automation-merged",
				Triggers: []*cmcautomationsv1.AutomationTrigger{{
					Event: "pull_request_merged",
					Types: []string{"merged"},
					Query: "base:main",
				}},
				Name:    "pr-merged",
				OwnerId: 1,
				RepoId:  2,
				UserId:  9001,
			}},
		}},
	}
	lookup := newTestCMCLookup(client)

	configs, err := lookup.ListForEvent(context.Background(), ListForEventRequest{
		Event: EventMatchRequest{
			OwnerID:      1,
			RepoID:       2,
			EventName:    EventPullRequest,
			ActivityType: ActivityPullRequestMerged,
		},
	})

	require.NoError(t, err)
	require.Len(t, configs, 1)
	triggers := configs[0].CustomAgent.Triggers()
	require.NotNil(t, triggers.PullRequestMerged)
	require.Nil(t, triggers.PullRequestOpened)
	require.Nil(t, triggers.PullRequestSynchronize)
	require.Equal(t, []string{"merged"}, triggers.PullRequestMerged.Types)
	require.Equal(t, "base:main", triggers.PullRequestMerged.Query)
}

func TestCMCLookupListForEventPaginatesAndBuildsJobScopedAgents(t *testing.T) {
	client := &fakeCMCAutomationsClient{
		listResp: []*cmcautomationsv1.ListRepositoryAutomationsResponse{
			{
				Automations: []*cmcautomationsv1.Automation{{
					Id:                "automation-1",
					Name:              "triage",
					Description:       "Triage new issues",
					Model:             "gpt-5",
					Prompt:            "Read the issue and triage it.",
					Tools:             []string{"github"},
					Permissions:       map[string]string{"issues": "write"},
					GithubMcpToolsets: []string{"issues"},
					Triggers: []*cmcautomationsv1.AutomationTrigger{{
						Event: "issues",
						Types: []string{"opened"},
					}},
					OwnerId: 1,
					RepoId:  2,
				}},
				HasNextPage: true,
			},
			{
				Automations: []*cmcautomationsv1.Automation{{
					Id:          "automation-2",
					Description: "Label new issues",
					Prompt:      "Label the issue.",
					Triggers: []*cmcautomationsv1.AutomationTrigger{{
						Event: "issues",
						Types: []string{"opened"},
					}},
					OwnerId: 1,
					RepoId:  2,
				}},
			},
		},
	}
	lookup := newTestCMCLookup(client)

	configs, err := lookup.ListForEvent(context.Background(), ListForEventRequest{
		Event: EventMatchRequest{
			OwnerID:      1,
			RepoID:       2,
			EventName:    EventIssues,
			ActivityType: ActivityIssueOpened,
		},
		Repo: RepoInfo{
			OwnerLogin: "octo",
			RepoName:   "hello",
		},
	})

	require.NoError(t, err)
	require.Len(t, configs, 2)
	require.Equal(t, "automation-1", configs[0].AutomationID)
	require.Equal(t, "automation-2", configs[1].AutomationID)
	require.Len(t, client.listReqs, 2)
	require.Equal(t, int32(cmcListPageSize), client.listReqs[0].GetPageSize())
	require.Equal(t, int32(1), client.listReqs[0].GetPageNumber())
	require.Equal(t, int32(2), client.listReqs[1].GetPageNumber())

	agent := configs[0].CustomAgent
	require.Equal(t, "triage", agent.Name())
	require.Equal(t, "Triage new issues", agent.Description())
	require.Equal(t, "gpt-5", agent.Model())
	require.Equal(t, "Read the issue and triage it.", agent.Prompt())
	require.Equal(t, []string{"github"}, agent.Tools())
	require.Equal(t, int64(1), agent.RepoOwnerID())
	require.Equal(t, int64(2), agent.RepoID())
	require.Equal(t, "octo", agent.RepoOwner())
	require.Equal(t, "hello", agent.RepoName())
	require.Equal(t, []string{"issues"}, agent.GitHubMCPToolsets())
	require.True(t, agent.Triggers().HasDefinedTriggers())
	require.NotNil(t, agent.Triggers().Issues)
	require.Equal(t, []string{"opened"}, agent.Triggers().Issues.Types)
	require.Equal(t, "automation-2", configs[1].CustomAgent.Name())
}

func TestCMCLookupListForEventPropagatesClientError(t *testing.T) {
	client := &fakeCMCAutomationsClient{
		listErr: errors.New("cmc unavailable"),
	}
	lookup := newTestCMCLookup(client)

	configs, err := lookup.ListForEvent(context.Background(), ListForEventRequest{
		Event: EventMatchRequest{
			OwnerID:      1,
			RepoID:       2,
			EventName:    EventIssues,
			ActivityType: ActivityIssueOpened,
		},
	})

	require.ErrorContains(t, err, "failed to list CMC automations")
	require.ErrorContains(t, err, "cmc unavailable")
	require.Nil(t, configs)
}

func TestCMCLookupListForEventUnsupportedEventReturnsErrorWithoutCallingCMC(t *testing.T) {
	client := &fakeCMCAutomationsClient{}
	lookup := newTestCMCLookup(client)

	configs, err := lookup.ListForEvent(context.Background(), ListForEventRequest{
		Event: EventMatchRequest{
			OwnerID:      1,
			RepoID:       2,
			EventName:    EventName("discussion"),
			ActivityType: "created",
		},
	})

	require.ErrorContains(t, err, "unsupported automation event lookup: discussion.created")
	require.Nil(t, configs)
	require.Empty(t, client.listReqs)
}

func TestCMCLookupListForEventWorkflowRunNonFailureSkipsCMC(t *testing.T) {
	client := &fakeCMCAutomationsClient{}
	lookup := newTestCMCLookup(client)

	configs, err := lookup.ListForEvent(context.Background(), ListForEventRequest{
		Event: EventMatchRequest{
			OwnerID:            1,
			RepoID:             2,
			EventName:          EventWorkflowRun,
			ActivityType:       ActivityWorkflowRunFailed,
			WorkflowConclusion: WorkflowConclusion("success"),
		},
	})

	require.NoError(t, err)
	require.Nil(t, configs)
	require.Empty(t, client.listReqs)
}

func TestCMCLookupListForEventPaginationCapReturnsPartialConfigs(t *testing.T) {
	responses := make([]*cmcautomationsv1.ListRepositoryAutomationsResponse, 0, cmcListMaxPages)
	for range cmcListMaxPages {
		responses = append(responses, &cmcautomationsv1.ListRepositoryAutomationsResponse{
			Automations: []*cmcautomationsv1.Automation{{
				Id:   "automation",
				Name: "automation",
				Triggers: []*cmcautomationsv1.AutomationTrigger{{
					Event: "issues",
					Types: []string{"opened"},
				}},
				OwnerId: 1,
				RepoId:  2,
			}},
			HasNextPage: true,
		})
	}
	client := &fakeCMCAutomationsClient{listResp: responses}
	lookup := newTestCMCLookup(client)

	configs, err := lookup.ListForEvent(context.Background(), ListForEventRequest{
		Event: EventMatchRequest{
			OwnerID:      1,
			RepoID:       2,
			EventName:    EventIssues,
			ActivityType: ActivityIssueOpened,
		},
	})

	require.NoError(t, err)
	require.Len(t, configs, cmcListMaxPages)
	require.Len(t, client.listReqs, cmcListMaxPages)
	require.Equal(t, int32(cmcListMaxPages), client.listReqs[cmcListMaxPages-1].GetPageNumber())
}

func TestCMCLookupListForEventSkipsInvalidPermissionsAutomation(t *testing.T) {
	client := &fakeCMCAutomationsClient{
		listResp: []*cmcautomationsv1.ListRepositoryAutomationsResponse{{
			Automations: []*cmcautomationsv1.Automation{
				{
					Id:          "bad-permissions",
					Name:        "bad",
					Permissions: map[string]string{"issues": "admin"},
					Triggers: []*cmcautomationsv1.AutomationTrigger{{
						Event: "issues",
						Types: []string{"opened"},
					}},
					OwnerId: 1,
					RepoId:  2,
				},
				{
					Id:   "good",
					Name: "good",
					Triggers: []*cmcautomationsv1.AutomationTrigger{{
						Event: "issues",
						Types: []string{"opened"},
					}},
					OwnerId: 1,
					RepoId:  2,
				},
			},
		}},
	}
	lookup := newTestCMCLookup(client)

	configs, err := lookup.ListForEvent(context.Background(), ListForEventRequest{
		Event: EventMatchRequest{
			OwnerID:      1,
			RepoID:       2,
			EventName:    EventIssues,
			ActivityType: ActivityIssueOpened,
		},
	})

	require.NoError(t, err)
	require.Len(t, configs, 1)
	require.Equal(t, "good", configs[0].AutomationID)
}

func TestMCPConfigFromCMCAutomationMapsRemoteAndSkipsUnsupportedServers(t *testing.T) {
	agent, err := customAgentFromCMCAutomation(
		context.Background(),
		observability.NewNoopExporters(),
		stats.Tags{},
		&cmcautomationsv1.Automation{
			Id:      "automation-1",
			Name:    "triage",
			OwnerId: 1,
			RepoId:  2,
			McpServers: []*cmcautomationsv1.MCPServer{
				{Name: "remote", Type: "http", Url: "https://example.com/mcp", Tools: []string{"search"}},
				{Name: "", Type: "http", Url: "https://example.com/empty"},
				{Name: "local", Type: "stdio", Tools: []string{"local-tool"}},
				{Name: "unknown", Type: "custom", Tools: []string{"custom-tool"}},
			},
		},
		RepoInfo{},
	)

	require.NoError(t, err)
	agentWithMCP, ok := agent.(interface{ MCPConfig() mcpconfig.JSON })
	require.True(t, ok)
	cfg := agentWithMCP.MCPConfig()
	require.Len(t, cfg.Servers, 1)
	require.Contains(t, cfg.Servers, "remote")
	require.Equal(t, "http", cfg.Servers["remote"].Type)
	require.Equal(t, []string{"search"}, cfg.Servers["remote"].Tools)
	require.NotNil(t, cfg.Servers["remote"].Remote)
	require.Equal(t, "https://example.com/mcp", cfg.Servers["remote"].URL)
}

func TestCMCLookupListForEventByAutomationID_Success(t *testing.T) {
	client := &fakeCMCAutomationsClient{
		getResp: &cmcautomationsv1.GetAutomationByIDResponse{
			Automation: &cmcautomationsv1.Automation{
				Id:      "auto-123",
				Name:    "fix-ci",
				Prompt:  "Fix the CI failure",
				OwnerId: 10,
				RepoId:  20,
				UserId:  9001,
				Triggers: []*cmcautomationsv1.AutomationTrigger{{
					Event:       "workflow_run",
					Types:       []string{"completed"},
					Conclusions: []string{"failure"},
				}},
			},
		},
	}
	lookup := newTestCMCLookup(client)

	configs, err := lookup.ListForEvent(context.Background(), ListForEventRequest{
		Event: EventMatchRequest{
			OwnerID:   10,
			RepoID:    20,
			EventName: EventWorkflowRun,
		},
		Repo: RepoInfo{
			OwnerLogin: "octo",
			RepoName:   "hello",
		},
		AutomationID: "auto-123",
	})

	require.NoError(t, err)
	require.Len(t, configs, 1)
	require.Equal(t, "auto-123", configs[0].AutomationID)
	require.Equal(t, int64(9001), configs[0].AutomationOwnerID)
	require.Equal(t, "fix-ci", configs[0].CustomAgent.Name())
	require.Len(t, client.getReqs, 1)
	require.Equal(t, "auto-123", client.getReqs[0].GetAutomationId())
	// Verify list was NOT called (getAutomationByID path used instead)
	require.Len(t, client.listReqs, 0)
}

func TestCMCLookupListForEventByAutomationID_Error(t *testing.T) {
	client := &fakeCMCAutomationsClient{
		getErr: errors.New("CMC unavailable"),
	}
	lookup := newTestCMCLookup(client)

	_, err := lookup.ListForEvent(context.Background(), ListForEventRequest{
		Event: EventMatchRequest{
			OwnerID:   10,
			RepoID:    20,
			EventName: EventInterval,
		},
		Repo: RepoInfo{
			OwnerLogin: "octo",
			RepoName:   "hello",
		},
		AutomationID: "auto-123",
	})

	require.Error(t, err)
	require.Contains(t, err.Error(), "failed to get automation by ID from CMC")
	require.Contains(t, err.Error(), "CMC unavailable")
}

func TestCMCLookupListForEventByAutomationID_NilResponse(t *testing.T) {
	client := &fakeCMCAutomationsClient{
		getResp: nil,
	}
	lookup := newTestCMCLookup(client)

	_, err := lookup.ListForEvent(context.Background(), ListForEventRequest{
		Event: EventMatchRequest{
			OwnerID:   10,
			RepoID:    20,
			EventName: EventInterval,
		},
		Repo: RepoInfo{
			OwnerLogin: "octo",
			RepoName:   "hello",
		},
		AutomationID: "auto-123",
	})

	require.Error(t, err)
	require.Contains(t, err.Error(), "not found in CMC")
}

func TestCMCLookupListForEventByAutomationID_NilAutomation(t *testing.T) {
	client := &fakeCMCAutomationsClient{
		getResp: &cmcautomationsv1.GetAutomationByIDResponse{
			Automation: nil,
		},
	}
	lookup := newTestCMCLookup(client)

	_, err := lookup.ListForEvent(context.Background(), ListForEventRequest{
		Event: EventMatchRequest{
			OwnerID:   10,
			RepoID:    20,
			EventName: EventInterval,
		},
		Repo: RepoInfo{
			OwnerLogin: "octo",
			RepoName:   "hello",
		},
		AutomationID: "auto-123",
	})

	require.Error(t, err)
	require.Contains(t, err.Error(), "not found in CMC")
}
