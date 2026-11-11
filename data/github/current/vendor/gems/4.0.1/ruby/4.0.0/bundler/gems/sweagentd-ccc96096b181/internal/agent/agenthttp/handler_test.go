package agenthttp

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	authd "github.com/github/authnd/client"
	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/agent"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/customagenttest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	jobsCustomAgent "github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/jobs/jobevents"
	"github.com/github/sweagentd/internal/jobs/progress"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Helper function to create spokes with repo-specific agents for testing repo/org precedence
func makeSpokesWithRepoSpecificAgents(t *testing.T, repoAgents, orgAgents map[string]string, repoID, orgRepoID uint64) *spokestest.Client {
	t.Helper()

	options := []spokestest.ClientOption{}

	// Add repository-specific agents
	for name, content := range repoAgents {
		option := spokestest.WithRepoBlob(repoID, filepath.Join(customagent.Directory, name+customagent.Extension), []byte(content))
		options = append(options, option)
	}

	// Add organization-specific agents
	for name, content := range orgAgents {
		option := spokestest.WithRepoBlob(orgRepoID, filepath.Join(customagent.OrgDirectory, name+customagent.Extension), []byte(content))
		options = append(options, option)
	}

	return spokestest.NewClient(t, options...)
}

// notFoundStore implements just the GetJob method of JobsStore used by Service.GetJob.
// It returns (nil, nil) to simulate a store that found no job record without error,
// allowing Service.GetJob to translate that into ErrJobNotFound for HTTP 404 path.
type notFoundStore struct{ jobstore }

func (s *notFoundStore) GetJob(ctx context.Context, owner, repo int64, id string) (*jobs.Job, error) {
	return nil, nil
}

func (s *notFoundStore) CreateProgress(ctx context.Context, progress *progress.Progress) (*progress.Progress, error) {
	return nil, nil
}

func (s *notFoundStore) BatchCreateProgress(ctx context.Context, progresses []*progress.Progress) ([]*progress.Progress, error) {
	return nil, nil
}

func (s *notFoundStore) ListProgress(ctx context.Context, assignmentID, jobID string) ([]*progress.Progress, error) {
	return nil, nil
}

func (s *notFoundStore) ListProgressByNamespace(ctx context.Context, assignmentID, jobID string, namespaces []string) ([]*progress.Progress, error) {
	return nil, nil
}

// mock callback + cleanup handlers to satisfy interface for NewHandler
type noopCallbackHandler struct{}

func (n *noopCallbackHandler) HandleCallback(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusTeapot)
}

type noopCleanupHandler struct{}

func (n *noopCleanupHandler) HandleCleanup(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusTeapot)
}

// mockCustomAgent is a test helper that implements sweagentd.CustomAgent
type mockCustomAgent struct {
	name        string
	repoOwnerID int64
	repoOwner   string
	repoID      int64
	repoName    string
	displayName string
	description string
	prompt      string
	tools       []string
	version     string
	mcpConfig   mcpconfig.JSON
}

func (m *mockCustomAgent) Name() string                             { return m.name }
func (m *mockCustomAgent) RepoOwnerID() int64                       { return m.repoOwnerID }
func (m *mockCustomAgent) RepoOwner() string                        { return m.repoOwner }
func (m *mockCustomAgent) RepoID() int64                            { return m.repoID }
func (m *mockCustomAgent) RepoName() string                         { return m.repoName }
func (m *mockCustomAgent) DisplayName() string                      { return m.displayName }
func (m *mockCustomAgent) Description() string                      { return m.description }
func (m *mockCustomAgent) Prompt() string                           { return m.prompt }
func (m *mockCustomAgent) Tools() []string                          { return m.tools }
func (m *mockCustomAgent) Version() string                          { return m.version }
func (m *mockCustomAgent) MCPConfig() mcpconfig.JSON                { return m.mcpConfig }
func (m *mockCustomAgent) Target() string                           { return "" }
func (m *mockCustomAgent) ConfigError() string                      { return "" }
func (m *mockCustomAgent) Metadata() map[string]string              { return nil }
func (m *mockCustomAgent) ArgumentHint() string                     { return "" }
func (m *mockCustomAgent) InferenceEnabled() bool                   { return false }
func (m *mockCustomAgent) Model() string                            { return "" }
func (m *mockCustomAgent) Handoffs() []sweagentd.CustomAgentHandoff { return nil }
func (m *mockCustomAgent) Permissions() map[string]string           { return nil }
func (m *mockCustomAgent) Triggers() sweagentd.CustomAgentTriggers {
	return sweagentd.CustomAgentTriggers{}
}
func (m *mockCustomAgent) Scope() string { return jobsCustomAgent.ScopeRepo }
func (m *mockCustomAgent) ToDB() jobsCustomAgent.DBRecord {
	return jobsCustomAgent.DBRecord{
		Name:        m.name,
		RepoOwnerID: m.repoOwnerID,
		RepoOwner:   m.repoOwner,
		RepoID:      m.repoID,
		RepoName:    m.repoName,
		DisplayName: m.displayName,
		Description: m.description,
		Tools:       m.tools,
		Version:     m.version,
	}
}

func TestServiceGetJob(t *testing.T) {
	cf := &github.NoopClientFactory{}
	store := memory.NewStore()
	spokes := customagenttest.MakeSpokes(t, map[string]string{})
	ghTwirp := githubtwirp.NewNoopClient()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	obsv := observability.NewNoopExporters()
	customAgentSvc := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
	svc := agent.NewService(store, cf, customAgentSvc, obsv, ffClient, ghTwirp, &jobevents.NoopEmitter{})
	ctx := context.Background()

	// seed job
	job := &jobs.Job{ID: "1-2-someuuid", OwnerID: 1, RepoID: 2}
	_, _ = store.CreateJob(ctx, job)

	t.Run("success", func(t *testing.T) {
		got, err := svc.GetJob(ctx, job.ID)
		require.NoError(t, err)
		require.Equal(t, job.ID, got.ID)
	})
	t.Run("invalid id", func(t *testing.T) {
		_, err := svc.GetJob(ctx, "badid")
		require.ErrorIs(t, err, agent.ErrInvalidJobIDFormat)
	})
	t.Run("not found", func(t *testing.T) {
		_, err := svc.GetJob(ctx, "1-2-missing")
		require.Error(t, err)
		require.NotErrorIs(t, err, agent.ErrInvalidJobIDFormat)
		require.NotErrorIs(t, err, agent.ErrInvalidJobIDOwner)
		require.NotErrorIs(t, err, agent.ErrInvalidJobIDRepo)
	})

	t.Run("invalid owner", func(t *testing.T) {
		_, err := svc.GetJob(ctx, "x-2-someuuid")
		require.ErrorIs(t, err, agent.ErrInvalidJobIDOwner)
	})
	t.Run("invalid repo", func(t *testing.T) {
		_, err := svc.GetJob(ctx, "1-y-someuuid")
		require.ErrorIs(t, err, agent.ErrInvalidJobIDRepo)
	})
}

func TestHandlerAuthorize(t *testing.T) {
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	cf := &github.NoopClientFactory{}
	tw := githubtwirp.NewNoopClient()
	agents := map[string]string{
		"agent1": "---\nkey: value\n---\nthis is agent 1",
		"agent2": "---\nkey: value\n---\nthis is agent 2",
	}
	spokes := customagenttest.MakeSpokes(t, agents)
	ghTwirp := githubtwirp.NewNoopClient()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
	h := NewHandler(obsv, featureflags.NewNoopClient(nil), store, cf, tw, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, agenticapptest.NewTestProvider(t), nil)

	ctx := context.Background()
	userCtx := requestctx.AddData(ctx, &requestctx.CtxData{UserInfo: &requestctx.UserInfo{ID: 1, TokenInfo: &requestctx.TokenInfo{ApplicationID: uint64(cf.AppID()), Type: string(authd.CredentialTypeUserToServerToken)}}})

	t.Run("success", func(t *testing.T) {
		info, err := h.authorize(userCtx)
		require.NoError(t, err)
		require.NotNil(t, info)
	})
	t.Run("missing user", func(t *testing.T) {
		_, err := h.authorize(context.Background())
		require.Error(t, err)
	})
	t.Run("wrong app id", func(t *testing.T) {
		badCtx := requestctx.AddData(ctx, &requestctx.CtxData{UserInfo: &requestctx.UserInfo{ID: 1, TokenInfo: &requestctx.TokenInfo{ApplicationID: 9999}}})
		_, err := h.authorize(badCtx)
		require.Error(t, err)
	})
}

func TestHandlerCheckEnablement(t *testing.T) {
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	// by default noop client returns false (zero value). Configure true.
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
	agents := map[string]string{
		"agent1": "---\nkey: value\n---\nthis is agent 1",
		"agent2": "---\nkey: value\n---\nthis is agent 2",
	}
	spokes := customagenttest.MakeSpokes(t, agents)
	ghTwirp := githubtwirp.NewNoopClient()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
	h := NewHandler(obsv, featureflags.NewNoopClient(nil), store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, agenticapptest.NewTestProvider(t), nil)

	ctx := context.Background()
	ok, err := h.checkEnablement(ctx, 1, 2, 3)
	require.NoError(t, err)
	require.True(t, ok)

	// disabled
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: false}
	ok, err = h.checkEnablement(ctx, 1, 2, 3)
	require.Error(t, err)
	require.False(t, ok)
}

