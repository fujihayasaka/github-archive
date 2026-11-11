package hydro

import (
	"context"
	"errors"
	"testing"

	"github.com/github/feature-management-client-go/vexi/v2"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/automations"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/events"
	"github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdtwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/require"
)

func TestShouldEnvironmentDispatchEvent(t *testing.T) {
	actors := &mockActors{actorID: 1, repositoryID: 2, ownerID: 3}

	tests := []struct {
		name            string
		environment     config.Environment
		environmentName string
		flags           map[string]bool
		expected        bool
	}{
		{
			name:            "non-staging env with no staging flags returns true",
			environment:     config.EnvironmentProduction,
			environmentName: "production",
			flags:           map[string]bool{},
			expected:        true,
		},
		{
			name:            "staging env with no staging flags returns false",
			environment:     config.EnvironmentStaging,
			environmentName: "staging",
			flags:           map[string]bool{},
			expected:        false,
		},
		{
			name:            "non-staging env with staging flag enabled returns false",
			environment:     config.EnvironmentProduction,
			environmentName: "production",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging": true,
			},
			expected: false,
		},
		{
			name:            "staging env matching staging flag returns true",
			environment:     config.EnvironmentStaging,
			environmentName: "staging",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging": true,
			},
			expected: true,
		},
		{
			name:            "staging env not matching staging flag returns false",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-jedi-knight",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging": true,
			},
			expected: false,
		},
		{
			name:            "staging-jedi-knight env matching jedi-knight flag returns true",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-jedi-knight",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging_jedi_knight": true,
			},
			expected: true,
		},
		{
			name:            "staging-sith-lord env matching sith-lord flag returns true",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-sith-lord",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging_sith_lord": true,
			},
			expected: true,
		},
		{
			name:            "staging and jedi-knight flags: staging env wins",
			environment:     config.EnvironmentStaging,
			environmentName: "staging",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging":             true,
				"sweagentd_route_user_or_repo_to_staging_jedi_knight": true,
			},
			expected: true,
		},
		{
			name:            "staging and jedi-knight flags: jedi-knight env loses",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-jedi-knight",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging":             true,
				"sweagentd_route_user_or_repo_to_staging_jedi_knight": true,
			},
			expected: false,
		},
		{
			name:            "staging and sith-lord flags: staging env wins",
			environment:     config.EnvironmentStaging,
			environmentName: "staging",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging":           true,
				"sweagentd_route_user_or_repo_to_staging_sith_lord": true,
			},
			expected: true,
		},
		{
			name:            "staging and sith-lord flags: sith-lord env loses",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-sith-lord",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging":           true,
				"sweagentd_route_user_or_repo_to_staging_sith_lord": true,
			},
			expected: false,
		},
		{
			name:            "jedi-knight and sith-lord flags: jedi-knight env wins",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-jedi-knight",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging_jedi_knight": true,
				"sweagentd_route_user_or_repo_to_staging_sith_lord":   true,
			},
			expected: true,
		},
		{
			name:            "jedi-knight and sith-lord flags: sith-lord env loses",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-sith-lord",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging_jedi_knight": true,
				"sweagentd_route_user_or_repo_to_staging_sith_lord":   true,
			},
			expected: false,
		},
		{
			name:            "staging-baby-yoda env matching baby-yoda flag returns true",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-baby-yoda",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging_baby_yoda": true,
			},
			expected: true,
		},
		{
			name:            "staging and baby-yoda flags: staging env wins",
			environment:     config.EnvironmentStaging,
			environmentName: "staging",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging":           true,
				"sweagentd_route_user_or_repo_to_staging_baby_yoda": true,
			},
			expected: true,
		},
		{
			name:            "staging and baby-yoda flags: baby-yoda env loses",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-baby-yoda",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging":           true,
				"sweagentd_route_user_or_repo_to_staging_baby_yoda": true,
			},
			expected: false,
		},
		{
			name:            "jedi-knight and baby-yoda flags: jedi-knight env wins",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-jedi-knight",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging_jedi_knight": true,
				"sweagentd_route_user_or_repo_to_staging_baby_yoda":   true,
			},
			expected: true,
		},
		{
			name:            "jedi-knight and baby-yoda flags: baby-yoda env loses",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-baby-yoda",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging_jedi_knight": true,
				"sweagentd_route_user_or_repo_to_staging_baby_yoda":   true,
			},
			expected: false,
		},
		{
			name:            "sith-lord and baby-yoda flags: sith-lord env wins",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-sith-lord",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging_sith_lord": true,
				"sweagentd_route_user_or_repo_to_staging_baby_yoda": true,
			},
			expected: true,
		},
		{
			name:            "sith-lord and baby-yoda flags: baby-yoda env loses",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-baby-yoda",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging_sith_lord": true,
				"sweagentd_route_user_or_repo_to_staging_baby_yoda": true,
			},
			expected: false,
		},
		{
			name:            "all four flags: staging env wins",
			environment:     config.EnvironmentStaging,
			environmentName: "staging",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging":             true,
				"sweagentd_route_user_or_repo_to_staging_jedi_knight": true,
				"sweagentd_route_user_or_repo_to_staging_sith_lord":   true,
				"sweagentd_route_user_or_repo_to_staging_baby_yoda":   true,
			},
			expected: true,
		},
		{
			name:            "all four flags: baby-yoda env loses",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-baby-yoda",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging":             true,
				"sweagentd_route_user_or_repo_to_staging_jedi_knight": true,
				"sweagentd_route_user_or_repo_to_staging_sith_lord":   true,
				"sweagentd_route_user_or_repo_to_staging_baby_yoda":   true,
			},
			expected: false,
		},
		{
			name:            "non-staging env with all staging flags returns false",
			environment:     config.EnvironmentProduction,
			environmentName: "production",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging":             true,
				"sweagentd_route_user_or_repo_to_staging_jedi_knight": true,
				"sweagentd_route_user_or_repo_to_staging_sith_lord":   true,
				"sweagentd_route_user_or_repo_to_staging_baby_yoda":   true,
			},
			expected: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			ffClient := featureflags.NewNoopClient(tc.flags)
			d := &Dispatcher{
				obsv:            observability.NewNoopExporters(),
				ffClient:        ffClient,
				environment:     tc.environment,
				environmentName: tc.environmentName,
			}

			result := d.shouldEnvironmentDispatchEvent(context.Background(), actors)
			require.Equal(t, tc.expected, result)
		})
	}
}

