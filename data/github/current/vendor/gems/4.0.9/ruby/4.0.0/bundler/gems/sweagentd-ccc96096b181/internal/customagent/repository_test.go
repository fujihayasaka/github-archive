package customagent

import (
	"context"
	"errors"
	"testing"

	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes/spokestest"
)

type mockRepoProvider struct {
	getRepositoryFunc     func(ctx context.Context, owner, repo string) (repo, error)
	getRepositoryByIDFunc func(ctx context.Context, repoID int64) (repo, error)
}

type mockRepo struct {
	id      int64
	ownerID int64
	name    string
	owner   string
}

func (r *mockRepo) GetID() int64 {
	return r.id
}

func (r *mockRepo) GetName() string {
	return r.name
}

func (r *mockRepo) GetOwnerID() int64 {
	return r.ownerID
}

func (r *mockRepo) GetOwnerName() string {
	return r.owner
}

func (m *mockRepoProvider) getRepository(ctx context.Context, owner, repo string) (repo, error) {
	if m.getRepositoryFunc == nil {
		return &mockRepo{id: 12345, ownerID: 456, name: repo, owner: owner}, nil
	}

	return m.getRepositoryFunc(ctx, owner, repo)
}

func (m *mockRepoProvider) getRepositoryByID(ctx context.Context, repoID int64) (repo, error) {
	if m.getRepositoryByIDFunc == nil {
		return &mockRepo{id: repoID, ownerID: 456, name: "test-repo", owner: "test-owner"}, nil
	}

	return m.getRepositoryByIDFunc(ctx, repoID)
}