func TestHandlerValidateNonce(t *testing.T) {
	h := &Handler{}
	nonce := "abc123"
	hash := jobs.HashNonce(nonce)
	req := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
	req.Header.Set(jobs.JobNonceHeader, nonce)
	require.NoError(t, h.validateNonce(req, hash))

	req2 := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
	// missing header
	require.Error(t, h.validateNonce(req2, hash))

	req3 := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
	req3.Header.Set(jobs.JobNonceHeader, "wrong")
	require.Error(t, h.validateNonce(req3, hash))
}

func TestHandlerGetJob(t *testing.T) {
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
	agents := map[string]string{
		"agent1": "---\nkey: value\n---\nthis is agent 1",
		"agent2": "---\nkey: value\n---\nthis is agent 2",
	}
	spokes := customagenttest.MakeSpokes(t, agents)
	ghTwirp := githubtwirp.NewNoopClient()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
	h := NewHandler(obsv, featureflags.NewNoopClient(nil), store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, agenticapptest.NewTestProvider(t), nil)

	// seed job
	nonce := "nonce-val"
	job := &jobs.Job{
		ID:               "1-2-uuid",
		OwnerID:          1,
		RepoID:           2,
		NonceHash:        jobs.HashNonce(nonce),
		ProblemStatement: jobs.ProblemStatement{Content: "Fix the bug"},
		CustomAgent:      jobsCustomAgent.DBRecord{Name: "", RepoOwner: "owner", RepoName: "repo", DisplayName: "", Description: "desc", Tools: []string{"tool1"}},
	}
	_, _ = store.CreateJob(context.Background(), job)

	baseCtx := requestctx.AddData(context.Background(), &requestctx.CtxData{UserInfo: &requestctx.UserInfo{ID: 123, TokenInfo: &requestctx.TokenInfo{ApplicationID: uint64(cf.AppID())}}})

	t.Run("missing job id", func(t *testing.T) {
		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/", nil)
		w := httptest.NewRecorder()
		h.getJob(w, req)
		require.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("hydrates custom agent with prompt from repo when not copilot", func(t *testing.T) {
		// The prompt we expect to be fetched from the repo (not stored in DB)
		expectedPrompt := "This is the hydrated prompt from the repository."
		customAgentName := "my-custom-agent"

		// Create spokes with the agent file that includes the prompt
		agentContent := `---
name: My Custom Agent
description: A custom agent for testing
tools: ["tool1", "tool2"]
---
` + expectedPrompt

		spokesWithAgent := customagenttest.MakeSpokesWithRepoAndCommitSHA(t, map[string]string{
			customAgentName: agentContent,
		}, "", 2) // repoID = 2 to match the job

		ghTwirpClient := githubtwirp.NewNoopClient()
		ghTwirpClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
		// Mock the repo lookup that happens during GetAgent
		ghTwirpClient.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         2,
						Name:       "repo",
						OwnerLogin: "owner",
						OwnerId:    1,
					},
				},
			}, nil
		}
		ghTwirpClient.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
			return &sweagentdTwirp.EnterpriseAgentsResponse{
				RepositoryId: 0, // No enterprise repo
			}, nil
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		customAgentSvcWithPrompt := customagent.NewService(observability.NewNoopExporters(), spokesWithAgent, ghTwirpClient, ffClient)
		storeWithCustomAgent := memory.NewStore()
		hWithCustomAgent := NewHandler(obsv, ffClient, storeWithCustomAgent, cf, ghTwirpClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvcWithPrompt, agenticapptest.NewTestProvider(t), nil)

		// Create a job with a custom agent (NOT copilot - name is not empty)
		// Note: The DBRecord intentionally does NOT have a Prompt field
		customAgentJob := &jobs.Job{
			ID:               "1-2-custom-agent-job",
			OwnerID:          1,
			RepoID:           2,
			NonceHash:        jobs.HashNonce(nonce),
			ProblemStatement: jobs.ProblemStatement{Content: "Do something with my custom agent"},
			CustomAgent: jobsCustomAgent.DBRecord{
				Name:        customAgentName,
				RepoOwner:   "owner",
				RepoOwnerID: 1,
				RepoName:    "repo",
				RepoID:      2,
				DisplayName: "My Custom Agent",
				Description: "A custom agent for testing",
				Tools:       []string{"tool1", "tool2"},
				Version:     "",
				// NOTE: No Prompt field here - it should be fetched from the repo
			},
		}
		_, _ = storeWithCustomAgent.CreateJob(baseCtx, customAgentJob)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-custom-agent-job", nil)
		req = muxSetParam(req, "jobID", customAgentJob.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		hWithCustomAgent.getJob(w, req)

		require.Equal(t, http.StatusOK, w.Code)

		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))

		// The key assertion: the prompt should be hydrated from the repo, not empty
		assert.Equal(t, expectedPrompt, resp.CustomAgent.Prompt, "prompt should be hydrated from repo")
		assert.Equal(t, customAgentName, resp.CustomAgent.Name)
		assert.Equal(t, "My Custom Agent", resp.CustomAgent.DisplayName)
		assert.Equal(t, "A custom agent for testing", resp.CustomAgent.Description)
		assert.ElementsMatch(t, []string{"tool1", "tool2"}, resp.CustomAgent.Tools)
	})

	t.Run("does not hydrate custom agent for copilot agent", func(t *testing.T) {
		// Create a job with the default Copilot agent (empty name)
		copilotJob := &jobs.Job{
			ID:               "1-2-copilot-job",
			OwnerID:          1,
			RepoID:           2,
			NonceHash:        jobs.HashNonce(nonce),
			ProblemStatement: jobs.ProblemStatement{Content: "Do something with copilot"},
			CustomAgent: jobsCustomAgent.DBRecord{
				Name:      "", // Empty name = Copilot agent
				RepoOwner: "owner",
				RepoName:  "repo",
			},
		}
		_, _ = store.CreateJob(baseCtx, copilotJob)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-copilot-job", nil)
		req = muxSetParam(req, "jobID", copilotJob.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.getJob(w, req)

		require.Equal(t, http.StatusOK, w.Code)

		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))

		// Copilot agent should have no prompt (and shouldn't try to fetch one)
		assert.Empty(t, resp.CustomAgent.Prompt, "copilot agent should have no prompt")
		assert.Empty(t, resp.CustomAgent.Name, "copilot agent should have empty name")
	})

	t.Run("job not found", func(t *testing.T) {
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		ghTwirp := githubtwirp.NewNoopClient()
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		obsv := observability.NewNoopExporters()
		customAgentSvc := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		nfSvc := agent.NewService(&notFoundStore{}, cf, customAgentSvc, obsv, ffClient, ghTwirp, &jobevents.NoopEmitter{})
		hnf := *h
		hnf.svc = nfSvc
		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-missing", nil)
		req = muxSetParam(req, "jobID", "1-2-missing")
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		hnf.getJob(w, req)
		require.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("success", func(t *testing.T) {
		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-uuid", nil)
		req = muxSetParam(req, "jobID", job.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.getJob(w, req)
		require.Equal(t, http.StatusOK, w.Code)
		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		require.Equal(t, job.ProblemStatement.Content, resp.ProblemStatement.Content)
	})

	t.Run("unauthorized app id", func(t *testing.T) {
		badCtx := requestctx.AddData(context.Background(), &requestctx.CtxData{UserInfo: &requestctx.UserInfo{ID: 123, TokenInfo: &requestctx.TokenInfo{ApplicationID: 999}}})
		req := httptest.NewRequestWithContext(badCtx, http.MethodGet, "/agent/jobs/1-2-uuid", nil)
		req = muxSetParam(req, "jobID", job.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.getJob(w, req)
		require.Equal(t, http.StatusUnauthorized, w.Code)
	})

	t.Run("missing nonce", func(t *testing.T) {
		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-uuid", nil)
		req = muxSetParam(req, "jobID", job.ID)
		w := httptest.NewRecorder()
		h.getJob(w, req)
		require.Equal(t, http.StatusUnauthorized, w.Code)
	})

	t.Run("invalid nonce", func(t *testing.T) {
		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-uuid", nil)
		req = muxSetParam(req, "jobID", job.ID)
		req.Header.Set(jobs.JobNonceHeader, "wrong")
		w := httptest.NewRecorder()
		h.getJob(w, req)
		require.Equal(t, http.StatusUnauthorized, w.Code)
	})

	t.Run("organization custom instructions included", func(t *testing.T) {
		// Set up mock organization custom instructions
		orgInstructions := "Always follow our coding standards and use TypeScript."
		noopClient.NoopSweagentdAPI.MockGetOrganizationCustomInstructions = func(ctx context.Context, req *sweagentdTwirp.GetOrganizationCustomInstructionsRequest) (*sweagentdTwirp.GetOrganizationCustomInstructionsResponse, error) {
			return &sweagentdTwirp.GetOrganizationCustomInstructionsResponse{
				OrganizationCustomInstructions: orgInstructions,
			}, nil
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		customAgentSvcEnabled := customagent.NewService(observability.NewNoopExporters(), spokes, noopClient, ffClient)
		h := NewHandler(obsv, ffClient, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvcEnabled, agenticapptest.NewTestProvider(t), nil)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-uuid", nil)
		req = muxSetParam(req, "jobID", job.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.getJob(w, req)
		require.Equal(t, http.StatusOK, w.Code)
		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))

		// Verify organization custom instructions are included
		assert.Equal(t, orgInstructions, resp.OrganizationCustomInstructions)
	})

	t.Run("excludes agents with config_error from available custom agents list", func(t *testing.T) {
		// Create agents with valid and invalid configurations
		agentsWithErrors := map[string]string{
			"valid-agent":   "---\nname: Valid Agent\ndescription: A valid agent\n---\nThis is a valid prompt",
			"invalid-agent": "---\nname: Missing description\n---\nThis agent is missing the required description field",
			"another-valid": "---\nname: Another Valid\ndescription: Another valid agent\n---\nAnother valid prompt",
		}
		spokesWithErrors := customagenttest.MakeSpokes(t, agentsWithErrors)
		ghTwirpWithErrors := githubtwirp.NewNoopClient()
		ffClientWithErrors := featureflags.NewNoopClient(map[string]bool{})
		customAgentSvcWithErrors := customagent.NewService(observability.NewNoopExporters(), spokesWithErrors, ghTwirpWithErrors, ffClientWithErrors)
		hWithErrors := NewHandler(obsv, ffClientWithErrors, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvcWithErrors, agenticapptest.NewTestProvider(t), nil)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-uuid", nil)
		req = muxSetParam(req, "jobID", job.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		hWithErrors.getJob(w, req)
		require.Equal(t, http.StatusOK, w.Code)
		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))

		// Verify that only valid agents are in the available custom agents list
		assert.Len(t, resp.AvailableCustomAgents, 2, "should only include valid agents")

		// Verify that the invalid agent is not in the list
		for _, agent := range resp.AvailableCustomAgents {
			assert.NotEqual(t, "invalid-agent", agent.Name, "invalid-agent should not be in available custom agents")
		}

		// Verify that valid agents are present
		agentNames := make([]string, len(resp.AvailableCustomAgents))
		for i, agent := range resp.AvailableCustomAgents {
			agentNames[i] = agent.Name
		}
		assert.Contains(t, agentNames, "valid-agent", "valid-agent should be in available custom agents")
		assert.Contains(t, agentNames, "another-valid", "another-valid should be in available custom agents")
	})

	t.Run("uses GetAgentForJob when CopilotSWEAgentCustomAgentPermissions flag enabled for job-scoped agent", func(t *testing.T) {
		// Setup with the custom agent permissions feature flag enabled
		jobScopedAgentName := "my-job-scoped-agent"
		expectedPrompt := "This is a job-scoped agent prompt from the database."
		expectedPermissions := map[string]string{
			"contents":      "write",
			"pull-requests": "write",
		}

		ghTwirpClient := githubtwirp.NewNoopClient()
		ghTwirpClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
		ghTwirpClient.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         2,
						Name:       "repo",
						OwnerLogin: "owner",
						OwnerId:    1,
					},
				},
			}, nil
		}

		spokesClient := customagenttest.MakeSpokes(t, map[string]string{})
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentPermissions: true,
		})
		customAgentSvcJobScoped := customagent.NewService(observability.NewNoopExporters(), spokesClient, ghTwirpClient, ffClient)
		storeWithJobScopedAgent := memory.NewStore()
		hWithJobScopedAgent := NewHandler(obsv, ffClient, storeWithJobScopedAgent, cf, ghTwirpClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvcJobScoped, agenticapptest.NewTestProvider(t), nil)

		// Create a job with a job-scoped custom agent (scope is "job")
		jobScopedJob := &jobs.Job{
			ID:               "1-2-job-scoped-agent-job",
			OwnerID:          1,
			RepoID:           2,
			NonceHash:        jobs.HashNonce(nonce),
			ProblemStatement: jobs.ProblemStatement{Content: "Do something with job-scoped agent"},
			CustomAgent: jobsCustomAgent.DBRecord{
				Name:        jobScopedAgentName,
				Scope:       jobsCustomAgent.ScopeJob,
				RepoOwner:   "owner",
				RepoOwnerID: 1,
				RepoName:    "repo",
				RepoID:      2,
				DisplayName: "My Job-Scoped Agent",
				Description: "A job-scoped agent for testing",
				Tools:       []string{"tool1", "tool2"},
				Version:     "",
				// Job-scoped agents store the prompt and permissions in the DB
				Prompt:      expectedPrompt,
				Permissions: expectedPermissions,
			},
		}
		_, _ = storeWithJobScopedAgent.CreateJob(baseCtx, jobScopedJob)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-job-scoped-agent-job", nil)
		req = muxSetParam(req, "jobID", jobScopedJob.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		hWithJobScopedAgent.getJob(w, req)

		require.Equal(t, http.StatusOK, w.Code)

		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))

		// The key assertion: when the flag is enabled, job-scoped agents should have their prompt loaded from DB
		assert.Equal(t, expectedPrompt, resp.CustomAgent.Prompt, "job-scoped agent prompt should be loaded from DB when flag enabled")
		assert.Equal(t, jobScopedAgentName, resp.CustomAgent.Name)
		assert.Equal(t, "My Job-Scoped Agent", resp.CustomAgent.DisplayName)
		assert.Equal(t, "A job-scoped agent for testing", resp.CustomAgent.Description)
		assert.ElementsMatch(t, []string{"tool1", "tool2"}, resp.CustomAgent.Tools)
	})

	t.Run("uses GetAgentForJob when CopilotSWEAgentCustomAgentPermissions flag enabled for regular custom agent", func(t *testing.T) {
		// Setup with the custom agent permissions feature flag enabled
		// For regular custom agents (non-job-scoped), this path fetches the agent from the repo by ID
		customAgentName := "my-regular-agent"
		expectedPrompt := "This is a regular custom agent prompt from the repo."

		// Create spokes with the agent file that includes the prompt
		agentContent := `---
name: My Regular Agent
description: A regular custom agent for testing
tools: ["tool1", "tool2"]
---
` + expectedPrompt

		spokesWithAgent := customagenttest.MakeSpokesWithRepoAndCommitSHA(t, map[string]string{
			customAgentName: agentContent,
		}, "", 2) // repoID = 2 to match the job

		ghTwirpClient := githubtwirp.NewNoopClient()
		ghTwirpClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
		ghTwirpClient.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         2,
						Name:       "repo",
						OwnerLogin: "owner",
						OwnerId:    1,
					},
				},
			}, nil
		}
		ghTwirpClient.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
			return &sweagentdTwirp.EnterpriseAgentsResponse{
				RepositoryId: 0, // No enterprise repo
			}, nil
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentPermissions: true,
		})
		customAgentSvcWithFlag := customagent.NewService(observability.NewNoopExporters(), spokesWithAgent, ghTwirpClient, ffClient)
		storeWithFlag := memory.NewStore()
		hWithFlag := NewHandler(obsv, ffClient, storeWithFlag, cf, ghTwirpClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvcWithFlag, agenticapptest.NewTestProvider(t), nil)

		// Create a job with a regular custom agent (scope defaults to "repo")
		regularAgentJob := &jobs.Job{
			ID:               "1-2-regular-agent-flag-job",
			OwnerID:          1,
			RepoID:           2,
			NonceHash:        jobs.HashNonce(nonce),
			ProblemStatement: jobs.ProblemStatement{Content: "Do something with regular agent with flag enabled"},
			CustomAgent: jobsCustomAgent.DBRecord{
				Name:        customAgentName,
				RepoOwner:   "owner",
				RepoOwnerID: 1,
				RepoName:    "repo",
				RepoID:      2,
				DisplayName: "My Regular Agent",
				Description: "A regular custom agent for testing",
				Tools:       []string{"tool1", "tool2"},
				Version:     "",
			},
		}
		_, _ = storeWithFlag.CreateJob(baseCtx, regularAgentJob)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-regular-agent-flag-job", nil)
		req = muxSetParam(req, "jobID", regularAgentJob.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		hWithFlag.getJob(w, req)

		require.Equal(t, http.StatusOK, w.Code)

		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))

		// The key assertion: when the flag is enabled, regular agents should still fetch prompt from repo
		assert.Equal(t, expectedPrompt, resp.CustomAgent.Prompt, "regular agent prompt should be fetched from repo when flag enabled")
		assert.Equal(t, customAgentName, resp.CustomAgent.Name)
		assert.Equal(t, "My Regular Agent", resp.CustomAgent.DisplayName)
		assert.Equal(t, "A regular custom agent for testing", resp.CustomAgent.Description)
		assert.ElementsMatch(t, []string{"tool1", "tool2"}, resp.CustomAgent.Tools)
	})

	t.Run("uses GetAgentForJob when CopilotSWEAgentCustomAgentPermissions flag enabled for copilot agent", func(t *testing.T) {
		// Ensure Copilot agent works correctly when the flag is enabled
		ghTwirpClient := githubtwirp.NewNoopClient()
		ghTwirpClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}

		spokesClient := customagenttest.MakeSpokes(t, map[string]string{})
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentPermissions: true,
		})
		customAgentSvcWithFlag := customagent.NewService(observability.NewNoopExporters(), spokesClient, ghTwirpClient, ffClient)
		storeWithFlag := memory.NewStore()
		hWithFlag := NewHandler(obsv, ffClient, storeWithFlag, cf, ghTwirpClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvcWithFlag, agenticapptest.NewTestProvider(t), nil)

		// Create a job with the default Copilot agent (empty name)
		copilotJobWithFlag := &jobs.Job{
			ID:               "1-2-copilot-flag-job",
			OwnerID:          1,
			RepoID:           2,
			NonceHash:        jobs.HashNonce(nonce),
			ProblemStatement: jobs.ProblemStatement{Content: "Do something with copilot with flag enabled"},
			CustomAgent: jobsCustomAgent.DBRecord{
				Name:      "", // Empty name = Copilot agent
				RepoOwner: "owner",
				RepoName:  "repo",
			},
		}
		_, _ = storeWithFlag.CreateJob(baseCtx, copilotJobWithFlag)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-copilot-flag-job", nil)
		req = muxSetParam(req, "jobID", copilotJobWithFlag.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		hWithFlag.getJob(w, req)

		require.Equal(t, http.StatusOK, w.Code)

		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))

		// Copilot agent should still have no prompt even with flag enabled
		assert.Empty(t, resp.CustomAgent.Prompt, "copilot agent should have no prompt even when flag enabled")
		assert.Empty(t, resp.CustomAgent.Name, "copilot agent should have empty name")
	})
}