// ownerOnlyFFClient is a mock featureflags.Client where routing FFs are only
// enabled via the owner (org/user) path, NOT via user+repo. This simulates an
// org-owned repo where the routing FF is enabled on the organization.
// IsEnabledForUserOrRepo returns false; IsEnabledForUserOrRepoOrOwner returns true.
type ownerOnlyFFClient struct {
	featureflags.NoopClient
	flags map[string]bool
}

func (c *ownerOnlyFFClient) IsEnabled(ctx context.Context, featureFlagName string, actors ...vexi.Actor) bool {
	return false
}
func (c *ownerOnlyFFClient) IsEnabledForUser(ctx context.Context, featureFlagName string, userID int64) bool {
	return false
}
func (c *ownerOnlyFFClient) IsEnabledForRepo(ctx context.Context, featureFlagName string, repoID int64) bool {
	return false
}
func (c *ownerOnlyFFClient) IsEnabledForUserOrRepo(ctx context.Context, featureFlagName string, userID, repoID int64) bool {
	return false
}
func (c *ownerOnlyFFClient) IsEnabledForRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.Repository) bool {
	f, ok := c.flags[featureFlagName]
	return ok && f
}
func (c *ownerOnlyFFClient) IsEnabledForUserOrRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.RepositoryWithActor) bool {
	f, ok := c.flags[featureFlagName]
	return ok && f
}
func (c *ownerOnlyFFClient) IsEnabledForGitHubApp(ctx context.Context, featureFlagName string, appID int64) bool {
	return false
}
func (c *ownerOnlyFFClient) IsEnabledForOAuthApp(ctx context.Context, featureFlagName string, appID int64) bool {
	return false
}

