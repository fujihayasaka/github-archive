package triggers

import (
	"context"
	"testing"

	stats "github.com/github/go-stats"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/store"
	"github.com/github/sweagentd/internal/customagent/store/memory"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/permissions"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdtwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

// stubStore returns a fixed set of records, bypassing Upsert/SetTimestamps
// so tests can control SyncedAt values directly.
type stubStore struct {
	records []*store.AgentRecord
}

func (s *stubStore) List(_ context.Context, _ int64) ([]*store.AgentRecord, error) {
	return s.records, nil
}

func TestHasIssueCreatedTriggers(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ctx := context.Background()

	t.Run("returns true when agent has issue opened trigger", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withIssueOpenedTrigger())

		checker := NewChecker(s, nil, obsv)
		has, err := checker.HasIssueCreatedTriggers(ctx, 1)
		require.NoError(t, err)
		require.True(t, has)
	})

	t.Run("returns false when repo has no agents", func(t *testing.T) {
		s := memory.NewStore()

		checker := NewChecker(s, nil, obsv)
		has, err := checker.HasIssueCreatedTriggers(ctx, 1)
		require.NoError(t, err)
		require.False(t, has)
	})

	t.Run("returns false when agents have no issue triggers", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withNoTriggers())

		checker := NewChecker(s, nil, obsv)
		has, err := checker.HasIssueCreatedTriggers(ctx, 1)
		require.NoError(t, err)
		require.False(t, has)
	})

	t.Run("returns false when agent has non-opened issue trigger", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withIssueReopenedTrigger())

		checker := NewChecker(s, nil, obsv)
		has, err := checker.HasIssueCreatedTriggers(ctx, 1)
		require.NoError(t, err)
		require.False(t, has)
	})

	t.Run("returns false when agent has sync error", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withIssueOpenedTrigger(), withSyncError("parse failed"))

		checker := NewChecker(s, nil, obsv)
		has, err := checker.HasIssueCreatedTriggers(ctx, 1)
		require.NoError(t, err)
		require.False(t, has)
	})

	t.Run("returns false when agent targets vscode only", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withIssueOpenedTrigger(), withTarget(customagent.TargetVSCode))

		checker := NewChecker(s, nil, obsv)
		has, err := checker.HasIssueCreatedTriggers(ctx, 1)
		require.NoError(t, err)
		require.False(t, has)
	})

	t.Run("returns true when agent targets github-copilot", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withIssueOpenedTrigger(), withTarget(customagent.TargetGitHubCopilot))

		checker := NewChecker(s, nil, obsv)
		has, err := checker.HasIssueCreatedTriggers(ctx, 1)
		require.NoError(t, err)
		require.True(t, has)
	})

	t.Run("returns true when one of multiple agents has trigger", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withNoTriggers())
		upsertRecord(ctx, t, s, 1, withIssueOpenedTrigger())

		checker := NewChecker(s, nil, obsv)
		has, err := checker.HasIssueCreatedTriggers(ctx, 1)
		require.NoError(t, err)
		require.True(t, has)
	})

	t.Run("does not match triggers from different repo", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 2, withIssueOpenedTrigger())

		checker := NewChecker(s, nil, obsv)
		has, err := checker.HasIssueCreatedTriggers(ctx, 1)
		require.NoError(t, err)
		require.False(t, has)
	})
}