func TestHandlerGetAgent(t *testing.T) {
	runTests := func(t *testing.T, validateJobNonce bool) {
		t.Run("returns custom agent details", func(t *testing.T) {
			result := runGetTest(t, "sha-999999999999999999999999999999999999", "agent1", "sha-999999999999999999999999999999999999", http.StatusOK, validateJobNonce)
			assert.Equal(t, "agent1", result.Name, "agent name should match")
			assert.Equal(t, "This is agent 1", result.Description, "agent description should match")
			assert.Equal(t, []string{"tool1", "tool2"}, result.Tools, "agent tools should match")
			assert.Equal(t, "This is the prompt for agent 1.", result.Prompt, "agent prompt should match")
			assert.Equal(t, "sha-999999999999999999999999999999999999", result.Version, "agent version should match")
		})

		t.Run("returns latest custom agent details", func(t *testing.T) {
			result := runGetTest(t, "", "agent1", "", http.StatusOK, validateJobNonce)
			assert.Equal(t, "agent1", result.Name, "agent name should match")
			assert.Equal(t, "This is agent 1", result.Description, "agent description should match")
			assert.Equal(t, []string{"tool1", "tool2"}, result.Tools, "agent tools should match")
			assert.Equal(t, "This is the prompt for agent 1.", result.Prompt, "agent prompt should match")
			assert.NotEmpty(t, result.Version, "agent version should be set")
		})

		t.Run("404s when repo not found", func(t *testing.T) {
			runGetTest(t, "repo-does-not-exist", "agent1", "", http.StatusNotFound, validateJobNonce)
		})

		t.Run("404s for non-existent agent", func(t *testing.T) {
			runGetTest(t, "", "does-not-exist", "", http.StatusNotFound, validateJobNonce)
		})

		t.Run("404s for non-existent version", func(t *testing.T) {
			runGetTest(t, "sha-999999999999999999999999999999999999", "agent1", "sha-999999999999999999999999999999999988", http.StatusNotFound, validateJobNonce)
		})
	}

	t.Run("without job nonce validation", func(t *testing.T) {
		runTests(t, false)
	})

	t.Run("with job nonce validation", func(t *testing.T) {
		runTests(t, true)

		// Additional tests for job-nonce validation failure modes
		t.Run("returns 400 when X-GitHub-Job-ID header is missing", func(t *testing.T) {
			testGetAgentValidationFailure(t, validationTestCase{
				includeJobIDHeader: false,
				includeNonceHeader: true,
				createJob:          true,
				expectedStatus:     http.StatusBadRequest,
			})
		})

		t.Run("returns 401 when nonce header is missing", func(t *testing.T) {
			testGetAgentValidationFailure(t, validationTestCase{
				includeJobIDHeader: true,
				includeNonceHeader: false,
				createJob:          true,
				expectedStatus:     http.StatusUnauthorized,
			})
		})

		t.Run("returns 401 when nonce is invalid", func(t *testing.T) {
			testGetAgentValidationFailure(t, validationTestCase{
				includeJobIDHeader: true,
				includeNonceHeader: true,
				invalidNonce:       true,
				createJob:          true,
				expectedStatus:     http.StatusUnauthorized,
			})
		})
	})
}