// TestShouldEnvironmentDispatchEvent_OrgOwnerRouting verifies that when a
// routing FF is enabled only on the repository owner (org), the event is
// correctly routed to staging instead of being processed by all environments.
// This is a regression test for a bug where IsEnabledForUserOrRepo missed
// org-owned repos, causing 3-4x duplicate trigger firings.
func TestShouldEnvironmentDispatchEvent_OrgOwnerRouting(t *testing.T) {
	actors := &mockActors{actorID: 1, repositoryID: 2, ownerID: 3}

	tests := []struct {
		name            string
		environment     config.Environment
		environmentName string
		flags           map[string]bool
		expected        bool
	}{
		{
			name:            "production skips when org-owner routing FF is enabled",
			environment:     config.EnvironmentProduction,
			environmentName: "production",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging": true,
			},
			expected: false,
		},
		{
			name:            "matching staging processes when org-owner routing FF is enabled",
			environment:     config.EnvironmentStaging,
			environmentName: "staging",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging": true,
			},
			expected: true,
		},
		{
			name:            "non-matching staging skips when org-owner routing FF is enabled",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-jedi-knight",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging": true,
			},
			expected: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			ffClient := &ownerOnlyFFClient{flags: tc.flags}
			d := &Dispatcher{
				obsv:            observability.NewNoopExporters(),
				ffClient:        ffClient,
				environment:     tc.environment,
				environmentName: tc.environmentName,
			}

			result := d.shouldEnvironmentDispatchEvent(context.Background(), actors)
			require.Equal(t, tc.expected, result)
		})
	}
}

func TestShouldProcessEvent_PullRequestStateChanged(t *testing.T) {
	ffEnabled := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentPRStateChangeAssignmentCheck: true,
	})
	ffDisabled := featureflags.NewNoopClient(nil)

	t.Run("returns true when AgentID is set", func(t *testing.T) {
		d := &Dispatcher{
			obsv:         observability.NewNoopExporters(),
			eventHandler: &events.NoopHandler{},
		}

		event := &events.PullRequestStateChangedEvent{
			Actor:       &events.Actor{ID: 1},
			Repo:        &events.Repository{ID: 2, OwnerID: 3},
			PullRequest: &events.PullRequest{ID: 10, Number: 42},
			AgentID:     123,
		}

		require.True(t, d.shouldProcessEvent(context.Background(), event))
	})

	t.Run("returns false when AgentID is zero and flag is disabled", func(t *testing.T) {
		d := &Dispatcher{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffDisabled,
			eventHandler: &events.NoopHandler{
				MockHasAssignmentForPR: func(_ context.Context, _, _ int64, _ *events.PullRequest) (bool, error) {
					return true, nil
				},
			},
		}

		event := &events.PullRequestStateChangedEvent{
			Actor:       &events.Actor{ID: 1},
			Repo:        &events.Repository{ID: 2, OwnerID: 3},
			PullRequest: &events.PullRequest{ID: 10, Number: 42},
			AgentID:     0,
		}

		require.False(t, d.shouldProcessEvent(context.Background(), event))
	})

	t.Run("returns true when AgentID is zero but PR has an assignment", func(t *testing.T) {
		d := &Dispatcher{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffEnabled,
			eventHandler: &events.NoopHandler{
				MockHasAssignmentForPR: func(_ context.Context, _, _ int64, _ *events.PullRequest) (bool, error) {
					return true, nil
				},
			},
		}

		event := &events.PullRequestStateChangedEvent{
			Actor:       &events.Actor{ID: 1},
			Repo:        &events.Repository{ID: 2, OwnerID: 3},
			PullRequest: &events.PullRequest{ID: 10, Number: 42},
			AgentID:     0,
		}

		require.True(t, d.shouldProcessEvent(context.Background(), event))
	})

	t.Run("returns false when AgentID is zero and PR has no assignment", func(t *testing.T) {
		d := &Dispatcher{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffEnabled,
			eventHandler: &events.NoopHandler{
				MockHasAssignmentForPR: func(_ context.Context, _, _ int64, _ *events.PullRequest) (bool, error) {
					return false, nil
				},
			},
		}

		event := &events.PullRequestStateChangedEvent{
			Actor:       &events.Actor{ID: 1},
			Repo:        &events.Repository{ID: 2, OwnerID: 3},
			PullRequest: &events.PullRequest{ID: 10, Number: 42},
			AgentID:     0,
		}

		require.False(t, d.shouldProcessEvent(context.Background(), event))
	})

	t.Run("returns false when AgentID is zero and assignment check errors", func(t *testing.T) {
		d := &Dispatcher{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffEnabled,
			eventHandler: &events.NoopHandler{
				MockHasAssignmentForPR: func(_ context.Context, _, _ int64, _ *events.PullRequest) (bool, error) {
					return false, errors.New("store unavailable")
				},
			},
		}

		event := &events.PullRequestStateChangedEvent{
			Actor:       &events.Actor{ID: 1},
			Repo:        &events.Repository{ID: 2, OwnerID: 3},
			PullRequest: &events.PullRequest{ID: 10, Number: 42},
			AgentID:     0,
		}

		require.False(t, d.shouldProcessEvent(context.Background(), event))
	})
}

