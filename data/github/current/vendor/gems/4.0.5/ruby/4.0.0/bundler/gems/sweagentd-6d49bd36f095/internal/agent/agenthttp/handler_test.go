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
	"github.com/github/sweagentd/internal/agentconfig"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/customagenttest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	jobsCustomAgent "github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/jobs/jobevents"
	"github.com/github/sweagentd/internal/jobs/progress"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/launcher"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/permissions"
	"github.com/github/sweagentd/internal/plugins"
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
type notFoundStore struct{}

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

func (s *notFoundStore) PatchJob(ctx context.Context, job *jobs.Job, patch db.JobPatch, opts ...db.PatchJobOption) error {
	return nil
}

func (s *notFoundStore) GetJobSummariesForAssignmentID(ctx context.Context, owner, repo int64, assignmentID string) ([]*jobs.JobSummary, error) {
	return nil, nil
}

func (s *notFoundStore) GetAssignment(ctx context.Context, owner, repo int64, id string) (*jobs.Assignment, error) {
	return nil, goerrors.New("assignment not found")
}

func (s *notFoundStore) PatchAssignment(ctx context.Context, assignment *jobs.Assignment, patch db.AssignmentPatch, opts ...db.PatchAssignmentOption) error {
	return nil
}

// noopPullRequestOpener implements pullRequestOpener for tests
type noopPullRequestOpener struct {
	err error
}

func (n *noopPullRequestOpener) OpenPullRequest(ctx context.Context, gh jobservice.PullRequestCreator, assignment *jobs.Assignment, job *jobs.Job, title, body string) error {
	if n.err != nil {
		return n.err
	}
	job.PullRequestID = 123
	job.PullRequestNumber = 789
	assignment.PullRequestID = 123
	assignment.PullRequestNumber = 789
	return nil
}