const agentContent string = `---
name: agent1
description: This is agent 1
tools: ["tool1", "tool2" ]
---
This is the prompt for agent 1.
`

func runGetTest(t *testing.T, dataVersion, expectedAgentName, expectedVersion string, expectedHTTPStatus int, validateJobNonce bool) customAgentDTO {
	obsv := observability.NewNoopExporters()
	cf := &github.NoopClientFactory{}
	store := memory.NewStore()
	ffs := map[string]bool{
		featureflags.CopilotSWEAgentCustomAgentValidateJobNonce: validateJobNonce,
	}
	ffClient := featureflags.NewNoopClient(ffs)
	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
		return nil, nil
	}
	if dataVersion == "repo-does-not-exist" {
		ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			return nil, customagent.ErrRepoNotFound
		}
	} else {
		ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         12345,
						Name:       "testrepo",
						OwnerLogin: "testowner",
						OwnerId:    456,
					},
				},
			}, nil
		}
	}

	ctx := requestctx.NewContext(context.Background())

	agents := map[string]string{
		"agent1": agentContent,
		"agent2": "---\nkey: value\n---\nthis is agent 2",
	}
	spokes := customagenttest.MakeSpokesWithCommitSHA(t, agents, dataVersion)
	customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
	h := NewHandler(obsv, ffClient, store, cf, ghTwirp, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, agenticapptest.NewTestProvider(t), nil)

	userInfo := &requestctx.UserInfo{
		ID:        123,
		TokenInfo: &requestctx.TokenInfo{Token: "token"},
	}
	err := requestctx.AddUser(ctx, userInfo)
	if err != nil {
		t.Fatalf("failed to add user to context: %v", err)
	}

	// When validating job nonce, create a job and set up the required headers
	nonce := "test-nonce"
	jobID := "456-12345-test-job-id"
	if validateJobNonce {
		job := &jobs.Job{
			ID:        jobID,
			OwnerID:   456,
			RepoID:    12345,
			NonceHash: jobs.HashNonce(nonce),
		}
		_, err := store.CreateJob(ctx, job)
		if err != nil {
			t.Fatalf("failed to create job: %v", err)
		}
	}

	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("repoOwner", "testowner")
	rctx.URLParams.Add("repoName", "testrepo")
	rctx.URLParams.Add("agentName", expectedAgentName)
	ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

	var req *http.Request
	if expectedVersion != "" {
		req = httptest.NewRequestWithContext(ctx, "GET", "/agent/custom-agents/testowner/testrepo/"+expectedAgentName+"?version="+expectedVersion, nil)
	} else {
		req = httptest.NewRequestWithContext(ctx, "GET", "/agent/custom-agents/testowner/testrepo/"+expectedAgentName, nil)
	}

	if validateJobNonce {
		req.Header.Set("X-GitHub-Job-ID", jobID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
	}

	rr := httptest.NewRecorder()
	h.getAgent(rr, req)

	// Check expected status
	if rr.Code != expectedHTTPStatus {
		t.Errorf("expected status %d, got %d", expectedHTTPStatus, rr.Code)
	}

	// If not OK, return empty result
	if rr.Code != http.StatusOK {
		return customAgentDTO{}
	}

	var result customAgentDTO
	err = json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err, "failed to unmarshal response")

	return result
}

// validationTestCase configures a test case for job-nonce validation failure modes
type validationTestCase struct {
	includeJobIDHeader bool
	includeNonceHeader bool
	invalidNonce       bool
	createJob          bool
	expectedStatus     int
}

// testGetAgentValidationFailure tests specific job-nonce validation failure scenarios
func testGetAgentValidationFailure(t *testing.T, tc validationTestCase) {
	obsv := observability.NewNoopExporters()
	cf := &github.NoopClientFactory{}
	store := memory.NewStore()
	ffs := map[string]bool{
		featureflags.CopilotSWEAgentCustomAgentValidateJobNonce: true,
	}
	ffClient := featureflags.NewNoopClient(ffs)
	ghTwirp := githubtwirp.NewNoopClient()
	// Mock returns no enterprise agents for this test scenario
	ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
		return nil, nil
	}
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{
					Id:         12345,
					Name:       "testrepo",
					OwnerLogin: "testowner",
					OwnerId:    456,
				},
			},
		}, nil
	}

	ctx := requestctx.NewContext(context.Background())

	agents := map[string]string{
		"agent1": agentContent,
	}
	spokes := customagenttest.MakeSpokesWithCommitSHA(t, agents, "")
	customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
	h := NewHandler(obsv, ffClient, store, cf, ghTwirp, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, agenticapptest.NewTestProvider(t), nil)

	userInfo := &requestctx.UserInfo{
		ID:        123,
		TokenInfo: &requestctx.TokenInfo{Token: "token"},
	}
	err := requestctx.AddUser(ctx, userInfo)
	if err != nil {
		t.Fatalf("failed to add user to context: %v", err)
	}

	nonce := "test-nonce"
	jobID := "456-12345-test-job-id"

	// Create job if requested
	if tc.createJob {
		job := &jobs.Job{
			ID:        jobID,
			OwnerID:   456,
			RepoID:    12345,
			NonceHash: jobs.HashNonce(nonce),
		}
		_, err := store.CreateJob(ctx, job)
		if err != nil {
			t.Fatalf("failed to create job: %v", err)
		}
	}

	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("repoOwner", "testowner")
	rctx.URLParams.Add("repoName", "testrepo")
	rctx.URLParams.Add("agentName", "agent1")
	ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

	req := httptest.NewRequestWithContext(ctx, "GET", "/agent/custom-agents/testowner/testrepo/agent1", nil)

	// Set headers based on test case
	if tc.includeJobIDHeader {
		req.Header.Set("X-GitHub-Job-ID", jobID)
	}
	if tc.includeNonceHeader {
		nonceToUse := nonce
		if tc.invalidNonce {
			nonceToUse = "invalid-nonce"
		}
		req.Header.Set(jobs.JobNonceHeader, nonceToUse)
	}

	rr := httptest.NewRecorder()
	h.getAgent(rr, req)

	// Check expected status
	if rr.Code != tc.expectedStatus {
		t.Errorf("expected status %d, got %d, body: %s", tc.expectedStatus, rr.Code, rr.Body.String())
	}
}