// mockAutomationLookup is a minimal automations.Lookup for tests.
type mockAutomationLookup struct {
	hasIssueCreated              bool
	hasWorkflowRunFailed         bool
	hasPullRequestMerged         bool
	hasPullRequestSynchronize    bool
	hasActiveForEventErr         error
	automationsDisabled          bool
	issueCreatedChecks           int
	workflowRunFailedChecks      int
	pullRequestMergedChecks      int
	pullRequestSynchronizeChecks int
}

func (m *mockAutomationLookup) HasActiveForEvent(_ context.Context, req automations.EventMatchRequest) (bool, error) {
	if m.hasActiveForEventErr != nil {
		return false, m.hasActiveForEventErr
	}
	switch req.EventName {
	case automations.EventIssues:
		m.issueCreatedChecks++
		return m.hasIssueCreated, nil
	case automations.EventWorkflowRun:
		m.workflowRunFailedChecks++
		return m.hasWorkflowRunFailed, nil
	case automations.EventPullRequest:
		switch req.ActivityType {
		case automations.ActivityPullRequestMerged:
			m.pullRequestMergedChecks++
			return m.hasPullRequestMerged, nil
		case automations.ActivityPullRequestSynchronize:
			m.pullRequestSynchronizeChecks++
			return m.hasPullRequestSynchronize, nil
		}
		return false, nil
	default:
		return false, nil
	}
}

func (m *mockAutomationLookup) ListForEvent(context.Context, automations.ListForEventRequest) ([]automations.RuntimeConfig, error) {
	return nil, nil
}

func (m *mockAutomationLookup) AutomationsDisabledFromConfig(_ context.Context, _ *sweagentdtwirp.ConfigurationForRepositoryResponse, _ int64, _ string) bool {
	return m.automationsDisabled
}

func TestShouldProcessEvent_IssueOpenedTrigger(t *testing.T) {
	ffEnabled := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentIssueOpenedTrigger: true,
	})
	ffDisabled := featureflags.NewNoopClient(nil)

	makeEvent := func(agentID int64) *events.IssueCreatedEvent {
		return &events.IssueCreatedEvent{
			Actor:   &events.Actor{ID: 1},
			Repo:    &events.Repository{ID: 2, OwnerID: 3},
			Owner:   &events.Actor{ID: 3},
			Issue:   &events.Issue{Number: 42},
			AgentID: agentID,
		}
	}

	t.Run("returns true when FF on, agent set, and triggers exist", func(t *testing.T) {
		lookup := &mockAutomationLookup{hasIssueCreated: true}
		d := &Dispatcher{
			obsv:             observability.NewNoopExporters(),
			ffClient:         ffEnabled,
			automationLookup: lookup,
		}
		require.True(t, d.shouldProcessEvent(context.Background(), makeEvent(99)))
		require.Equal(t, 1, lookup.issueCreatedChecks)
	})

	t.Run("returns false before lookup when FF disabled", func(t *testing.T) {
		lookup := &mockAutomationLookup{hasIssueCreated: true}
		d := &Dispatcher{
			obsv:             observability.NewNoopExporters(),
			ffClient:         ffDisabled,
			automationLookup: lookup,
		}
		require.False(t, d.shouldProcessEvent(context.Background(), makeEvent(99)))
		require.Equal(t, 0, lookup.issueCreatedChecks)
	})

	t.Run("returns false before lookup when agent ID is zero", func(t *testing.T) {
		lookup := &mockAutomationLookup{hasIssueCreated: true}
		d := &Dispatcher{
			obsv:             observability.NewNoopExporters(),
			ffClient:         ffEnabled,
			automationLookup: lookup,
		}
		require.False(t, d.shouldProcessEvent(context.Background(), makeEvent(0)))
		require.Equal(t, 0, lookup.issueCreatedChecks)
	})
}