func TestAgentsWithIssueCreatedTriggers(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ctx := context.Background()
	repo := RepoInfo{OwnerID: 456, OwnerLogin: "test-org", RepoName: "test-repo"}

	t.Run("returns agents with issue opened triggers", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withIssueOpenedTrigger(), withName("issue-agent"))

		checker := NewChecker(s, nil, obsv)
		agents, err := checker.AgentsWithIssueCreatedTriggers(ctx, 1, repo)
		require.NoError(t, err)
		require.Len(t, agents, 1)
		require.Equal(t, "issue-agent", agents[0].Name())
		require.Equal(t, int64(456), agents[0].RepoOwnerID())
		require.Equal(t, "test-org", agents[0].RepoOwner())
		require.Equal(t, "test-repo", agents[0].RepoName())
	})

	t.Run("filters out agents without triggers", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withNoTriggers(), withName("no-trigger"))
		upsertRecord(ctx, t, s, 1, withIssueOpenedTrigger(), withName("has-trigger"))

		checker := NewChecker(s, nil, obsv)
		agents, err := checker.AgentsWithIssueCreatedTriggers(ctx, 1, repo)
		require.NoError(t, err)
		require.Len(t, agents, 1)
		require.Equal(t, "has-trigger", agents[0].Name())
	})

	t.Run("returns empty slice when no triggers match", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withNoTriggers())

		checker := NewChecker(s, nil, obsv)
		agents, err := checker.AgentsWithIssueCreatedTriggers(ctx, 1, repo)
		require.NoError(t, err)
		require.Empty(t, agents)
	})

	t.Run("returns agents with configured permissions from store record", func(t *testing.T) {
		s := memory.NewStore()
		configuredPerms := permissions.New(map[string]string{
			"contents": "write",
			"issues":   "write",
		})
		upsertRecord(ctx, t, s, 1, withIssueOpenedTrigger(), withName("perms-agent"), withPermissions(configuredPerms))

		checker := NewChecker(s, nil, obsv)
		agents, err := checker.AgentsWithIssueCreatedTriggers(ctx, 1, repo)
		require.NoError(t, err)
		require.Len(t, agents, 1)

		// Verify the agent's permissions match what was stored, not the defaults
		p, ok := agents[0].(interface {
			Permissions() permissions.Permissions
		})
		require.True(t, ok, "agent should implement Permissions()")
		agentPerms := p.Permissions()
		require.Equal(t, "write", agentPerms.ToMap()["contents"])
		require.Equal(t, "write", agentPerms.ToMap()["issues"])
	})

	t.Run("returns privileged agent with MCP config from store record", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withIssueOpenedTrigger(), withName("mcp-agent"), withMCPServers([]store.MCPServer{
			{
				Name:    "my-server",
				Type:    "stdio",
				Tools:   []string{"*"},
				Command: "npx",
				Args:    []string{"-y", "my-mcp-server"},
			},
		}))

		checker := NewChecker(s, nil, obsv)
		agents, err := checker.AgentsWithIssueCreatedTriggers(ctx, 1, repo)
		require.NoError(t, err)
		require.Len(t, agents, 1)

		// Verify the agent is a PrivilegedAgent with MCP config
		m, ok := agents[0].(interface{ MCPConfig() mcpconfig.JSON })
		require.True(t, ok, "agent with MCP servers should be a PrivilegedAgent implementing MCPConfig()")
		mcpCfg := m.MCPConfig()
		require.Len(t, mcpCfg.Servers, 1)
		require.Contains(t, mcpCfg.Servers, "my-server")
		require.Equal(t, "npx", mcpCfg.Servers["my-server"].Command)
	})

	t.Run("deduplicates agents with same path keeping most recent", func(t *testing.T) {
		agentPath := ".github/agents/issue-triage.md"
		records := []*store.AgentRecord{
			{ID: "old", ScopeID: 1, Path: agentPath, TreeOID: "old-sha", SyncedAt: 100,
				Config: store.AgentConfig{Name: "issue-agent", Tools: []string{"*"},
					Triggers: sweagentd.CustomAgentTriggers{Issues: &sweagentd.CustomAgentTrigger{Types: []string{"opened"}}}}},
			{ID: "newest", ScopeID: 1, Path: agentPath, TreeOID: "newest-sha", SyncedAt: 300,
				Config: store.AgentConfig{Name: "issue-agent", Tools: []string{"*"},
					Triggers: sweagentd.CustomAgentTriggers{Issues: &sweagentd.CustomAgentTrigger{Types: []string{"opened"}}}}},
			{ID: "middle", ScopeID: 1, Path: agentPath, TreeOID: "middle-sha", SyncedAt: 200,
				Config: store.AgentConfig{Name: "issue-agent", Tools: []string{"*"},
					Triggers: sweagentd.CustomAgentTriggers{Issues: &sweagentd.CustomAgentTrigger{Types: []string{"opened"}}}}},
		}
		stub := &stubStore{records: records}
		checker := NewChecker(stub, nil, obsv)
		agents, err := checker.AgentsWithIssueCreatedTriggers(ctx, 1, repo)
		require.NoError(t, err)
		require.Len(t, agents, 1, "duplicate records for the same path should be deduplicated")
		require.Equal(t, "newest-sha", agents[0].Version(), "should keep the most recently synced record")
	})
}