// muxSetParam sets a chi URL param for tests without full router.
func muxSetParam(r *http.Request, key, value string) *http.Request {
	routeContext := chi.NewRouteContext()
	routeContext.URLParams.Add(key, value)
	return r.WithContext(context.WithValue(r.Context(), chi.RouteCtxKey, routeContext))
}

// TestFromDomainMapping validates that all relevant fields from the domain model
// are mapped into the DTO structure exactly as expected. It also ensures that
// slice semantics (nil vs empty) are preserved.
func TestFromDomainMapping(t *testing.T) {
	// TODO (chuxel): Remove this legacy path once CopilotSWEAgentCustomAgentPermissions feature flag is fully rolled out
	t.Run("populated custom agent, available agents, and problem statement", func(t *testing.T) {
		domain := &jobs.Job{
			ID: "1-2-someuuid",
			ProblemStatement: jobs.ProblemStatement{
				Content: "Fix the failing tests in module X",
			},
		}
		// Create a mock custom agent with the prompt (simulating what GetAgent would return)
		customAgent := &mockCustomAgent{
			name:        "refactorer",
			repoOwnerID: 1,
			repoOwner:   "octo-org",
			repoID:      2,
			repoName:    "octo-repo",
			displayName: "Refactorer",
			description: "Refactors code intelligently",
			prompt:      "This is the agent's prompt from the repo",
			tools:       []string{"search", "write", "format"},
			mcpConfig:   mcpconfig.JSON{Servers: map[string]mcpconfig.Server{}},
		}
		availableCustomAgents := []sweagentd.CustomAgent{
			customagent.FromDB(jobsCustomAgent.DBRecord{
				Name:        "refactorer",
				RepoOwnerID: 3,
				RepoOwner:   "octo-org",
				RepoID:      4,
				RepoName:    "octo-repo",
				DisplayName: "Refactorer",
				Description: "Refactors code intelligently",
				Tools:       []string{"search", "write", "format"},
				MCPServers:  []jobsCustomAgent.MCPServer{},
			}),
		}
		dto := jobDTOFromDomain(domain, customAgent, availableCustomAgents, "")
		require.NotNil(t, dto)
		assert.Equal(t, domain.ID, dto.ID)
		assert.Equal(t, domain.ProblemStatement.Content, dto.ProblemStatement.Content)

		assert.Equal(t, customAgent.Name(), dto.CustomAgent.Name)
		assert.Equal(t, customAgent.RepoOwnerID(), dto.CustomAgent.RepoOwnerID)
		assert.Equal(t, customAgent.RepoOwner(), dto.CustomAgent.RepoOwner)
		assert.Equal(t, customAgent.RepoID(), dto.CustomAgent.RepoID)
		assert.Equal(t, customAgent.RepoName(), dto.CustomAgent.RepoName)
		assert.Equal(t, customAgent.DisplayName(), dto.CustomAgent.DisplayName)
		assert.Equal(t, customAgent.Description(), dto.CustomAgent.Description)
		assert.Equal(t, customAgent.Prompt(), dto.CustomAgent.Prompt)
		assert.ElementsMatch(t, customAgent.Tools(), dto.CustomAgent.Tools)
		assert.Equal(t, len(availableCustomAgents), len(dto.AvailableCustomAgents))
		assert.Equal(t, availableCustomAgents[0].Name(), dto.AvailableCustomAgents[0].Name)
		assert.Equal(t, availableCustomAgents[0].RepoOwner(), dto.AvailableCustomAgents[0].RepoOwner)
		assert.Equal(t, availableCustomAgents[0].RepoOwnerID(), dto.AvailableCustomAgents[0].RepoOwnerID)
		assert.Equal(t, availableCustomAgents[0].RepoName(), dto.AvailableCustomAgents[0].RepoName)
		assert.Equal(t, availableCustomAgents[0].RepoID(), dto.AvailableCustomAgents[0].RepoID)
		assert.Equal(t, availableCustomAgents[0].DisplayName(), dto.AvailableCustomAgents[0].DisplayName)
		assert.Equal(t, availableCustomAgents[0].Description(), dto.AvailableCustomAgents[0].Description)
		assert.ElementsMatch(t, availableCustomAgents[0].Tools(), dto.AvailableCustomAgents[0].Tools)
		assert.Equal(t, availableCustomAgents[0].Version(), dto.AvailableCustomAgents[0].Version)
		// Prompt is excluded in AvailableCustomAgents by design
		assert.Empty(t, dto.AvailableCustomAgents[0].Prompt)
		// MCPServers should be included in both CustomAgent and AvailableCustomAgents
		assert.NotNil(t, dto.CustomAgent.MCPServers)
		assert.NotNil(t, dto.AvailableCustomAgents[0].MCPServers)
	})

	t.Run("empty tool slice preservation", func(t *testing.T) {
		domainEmpty := &jobs.Job{ID: "1-2-uuid-empty"}
		customAgent := &mockCustomAgent{
			name:  "empty-agent",
			tools: []string{},
		}
		dtoEmpty := jobDTOFromDomain(domainEmpty, customAgent, []sweagentd.CustomAgent{}, "")
		require.NotNil(t, dtoEmpty)
		assert.NotNil(t, dtoEmpty.CustomAgent.Tools, "expected non-nil empty slice to stay non-nil")
		assert.Len(t, dtoEmpty.CustomAgent.Tools, 0)
	})

	t.Run("MCP servers mapping", func(t *testing.T) {
		domain := &jobs.Job{
			ID: "1-2-uuid-with-mcp",
			ProblemStatement: jobs.ProblemStatement{
				Content: "Test MCP servers functionality",
			},
		}
		customAgent := &mockCustomAgent{
			name:        "mcp-agent",
			repoOwner:   "test-org",
			repoName:    "test-repo",
			displayName: "MCP Test Agent",
			description: "Agent for testing MCP servers",
			tools:       []string{"*"},
			mcpConfig: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"filesystem": {
						Type:  "local",
						Tools: []string{"read_file", "write_file"},
						Local: &mcpconfig.Local{
							Command: "npx",
							Args:    []string{"-y", "@modelcontextprotocol/server-filesystem", "/tmp"},
							Env:     map[string]string{"NODE_ENV": "development"},
						},
					},
					"web-search": {
						Type:  "sse",
						Tools: []string{"web_search"},
						Remote: &mcpconfig.Remote{
							URL:     "https://api.example.com/mcp",
							Headers: map[string]string{"Authorization": "Bearer token"},
						},
					},
				},
			},
		}

		availableAgent := customagent.FromDB(jobsCustomAgent.DBRecord{
			Name:        "available-mcp-agent",
			RepoOwner:   "test-org",
			RepoName:    "test-repo",
			DisplayName: "Available MCP Agent",
			Description: "Available agent with MCP",
			Tools:       []string{"basic_tool"},
			// MCP Content should not be returned since not priv'd
			MCPServers: []jobsCustomAgent.MCPServer{
				{
					Name:    "simple-mcp",
					Type:    "local",
					Tools:   []string{"simple_tool"},
					Command: "simple-server",
				},
			},
		})

		// Next, test priv'd agents
		dto := jobDTOFromDomain(domain, customAgent, []sweagentd.CustomAgent{availableAgent}, "")
		require.NotNil(t, dto)

		// Test CustomAgent MCPServers (should include all MCP server details)
		assert.NotNil(t, dto.CustomAgent.MCPServers)
		assert.Contains(t, dto.CustomAgent.MCPServers, "filesystem")
		assert.Contains(t, dto.CustomAgent.MCPServers, "web-search")

		// Verify filesystem server details (local type)
		filesystemServer := dto.CustomAgent.MCPServers["filesystem"]
		assert.Equal(t, "local", filesystemServer.Type)
		assert.ElementsMatch(t, []string{"read_file", "write_file"}, filesystemServer.Tools)
		assert.NotNil(t, filesystemServer.Local)
		assert.Equal(t, "npx", filesystemServer.Command)
		assert.ElementsMatch(t, []string{"-y", "@modelcontextprotocol/server-filesystem", "/tmp"}, filesystemServer.Args)
		assert.Equal(t, "development", filesystemServer.Env["NODE_ENV"])
		assert.Nil(t, filesystemServer.Remote)

		// Verify web-search server details (remote type)
		webSearchServer := dto.CustomAgent.MCPServers["web-search"]
		assert.Equal(t, "sse", webSearchServer.Type)
		assert.ElementsMatch(t, []string{"web_search"}, webSearchServer.Tools)
		assert.NotNil(t, webSearchServer.Remote)
		assert.Equal(t, "https://api.example.com/mcp", webSearchServer.URL)
		assert.Equal(t, "Bearer token", webSearchServer.Headers["Authorization"])
		assert.Nil(t, webSearchServer.Local)

		// Test AvailableCustomAgents MCPServers (should NOT include prompt but should include MCP servers)
		require.Len(t, dto.AvailableCustomAgents, 1)
		availableDTO := dto.AvailableCustomAgents[0]
		assert.Empty(t, availableDTO.Prompt, "available agents should not include prompt")
		assert.NotNil(t, availableDTO.MCPServers)
		assert.Contains(t, availableDTO.MCPServers, "simple-mcp")

		simpleMCPServer := availableDTO.MCPServers["simple-mcp"]
		assert.Equal(t, "local", simpleMCPServer.Type)
		assert.ElementsMatch(t, []string{"simple_tool"}, simpleMCPServer.Tools)
		assert.Equal(t, "simple-server", simpleMCPServer.Command)
	})

	t.Run("empty MCP servers", func(t *testing.T) {
		domain := &jobs.Job{
			ID: "1-2-uuid-no-mcp",
		}
		customAgent := &mockCustomAgent{
			name:      "no-mcp-agent",
			tools:     []string{"*"},
			mcpConfig: mcpconfig.JSON{Servers: map[string]mcpconfig.Server{}},
		}

		dto := jobDTOFromDomain(domain, customAgent, []sweagentd.CustomAgent{}, "")
		require.NotNil(t, dto)

		// Empty MCP servers should result in empty servers map
		assert.NotNil(t, dto.CustomAgent.MCPServers)
		assert.Empty(t, dto.CustomAgent.MCPServers)
	})

	// Tests for GetAgentForJob with CopilotSWEAgentCustomAgentPermissions feature flag enabled
	// These tests verify the DTO mapping for different agent types returned by Service.FromDB

	t.Run("job-scoped agent mapping with prompt and permissions", func(t *testing.T) {
		// When CopilotSWEAgentCustomAgentPermissions is enabled, job-scoped agents are loaded with
		// their prompt and permissions from the DB. This tests the DTO mapping for that case.
		domain := &jobs.Job{
			ID: "1-2-job-scoped-mapping-test",
			ProblemStatement: jobs.ProblemStatement{
				Content: "Test job-scoped agent mapping",
			},
		}

		// Create a job-scoped agent as Service.FromDB would return it
		jobScopedAgent := &mockCustomAgent{
			name:        "my-job-scoped-agent",
			repoOwnerID: 1,
			repoOwner:   "test-org",
			repoID:      2,
			repoName:    "test-repo",
			displayName: "My Job-Scoped Agent",
			description: "A job-scoped agent passed via Twirp API",
			prompt:      "You are a job-scoped agent with a custom prompt from the database",
			tools:       []string{"tool1", "tool2"},
			mcpConfig:   mcpconfig.JSON{Servers: map[string]mcpconfig.Server{}},
		}

		dto := jobDTOFromDomain(domain, jobScopedAgent, []sweagentd.CustomAgent{}, "")
		require.NotNil(t, dto)

		// Verify job-scoped agent fields are properly mapped
		assert.Equal(t, jobScopedAgent.Name(), dto.CustomAgent.Name)
		assert.Equal(t, jobScopedAgent.RepoOwnerID(), dto.CustomAgent.RepoOwnerID)
		assert.Equal(t, jobScopedAgent.RepoOwner(), dto.CustomAgent.RepoOwner)
		assert.Equal(t, jobScopedAgent.RepoID(), dto.CustomAgent.RepoID)
		assert.Equal(t, jobScopedAgent.RepoName(), dto.CustomAgent.RepoName)
		assert.Equal(t, jobScopedAgent.DisplayName(), dto.CustomAgent.DisplayName)
		assert.Equal(t, jobScopedAgent.Description(), dto.CustomAgent.Description)
		// Key assertion: prompt should be included for job-scoped agents
		assert.Equal(t, jobScopedAgent.Prompt(), dto.CustomAgent.Prompt)
		assert.ElementsMatch(t, jobScopedAgent.Tools(), dto.CustomAgent.Tools)
	})

	t.Run("copilot agent mapping when feature flag enabled", func(t *testing.T) {
		// When CopilotSWEAgentCustomAgentPermissions is enabled, Copilot agents are still
		// returned by Service.FromDB but with empty name and no prompt.
		domain := &jobs.Job{
			ID: "1-2-copilot-mapping-test",
			ProblemStatement: jobs.ProblemStatement{
				Content: "Test Copilot agent mapping",
			},
		}

		// Create a Copilot agent as Service.FromDB would return it
		copilotAgent := &mockCustomAgent{
			name:        "", // Empty name indicates Copilot agent
			repoOwnerID: 1,
			repoOwner:   "test-org",
			repoID:      2,
			repoName:    "test-repo",
			displayName: "",
			description: "",
			prompt:      "", // Copilot has no prompt
			tools:       []string{"*"},
			mcpConfig:   mcpconfig.JSON{Servers: map[string]mcpconfig.Server{}},
		}

		dto := jobDTOFromDomain(domain, copilotAgent, []sweagentd.CustomAgent{}, "")
		require.NotNil(t, dto)

		// Verify Copilot agent fields are properly mapped
		assert.Empty(t, dto.CustomAgent.Name)
		assert.Empty(t, dto.CustomAgent.Prompt)
		assert.Equal(t, copilotAgent.RepoOwnerID(), dto.CustomAgent.RepoOwnerID)
		assert.Equal(t, copilotAgent.RepoOwner(), dto.CustomAgent.RepoOwner)
		assert.Equal(t, copilotAgent.RepoID(), dto.CustomAgent.RepoID)
		assert.Equal(t, copilotAgent.RepoName(), dto.CustomAgent.RepoName)
		assert.ElementsMatch(t, copilotAgent.Tools(), dto.CustomAgent.Tools)
	})

	t.Run("regular custom agent mapping when fetched via GetAgentForJob", func(t *testing.T) {
		// When CopilotSWEAgentCustomAgentPermissions is enabled, regular custom agents are
		// fetched from the repo by Service.FromDB -> GetAgentByRepoID. This tests
		// that the prompt from the fetched agent is properly included in the DTO.
		domain := &jobs.Job{
			ID: "1-2-regular-mapping-test",
			ProblemStatement: jobs.ProblemStatement{
				Content: "Test regular agent mapping",
			},
		}

		// Create a regular agent as would be returned when fetched from repo
		regularAgent := &mockCustomAgent{
			name:        "my-regular-agent",
			repoOwnerID: 1,
			repoOwner:   "test-org",
			repoID:      2,
			repoName:    "test-repo",
			displayName: "My Regular Agent",
			description: "A regular custom agent from the repo",
			prompt:      "You are a regular agent with a prompt from the repository",
			tools:       []string{"tool1", "tool2", "tool3"},
			version:     "sha-abc123def456",
			mcpConfig:   mcpconfig.JSON{Servers: map[string]mcpconfig.Server{}},
		}

		dto := jobDTOFromDomain(domain, regularAgent, []sweagentd.CustomAgent{}, "")
		require.NotNil(t, dto)

		// Verify regular agent fields are properly mapped including prompt
		assert.Equal(t, regularAgent.Name(), dto.CustomAgent.Name)
		assert.Equal(t, regularAgent.RepoOwnerID(), dto.CustomAgent.RepoOwnerID)
		assert.Equal(t, regularAgent.RepoOwner(), dto.CustomAgent.RepoOwner)
		assert.Equal(t, regularAgent.RepoID(), dto.CustomAgent.RepoID)
		assert.Equal(t, regularAgent.RepoName(), dto.CustomAgent.RepoName)
		assert.Equal(t, regularAgent.DisplayName(), dto.CustomAgent.DisplayName)
		assert.Equal(t, regularAgent.Description(), dto.CustomAgent.Description)
		// Key assertion: prompt should be included for regular agents fetched from repo
		assert.Equal(t, regularAgent.Prompt(), dto.CustomAgent.Prompt)
		assert.ElementsMatch(t, regularAgent.Tools(), dto.CustomAgent.Tools)
		assert.Equal(t, regularAgent.Version(), dto.CustomAgent.Version)
	})

	t.Run("privileged agent with MCP servers mapping when feature flag enabled", func(t *testing.T) {
		// When CopilotSWEAgentCustomAgentPermissions is enabled, privileged agents (from org repos
		// or enterprise repos) include MCP server configurations.
		domain := &jobs.Job{
			ID: "1-2-privileged-mapping-test",
			ProblemStatement: jobs.ProblemStatement{
				Content: "Test privileged agent mapping",
			},
		}

		// Create a privileged agent with MCP servers as would be returned
		privilegedAgent := &mockCustomAgent{
			name:        "my-privileged-agent",
			repoOwnerID: 1,
			repoOwner:   "test-org",
			repoID:      2,
			repoName:    ".github", // Org repo = privileged
			displayName: "My Privileged Agent",
			description: "A privileged agent with MCP servers",
			prompt:      "You are a privileged agent",
			tools:       []string{"*"},
			mcpConfig: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"local-mcp": {
						Type:  "local",
						Tools: []string{"local_tool"},
						Local: &mcpconfig.Local{
							Command: "python",
							Args:    []string{"-m", "mcp_server"},
							Env:     map[string]string{"DEBUG": "true"},
						},
					},
					"remote-mcp": {
						Type:  "http",
						Tools: []string{"remote_tool"},
						Remote: &mcpconfig.Remote{
							URL:     "https://mcp.example.com",
							Headers: map[string]string{"Authorization": "Bearer secret"},
						},
					},
				},
			},
		}

		dto := jobDTOFromDomain(domain, privilegedAgent, []sweagentd.CustomAgent{}, "")
		require.NotNil(t, dto)

		// Verify privileged agent fields are properly mapped
		assert.Equal(t, privilegedAgent.Name(), dto.CustomAgent.Name)
		assert.Equal(t, privilegedAgent.Prompt(), dto.CustomAgent.Prompt)
		assert.ElementsMatch(t, privilegedAgent.Tools(), dto.CustomAgent.Tools)

		// Verify MCP servers are properly mapped
		assert.NotNil(t, dto.CustomAgent.MCPServers)
		assert.Len(t, dto.CustomAgent.MCPServers, 2)

		// Verify local MCP server
		localServer, ok := dto.CustomAgent.MCPServers["local-mcp"]
		assert.True(t, ok)
		assert.Equal(t, "local", localServer.Type)
		assert.ElementsMatch(t, []string{"local_tool"}, localServer.Tools)
		assert.NotNil(t, localServer.Local)
		assert.Equal(t, "python", localServer.Command)
		assert.ElementsMatch(t, []string{"-m", "mcp_server"}, localServer.Args)
		assert.Equal(t, "true", localServer.Env["DEBUG"])

		// Verify remote MCP server
		remoteServer, ok := dto.CustomAgent.MCPServers["remote-mcp"]
		assert.True(t, ok)
		assert.Equal(t, "http", remoteServer.Type)
		assert.ElementsMatch(t, []string{"remote_tool"}, remoteServer.Tools)
		assert.NotNil(t, remoteServer.Remote)
		assert.Equal(t, "https://mcp.example.com", remoteServer.URL)
		assert.Equal(t, "Bearer secret", remoteServer.Headers["Authorization"])
	})
}