func TestShouldProcessEvent_AutomationRunRequestedManualFlag(t *testing.T) {
	makeEvent := func(eventName automations.EventName) *events.AutomationRunRequestedEvent {
		return &events.AutomationRunRequestedEvent{
			Event:   string(eventName),
			RepoID:  2,
			OwnerID: 3,
		}
	}

	ffEnabled := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentCustomAgentTriggersDisableInterval: true,
		featureflags.CopilotSWEAgentCustomAgentTriggersDisableManual:   true,
	})
	d := &Dispatcher{
		obsv:     observability.NewNoopExporters(),
		ffClient: ffEnabled,
	}

	require.True(t, d.shouldProcessEvent(context.Background(), makeEvent(automations.EventInterval)))
	require.True(t, d.shouldProcessEvent(context.Background(), makeEvent(automations.EventManual)))
	require.True(t, d.shouldProcessEvent(context.Background(), makeEvent(automations.EventIssues)))

	ffDisabled := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentCustomAgentTriggersDisableInterval: true,
	})
	d.ffClient = ffDisabled
	require.False(t, d.shouldProcessEvent(context.Background(), makeEvent(automations.EventManual)))
}

func TestShouldProcessEvent_MergeConflict(t *testing.T) {
	mergeConflictFlag := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentMergeConflictTrigger: true,
	})
	noFlags := featureflags.NewNoopClient(nil)

	makeEvent := func(agentID int64) *events.MergeConflictEvent {
		return &events.MergeConflictEvent{
			Repo:    &events.MergeConflictRepository{ID: 100},
			AgentID: agentID,
		}
	}

	t.Run("returns true when merge conflict flag enabled", func(t *testing.T) {
		d := &Dispatcher{
			obsv:     observability.NewNoopExporters(),
			ffClient: mergeConflictFlag,
		}
		require.True(t, d.shouldProcessEvent(context.Background(), makeEvent(1)))
	})

	t.Run("returns false when agent ID is zero", func(t *testing.T) {
		d := &Dispatcher{
			obsv:     observability.NewNoopExporters(),
			ffClient: mergeConflictFlag,
		}
		require.False(t, d.shouldProcessEvent(context.Background(), makeEvent(0)))
	})

	t.Run("returns false when merge_conflict_trigger flag disabled", func(t *testing.T) {
		d := &Dispatcher{
			obsv:     observability.NewNoopExporters(),
			ffClient: noFlags,
		}
		require.False(t, d.shouldProcessEvent(context.Background(), makeEvent(1)))
	})
}