func TestHasWorkflowRunFailedTriggers(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ctx := context.Background()

	t.Run("returns true when agent has workflow_run failed trigger", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withWorkflowRunFailedTrigger())

		checker := NewChecker(s, nil, obsv)
		has, err := checker.HasWorkflowRunFailedTriggers(ctx, 1)
		require.NoError(t, err)
		require.True(t, has)
	})

	t.Run("returns false when repo has no agents", func(t *testing.T) {
		s := memory.NewStore()

		checker := NewChecker(s, nil, obsv)
		has, err := checker.HasWorkflowRunFailedTriggers(ctx, 1)
		require.NoError(t, err)
		require.False(t, has)
	})

	t.Run("returns false when agents have no workflow_run triggers", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withNoTriggers())

		checker := NewChecker(s, nil, obsv)
		has, err := checker.HasWorkflowRunFailedTriggers(ctx, 1)
		require.NoError(t, err)
		require.False(t, has)
	})

	t.Run("returns false when agent has workflow_run trigger without workflows list", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withWorkflowRunFailedTriggerNoWorkflows())

		checker := NewChecker(s, nil, obsv)
		has, err := checker.HasWorkflowRunFailedTriggers(ctx, 1)
		require.NoError(t, err)
		require.False(t, has)
	})

	t.Run("returns false when agent has sync error", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withWorkflowRunFailedTrigger(), withSyncError("parse failed"))

		checker := NewChecker(s, nil, obsv)
		has, err := checker.HasWorkflowRunFailedTriggers(ctx, 1)
		require.NoError(t, err)
		require.False(t, has)
	})

	t.Run("returns false when agent targets vscode only", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withWorkflowRunFailedTrigger(), withTarget(customagent.TargetVSCode))

		checker := NewChecker(s, nil, obsv)
		has, err := checker.HasWorkflowRunFailedTriggers(ctx, 1)
		require.NoError(t, err)
		require.False(t, has)
	})

	t.Run("does not match triggers from different repo", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 2, withWorkflowRunFailedTrigger())

		checker := NewChecker(s, nil, obsv)
		has, err := checker.HasWorkflowRunFailedTriggers(ctx, 1)
		require.NoError(t, err)
		require.False(t, has)
	})
}

func TestAgentsWithWorkflowRunFailedTriggers(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ctx := context.Background()
	repo := RepoInfo{OwnerID: 456, OwnerLogin: "test-org", RepoName: "test-repo"}

	t.Run("returns agents with workflow_run failed trigger matching specified workflow", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withWorkflowRunFailedTrigger(), withName("ci-fix-agent"))

		checker := NewChecker(s, nil, obsv)
		agents, err := checker.AgentsWithWorkflowRunFailedTriggers(ctx, 1, repo, "CI")
		require.NoError(t, err)
		require.Len(t, agents, 1)
		require.Equal(t, "ci-fix-agent", agents[0].Name())
	})

	t.Run("skips agents without workflows list", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withWorkflowRunFailedTriggerNoWorkflows(), withName("ci-fix-agent"))

		checker := NewChecker(s, nil, obsv)
		agents, err := checker.AgentsWithWorkflowRunFailedTriggers(ctx, 1, repo, "CI")
		require.NoError(t, err)
		require.Empty(t, agents)
	})

	t.Run("returns agents when workflow name matches filter", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withWorkflowRunFailedTriggerForWorkflows("CI", "Tests"), withName("ci-agent"))

		checker := NewChecker(s, nil, obsv)
		agents, err := checker.AgentsWithWorkflowRunFailedTriggers(ctx, 1, repo, "CI")
		require.NoError(t, err)
		require.Len(t, agents, 1)
	})

	t.Run("filters out agents when workflow name does not match", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withWorkflowRunFailedTriggerForWorkflows("CI", "Tests"), withName("ci-agent"))

		checker := NewChecker(s, nil, obsv)
		agents, err := checker.AgentsWithWorkflowRunFailedTriggers(ctx, 1, repo, "Deploy")
		require.NoError(t, err)
		require.Empty(t, agents)
	})

	t.Run("matches workflow names case-insensitively", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withWorkflowRunFailedTriggerForWorkflows("ci", "tests"), withName("ci-agent"))

		checker := NewChecker(s, nil, obsv)
		agents, err := checker.AgentsWithWorkflowRunFailedTriggers(ctx, 1, repo, "CI")
		require.NoError(t, err)
		require.Len(t, agents, 1)
	})

	t.Run("filters out agents without triggers", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withNoTriggers(), withName("no-trigger"))
		upsertRecord(ctx, t, s, 1, withWorkflowRunFailedTrigger(), withName("has-trigger"))

		checker := NewChecker(s, nil, obsv)
		agents, err := checker.AgentsWithWorkflowRunFailedTriggers(ctx, 1, repo, "CI")
		require.NoError(t, err)
		require.Len(t, agents, 1)
		require.Equal(t, "has-trigger", agents[0].Name())
	})

	t.Run("returns empty slice when no triggers match", func(t *testing.T) {
		s := memory.NewStore()
		upsertRecord(ctx, t, s, 1, withNoTriggers())

		checker := NewChecker(s, nil, obsv)
		agents, err := checker.AgentsWithWorkflowRunFailedTriggers(ctx, 1, repo, "CI")
		require.NoError(t, err)
		require.Empty(t, agents)
	})
}