func TestRepositoryAgents(t *testing.T) {
	t.Run("returns ErrNoAgentsFound when no github agents directory exist", func(t *testing.T) {
		r := &Repository{
			spokes:    spokestest.NewClient(t),
			obsv:      observability.NewNoopExporters(),
			directory: Directory,
		}

		_, err := r.agents(context.Background(), false)
		if !errors.Is(err, ErrNoAgentsFound) {
			t.Fatalf("expected ErrNoAgentsFound, got %v", err)
		}
	})

	t.Run("returns nil, nil when agents directory contains only non-agent files", func(t *testing.T) {
		// Create files that will be filtered out - none have .md extension or are README.md
		r := &Repository{
			spokes: spokestest.NewClient(t,
				spokestest.WithBlob(".github/agents/README.md", []byte("readme content")), // filtered out
				spokestest.WithBlob(".github/agents/notes.txt", []byte("notes content")),  // filtered out (wrong extension)
				spokestest.WithBlob(".github/agents/config.json", []byte("json content")), // filtered out (wrong extension)
			),
			obsv:      observability.NewNoopExporters(),
			directory: Directory,
		}

		agents, err := r.agents(context.Background(), false)
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		if agents != nil {
			t.Fatalf("expected nil agents, got %v", agents)
		}
	})

	t.Run("agent name is derived from filename", func(t *testing.T) {
		contents := "---\nname: agent\ndescription: test agent\nkey: value\n---\nthis is a prompt"
		r := &Repository{
			spokes: spokestest.NewClient(t,
				spokestest.WithBlob(".github/agents/agent-one.md", []byte(contents)),
				spokestest.WithBlob(".github/agents/agent-two.md", []byte(contents)),
				spokestest.WithBlob(".github/agents/agent-three.agent.md", []byte(contents)),
				spokestest.WithBlob(".github/agents/agent-four.agent.md", []byte(contents)),
			),
			obsv:      observability.NewNoopExporters(),
			directory: Directory,
		}

		agents, err := r.agents(context.Background(), false)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}

		if len(agents) != 4 {
			t.Fatalf("expected 4 agents, got %d", len(agents))
		}

		expectedNames := map[string]bool{
			"agent-one":   true,
			"agent-two":   true,
			"agent-three": true,
			"agent-four":  true,
		}

		expectedFilenames := map[string]bool{
			"agent-one.md":         true,
			"agent-two.md":         true,
			"agent-three.agent.md": true,
			"agent-four.agent.md":  true,
		}

		for _, agent := range agents {
			if !expectedNames[agent.Name()] {
				t.Errorf("unexpected agent name: %s", agent.Name())
			}
			if !expectedFilenames[agent.metadata.Filename] {
				t.Errorf("unexpected agent filename: %s", agent.metadata.Filename)
			}
		}
	})

	t.Run("skips invalid agent configurations", func(t *testing.T) {
		validContents := "---\nname: valid-agent\ndescription: A valid agent\n---\nprompt"
		invalidNoDesc := "---\nname: missing-desc\n---\nprompt"
		invalidMalformed := "---\nname: bad\ninvalid yaml: [unclosed\n---\nprompt"

		r := &Repository{
			spokes: spokestest.NewClient(t,
				spokestest.WithBlob(".github/agents/valid.md", []byte(validContents)),
				spokestest.WithBlob(".github/agents/no-desc.md", []byte(invalidNoDesc)),
				spokestest.WithBlob(".github/agents/malformed.md", []byte(invalidMalformed)),
			),
			obsv:      observability.NewNoopExporters(),
			owner:     "test-owner",
			name:      "test-repo",
			directory: Directory,
		}

		agents, err := r.agents(context.Background(), true)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}

		// Only the valid agent should be returned, invalid ones should be skipped
		if len(agents) != 1 {
			t.Fatalf("expected 1 valid agent, got %d", len(agents))
		}
		if agents[0].Name() != "valid" {
			t.Errorf("expected agent name 'valid', got %s", agents[0].Name())
		}
	})

	t.Run("includes invalid agent configurations when excludeInvalidConfig is false", func(t *testing.T) {
		validContents := "---\nname: valid-agent\ndescription: A valid agent\n---\nprompt"
		invalidNoDesc := "---\nname: missing-desc\n---\nprompt"

		// A fully malformed yaml should be excluded
		invalidMalformed := "---\nname: bad\ninvalid yaml: [unclosed\n---\nprompt"

		r := &Repository{
			spokes: spokestest.NewClient(t,
				spokestest.WithBlob(".github/agents/valid.md", []byte(validContents)),
				spokestest.WithBlob(".github/agents/no-desc.md", []byte(invalidNoDesc)),
				spokestest.WithBlob(".github/agents/malformed.md", []byte(invalidMalformed)),
			),
			obsv:      observability.NewNoopExporters(),
			owner:     "test-owner",
			name:      "test-repo",
			directory: Directory,
		}

		agents, err := r.agents(context.Background(), false)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}

		// All agents should be returned (valid + invalid ones)
		if len(agents) != 2 {
			t.Fatalf("expected 2 agents (1 valid + 2 invalid - 1 malformed), got %d", len(agents))
		}

		// Verify that valid agent doesn't have config error
		var validAgent *Agent
		for _, agent := range agents {
			if agent.Name() == "valid" {
				validAgent = agent
				break
			}
		}
		if validAgent == nil {
			t.Fatal("expected to find valid agent")
		}
		if validAgent.metadata.ConfigError != "" {
			t.Errorf("expected valid agent to have no config error, got: %s", validAgent.metadata.ConfigError)
		}

		// Verify that invalid agents have config errors
		var invalidAgent *Agent
		for _, agent := range agents {
			if agent.Name() == "no-desc" {
				invalidAgent = agent
				break
			}
		}
		if invalidAgent == nil {
			t.Fatal("expected to find invalid agent: no-desc")
		}
		if invalidAgent.metadata.ConfigError == "" {
			t.Error("expected invalid agent 'no-desc' to have config error")
		}
	})

	t.Run("returns agents in standard and privileged directory", func(t *testing.T) {
		r := &Repository{
			spokes: spokestest.NewClient(t,
				spokestest.WithBlob("agents/README.md", []byte("readme content")), // filtered out
				spokestest.WithBlob("agents/test-agent1.md", []byte("---\nname: valid-agent\ndescription: A valid agent\n---\nprompt")),
				spokestest.WithBlob(".github/agents/README.md", []byte("readme content")), // filtered out
				spokestest.WithBlob(".github/agents/test-agent2.md", []byte("---\nname: valid-agent\ndescription: A valid agent\n---\nprompt")),
			),
			obsv:      observability.NewNoopExporters(),
			directory: Directory,
		}

		agents, err := r.agents(context.Background(), false)
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		if agents == nil {
			t.Fatal("expected agents, got nil")
		}
		if len(agents) != 1 {
			t.Fatalf("expected 1 agents, got %d", len(agents))
		}

		r.directory = OrgDirectory
		privAgents, err := r.agents(context.Background(), false)
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		if privAgents == nil {
			t.Fatal("expected agents, got nil")
		}
		if len(privAgents) != 1 {
			t.Fatalf("expected 1 agents, got %d", len(privAgents))
		}
	})
}