func TestShouldProcessEvent_PullRequestMergedTrigger(t *testing.T) {
	ffEnabled := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentPullRequestMergedTrigger: true,
	})
	ffDisabled := featureflags.NewNoopClient(nil)

	// NewTestProviderWithID(t, 123) constructs a copilot with botID = 124 (appID+1).
	const botID = int64(124)
	appProvider := agenticapptest.NewTestProviderWithID(t, 123)

	makeMergedEvent := func(authorID int64) *events.PullRequestStateChangedEvent {
		return &events.PullRequestStateChangedEvent{
			Actor: &events.Actor{ID: 1},
			Repo:  &events.Repository{ID: 2, OwnerID: 3},
			PullRequest: &events.PullRequest{
				ID:       10,
				Number:   42,
				State:    events.PullRequestStateMerged,
				AuthorID: authorID,
			},
		}
	}

	t.Run("returns true when FF on, has matching triggers, and author is not a bot", func(t *testing.T) {
		lookup := &mockAutomationLookup{hasPullRequestMerged: true}
		d := &Dispatcher{
			obsv:             observability.NewNoopExporters(),
			ffClient:         ffEnabled,
			eventHandler:     &events.NoopHandler{},
			automationLookup: lookup,
			appProvider:      appProvider,
		}
		require.True(t, d.shouldProcessEvent(context.Background(), makeMergedEvent(99)))
		require.Equal(t, 1, lookup.pullRequestMergedChecks)
	})

	t.Run("returns false when PR is not in merged state", func(t *testing.T) {
		lookup := &mockAutomationLookup{hasPullRequestMerged: true}
		d := &Dispatcher{
			obsv:             observability.NewNoopExporters(),
			ffClient:         ffEnabled,
			eventHandler:     &events.NoopHandler{},
			automationLookup: lookup,
			appProvider:      appProvider,
		}
		event := makeMergedEvent(99)
		event.PullRequest.State = events.PullRequestStateClosed
		require.False(t, d.shouldProcessEvent(context.Background(), event))
		require.Equal(t, 0, lookup.pullRequestMergedChecks)
	})

	t.Run("returns false when FF disabled", func(t *testing.T) {
		lookup := &mockAutomationLookup{hasPullRequestMerged: true}
		d := &Dispatcher{
			obsv:             observability.NewNoopExporters(),
			ffClient:         ffDisabled,
			eventHandler:     &events.NoopHandler{},
			automationLookup: lookup,
			appProvider:      appProvider,
		}
		require.False(t, d.shouldProcessEvent(context.Background(), makeMergedEvent(99)))
		require.Equal(t, 0, lookup.pullRequestMergedChecks)
	})

	t.Run("returns false when PR author is a known bot", func(t *testing.T) {
		lookup := &mockAutomationLookup{hasPullRequestMerged: true}
		d := &Dispatcher{
			obsv:             observability.NewNoopExporters(),
			ffClient:         ffEnabled,
			eventHandler:     &events.NoopHandler{},
			automationLookup: lookup,
			appProvider:      appProvider,
		}
		require.False(t, d.shouldProcessEvent(context.Background(), makeMergedEvent(botID)))
		require.Equal(t, 0, lookup.pullRequestMergedChecks)
	})

	t.Run("returns false when no active triggers found", func(t *testing.T) {
		lookup := &mockAutomationLookup{hasPullRequestMerged: false}
		d := &Dispatcher{
			obsv:             observability.NewNoopExporters(),
			ffClient:         ffEnabled,
			eventHandler:     &events.NoopHandler{},
			automationLookup: lookup,
			appProvider:      appProvider,
		}
		require.False(t, d.shouldProcessEvent(context.Background(), makeMergedEvent(99)))
		require.Equal(t, 1, lookup.pullRequestMergedChecks)
	})

	t.Run("returns false when lookup returns an error", func(t *testing.T) {
		lookup := &mockAutomationLookup{hasActiveForEventErr: errors.New("store unavailable")}
		d := &Dispatcher{
			obsv:             observability.NewNoopExporters(),
			ffClient:         ffEnabled,
			eventHandler:     &events.NoopHandler{},
			automationLookup: lookup,
			appProvider:      appProvider,
		}
		require.False(t, d.shouldProcessEvent(context.Background(), makeMergedEvent(99)))
	})

	t.Run("falls back to Service cancellation path when automationLookup is nil", func(t *testing.T) {
		// Mirrors the Service dispatcher (nil lookup): the merged-trigger
		// helper is bypassed; existing AgentID/assignment fallback applies.
		d := &Dispatcher{
			obsv:         observability.NewNoopExporters(),
			ffClient:     ffEnabled,
			eventHandler: &events.NoopHandler{},
			appProvider:  appProvider,
			// automationLookup is intentionally nil.
		}
		event := makeMergedEvent(99)
		event.AgentID = 999
		require.True(t, d.shouldProcessEvent(context.Background(), event))
	})
}

func TestTriggerForEvent_PullRequestStateChanged(t *testing.T) {
	tests := []struct {
		name     string
		event    *events.PullRequestStateChangedEvent
		expected string
	}{
		{
			name: "merged state returns pull_request_merged",
			event: &events.PullRequestStateChangedEvent{
				PullRequest: &events.PullRequest{State: events.PullRequestStateMerged},
			},
			expected: "pull_request_merged",
		},
		{
			name: "closed state returns empty",
			event: &events.PullRequestStateChangedEvent{
				PullRequest: &events.PullRequest{State: events.PullRequestStateClosed},
			},
			expected: "",
		},
		{
			name: "open state returns empty",
			event: &events.PullRequestStateChangedEvent{
				PullRequest: &events.PullRequest{State: events.PullRequestStateOpen},
			},
			expected: "",
		},
		{
			name:     "nil pull request returns empty",
			event:    &events.PullRequestStateChangedEvent{PullRequest: nil},
			expected: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.Equal(t, tt.expected, triggerForEvent(tt.event))
		})
	}
}