// test helpers

type recordOption func(*store.AgentRecord)

func withIssueOpenedTrigger() recordOption {
	return func(r *store.AgentRecord) {
		r.Config.Triggers = sweagentd.CustomAgentTriggers{
			Issues: &sweagentd.CustomAgentTrigger{
				Types: []string{IssuesTypeOpened},
			},
		}
	}
}

func withIssueReopenedTrigger() recordOption {
	return func(r *store.AgentRecord) {
		r.Config.Triggers = sweagentd.CustomAgentTriggers{
			Issues: &sweagentd.CustomAgentTrigger{
				Types: []string{"reopened"},
			},
		}
	}
}

func withWorkflowRunFailedTrigger() recordOption {
	return func(r *store.AgentRecord) {
		r.Config.Triggers = sweagentd.CustomAgentTriggers{
			WorkflowRun: &sweagentd.CustomAgentWorkflowRunTrigger{
				Types:     []string{WorkflowRunTypeFailed},
				Workflows: []string{"CI"},
			},
		}
	}
}

func withWorkflowRunFailedTriggerNoWorkflows() recordOption {
	return func(r *store.AgentRecord) {
		r.Config.Triggers = sweagentd.CustomAgentTriggers{
			WorkflowRun: &sweagentd.CustomAgentWorkflowRunTrigger{
				Types: []string{WorkflowRunTypeFailed},
			},
		}
	}
}

func withWorkflowRunFailedTriggerForWorkflows(workflows ...string) recordOption {
	return func(r *store.AgentRecord) {
		r.Config.Triggers = sweagentd.CustomAgentTriggers{
			WorkflowRun: &sweagentd.CustomAgentWorkflowRunTrigger{
				Types:     []string{WorkflowRunTypeFailed},
				Workflows: workflows,
			},
		}
	}
}

func withNoTriggers() recordOption {
	return func(r *store.AgentRecord) {
		r.Config.Triggers = sweagentd.CustomAgentTriggers{}
	}
}

func withSyncError(msg string) recordOption {
	return func(r *store.AgentRecord) {
		r.SyncError = msg
	}
}

func withTarget(target string) recordOption {
	return func(r *store.AgentRecord) {
		r.Config.Target = target
	}
}

func withName(name string) recordOption {
	return func(r *store.AgentRecord) {
		r.Config.Name = name
	}
}

func withPermissions(perms permissions.Permissions) recordOption {
	return func(r *store.AgentRecord) {
		r.Config.Permissions = perms
	}
}

func withMCPServers(servers []store.MCPServer) recordOption {
	return func(r *store.AgentRecord) {
		r.Config.MCPServers = servers
	}
}