func TestHandlerGetAgentWithMCPServers(t *testing.T) {
	runTest := func(t *testing.T, repoName string, enterprisePrivileged, isPrivileged bool) {
		t.Helper()
		obsv := observability.NewNoopExporters()
		ffs := map[string]bool{}
		ffClient := featureflags.NewNoopClient(ffs)
		cf := &github.NoopClientFactory{}
		store := memory.NewStore()

		agentWithMCP := `---
name: mcp-agent
description: Test agent with MCP
tools: ["*"]
mcp-servers:
  test-server:
    type: local
    tools: ["test_tool"]
    command: test-cmd
    args: ["arg1", "arg2"]
---
Test prompt with MCP.`

		privRepoID := uint64(1)
		agents := map[string]string{
			"mcp-agent": agentWithMCP,
		}
		privAgents := agents
		if isPrivileged {
			agents = map[string]string{}
			if !enterprisePrivileged {
				privRepoID = uint64(2)
			}
		} else {
			privAgents = map[string]string{}
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, agents, privAgents, uint64(1), privRepoID)
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
			if !enterprisePrivileged {
				return &sweagentdTwirp.EnterpriseAgentsResponse{
					RepositoryId: 999999,
				}, nil
			}
			return &sweagentdTwirp.EnterpriseAgentsResponse{
				RepositoryId: 1,
			}, nil
		}

		customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, store, cf, ghTwirp, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, agenticapptest.NewTestProvider(t), nil)

		ctx := requestctx.NewContext(context.Background())
		userInfo := &requestctx.UserInfo{
			ID:        123,
			TokenInfo: &requestctx.TokenInfo{Token: "token"},
		}
		err := requestctx.AddUser(ctx, userInfo)
		require.NoError(t, err)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		rctx.URLParams.Add("repoName", repoName)
		rctx.URLParams.Add("agentName", "mcp-agent")
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo/mcp-agent", nil)
		rr := httptest.NewRecorder()
		h.getAgent(rr, req)

		require.Equal(t, http.StatusOK, rr.Code)

		var result customAgentDTO
		err = json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)

		if isPrivileged {
			// Verify basic agent info
			assert.Equal(t, "mcp-agent", result.Name)
			assert.Equal(t, "Test agent with MCP", result.Description)
			assert.Equal(t, "Test prompt with MCP.", result.Prompt)

			// Verify MCP servers are included in HTTP response
			assert.NotNil(t, result.MCPServers)
			assert.Contains(t, result.MCPServers, "test-server")

			testServer := result.MCPServers["test-server"]
			assert.Equal(t, "local", testServer.Type)
			assert.ElementsMatch(t, []string{"test_tool"}, testServer.Tools)
			assert.NotNil(t, testServer.Local)
			assert.Equal(t, "test-cmd", testServer.Command)
			assert.ElementsMatch(t, []string{"arg1", "arg2"}, testServer.Args)
		} else {
			assert.Nil(t, result.MCPServers, "MCP servers should be nil for non-privileged repo")
		}
	}

	t.Run("returns MCP servers in response", func(t *testing.T) {
		runTest(t, ".github", false, true) // Privileged repo to get MCP servers
	})

	t.Run("does not return MCP servers for non-privileged repo", func(t *testing.T) {
		runTest(t, "testrepo", false, false) // Non-privileged repo should not return MCP servers
	})

	t.Run("returns MCP servers in response for enterprise repo", func(t *testing.T) {
		runTest(t, "testrepo", true, true) // Privileged repo to get MCP servers
	})
}