func (n *noopPullRequestOpener) StoreGeneratedPullData(ctx context.Context, job *jobs.Job, title, description string) error {
	return nil
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
	name                   string
	repoOwnerID            int64
	repoOwner              string
	repoID                 int64
	repoName               string
	displayName            string
	description            string
	prompt                 string
	tools                  []string
	version                string
	mcpConfig              mcpconfig.JSON
	inferenceEnabled       bool
	disableModelInvocation bool
	userInvocable          bool
	perms                  permissions.Permissions
	githubMCPToolsets      []string
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
func (m *mockCustomAgent) InferenceEnabled() bool                   { return m.inferenceEnabled }
func (m *mockCustomAgent) DisableModelInvocation() bool             { return m.disableModelInvocation }
func (m *mockCustomAgent) UserInvocable() bool                      { return m.userInvocable }
func (m *mockCustomAgent) Model() string                            { return "" }
func (m *mockCustomAgent) Handoffs() []sweagentd.CustomAgentHandoff { return nil }
func (m *mockCustomAgent) Permissions() permissions.Permissions     { return m.perms }
func (m *mockCustomAgent) Triggers() sweagentd.CustomAgentTriggers {
	return sweagentd.CustomAgentTriggers{}
}
func (m *mockCustomAgent) GitHubMCPToolsets() []string { return m.githubMCPToolsets }
func (m *mockCustomAgent) Skills() []string            { return nil }
func (m *mockCustomAgent) Scope() string               { return agentconfig.ScopeRepository }
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
	svc := agent.NewService(store, cf, customAgentSvc, nil, obsv, ffClient, ghTwirp, &jobevents.NoopEmitter{}, agenticapptest.NewTestProvider(t), nil, nil)
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
	pluginsSvc := plugins.NewService(obsv, spokes, ghTwirp, "https://github.com")
	h := NewHandler(obsv, featureflags.NewNoopClient(nil), store, cf, tw, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginsSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

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
	pluginsSvc := plugins.NewService(obsv, spokes, ghTwirp, "https://github.com")
	h := NewHandler(obsv, featureflags.NewNoopClient(nil), store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginsSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

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

func TestHandlerGetJob_S2SSkipsEnablement(t *testing.T) {
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	cf := &github.NoopClientFactory{}
	// Configure enablement as false — S2S should bypass this.
	disabledClient := githubtwirp.NewNoopClient()
	disabledClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: false}
	agents := map[string]string{"agent1": "---\nkey: value\n---\nthis is agent 1"}
	spokes := customagenttest.MakeSpokes(t, agents)
	ghTwirp := githubtwirp.NewNoopClient()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
	pluginsSvc := plugins.NewService(obsv, spokes, ghTwirp, "https://github.com")
	h := NewHandler(obsv, featureflags.NewNoopClient(nil), store, cf, disabledClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginsSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

	nonce := "nonce-val"
	job := &jobs.Job{
		ID:        "1-2-uuid",
		OwnerID:   1,
		RepoID:    2,
		ActorID:   77777,
		NonceHash: jobs.HashNonce(nonce),
		Action:    jobs.AgentActionFix,
	}
	_, _ = store.CreateJob(context.Background(), job)

	// S2S context: user.ID is the installation ID, not the org/user ID.
	s2sCtx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID: 99999,
			TokenInfo: &requestctx.TokenInfo{
				Type:          string(authd.CredentialTypeServerToServerToken),
				ApplicationID: uint64(cf.AppID()),
			},
		},
	})

	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("jobID", job.ID)

	req := httptest.NewRequestWithContext(s2sCtx, http.MethodGet, "/agent/jobs/"+job.ID, nil)
	req = req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))
	req.Header.Set(jobs.JobNonceHeader, nonce)
	w := httptest.NewRecorder()
	h.getJob(w, req)
	// Should not 404 — S2S skips enablement even though IsAgentEnabled=false.
	require.NotEqual(t, http.StatusNotFound, w.Code, "S2S token should skip enablement check")
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
	pluginsSvc := plugins.NewService(obsv, spokes, ghTwirp, "https://github.com")
	h := NewHandler(obsv, featureflags.NewNoopClient(nil), store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginsSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

	// seed job
	nonce := "nonce-val"
	job := &jobs.Job{
		ID:               "1-2-uuid",
		OwnerID:          1,
		RepoID:           2,
		NonceHash:        jobs.HashNonce(nonce),
		ProblemStatement: jobs.ProblemStatement{Content: "Fix the bug"},
		CustomAgent:      jobsCustomAgent.DBRecord{Name: "", RepoOwner: "owner", RepoName: "repo", DisplayName: "", Description: "desc", Tools: []string{"tool1"}},
		Action:           jobs.AgentActionFix,
		BranchName:       "copilot/fix-123",
		Args:             launcher.LaunchAgentOpts{GitHubRepo: "owner/repo"},
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
		hWithCustomAgent := NewHandler(obsv, ffClient, storeWithCustomAgent, cf, ghTwirpClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvcWithPrompt, nil, pluginsSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

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

	t.Run("populates plugins in job DTO when FF enabled", func(t *testing.T) {
		settingsJSON := `{"enabledPlugins": {"octocat/my-plugin": true}}`
		spokesWithSettings := spokestest.NewClient(t,
			spokestest.WithRepoBlob(2, ".github/copilot/settings.json", []byte(settingsJSON)),
		)
		ghTwirpWithPlugins := githubtwirp.NewNoopClient()
		ghTwirpWithPlugins.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
		pluginsFF := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentPluginsEnabled: true,
		})
		pluginsSvcEnabled := plugins.NewService(obsv, spokesWithSettings, ghTwirpWithPlugins, "https://github.com")
		customAgentSvcForPlugins := customagent.NewService(obsv, spokesWithSettings, ghTwirpWithPlugins, pluginsFF)
		storeWithPlugins := memory.NewStore()
		hWithPlugins := NewHandler(obsv, pluginsFF, storeWithPlugins, cf, ghTwirpWithPlugins, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvcForPlugins, nil, pluginsSvcEnabled, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

		pluginJob := &jobs.Job{
			ID:               "1-2-plugin-job",
			OwnerID:          1,
			RepoID:           2,
			NonceHash:        jobs.HashNonce(nonce),
			ProblemStatement: jobs.ProblemStatement{Content: "Fix something"},
			CustomAgent:      jobsCustomAgent.DBRecord{RepoOwner: "owner", RepoName: "repo"},
			Args:             launcher.LaunchAgentOpts{GitHubRepo: "owner/repo", GitHubRepoID: 2},
		}
		_, _ = storeWithPlugins.CreateJob(baseCtx, pluginJob)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-plugin-job", nil)
		req = muxSetParam(req, "jobID", pluginJob.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		hWithPlugins.getJob(w, req)

		require.Equal(t, http.StatusOK, w.Code)
		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))

		require.Len(t, resp.PluginRepos, 1)
		assert.Equal(t, "https://github.com/octocat/my-plugin", resp.PluginRepos[0].CloneURL)
		assert.Empty(t, resp.PluginRepos[0].SHA, "settings-based plugins should not have SHA")
	})

	t.Run("populates org-level plugins in job DTO", func(t *testing.T) {
		// Org settings live at copilot/settings.json inside the org's .github repo (ID 2 per noop).
		// The source repo uses a distinct ID (5) so it contributes no repo-level settings.
		orgSettingsJSON := `{"enabledPlugins": {"org-owner/org-plugin": true}}`
		orgSpokes := spokestest.NewClient(t,
			// repoID 2 is the .github org repo returned by the noop ghtwirp
			spokestest.WithRepoBlob(2, "copilot/settings.json", []byte(orgSettingsJSON)),
		)
		ghTwirpOrg := githubtwirp.NewNoopClient()
		ghTwirpOrg.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
		orgPluginsFF := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentPluginsEnabled: true,
		})
		pluginsSvcOrg := plugins.NewService(obsv, orgSpokes, ghTwirpOrg, "https://github.com")
		customAgentSvcOrg := customagent.NewService(obsv, orgSpokes, ghTwirpOrg, orgPluginsFF)
		storeOrg := memory.NewStore()
		hWithOrgPlugins := NewHandler(obsv, orgPluginsFF, storeOrg, cf, ghTwirpOrg, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvcOrg, nil, pluginsSvcOrg, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

		orgPluginJob := &jobs.Job{
			ID:               "1-5-org-plugin-job",
			OwnerID:          1,
			RepoID:           5, // distinct from the .github org repo (ID 2)
			NonceHash:        jobs.HashNonce(nonce),
			ProblemStatement: jobs.ProblemStatement{Content: "Fix something"},
			CustomAgent:      jobsCustomAgent.DBRecord{RepoOwner: "org-owner", RepoName: "repo"},
			Args:             launcher.LaunchAgentOpts{GitHubRepo: "org-owner/repo", GitHubRepoID: 5, GitHubRepoOwner: "org-owner"},
		}
		_, _ = storeOrg.CreateJob(baseCtx, orgPluginJob)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-5-org-plugin-job", nil)
		req = muxSetParam(req, "jobID", orgPluginJob.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		hWithOrgPlugins.getJob(w, req)

		require.Equal(t, http.StatusOK, w.Code)
		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))

		require.Len(t, resp.PluginRepos, 1)
		assert.Equal(t, "https://github.com/org-owner/org-plugin", resp.PluginRepos[0].CloneURL)
	})

	t.Run("omits plugins from job DTO when FF disabled", func(t *testing.T) {
		settingsJSON := `{"enabledPlugins": {"octocat/my-plugin": true}}`
		spokesWithSettings := spokestest.NewClient(t,
			spokestest.WithRepoBlob(2, ".github/copilot/settings.json", []byte(settingsJSON)),
		)
		ghTwirpForDisabled := githubtwirp.NewNoopClient()
		ghTwirpForDisabled.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
		disabledPluginsFF := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentPluginsEnabled: false,
		})
		pluginsSvcDisabled := plugins.NewService(obsv, spokesWithSettings, ghTwirpForDisabled, "https://github.com")
		customAgentSvcDisabled := customagent.NewService(obsv, spokesWithSettings, ghTwirpForDisabled, disabledPluginsFF)
		storeDisabled := memory.NewStore()
		hDisabled := NewHandler(obsv, disabledPluginsFF, storeDisabled, cf, ghTwirpForDisabled, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvcDisabled, nil, pluginsSvcDisabled, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

		disabledJob := &jobs.Job{
			ID:               "1-2-plugin-disabled-job",
			OwnerID:          1,
			RepoID:           2,
			NonceHash:        jobs.HashNonce(nonce),
			ProblemStatement: jobs.ProblemStatement{Content: "Fix something"},
			CustomAgent:      jobsCustomAgent.DBRecord{RepoOwner: "owner", RepoName: "repo"},
			Args:             launcher.LaunchAgentOpts{GitHubRepo: "owner/repo", GitHubRepoID: 2},
		}
		_, _ = storeDisabled.CreateJob(baseCtx, disabledJob)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-plugin-disabled-job", nil)
		req = muxSetParam(req, "jobID", disabledJob.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		hDisabled.getJob(w, req)

		require.Equal(t, http.StatusOK, w.Code)
		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))

		assert.Empty(t, resp.PluginRepos)
	})

	t.Run("includes agent source in plugin repos", func(t *testing.T) {
		agentSourceSpokes := spokestest.NewClient(t)
		agentSourceTwirp := githubtwirp.NewNoopClient()
		agentSourceTwirp.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
		agentSourceFF := featureflags.NewNoopClient(map[string]bool{})
		agentSourceCustomAgentSvc := customagent.NewService(obsv, agentSourceSpokes, agentSourceTwirp, agentSourceFF)

		testApp := agenticapptest.NewTestApp(42).WithAgentSource(&sweagentd.AgentSource{
			URL: "https://github.com/myorg/my-agent-repo",
			SHA: "abc123",
		})
		copilot := agenticapptest.NewTestCopilot(t)
		provider := agenticapp.NewProvider(copilot, testApp)

		agentSourcePluginsSvc := plugins.NewService(obsv, agentSourceSpokes, agentSourceTwirp, "https://github.com")
		agentSourceStore := memory.NewStore()
		hAgentSource := NewHandler(obsv, agentSourceFF, agentSourceStore, cf, agentSourceTwirp, &noopCallbackHandler{}, &noopCleanupHandler{}, agentSourceCustomAgentSvc, nil, agentSourcePluginsSvc, provider, nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

		agentSourceJob := &jobs.Job{
			ID:               "1-2-agent-source-job",
			OwnerID:          1,
			RepoID:           2,
			AgentID:          42,
			NonceHash:        jobs.HashNonce(nonce),
			ProblemStatement: jobs.ProblemStatement{Content: "Fix something"},
			CustomAgent:      jobsCustomAgent.DBRecord{RepoOwner: "owner", RepoName: "repo"},
			Args:             launcher.LaunchAgentOpts{GitHubRepo: "owner/repo", GitHubRepoID: 2},
		}
		_, _ = agentSourceStore.CreateJob(baseCtx, agentSourceJob)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-agent-source-job", nil)
		req = muxSetParam(req, "jobID", agentSourceJob.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		hAgentSource.getJob(w, req)

		require.Equal(t, http.StatusOK, w.Code)
		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))

		require.Len(t, resp.PluginRepos, 1)
		assert.Equal(t, "https://github.com/myorg/my-agent-repo", resp.PluginRepos[0].CloneURL)
		assert.Equal(t, "abc123", resp.PluginRepos[0].SHA, "agentic app source should include SHA")
	})

	t.Run("job not found", func(t *testing.T) {
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		ghTwirp := githubtwirp.NewNoopClient()
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		obsv := observability.NewNoopExporters()
		customAgentSvc := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		nfSvc := agent.NewService(&notFoundStore{}, cf, customAgentSvc, nil, obsv, ffClient, ghTwirp, &jobevents.NoopEmitter{}, agenticapptest.NewTestProvider(t), nil, nil)
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
		assert.Equal(t, "fix", resp.Action)
		assert.Equal(t, "owner/repo", resp.Repository)
		assert.Equal(t, "https://github.com", resp.ServerURL)
		assert.Equal(t, "copilot/fix-123", resp.BranchName)
		assert.Equal(t, "commit-login", resp.CommitLogin)
		assert.Equal(t, "commit@email.com", resp.CommitEmail)
		assert.Nil(t, resp.AgenticApp, "default copilot app should have no agentic_app")
	})

	t.Run("success with app metadata", func(t *testing.T) {
		ccrAppID := int64(946600)
		testApp := agenticapptest.NewTestAppWithDetails(ccrAppID, ccrAppID+1, "ccr", "ccr")
		testApp.WithMetadata(map[string]string{"capi_integration_id": "copilot-pull-request-reviewer"})
		testApp.WithGlobalApp() // CCR is a known static agent, not third-party.
		ccrProvider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, testApp)

		ccrStore := memory.NewStore()
		ccrNoopClient := githubtwirp.NewNoopClient()
		ccrNoopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
		ccrFfClient := featureflags.NewNoopClient(map[string]bool{})
		ccrCaSvc := customagent.NewService(observability.NewNoopExporters(), customagenttest.MakeSpokes(t, map[string]string{}), ccrNoopClient, ccrFfClient)
		ccrHandler := NewHandler(obsv, ccrFfClient, ccrStore, cf, ccrNoopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, ccrCaSvc, nil, pluginsSvc, ccrProvider, nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

		ccrJob := &jobs.Job{
			ID:               "1-2-ccr-meta",
			OwnerID:          1,
			RepoID:           2,
			AgentID:          ccrAppID,
			NonceHash:        jobs.HashNonce(nonce),
			ProblemStatement: jobs.ProblemStatement{Content: "Review this PR"},
			CustomAgent:      jobsCustomAgent.DBRecord{Name: "", RepoOwner: "owner", RepoName: "repo"},
			Action:           jobs.AgentActionFix,
			Args:             launcher.LaunchAgentOpts{GitHubRepo: "owner/repo"},
		}
		_, _ = ccrStore.CreateJob(baseCtx, ccrJob)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-ccr-meta", nil)
		req = muxSetParam(req, "jobID", ccrJob.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		ccrHandler.getJob(w, req)
		require.Equal(t, http.StatusOK, w.Code)

		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		assert.Equal(t, &agenticAppDTO{Metadata: map[string]string{"capi_integration_id": "copilot-pull-request-reviewer"}}, resp.AgenticApp)
	})

	t.Run("third-party agentic integration id gated by feature flag", func(t *testing.T) {
		tpAppID := int64(987654)
		setupApp := func() *agenticapptest.TestApp {
			a := agenticapptest.NewTestAppWithDetails(tpAppID, tpAppID+1, "tp", "tp")
			a.WithMetadata(map[string]string{"capi_integration_id": "third-party-agentic"})
			return a
		}
		setupHandler := func(t *testing.T, ffs map[string]bool, app *agenticapptest.TestApp) (*Handler, *jobs.Job, *http.Request, *httptest.ResponseRecorder) {
			t.Helper()
			provider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, app)
			store := memory.NewStore()
			noopClient := githubtwirp.NewNoopClient()
			noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
			ffClient := featureflags.NewNoopClient(ffs)
			caSvc := customagent.NewService(observability.NewNoopExporters(), customagenttest.MakeSpokes(t, map[string]string{}), noopClient, ffClient)
			handler := NewHandler(obsv, ffClient, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, caSvc, nil, pluginsSvc, provider, nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

			j := &jobs.Job{
				ID:               "1-2-tp-meta",
				OwnerID:          1,
				RepoID:           2,
				AgentID:          tpAppID,
				NonceHash:        jobs.HashNonce(nonce),
				ProblemStatement: jobs.ProblemStatement{Content: "Do work"},
				CustomAgent:      jobsCustomAgent.DBRecord{Name: "", RepoOwner: "owner", RepoName: "repo"},
				Action:           jobs.AgentActionFix,
				Args:             launcher.LaunchAgentOpts{GitHubRepo: "owner/repo"},
			}
			_, _ = store.CreateJob(baseCtx, j)

			req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-tp-meta", nil)
			req = muxSetParam(req, "jobID", j.ID)
			req.Header.Set(jobs.JobNonceHeader, nonce)
			return handler, j, req, httptest.NewRecorder()
		}

		t.Run("flag enabled emits third-party-agentic integration id", func(t *testing.T) {
			handler, _, req, w := setupHandler(t, map[string]bool{
				featureflags.CopilotSWEAgentThirdPartyAgenticIntegrationID: true,
			}, setupApp())
			handler.getJob(w, req)
			require.Equal(t, http.StatusOK, w.Code)
			var resp jobDTO
			require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
			assert.Equal(t, &agenticAppDTO{Metadata: map[string]string{"capi_integration_id": "third-party-agentic"}}, resp.AgenticApp)
		})

		t.Run("flag disabled strips third-party-agentic integration id", func(t *testing.T) {
			handler, _, req, w := setupHandler(t, map[string]bool{
				featureflags.CopilotSWEAgentThirdPartyAgenticIntegrationID: false,
			}, setupApp())
			handler.getJob(w, req)
			require.Equal(t, http.StatusOK, w.Code)
			var resp jobDTO
			require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
			assert.Nil(t, resp.AgenticApp, "3P metadata should be stripped when the gate is off")
		})
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

	t.Run("invalid agent id in job returns 404", func(t *testing.T) {
		invalidAgentJob := &jobs.Job{
			ID:               "1-2-invalid-agent",
			OwnerID:          1,
			RepoID:           2,
			NonceHash:        jobs.HashNonce(nonce),
			ProblemStatement: jobs.ProblemStatement{Content: "Fix the bug"},
			AgentID:          9999, // not recognized by the test provider
		}
		_, _ = store.CreateJob(baseCtx, invalidAgentJob)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-invalid-agent", nil)
		req = muxSetParam(req, "jobID", invalidAgentJob.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.getJob(w, req)
		require.Equal(t, http.StatusNotFound, w.Code)
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
		h := NewHandler(obsv, ffClient, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvcEnabled, nil, pluginsSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

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
		hWithErrors := NewHandler(obsv, ffClientWithErrors, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvcWithErrors, nil, pluginsSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

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

	t.Run("uses GetAgentForJob for job-scoped agent", func(t *testing.T) {
		// Setup for job-scoped agent
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
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		customAgentSvcJobScoped := customagent.NewService(observability.NewNoopExporters(), spokesClient, ghTwirpClient, ffClient)
		storeWithJobScopedAgent := memory.NewStore()
		hWithJobScopedAgent := NewHandler(obsv, ffClient, storeWithJobScopedAgent, cf, ghTwirpClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvcJobScoped, nil, pluginsSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")
		jobScopedJob := &jobs.Job{
			ID:               "1-2-job-scoped-agent-job",
			OwnerID:          1,
			RepoID:           2,
			NonceHash:        jobs.HashNonce(nonce),
			ProblemStatement: jobs.ProblemStatement{Content: "Do something with job-scoped agent"},
			CustomAgent: jobsCustomAgent.DBRecord{
				Name:        jobScopedAgentName,
				Scope:       agentconfig.ScopeJob,
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

	t.Run("uses GetAgentForJob for regular custom agent", func(t *testing.T) {
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

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		customAgentSvcWithFlag := customagent.NewService(observability.NewNoopExporters(), spokesWithAgent, ghTwirpClient, ffClient)
		storeWithFlag := memory.NewStore()
		hWithFlag := NewHandler(obsv, ffClient, storeWithFlag, cf, ghTwirpClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvcWithFlag, nil, pluginsSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

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

	t.Run("uses GetAgentForJob for copilot agent", func(t *testing.T) {
		// Ensure Copilot agent works correctly
		ghTwirpClient := githubtwirp.NewNoopClient()
		ghTwirpClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}

		spokesClient := customagenttest.MakeSpokes(t, map[string]string{})
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		customAgentSvcWithFlag := customagent.NewService(observability.NewNoopExporters(), spokesClient, ghTwirpClient, ffClient)
		storeWithFlag := memory.NewStore()
		hWithFlag := NewHandler(obsv, ffClient, storeWithFlag, cf, ghTwirpClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvcWithFlag, nil, pluginsSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

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
	t.Run("returns custom agent details", func(t *testing.T) {
		result := runGetTest(t, "sha-999999999999999999999999999999999999", "agent1", "sha-999999999999999999999999999999999999", http.StatusOK)
		assert.Equal(t, "agent1", result.Name, "agent name should match")
		assert.Equal(t, "This is agent 1", result.Description, "agent description should match")
		assert.Equal(t, []string{"tool1", "tool2"}, result.Tools, "agent tools should match")
		assert.Equal(t, "This is the prompt for agent 1.", result.Prompt, "agent prompt should match")
		assert.Equal(t, "sha-999999999999999999999999999999999999", result.Version, "agent version should match")
	})

	t.Run("returns latest custom agent details", func(t *testing.T) {
		result := runGetTest(t, "", "agent1", "", http.StatusOK)
		assert.Equal(t, "agent1", result.Name, "agent name should match")
		assert.Equal(t, "This is agent 1", result.Description, "agent description should match")
		assert.Equal(t, []string{"tool1", "tool2"}, result.Tools, "agent tools should match")
		assert.Equal(t, "This is the prompt for agent 1.", result.Prompt, "agent prompt should match")
		assert.NotEmpty(t, result.Version, "agent version should be set")
	})

	t.Run("404s for non-existent agent", func(t *testing.T) {
		runGetTest(t, "", "does-not-exist", "", http.StatusNotFound)
	})

	t.Run("404s for non-existent version", func(t *testing.T) {
		runGetTest(t, "sha-999999999999999999999999999999999999", "agent1", "sha-999999999999999999999999999999999988", http.StatusNotFound)
	})

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
}

const agentContent string = `---
name: agent1
description: This is agent 1
tools: ["tool1", "tool2" ]
---
This is the prompt for agent 1.
`

func runGetTest(t *testing.T, dataVersion, expectedAgentName, expectedVersion string, expectedHTTPStatus int) customAgentDTO {
	obsv := observability.NewNoopExporters()
	cf := &github.NoopClientFactory{}
	store := memory.NewStore()
	ffs := map[string]bool{}
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
	pluginsSvc := plugins.NewService(obsv, spokes, ghTwirp, "https://github.com")
	h := NewHandler(obsv, ffClient, store, cf, ghTwirp, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginsSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

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

	job := &jobs.Job{
		ID:        jobID,
		OwnerID:   456,
		RepoID:    12345,
		NonceHash: jobs.HashNonce(nonce),
	}
	_, err = store.CreateJob(ctx, job)
	if err != nil {
		t.Fatalf("failed to create job: %v", err)
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

	req.Header.Set("X-GitHub-Job-ID", jobID)
	req.Header.Set(jobs.JobNonceHeader, nonce)

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
	ffs := map[string]bool{}
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
	h := NewHandler(obsv, ffClient, store, cf, ghTwirp, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, nil, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

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
			&mockCustomAgent{
				name:        "refactorer",
				repoOwnerID: 3,
				repoOwner:   "octo-org",
				repoID:      4,
				repoName:    "octo-repo",
				displayName: "Refactorer",
				description: "Refactors code intelligently",
				tools:       []string{"search", "write", "format"},
				mcpConfig:   mcpconfig.JSON{Servers: map[string]mcpconfig.Server{}},
			},
		}
		dto := jobDTOFromDomain(domain, customAgent, availableCustomAgents, nil, nil, "", jobExtraFields{})
		require.NotNil(t, dto)
		assert.Equal(t, domain.ID, dto.ID)
		assert.Equal(t, domain.ProblemStatement.Content, dto.ProblemStatement.Content)
		assert.False(t, dto.IsTrigger)

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
		// MCPProxyURL should always be set to the default
		assert.Equal(t, defaultMCPProxyURL, dto.MCPProxyURL)
	})

	t.Run("trigger jobs expose runtime trigger marker", func(t *testing.T) {
		domain := &jobs.Job{
			ID:          "1-2-triggered",
			IsTriggered: true,
		}
		customAgent := &mockCustomAgent{
			name:  "automation-agent",
			tools: []string{"*"},
		}

		dto := jobDTOFromDomain(domain, customAgent, []sweagentd.CustomAgent{}, nil, nil, "", jobExtraFields{})
		require.NotNil(t, dto)
		assert.True(t, dto.IsTrigger)

		raw, err := json.Marshal(dto)
		require.NoError(t, err)
		assert.Contains(t, string(raw), `"is_trigger":true`)
	})

	t.Run("empty tool slice preservation", func(t *testing.T) {
		domainEmpty := &jobs.Job{ID: "1-2-uuid-empty"}
		customAgent := &mockCustomAgent{
			name:  "empty-agent",
			tools: []string{},
		}
		dtoEmpty := jobDTOFromDomain(domainEmpty, customAgent, []sweagentd.CustomAgent{}, nil, nil, "", jobExtraFields{})
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

		availableAgent := &mockCustomAgent{
			name:        "available-mcp-agent",
			repoOwner:   "test-org",
			repoName:    "test-repo",
			displayName: "Available MCP Agent",
			description: "Available agent with MCP",
			tools:       []string{"basic_tool"},
			mcpConfig: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"simple-mcp": {
						Type:  "local",
						Tools: []string{"simple_tool"},
						Local: &mcpconfig.Local{
							Command: "simple-server",
						},
					},
				},
			},
		}

		// Next, test priv'd agents
		dto := jobDTOFromDomain(domain, customAgent, []sweagentd.CustomAgent{availableAgent}, nil, nil, "", jobExtraFields{})
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

		dto := jobDTOFromDomain(domain, customAgent, []sweagentd.CustomAgent{}, nil, nil, "", jobExtraFields{})
		require.NotNil(t, dto)

		// Empty MCP servers should result in empty servers map
		assert.NotNil(t, dto.CustomAgent.MCPServers)
		assert.Empty(t, dto.CustomAgent.MCPServers)
	})

	// Tests for GetAgentForJob DTO mapping
	// These tests verify the DTO mapping for different agent types returned by Service.FromDB

	t.Run("job-scoped agent mapping with prompt and permissions", func(t *testing.T) {
		// Job-scoped agents are loaded with
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

		dto := jobDTOFromDomain(domain, jobScopedAgent, []sweagentd.CustomAgent{}, nil, nil, "", jobExtraFields{})
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
		// Copilot agents are still
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

		dto := jobDTOFromDomain(domain, copilotAgent, []sweagentd.CustomAgent{}, nil, nil, "", jobExtraFields{})
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
		// Regular custom agents are
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

		dto := jobDTOFromDomain(domain, regularAgent, []sweagentd.CustomAgent{}, nil, nil, "", jobExtraFields{})
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
		// Privileged agents (from org repos
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

		dto := jobDTOFromDomain(domain, privilegedAgent, []sweagentd.CustomAgent{}, nil, nil, "", jobExtraFields{})
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
		h := NewHandler(obsv, ffClient, store, cf, ghTwirp, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, nil, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

		ctx := requestctx.NewContext(context.Background())
		userInfo := &requestctx.UserInfo{
			ID:        123,
			TokenInfo: &requestctx.TokenInfo{Token: "token"},
		}
		err := requestctx.AddUser(ctx, userInfo)
		require.NoError(t, err)

		// Create a job in the store so that getAgentWithJobValidation can find it.
		nonce := "test-nonce"
		jobID := "456-1-test-mcp-job"
		job := &jobs.Job{
			ID:        jobID,
			OwnerID:   456,
			RepoID:    1,
			NonceHash: jobs.HashNonce(nonce),
		}
		_, err = store.CreateJob(ctx, job)
		require.NoError(t, err)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		rctx.URLParams.Add("repoName", repoName)
		rctx.URLParams.Add("agentName", "mcp-agent")
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo/mcp-agent", nil)
		req.Header.Set("X-GitHub-Job-ID", jobID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
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
	h := NewHandler(obsv, ffClient, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, nil, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

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

		dto := jobDTOFromDomain(domain, customAgent, []sweagentd.CustomAgent{}, nil, nil, orgInstructions, jobExtraFields{})

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

		dto := jobDTOFromDomain(domain, customAgent, []sweagentd.CustomAgent{}, nil, nil, "", jobExtraFields{})

		require.NotNil(t, dto)
		assert.Empty(t, dto.OrganizationCustomInstructions)
	})
}

func TestJobDTOFromDomainDisableModelInvocation(t *testing.T) {
	t.Run("disable_model_invocation true is mapped to DTO", func(t *testing.T) {
		domain := &jobs.Job{ID: "1-2-disable-model"}
		agent := &mockCustomAgent{
			name:                   "test-agent",
			tools:                  []string{"*"},
			disableModelInvocation: true,
		}

		dto := jobDTOFromDomain(domain, agent, []sweagentd.CustomAgent{}, nil, nil, "", jobExtraFields{})
		require.NotNil(t, dto)
		assert.True(t, dto.CustomAgent.DisableModelInvocation)
		assert.False(t, dto.CustomAgent.InferenceEnabled)
	})

	t.Run("disable_model_invocation false is mapped to DTO", func(t *testing.T) {
		domain := &jobs.Job{ID: "1-2-enable-model"}
		agent := &mockCustomAgent{
			name:                   "test-agent",
			tools:                  []string{"*"},
			disableModelInvocation: false,
			inferenceEnabled:       true,
		}

		dto := jobDTOFromDomain(domain, agent, []sweagentd.CustomAgent{}, nil, nil, "", jobExtraFields{})
		require.NotNil(t, dto)
		assert.False(t, dto.CustomAgent.DisableModelInvocation)
		assert.True(t, dto.CustomAgent.InferenceEnabled)
	})
}

func TestJobDTOFromDomainUserInvocable(t *testing.T) {
	t.Run("user_invocable true is mapped to DTO", func(t *testing.T) {
		domain := &jobs.Job{ID: "1-2-enable-user-invocable"}
		agent := &mockCustomAgent{
			name:          "test-agent",
			tools:         []string{"*"},
			userInvocable: true,
		}

		dto := jobDTOFromDomain(domain, agent, []sweagentd.CustomAgent{}, nil, nil, "", jobExtraFields{})
		require.NotNil(t, dto)
		assert.True(t, dto.CustomAgent.UserInvocable)
	})

	t.Run("user_invocable false is mapped to DTO", func(t *testing.T) {
		domain := &jobs.Job{ID: "1-2-disable-user-invocable"}
		agent := &mockCustomAgent{
			name:          "test-agent",
			tools:         []string{"*"},
			userInvocable: false,
		}

		dto := jobDTOFromDomain(domain, agent, []sweagentd.CustomAgent{}, nil, nil, "", jobExtraFields{})
		require.NotNil(t, dto)
		assert.False(t, dto.CustomAgent.UserInvocable)
	})
}

func TestJobDTOFromDomainEventFields(t *testing.T) {
	t.Run("event fields included in DTO", func(t *testing.T) {
		domain := &jobs.Job{
			ID: "1-2-event-fields",
			ProblemStatement: jobs.ProblemStatement{
				Content: "Fix the failing tests",
			},
			EventType:        jobs.EventTypeIssueAssignment,
			EventURL:         "https://github.com/owner/repo/issues/42",
			EventIdentifiers: []string{"42", "owner/repo"},
		}
		customAgent := &mockCustomAgent{}

		dto := jobDTOFromDomain(domain, customAgent, []sweagentd.CustomAgent{}, nil, nil, "", jobExtraFields{})

		require.NotNil(t, dto)
		assert.Equal(t, "issue_assignment", dto.EventType)
		assert.Equal(t, "https://github.com/owner/repo/issues/42", dto.EventURL)
		assert.Equal(t, []string{"42", "owner/repo"}, dto.EventIdentifiers)
	})

	t.Run("empty event fields omitted from DTO", func(t *testing.T) {
		domain := &jobs.Job{
			ID: "1-2-no-event",
			ProblemStatement: jobs.ProblemStatement{
				Content: "Fix the failing tests",
			},
		}
		customAgent := &mockCustomAgent{}

		dto := jobDTOFromDomain(domain, customAgent, []sweagentd.CustomAgent{}, nil, nil, "", jobExtraFields{})

		require.NotNil(t, dto)
		assert.Empty(t, dto.EventType)
		assert.Empty(t, dto.EventURL)
		assert.Empty(t, dto.EventIdentifiers)
	})
}

func TestJobDTOFromDomainGitHubBlock(t *testing.T) {
	t.Run("github omitted when no permissions and no toolsets", func(t *testing.T) {
		domain := &jobs.Job{ID: "1-2-no-github"}
		agent := &mockCustomAgent{
			name:  "plain-agent",
			tools: []string{"*"},
			// perms zero-value and githubMCPToolsets nil → github block omitted
		}

		dto := jobDTOFromDomain(domain, agent, []sweagentd.CustomAgent{}, nil, nil, "", jobExtraFields{})
		require.NotNil(t, dto)
		assert.Nil(t, dto.CustomAgent.GitHub, "github block should be nil when neither permissions nor toolsets are set")

		// Verify JSON serialization omits the key entirely
		raw, err := json.Marshal(dto)
		require.NoError(t, err)
		assert.NotContains(t, string(raw), `"github"`)
	})

	t.Run("github present with permissions only", func(t *testing.T) {
		domain := &jobs.Job{ID: "1-2-perms-only"}
		agent := &mockCustomAgent{
			name:  "perms-agent",
			tools: []string{"*"},
			perms: permissions.New(map[string]string{
				"contents":      "write",
				"pull-requests": "read",
				"metadata":      "read",
			}),
		}

		dto := jobDTOFromDomain(domain, agent, []sweagentd.CustomAgent{}, nil, nil, "", jobExtraFields{})
		require.NotNil(t, dto)
		require.NotNil(t, dto.CustomAgent.GitHub, "github block should be present when permissions are set")
		assert.Equal(t, map[string]string{
			"contents":      "write",
			"pull-requests": "read",
			"metadata":      "read",
		}, dto.CustomAgent.GitHub.Permissions)
		assert.Nil(t, dto.CustomAgent.GitHub.Toolsets)

		// Verify JSON round-trip
		raw, err := json.Marshal(dto)
		require.NoError(t, err)
		var decoded jobDTO
		require.NoError(t, json.Unmarshal(raw, &decoded))
		assert.Equal(t, "write", decoded.CustomAgent.GitHub.Permissions["contents"])
		assert.Equal(t, "read", decoded.CustomAgent.GitHub.Permissions["pull-requests"])
		assert.Nil(t, decoded.CustomAgent.GitHub.Toolsets)
	})

	t.Run("github present with toolsets only", func(t *testing.T) {
		domain := &jobs.Job{ID: "1-2-toolsets-only"}
		agent := &mockCustomAgent{
			name:              "toolsets-agent",
			tools:             []string{"*"},
			githubMCPToolsets: []string{"code_review", "pull_requests"},
		}

		dto := jobDTOFromDomain(domain, agent, []sweagentd.CustomAgent{}, nil, nil, "", jobExtraFields{})
		require.NotNil(t, dto)
		require.NotNil(t, dto.CustomAgent.GitHub, "github block should be present when toolsets are set")
		assert.Nil(t, dto.CustomAgent.GitHub.Permissions)
		assert.Equal(t, []string{"code_review", "pull_requests"}, dto.CustomAgent.GitHub.Toolsets)

		// Verify JSON round-trip
		raw, err := json.Marshal(dto)
		require.NoError(t, err)
		var decoded jobDTO
		require.NoError(t, json.Unmarshal(raw, &decoded))
		assert.Nil(t, decoded.CustomAgent.GitHub.Permissions)
		assert.Equal(t, []string{"code_review", "pull_requests"}, decoded.CustomAgent.GitHub.Toolsets)
	})

	t.Run("github present with both permissions and toolsets", func(t *testing.T) {
		domain := &jobs.Job{ID: "1-2-both"}
		agent := &mockCustomAgent{
			name:  "full-agent",
			tools: []string{"*"},
			perms: permissions.New(map[string]string{
				"contents": "read",
				"issues":   "write",
				"metadata": "read",
			}),
			githubMCPToolsets: []string{"issues", "code_security"},
		}

		dto := jobDTOFromDomain(domain, agent, []sweagentd.CustomAgent{}, nil, nil, "", jobExtraFields{})
		require.NotNil(t, dto)
		require.NotNil(t, dto.CustomAgent.GitHub)
		assert.Equal(t, "read", dto.CustomAgent.GitHub.Permissions["contents"])
		assert.Equal(t, "write", dto.CustomAgent.GitHub.Permissions["issues"])
		assert.Equal(t, []string{"issues", "code_security"}, dto.CustomAgent.GitHub.Toolsets)

		// Verify JSON structure
		raw, err := json.Marshal(dto)
		require.NoError(t, err)
		assert.Contains(t, string(raw), `"github"`)
		assert.Contains(t, string(raw), `"permissions"`)
		assert.Contains(t, string(raw), `"toolsets"`)
	})

	t.Run("available agents carry github block independently", func(t *testing.T) {
		domain := &jobs.Job{ID: "1-2-avail"}
		primary := &mockCustomAgent{
			name:  "primary",
			tools: []string{"*"},
			// no permissions or toolsets
		}
		secondary := &mockCustomAgent{
			name:              "secondary",
			tools:             []string{"*"},
			githubMCPToolsets: []string{"pull_requests"},
		}
		available := []sweagentd.CustomAgent{secondary}

		dto := jobDTOFromDomain(domain, primary, available, nil, nil, "", jobExtraFields{})
		require.NotNil(t, dto)
		assert.Nil(t, dto.CustomAgent.GitHub, "primary agent should not have github block")
		require.Len(t, dto.AvailableCustomAgents, 1)
		require.NotNil(t, dto.AvailableCustomAgents[0].GitHub, "secondary agent should have github block")
		assert.Equal(t, []string{"pull_requests"}, dto.AvailableCustomAgents[0].GitHub.Toolsets)
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
	h := NewHandler(obsv, featureflags.NewNoopClient(nil), store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, nil, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

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

	t.Run("filters by ns query param", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/agent/jobs/1-2-uuid/progress?ns=runtime", http.NoBody).WithContext(baseCtx)
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

	t.Run("combines namespace and ns query params", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/agent/jobs/1-2-uuid/progress?namespace=runtime&ns=agent", http.NoBody).WithContext(baseCtx)
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
	h := NewHandler(obsv, featureflags.NewNoopClient(nil), store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, nil, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

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

	t.Run("report_progress kind stores progress and triggers PR update side-effect", func(t *testing.T) {
		// Seed a job with PR fields so UpdateJobPullRequestMidSession proceeds past HasPullRequest check
		prJob := &jobs.Job{
			ID:                "1-2-pr-uuid",
			OwnerID:           1,
			RepoID:            2,
			AssignmentID:      "assignment-pr",
			NonceHash:         jobs.HashNonce(nonce),
			PullRequestID:     100,
			PullRequestNumber: 42,
		}
		_, _ = store.CreateJob(ctx, prJob)

		body := `{
			"namespace": "sessions-v2",
			"kind": "report_progress",
			"version": 1,
			"content": "{\"pr_title\":\"New Title\",\"pr_description\":\"New Description\"}"
		}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-pr-uuid/progress", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", "1-2-pr-uuid")
		rr := httptest.NewRecorder()
		h.createProgress(rr, req)

		// Progress is always stored regardless of side-effect outcome
		require.Equal(t, http.StatusCreated, rr.Code)
		var result progressDTO
		err := json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)
		require.Equal(t, "sessions-v2", result.Namespace)
		require.Equal(t, "report_progress", result.Kind)
	})

	t.Run("report_progress kind with no PR is a no-op side-effect", func(t *testing.T) {
		// The original job has no PR fields, so side-effect is silently skipped
		body := `{
			"namespace": "sessions-v2",
			"kind": "report_progress",
			"version": 1,
			"content": "{\"pr_title\":\"Title\"}"
		}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-uuid/progress", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", "1-2-uuid")
		rr := httptest.NewRecorder()
		h.createProgress(rr, req)

		require.Equal(t, http.StatusCreated, rr.Code)
	})

	t.Run("comment_reply kind stores progress and triggers reply side-effect", func(t *testing.T) {
		body := `{
			"namespace": "sessions-v2",
			"kind": "comment_reply",
			"version": 1,
			"content": "{\"comment_id\":99,\"message\":\"Done fixing!\"}"
		}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-pr-uuid/progress", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", "1-2-pr-uuid")
		rr := httptest.NewRecorder()
		h.createProgress(rr, req)

		// Progress stored; side-effect may log errors but doesn't fail the response
		require.Equal(t, http.StatusCreated, rr.Code)
		var result progressDTO
		err := json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)
		require.Equal(t, "sessions-v2", result.Namespace)
		require.Equal(t, "comment_reply", result.Kind)
	})

	t.Run("non-sessions-v2 namespace does not trigger side-effects", func(t *testing.T) {
		body := `{
			"namespace": "runtime",
			"kind": "report_progress",
			"version": 1,
			"content": "{\"pr_title\":\"Should not trigger\"}"
		}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-uuid/progress", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", "1-2-uuid")
		rr := httptest.NewRecorder()
		h.createProgress(rr, req)

		require.Equal(t, http.StatusCreated, rr.Code)
	})

	t.Run("rejects oversized single progress item with 413", func(t *testing.T) {
		large := strings.Repeat("a", maxProgressDocumentBytes+1)
		innerJSON, err := json.Marshal(map[string]string{"message": large})
		require.NoError(t, err)
		contentJSON, err := json.Marshal(string(innerJSON))
		require.NoError(t, err)
		body := `{"namespace":"runtime","kind":"log","version":1,"content":` + string(contentJSON) + `}`

		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-uuid/progress", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", "1-2-uuid")
		rr := httptest.NewRecorder()
		h.createProgress(rr, req)

		require.Equal(t, http.StatusRequestEntityTooLarge, rr.Code)
		require.Contains(t, rr.Body.String(), "exceeds max")
		require.Contains(t, rr.Body.String(), `namespace="runtime"`)
	})

	t.Run("rejects batch when an item is oversized and stores none", func(t *testing.T) {
		large := strings.Repeat("b", maxProgressDocumentBytes+1)
		innerJSON, err := json.Marshal(map[string]string{"message": large})
		require.NoError(t, err)
		largeContentJSON, err := json.Marshal(string(innerJSON))
		require.NoError(t, err)

		body := `[
			{"namespace":"runtime","kind":"log","version":1,"content":"{\"ok\":true}"},
			{"namespace":"runtime","kind":"giant","version":1,"content":` + string(largeContentJSON) + `},
			{"namespace":"runtime","kind":"log","version":1,"content":"{\"ok\":true}"}
		]`

		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-uuid/progress", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", "1-2-uuid")
		rr := httptest.NewRecorder()
		h.createProgress(rr, req)

		require.Equal(t, http.StatusRequestEntityTooLarge, rr.Code)
		require.Contains(t, rr.Body.String(), `kind="giant"`)
		stored, err := store.ListProgress(ctx, job.AssignmentID, job.ID)
		require.NoError(t, err)
		for _, p := range stored {
			require.NotEqual(t, "giant", p.Kind, "oversized item must not be stored")
		}
	})

	t.Run("rejects request body exceeding maxProgressRequestBytes with 413", func(t *testing.T) {
		oversize := strings.Repeat("z", maxProgressRequestBytes+1)
		body := `{"namespace":"runtime","kind":"log","version":1,"content":"` + oversize + `"}`

		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-uuid/progress", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", "1-2-uuid")
		rr := httptest.NewRecorder()
		h.createProgress(rr, req)

		require.Equal(t, http.StatusRequestEntityTooLarge, rr.Code)
		require.Contains(t, rr.Body.String(), "request body exceeds")
	})
}

func TestHandlerGetJob_SessionToken(t *testing.T) {
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopTwirp := githubtwirp.NewNoopClient()
	noopTwirp.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
	agents := map[string]string{
		"agent1": "---\nkey: value\n---\nthis is agent 1",
	}
	spokes := customagenttest.MakeSpokes(t, agents)
	ghTwirp := githubtwirp.NewNoopClient()

	nonce := "nonce-val"
	baseCtx := requestctx.AddData(context.Background(), &requestctx.CtxData{UserInfo: &requestctx.UserInfo{ID: 123, TokenInfo: &requestctx.TokenInfo{ApplicationID: uint64(cf.AppID())}}})

	t.Run("returns capi_session_token when auto-mode experiment is active", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentAutoModelExperiment: true,
		})
		customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		capiClient := capi.NewNoopClient()
		capiClient.MockCreateModelSession = func(ctx context.Context, userID uint64, modelHints []string, existingToken string) (*capi.ModelSessionResponse, error) {
			require.Equal(t, []string{"gpt-4"}, modelHints, "model hints should have prefix stripped")
			return &capi.ModelSessionResponse{
				SessionToken: "test-session-token-123",
				ExpiresAt:    1700000000,
			}, nil
		}

		h := NewHandler(obsv, ffClient, store, cf, noopTwirp, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, nil, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capiClient, nil, "")

		job := &jobs.Job{
			ID:               "1-2-auto-mode-job",
			OwnerID:          1,
			RepoID:           2,
			NonceHash:        jobs.HashNonce(nonce),
			ProblemStatement: jobs.ProblemStatement{Content: "Fix the bug"},
			Model:            "sweagent-capi:gpt-4",
			IsAutoMode:       true,
			Action:           jobs.AgentActionFix,
			Args:             launcher.LaunchAgentOpts{GitHubRepo: "owner/repo"},
			CustomAgent:      jobsCustomAgent.DBRecord{RepoOwner: "owner", RepoName: "repo"},
		}
		_, _ = store.CreateJob(baseCtx, job)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-auto-mode-job", nil)
		req = muxSetParam(req, "jobID", job.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.getJob(w, req)

		require.Equal(t, http.StatusOK, w.Code)
		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		assert.Equal(t, "test-session-token-123", resp.CAPISessionToken)
	})

	t.Run("returns no capi_session_token when experiment is not active", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentAutoModelExperiment: false,
		})
		customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		capiClient := capi.NewNoopClient()
		h := NewHandler(obsv, ffClient, store, cf, noopTwirp, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, nil, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capiClient, nil, "")

		job := &jobs.Job{
			ID:               "1-2-no-experiment-job",
			OwnerID:          1,
			RepoID:           2,
			NonceHash:        jobs.HashNonce(nonce),
			ProblemStatement: jobs.ProblemStatement{Content: "Fix the bug"},
			Model:            "sweagent-capi:gpt-4",
			IsAutoMode:       true,
			Action:           jobs.AgentActionFix,
			Args:             launcher.LaunchAgentOpts{GitHubRepo: "owner/repo"},
			CustomAgent:      jobsCustomAgent.DBRecord{RepoOwner: "owner", RepoName: "repo"},
		}
		_, _ = store.CreateJob(baseCtx, job)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-no-experiment-job", nil)
		req = muxSetParam(req, "jobID", job.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.getJob(w, req)

		require.Equal(t, http.StatusOK, w.Code)
		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		assert.Empty(t, resp.CAPISessionToken)
	})

	t.Run("returns no capi_session_token when job is not auto mode", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentAutoModelExperiment: true,
		})
		customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		capiClient := capi.NewNoopClient()
		h := NewHandler(obsv, ffClient, store, cf, noopTwirp, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, nil, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capiClient, nil, "")

		job := &jobs.Job{
			ID:               "1-2-not-auto-mode-job",
			OwnerID:          1,
			RepoID:           2,
			NonceHash:        jobs.HashNonce(nonce),
			ProblemStatement: jobs.ProblemStatement{Content: "Fix the bug"},
			Model:            "sweagent-capi:gpt-4",
			IsAutoMode:       false,
			Action:           jobs.AgentActionFix,
			Args:             launcher.LaunchAgentOpts{GitHubRepo: "owner/repo"},
			CustomAgent:      jobsCustomAgent.DBRecord{RepoOwner: "owner", RepoName: "repo"},
		}
		_, _ = store.CreateJob(baseCtx, job)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-not-auto-mode-job", nil)
		req = muxSetParam(req, "jobID", job.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.getJob(w, req)

		require.Equal(t, http.StatusOK, w.Code)
		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		assert.Empty(t, resp.CAPISessionToken)
	})

	t.Run("returns no capi_session_token for org-billed auto-mode job", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentAutoModelExperiment: true,
		})
		customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		capiClient := capi.NewNoopClient()
		capiClient.MockCreateModelSession = func(ctx context.Context, userID uint64, modelHints []string, existingToken string) (*capi.ModelSessionResponse, error) {
			t.Fatal("CreateModelSession should not be called for org-billed jobs")
			return nil, nil
		}

		h := NewHandler(obsv, ffClient, store, cf, noopTwirp, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, nil, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capiClient, nil, "")

		job := &jobs.Job{
			ID:               "1-2-org-billed-job",
			OwnerID:          1,
			RepoID:           2,
			NonceHash:        jobs.HashNonce(nonce),
			ProblemStatement: jobs.ProblemStatement{Content: "Fix the bug"},
			Model:            "sweagent-capi:gpt-4",
			IsAutoMode:       true,
			ActorType:        jobs.ActorTypeOrg,
			ActorID:          999,
			Action:           jobs.AgentActionFixPRComment,
			Args:             launcher.LaunchAgentOpts{GitHubRepo: "owner/repo"},
			CustomAgent:      jobsCustomAgent.DBRecord{RepoOwner: "owner", RepoName: "repo"},
		}
		_, _ = store.CreateJob(baseCtx, job)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-org-billed-job", nil)
		req = muxSetParam(req, "jobID", job.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.getJob(w, req)

		require.Equal(t, http.StatusOK, w.Code)
		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		assert.Empty(t, resp.CAPISessionToken)
	})

	t.Run("auto-intent refines auto_mode_model when flag is enabled and router returns chosen_model", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentAutoModelExperiment: true,
			featureflags.CopilotSWEAgentAutoIntent:      true,
		})
		customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		var intentCalls int
		capiClient := capi.NewNoopClient()
		capiClient.MockCreateModelSession = func(ctx context.Context, userID uint64, modelHints []string, existingToken string) (*capi.ModelSessionResponse, error) {
			return &capi.ModelSessionResponse{
				SessionToken:    "session-token",
				SelectedModel:   "claude-sonnet-4.6",
				AvailableModels: []string{"claude-sonnet-4.6", "gpt-5-mini"},
				ExpiresAt:       1700000000,
			}, nil
		}
		capiClient.MockCreateModelSessionIntent = func(ctx context.Context, userID uint64, sessionToken string, intentReq capi.ModelSessionIntentRequest) (*capi.ModelSessionIntentResponse, error) {
			intentCalls++
			require.Equal(t, "session-token", sessionToken)
			require.Equal(t, "Refactor this", intentReq.Prompt)
			require.Equal(t, []string{"claude-sonnet-4.6", "gpt-5-mini"}, intentReq.AvailableModels)
			return &capi.ModelSessionIntentResponse{
				ChosenModel:     "gpt-5-mini",
				CandidateModels: []string{"gpt-5-mini", "claude-sonnet-4.6"},
				Fallback:        false,
			}, nil
		}

		h := NewHandler(obsv, ffClient, store, cf, noopTwirp, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, nil, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capiClient, nil, "")

		job := &jobs.Job{
			ID:               "1-2-auto-intent-job",
			OwnerID:          1,
			RepoID:           2,
			NonceHash:        jobs.HashNonce(nonce),
			ProblemStatement: jobs.ProblemStatement{Content: "Refactor this"},
			Model:            "sweagent-capi:auto",
			IsAutoMode:       true,
			Action:           jobs.AgentActionFix,
			Args:             launcher.LaunchAgentOpts{GitHubRepo: "owner/repo"},
			CustomAgent:      jobsCustomAgent.DBRecord{RepoOwner: "owner", RepoName: "repo"},
		}
		_, _ = store.CreateJob(baseCtx, job)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/"+job.ID, nil)
		req = muxSetParam(req, "jobID", job.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.getJob(w, req)

		require.Equal(t, http.StatusOK, w.Code)
		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		assert.Equal(t, 1, intentCalls)
		assert.Equal(t, "gpt-5-mini", resp.AutoModeModel)
		assert.Equal(t, "session-token", resp.CAPISessionToken)
	})

	t.Run("auto-intent fallback=true keeps the auto-mode selected_model", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentAutoModelExperiment: true,
			featureflags.CopilotSWEAgentAutoIntent:      true,
		})
		customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		capiClient := capi.NewNoopClient()
		capiClient.MockCreateModelSession = func(ctx context.Context, userID uint64, modelHints []string, existingToken string) (*capi.ModelSessionResponse, error) {
			return &capi.ModelSessionResponse{
				SessionToken:    "session-token",
				SelectedModel:   "claude-sonnet-4.6",
				AvailableModels: []string{"claude-sonnet-4.6", "gpt-5-mini"},
			}, nil
		}
		capiClient.MockCreateModelSessionIntent = func(ctx context.Context, userID uint64, sessionToken string, intentReq capi.ModelSessionIntentRequest) (*capi.ModelSessionIntentResponse, error) {
			return &capi.ModelSessionIntentResponse{
				ChosenModel: "gpt-5-mini",
				Fallback:    true,
			}, nil
		}

		h := NewHandler(obsv, ffClient, store, cf, noopTwirp, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, nil, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capiClient, nil, "")

		job := &jobs.Job{
			ID:               "1-2-auto-intent-fallback-job",
			OwnerID:          1,
			RepoID:           2,
			NonceHash:        jobs.HashNonce(nonce),
			ProblemStatement: jobs.ProblemStatement{Content: "Refactor this"},
			Model:            "sweagent-capi:auto",
			IsAutoMode:       true,
			Action:           jobs.AgentActionFix,
			Args:             launcher.LaunchAgentOpts{GitHubRepo: "owner/repo"},
			CustomAgent:      jobsCustomAgent.DBRecord{RepoOwner: "owner", RepoName: "repo"},
		}
		_, _ = store.CreateJob(baseCtx, job)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/"+job.ID, nil)
		req = muxSetParam(req, "jobID", job.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.getJob(w, req)

		require.Equal(t, http.StatusOK, w.Code)
		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		assert.Equal(t, "claude-sonnet-4.6", resp.AutoModeModel, "fallback=true must keep auto-mode selected_model")
	})

	t.Run("auto-intent is not called when flag is disabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentAutoModelExperiment: true,
		})
		customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		capiClient := capi.NewNoopClient()
		capiClient.MockCreateModelSession = func(ctx context.Context, userID uint64, modelHints []string, existingToken string) (*capi.ModelSessionResponse, error) {
			return &capi.ModelSessionResponse{
				SessionToken:    "session-token",
				SelectedModel:   "claude-sonnet-4.6",
				AvailableModels: []string{"claude-sonnet-4.6", "gpt-5-mini"},
			}, nil
		}
		capiClient.MockCreateModelSessionIntent = func(ctx context.Context, userID uint64, sessionToken string, intentReq capi.ModelSessionIntentRequest) (*capi.ModelSessionIntentResponse, error) {
			t.Fatal("CreateModelSessionIntent should not be called when CopilotSWEAgentAutoIntent is disabled")
			return nil, nil
		}

		h := NewHandler(obsv, ffClient, store, cf, noopTwirp, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, nil, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capiClient, nil, "")

		job := &jobs.Job{
			ID:               "1-2-auto-intent-disabled-job",
			OwnerID:          1,
			RepoID:           2,
			NonceHash:        jobs.HashNonce(nonce),
			ProblemStatement: jobs.ProblemStatement{Content: "Refactor this"},
			Model:            "sweagent-capi:auto",
			IsAutoMode:       true,
			Action:           jobs.AgentActionFix,
			Args:             launcher.LaunchAgentOpts{GitHubRepo: "owner/repo"},
			CustomAgent:      jobsCustomAgent.DBRecord{RepoOwner: "owner", RepoName: "repo"},
		}
		_, _ = store.CreateJob(baseCtx, job)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/"+job.ID, nil)
		req = muxSetParam(req, "jobID", job.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.getJob(w, req)

		require.Equal(t, http.StatusOK, w.Code)
		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		assert.Equal(t, "claude-sonnet-4.6", resp.AutoModeModel)
	})
}