func upsertRecord(ctx context.Context, t *testing.T, s *memory.Store, repoID int64, opts ...recordOption) {
	t.Helper()

	record := &store.AgentRecord{
		ID:      uuid.NewString(),
		ScopeID: repoID,
		Path:    ".github/agents/" + uuid.NewString() + ".md",
		Config: store.AgentConfig{
			Name:        "default-agent",
			DisplayName: "Default Agent",
			Description: "A test agent",
			Tools:       []string{"*"},
		},
		TreeOID: "abc123",
	}

	for _, opt := range opts {
		opt(record)
	}

	_, err := s.Upsert(ctx, record)
	require.NoError(t, err)
}

// stubGhTwirp is a tiny ghTwirpClient implementation used in automations-policy tests (sweagentd#11400).
type stubGhTwirp struct {
	automationsDisabled bool
	err                 error
	calls               int
}

func (s *stubGhTwirp) IsAgentEnabled(_ context.Context, _, _, _ int64) (bool, *sweagentdtwirp.ConfigurationForRepositoryResponse, error) {
	s.calls++
	if s.err != nil {
		return false, nil, s.err
	}
	return true, &sweagentdtwirp.ConfigurationForRepositoryResponse{
		IsAgentEnabled:      true,
		AutomationsDisabled: s.automationsDisabled,
	}, nil
}

func TestChecker_AutomationsDisabled(t *testing.T) {
	ctx := context.Background()

	t.Run("nil ghTwirp returns (false, nil) without error", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		checker := NewChecker(nil, nil, obsv)

		disabled, err := checker.AutomationsDisabled(ctx, 100, 200, 1, "issue_created")
		require.NoError(t, err)
		require.False(t, disabled, "with no twirp client the automations policy must not gate triggers")
	})

	t.Run("returns true and emits metric when automations are disabled", func(t *testing.T) {
		var counterCalls []capturedCounter
		obsv := observability.NewNoopExporters()
		obsv.Statter = &observability.MockStatter{
			MockCounter: func(key string, tags stats.Tags, value int64) {
				counterCalls = append(counterCalls, capturedCounter{key: key, tags: tags, value: value})
			},
		}
		twirp := &stubGhTwirp{automationsDisabled: true}

		checker := NewChecker(nil, twirp, obsv)
		disabled, err := checker.AutomationsDisabled(ctx, 100, 200, 1, "issue_created")
		require.NoError(t, err)
		require.True(t, disabled)
		require.Equal(t, 1, twirp.calls)

		require.Len(t, counterCalls, 1, "Checker must emit the triggers.skipped metric exactly once")
		c := counterCalls[0]
		require.Equal(t, "triggers.skipped", c.key)
		require.Equal(t, "issue_created", c.tags["trigger_type"])
		require.Equal(t, "automations_disabled", c.tags["reason"])
	})

	t.Run("returns false and emits no metric when automations are enabled", func(t *testing.T) {
		var counterCalls []capturedCounter
		obsv := observability.NewNoopExporters()
		obsv.Statter = &observability.MockStatter{
			MockCounter: func(key string, tags stats.Tags, value int64) {
				counterCalls = append(counterCalls, capturedCounter{key: key, tags: tags, value: value})
			},
		}
		twirp := &stubGhTwirp{automationsDisabled: false}

		checker := NewChecker(nil, twirp, obsv)
		disabled, err := checker.AutomationsDisabled(ctx, 100, 200, 1, "issue_created")
		require.NoError(t, err)
		require.False(t, disabled)
		require.Equal(t, 1, twirp.calls)
		require.Empty(t, counterCalls, "no metric should be emitted when the policy permits automations")
	})

	t.Run("twirp errors are surfaced", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		twirp := &stubGhTwirp{err: goerrors.Errorf("boom")}

		checker := NewChecker(nil, twirp, obsv)
		_, err := checker.AutomationsDisabled(ctx, 100, 200, 1, "issue_created")
		require.Error(t, err, "twirp errors must surface so callers can decide how to react")
	})
}

// capturedCounter records a single MockStatter.Counter call for assertions.
type capturedCounter struct {
	key   string
	tags  stats.Tags
	value int64
}