func TestOrganizationCustomInstructions(t *testing.T) {
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
	agents := map[string]string{
		"agent1": "---\nkey: value\n---\nthis is agent 1",
		"agent2": "---\nkey: value\n---\nthis is agent 2",
	}
	spokes := customagenttest.MakeSpokes(t, agents)

	ffClient := featureflags.NewNoopClient(map[string]bool{})
	customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, noopClient, ffClient)
	h := NewHandler(obsv, ffClient, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, agenticapptest.NewTestProvider(t), nil)

	// seed job
	nonce := "nonce-val"
	job := &jobs.Job{
		ID:               "1-2-uuid",
		OwnerID:          1,
		RepoID:           2,
		NonceHash:        jobs.HashNonce(nonce),
		ProblemStatement: jobs.ProblemStatement{Content: "Fix the bug"},
		CustomAgent:      jobsCustomAgent.DBRecord{Name: "", RepoOwner: "owner", RepoName: "repo", DisplayName: "", Description: "desc", Tools: []string{"tool1"}},
	}
	_, _ = store.CreateJob(context.Background(), job)

	baseCtx := requestctx.AddData(context.Background(), &requestctx.CtxData{UserInfo: &requestctx.UserInfo{ID: 123, TokenInfo: &requestctx.TokenInfo{ApplicationID: uint64(cf.AppID())}}})

	t.Run("organization custom instructions included in response", func(t *testing.T) {
		// Set up mock organization custom instructions
		orgInstructions := "Always follow coding best practices and write comprehensive tests."
		noopClient.NoopSweagentdAPI.MockGetOrganizationCustomInstructions = func(ctx context.Context, req *sweagentdTwirp.GetOrganizationCustomInstructionsRequest) (*sweagentdTwirp.GetOrganizationCustomInstructionsResponse, error) {
			return &sweagentdTwirp.GetOrganizationCustomInstructionsResponse{
				OrganizationCustomInstructions: orgInstructions,
			}, nil
		}

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-uuid", nil)
		req = muxSetParam(req, "jobID", job.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.getJob(w, req)
		require.Equal(t, http.StatusOK, w.Code)
		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))

		// Verify organization custom instructions are included
		assert.Equal(t, orgInstructions, resp.OrganizationCustomInstructions)
	})
}

// Add test for jobDTOFromDomain with organization custom instructions
func TestJobDTOFromDomainWithOrganizationCustomInstructions(t *testing.T) {
	t.Run("organization custom instructions included in DTO", func(t *testing.T) {
		domain := &jobs.Job{
			ID: "1-2-someuuid",
			ProblemStatement: jobs.ProblemStatement{
				Content: "Fix the failing tests",
			},
		}
		customAgent := &mockCustomAgent{}
		orgInstructions := "Follow company coding standards and write tests."

		dto := jobDTOFromDomain(domain, customAgent, []sweagentd.CustomAgent{}, orgInstructions)

		require.NotNil(t, dto)
		assert.Equal(t, orgInstructions, dto.OrganizationCustomInstructions)
	})

	t.Run("empty organization custom instructions excluded from DTO", func(t *testing.T) {
		domain := &jobs.Job{
			ID: "1-2-someuuid",
			ProblemStatement: jobs.ProblemStatement{
				Content: "Fix the failing tests",
			},
		}
		customAgent := &mockCustomAgent{}

		dto := jobDTOFromDomain(domain, customAgent, []sweagentd.CustomAgent{}, "")

		require.NotNil(t, dto)
		assert.Empty(t, dto.OrganizationCustomInstructions)
	})
}