func TestRepositoryAgentConfig(t *testing.T) {
	t.Run("return ErrNotFound when agent config does not exist", func(t *testing.T) {
		r := &Repository{
			spokes: spokestest.NewClient(t),
			obsv:   observability.NewNoopExporters(),
		}

		for _, dir := range []string{OrgDirectory, Directory} {
			r.directory = dir
			_, err := r.agentConfig(context.Background(), "nonexistent-agent", "")
			if !errors.Is(err, ErrRequestedAgentNotFound) {
				t.Fatalf("expected ErrNotFound for %s, got %v", dir, err)
			}
		}
	})
}

func TestRepositoryAgent(t *testing.T) {
	t.Run("returns error and no agent when errorOnInvalidConfig is true", func(t *testing.T) {
		invalidContents := "---\nname: Missing description\n---\nprompt"

		r := &Repository{
			spokes: spokestest.NewClient(t,
				spokestest.WithBlob(".github/agents/invalid-agent.md", []byte(invalidContents)),
			),
			obsv:      observability.NewNoopExporters(),
			owner:     "test-owner",
			name:      "test-repo",
			directory: Directory,
		}

		me := Metadata{
			Name:        "invalid-agent",
			RepoID:      123,
			RepoOwnerID: 456,
			Version:     "",
		}

		agent, err := r.agent(context.Background(), me, true)
		if err == nil {
			t.Fatal("expected error when errorOnInvalidConfig is true")
		}
		if agent != nil {
			t.Fatal("expected no agent when errorOnInvalidConfig is true")
		}
	})

	t.Run("returns valid agent successfully regardless of errorOnInvalidConfig flag", func(t *testing.T) {
		validContents := "---\nname: valid-agent\ndescription: A valid agent\n---\nprompt"

		r := &Repository{
			spokes: spokestest.NewClient(t,
				spokestest.WithBlob(".github/agents/valid-agent.md", []byte(validContents)),
			),
			obsv:      observability.NewNoopExporters(),
			owner:     "test-owner",
			name:      "test-repo",
			directory: Directory,
		}

		me := Metadata{
			Name:        "valid-agent",
			RepoID:      123,
			RepoOwnerID: 456,
			Version:     "",
		}

		// Test with errorOnInvalidConfig = false
		agent, err := r.agent(context.Background(), me, false)
		if err != nil {
			t.Fatalf("unexpected error with errorOnInvalidConfig=false: %v", err)
		}
		if agent == nil {
			t.Fatal("expected agent with errorOnInvalidConfig=false")
		}
		if agent.metadata.ConfigError != "" {
			t.Errorf("expected no config error for valid agent, got: %s", agent.metadata.ConfigError)
		}

		// Test with errorOnInvalidConfig = true
		agent, err = r.agent(context.Background(), me, true)
		if err != nil {
			t.Fatalf("unexpected error with errorOnInvalidConfig=true: %v", err)
		}
		if agent == nil {
			t.Fatal("expected agent with errorOnInvalidConfig=true")
		}
		if agent.metadata.ConfigError != "" {
			t.Errorf("expected no config error for valid agent, got: %s", agent.metadata.ConfigError)
		}
	})

	t.Run("handles non-config errors properly", func(t *testing.T) {
		r := &Repository{
			spokes:    spokestest.NewClient(t), // No agent files setup
			obsv:      observability.NewNoopExporters(),
			owner:     "test-owner",
			name:      "test-repo",
			directory: Directory,
		}

		me := Metadata{
			Name:        "nonexistent-agent",
			RepoID:      123,
			RepoOwnerID: 456,
			Version:     "",
		}

		// Both flags should behave the same for non-config errors (like file not found)
		agent, err := r.agent(context.Background(), me, false)
		if err == nil {
			t.Fatal("expected error for nonexistent agent")
		}
		if agent != nil {
			t.Fatal("expected no agent for nonexistent agent")
		}

		agent, err = r.agent(context.Background(), me, true)
		if err == nil {
			t.Fatal("expected error for nonexistent agent")
		}
		if agent != nil {
			t.Fatal("expected no agent for nonexistent agent")
		}
	})
}