func TestShouldProcessEvent_PullRequestSynchronizeTrigger(t *testing.T) {
	ffEnabled := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentPullRequestSynchronizeTrigger: true,
	})
	ffDisabled := featureflags.NewNoopClient(nil)

	makeEvent := func(agentID int64) *events.PullRequestSynchronizeEvent {
		return &events.PullRequestSynchronizeEvent{
			Actor: &events.Actor{ID: 1},
			Repo:  &events.Repository{ID: 2, OwnerID: 3},
			PullRequest: &events.PullRequest{
				ID:         10,
				Number:     42,
				HeadBranch: "feature",
				BaseBranch: "main",
			},
			AgentID: agentID,
		}
	}

	t.Run("returns true when FF on, agent set, not a fork, and triggers exist", func(t *testing.T) {
		lookup := &mockAutomationLookup{hasPullRequestSynchronize: true}
		d := &Dispatcher{
			obsv:             observability.NewNoopExporters(),
			ffClient:         ffEnabled,
			eventHandler:     &events.NoopHandler{},
			automationLookup: lookup,
		}
		require.True(t, d.shouldProcessEvent(context.Background(), makeEvent(99)))
		require.Equal(t, 1, lookup.pullRequestSynchronizeChecks)
	})

	t.Run("returns false when AgentID is zero", func(t *testing.T) {
		lookup := &mockAutomationLookup{hasPullRequestSynchronize: true}
		d := &Dispatcher{
			obsv:             observability.NewNoopExporters(),
			ffClient:         ffEnabled,
			eventHandler:     &events.NoopHandler{},
			automationLookup: lookup,
		}
		require.False(t, d.shouldProcessEvent(context.Background(), makeEvent(0)))
		require.Equal(t, 0, lookup.pullRequestSynchronizeChecks)
	})

	t.Run("returns false when FF disabled", func(t *testing.T) {
		lookup := &mockAutomationLookup{hasPullRequestSynchronize: true}
		d := &Dispatcher{
			obsv:             observability.NewNoopExporters(),
			ffClient:         ffDisabled,
			eventHandler:     &events.NoopHandler{},
			automationLookup: lookup,
		}
		require.False(t, d.shouldProcessEvent(context.Background(), makeEvent(99)))
		require.Equal(t, 0, lookup.pullRequestSynchronizeChecks)
	})

	t.Run("returns false when no active triggers found", func(t *testing.T) {
		lookup := &mockAutomationLookup{hasPullRequestSynchronize: false}
		d := &Dispatcher{
			obsv:             observability.NewNoopExporters(),
			ffClient:         ffEnabled,
			eventHandler:     &events.NoopHandler{},
			automationLookup: lookup,
		}
		require.False(t, d.shouldProcessEvent(context.Background(), makeEvent(99)))
		require.Equal(t, 1, lookup.pullRequestSynchronizeChecks)
	})

	t.Run("returns false when automationLookup is nil (Service dispatcher)", func(t *testing.T) {
		d := &Dispatcher{
			obsv:         observability.NewNoopExporters(),
			ffClient:     ffEnabled,
			eventHandler: &events.NoopHandler{},
		}
		require.False(t, d.shouldProcessEvent(context.Background(), makeEvent(99)))
	})

	t.Run("returns false when lookup returns an error", func(t *testing.T) {
		lookup := &mockAutomationLookup{hasActiveForEventErr: errors.New("store unavailable")}
		d := &Dispatcher{
			obsv:             observability.NewNoopExporters(),
			ffClient:         ffEnabled,
			eventHandler:     &events.NoopHandler{},
			automationLookup: lookup,
		}
		require.False(t, d.shouldProcessEvent(context.Background(), makeEvent(99)))
	})
}

func TestShouldProcessTopic(t *testing.T) {
	d := &Dispatcher{obsv: observability.NewNoopExporters()}

	t.Run("accepts every topic in topics.All", func(t *testing.T) {
		for _, topic := range topics.All {
			require.Truef(t, d.shouldProcessTopic(context.Background(), topic),
				"topics.All contains %q but shouldProcessTopic rejects it; add a case to the switch in filters.go", topic)
		}
	})

	t.Run("rejects unknown topics", func(t *testing.T) {
		require.False(t, d.shouldProcessTopic(context.Background(), "github.v1.UnknownTopic"))
	})
}