func TestHandlerGetProgress(t *testing.T) {
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
	spokes := customagenttest.MakeSpokes(t, map[string]string{})
	ghTwirp := githubtwirp.NewNoopClient()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
	h := NewHandler(obsv, featureflags.NewNoopClient(nil), store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, agenticapptest.NewTestProvider(t), nil)

	// seed job
	nonce := "nonce-val"
	job := &jobs.Job{
		ID:               "1-2-uuid",
		OwnerID:          1,
		RepoID:           2,
		AssignmentID:     "assignment-123",
		NonceHash:        jobs.HashNonce(nonce),
		ProblemStatement: jobs.ProblemStatement{Content: "Fix the bug"},
	}
	ctx := context.Background()
	_, _ = store.CreateJob(ctx, job)

	// seed progress updates
	progress1 := job.NewProgress("runtime", "log", 1, map[string]any{"message": "Starting task"})
	progress2 := job.NewProgress("runtime", "status", 1, map[string]any{"state": "in_progress"})
	progress3 := job.NewProgress("agent", "tool_call", 1, map[string]any{"tool": "grep"})

	_, _ = store.CreateProgress(ctx, progress1)
	_, _ = store.CreateProgress(ctx, progress2)
	_, _ = store.CreateProgress(ctx, progress3)

	baseCtx := requestctx.AddData(context.Background(), &requestctx.CtxData{UserInfo: &requestctx.UserInfo{ID: 123, TokenInfo: &requestctx.TokenInfo{ApplicationID: uint64(cf.AppID())}}})

	t.Run("returns all progress without query params", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/agent/jobs/1-2-uuid/progress", http.NoBody).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req = muxSetParam(req, "jobID", "1-2-uuid")
		rr := httptest.NewRecorder()
		h.getProgress(rr, req)

		require.Equal(t, http.StatusOK, rr.Code)
		var result []progressDTO
		err := json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)
		require.Len(t, result, 3)
	})

	t.Run("filters by single namespace", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/agent/jobs/1-2-uuid/progress?namespace=runtime", http.NoBody).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req = muxSetParam(req, "jobID", "1-2-uuid")
		rr := httptest.NewRecorder()
		h.getProgress(rr, req)

		require.Equal(t, http.StatusOK, rr.Code)
		var result []progressDTO
		err := json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)
		require.Len(t, result, 2)
		for _, p := range result {
			require.Equal(t, "runtime", p.Namespace)
		}
	})

	t.Run("filters by multiple namespaces", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/agent/jobs/1-2-uuid/progress?namespace=runtime&namespace=agent", http.NoBody).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req = muxSetParam(req, "jobID", "1-2-uuid")
		rr := httptest.NewRecorder()
		h.getProgress(rr, req)

		require.Equal(t, http.StatusOK, rr.Code)
		var result []progressDTO
		err := json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)
		require.Len(t, result, 3)
	})

	t.Run("filters by comma-separated namespaces", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/agent/jobs/1-2-uuid/progress?namespace=runtime,agent", http.NoBody).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req = muxSetParam(req, "jobID", "1-2-uuid")
		rr := httptest.NewRecorder()
		h.getProgress(rr, req)

		require.Equal(t, http.StatusOK, rr.Code)
		var result []progressDTO
		err := json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)
		require.Len(t, result, 3)
	})

	t.Run("returns empty array for non-matching namespace", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/agent/jobs/1-2-uuid/progress?namespace=nonexistent", http.NoBody).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req = muxSetParam(req, "jobID", "1-2-uuid")
		rr := httptest.NewRecorder()
		h.getProgress(rr, req)

		require.Equal(t, http.StatusOK, rr.Code)
		var result []progressDTO
		err := json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)
		require.Empty(t, result)
	})

	t.Run("unauthorized without nonce", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/agent/jobs/1-2-uuid/progress", http.NoBody).WithContext(baseCtx)
		req = muxSetParam(req, "jobID", "1-2-uuid")
		rr := httptest.NewRecorder()
		h.getProgress(rr, req)

		require.Equal(t, http.StatusUnauthorized, rr.Code)
	})

	t.Run("bad request without job id", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/agent/jobs//progress", http.NoBody).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		rr := httptest.NewRecorder()
		h.getProgress(rr, req)

		require.Equal(t, http.StatusBadRequest, rr.Code)
	})
}

func TestHandlerCreateProgress(t *testing.T) {
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
	spokes := customagenttest.MakeSpokes(t, map[string]string{})
	ghTwirp := githubtwirp.NewNoopClient()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
	h := NewHandler(obsv, featureflags.NewNoopClient(nil), store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, agenticapptest.NewTestProvider(t), nil)

	// seed job
	nonce := "nonce-val"
	job := &jobs.Job{
		ID:               "1-2-uuid",
		OwnerID:          1,
		RepoID:           2,
		AssignmentID:     "assignment-123",
		NonceHash:        jobs.HashNonce(nonce),
		ProblemStatement: jobs.ProblemStatement{Content: "Fix the bug"},
	}
	ctx := context.Background()
	_, _ = store.CreateJob(ctx, job)

	baseCtx := requestctx.AddData(context.Background(), &requestctx.CtxData{UserInfo: &requestctx.UserInfo{ID: 123, TokenInfo: &requestctx.TokenInfo{ApplicationID: uint64(cf.AppID())}}})

	t.Run("creates single progress and returns single object", func(t *testing.T) {
		body := `{
			"namespace": "runtime",
			"kind": "log",
			"version": 1,
			"content": "{\"message\":\"test log\"}"
		}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-uuid/progress", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", "1-2-uuid")
		rr := httptest.NewRecorder()
		h.createProgress(rr, req)

		require.Equal(t, http.StatusCreated, rr.Code)
		var result progressDTO
		err := json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)
		require.NotEmpty(t, result.ID)
		require.Equal(t, "runtime", result.Namespace)
		require.Equal(t, "log", result.Kind)
		require.Equal(t, int64(1), result.Version)
		require.Contains(t, result.Content, "test log")
	})

	t.Run("creates multiple progress and returns array", func(t *testing.T) {
		body := `[
			{
				"namespace": "runtime",
				"kind": "log",
				"version": 1,
				"content": "{\"message\":\"log 1\"}"
			},
			{
				"namespace": "agent",
				"kind": "status",
				"version": 1,
				"content": "{\"state\":\"running\"}"
			}
		]`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-uuid/progress", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", "1-2-uuid")
		rr := httptest.NewRecorder()
		h.createProgress(rr, req)

		require.Equal(t, http.StatusCreated, rr.Code)
		var result []progressDTO
		err := json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)
		require.Len(t, result, 2)
		require.Equal(t, "runtime", result[0].Namespace)
		require.Equal(t, "log", result[0].Kind)
		require.Equal(t, "agent", result[1].Namespace)
		require.Equal(t, "status", result[1].Kind)
	})

	t.Run("validates required fields", func(t *testing.T) {
		testCases := []struct {
			name string
			body string
		}{
			{
				name: "missing namespace",
				body: `{"kind": "log", "version": 1, "content": "{}"}`,
			},
			{
				name: "missing kind",
				body: `{"namespace": "runtime", "version": 1, "content": "{}"}`,
			},
			{
				name: "missing content",
				body: `{"namespace": "runtime", "kind": "log", "version": 1}`,
			},
		}

		for _, tc := range testCases {
			t.Run(tc.name, func(t *testing.T) {
				req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-uuid/progress", strings.NewReader(tc.body)).WithContext(baseCtx)
				req.Header.Set(jobs.JobNonceHeader, nonce)
				req.Header.Set("Content-Type", "application/json")
				req = muxSetParam(req, "jobID", "1-2-uuid")
				rr := httptest.NewRecorder()
				h.createProgress(rr, req)

				require.Equal(t, http.StatusBadRequest, rr.Code)
			})
		}
	})

	t.Run("bad request with empty array", func(t *testing.T) {
		body := `[]`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-uuid/progress", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", "1-2-uuid")
		rr := httptest.NewRecorder()
		h.createProgress(rr, req)

		require.Equal(t, http.StatusBadRequest, rr.Code)
	})

	t.Run("bad request with invalid JSON", func(t *testing.T) {
		body := `{invalid json}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-uuid/progress", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", "1-2-uuid")
		rr := httptest.NewRecorder()
		h.createProgress(rr, req)

		require.Equal(t, http.StatusBadRequest, rr.Code)
	})

	t.Run("unauthorized without nonce", func(t *testing.T) {
		body := `{"namespace": "runtime", "kind": "log", "version": 1, "content": "{}"}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-uuid/progress", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", "1-2-uuid")
		rr := httptest.NewRecorder()
		h.createProgress(rr, req)

		require.Equal(t, http.StatusUnauthorized, rr.Code)
	})

	t.Run("bad request without job id", func(t *testing.T) {
		body := `{"namespace": "runtime", "kind": "log", "version": 1, "content": "{}"}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs//progress", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		rr := httptest.NewRecorder()
		h.createProgress(rr, req)

		require.Equal(t, http.StatusBadRequest, rr.Code)
	})

	t.Run("content is properly serialized as JSON", func(t *testing.T) {
		body := `{
			"namespace": "runtime",
			"kind": "log",
			"version": 1,
			"content": "{\"message\":\"hello\",\"level\":\"info\",\"count\":42}"
		}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-uuid/progress", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", "1-2-uuid")
		rr := httptest.NewRecorder()
		h.createProgress(rr, req)

		require.Equal(t, http.StatusCreated, rr.Code)
		var result progressDTO
		err := json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)

		// Verify content can be unmarshaled back to the expected structure
		var content map[string]any
		err = json.Unmarshal([]byte(result.Content), &content)
		require.NoError(t, err)
		require.Equal(t, "hello", content["message"])
		require.Equal(t, "info", content["level"])
		require.InEpsilon(t, float64(42), content["count"], 0.000)
	})
}
