package agenthttp

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	authd "github.com/github/authnd/client"
	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/agent"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/customagenttest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	jobsCustomAgent "github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/jobs/store/memory"
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
		option := spokestest.ClientWithRepoBlob(repoID, filepath.Join(customagent.Directory, name+customagent.Extension), []byte(content))
		options = append(options, option)
	}

	// Add organization-specific agents
	for name, content := range orgAgents {
		option := spokestest.ClientWithRepoBlob(orgRepoID, filepath.Join(customagent.OrgDirectory, name+customagent.Extension), []byte(content))
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

// mock callback + cleanup handlers to satisfy interface for NewHandler
type noopCallbackHandler struct{}

func (n *noopCallbackHandler) HandleCallback(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusTeapot)
}

type noopCleanupHandler struct{}

func (n *noopCleanupHandler) HandleCleanup(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusTeapot)
}

func TestServiceGetJob(t *testing.T) {
	cf := &github.NoopClientFactory{}
	store := memory.NewStore()
	spokes := customagenttest.MakeSpokes(t, map[string]string{})
	ghTwirp := githubtwirp.NewNoopClient()
	ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
	obsv := observability.NewNoopExporters()
	customAgentSvc := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
	svc := agent.NewService(store, cf, customAgentSvc, obsv, ffClient, ghTwirp)
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
	ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
	customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
	h := NewHandler(obsv, featureflags.NewNoopClient(nil), store, cf, tw, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc)

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
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsSweagentdEnabled: true}
	agents := map[string]string{
		"agent1": "---\nkey: value\n---\nthis is agent 1",
		"agent2": "---\nkey: value\n---\nthis is agent 2",
	}
	spokes := customagenttest.MakeSpokes(t, agents)
	ghTwirp := githubtwirp.NewNoopClient()
	ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
	customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
	h := NewHandler(obsv, featureflags.NewNoopClient(nil), store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc)

	ctx := context.Background()
	ok, err := h.checkEnablement(ctx, 1, 2)
	require.NoError(t, err)
	require.True(t, ok)

	// disabled
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsSweagentdEnabled: false}
	ok, err = h.checkEnablement(ctx, 1, 2)
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
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsSweagentdEnabled: true}
	agents := map[string]string{
		"agent1": "---\nkey: value\n---\nthis is agent 1",
		"agent2": "---\nkey: value\n---\nthis is agent 2",
	}
	spokes := customagenttest.MakeSpokes(t, agents)
	ghTwirp := githubtwirp.NewNoopClient()
	ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
	customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
	h := NewHandler(obsv, featureflags.NewNoopClient(nil), store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc)

	// seed job
	nonce := "nonce-val"
	job := &jobs.Job{
		ID:               "1-2-uuid",
		OwnerID:          1,
		RepoID:           2,
		RepoOwner:        "owner",
		RepoName:         "repo",
		NonceHash:        jobs.HashNonce(nonce),
		ProblemStatement: jobs.ProblemStatement{Content: "Fix the bug"},
		CustomAgent:      jobsCustomAgent.DBRecord{Name: "default", RepoOwner: "owner", RepoName: "repo", DisplayName: "Default", Description: "desc", Prompt: "prompt", Tools: []string{"tool1"}},
	}
	_, _ = store.CreateJob(context.Background(), job)

	baseCtx := requestctx.AddData(context.Background(), &requestctx.CtxData{UserInfo: &requestctx.UserInfo{ID: 123, TokenInfo: &requestctx.TokenInfo{ApplicationID: uint64(cf.AppID())}}})

	t.Run("missing job id", func(t *testing.T) {
		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/", nil)
		w := httptest.NewRecorder()
		h.getJob(w, req)
		require.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("job not found", func(t *testing.T) {
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		ghTwirp := githubtwirp.NewNoopClient()
		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		obsv := observability.NewNoopExporters()
		customAgentSvc := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		nfSvc := agent.NewService(&notFoundStore{}, cf, customAgentSvc, obsv, ffClient, ghTwirp)
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

	t.Run("organization custom instructions included when enabled", func(t *testing.T) {
		// Set up mock organization custom instructions
		orgInstructions := "Always follow our coding standards and use TypeScript."
		noopClient.NoopSweagentdAPI.MockGetOrganizationCustomInstructions = func(ctx context.Context, req *sweagentdTwirp.GetOrganizationCustomInstructionsRequest) (*sweagentdTwirp.GetOrganizationCustomInstructionsResponse, error) {
			return &sweagentdTwirp.GetOrganizationCustomInstructionsResponse{
				OrganizationCustomInstructions: orgInstructions,
			}, nil
		}

		// Enable organization custom instructions feature flag
		ffs := map[string]bool{
			featureflags.CopilotSWEAgentOrganizationCustomInstructions: true,
		}
		ffClient := featureflags.NewNoopClient(ffs)
		customAgentSvcEnabled := customagent.NewService(observability.NewNoopExporters(), spokes, noopClient, ffClient)
		h := NewHandler(obsv, ffClient, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvcEnabled)

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
		ffClientWithErrors := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		customAgentSvcWithErrors := customagent.NewService(observability.NewNoopExporters(), spokesWithErrors, ghTwirpWithErrors, ffClientWithErrors)
		hWithErrors := NewHandler(obsv, ffClientWithErrors, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvcWithErrors)

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

	t.Run("404s when repo not found", func(t *testing.T) {
		runGetTest(t, "repo-does-not-exist", "agent1", "", http.StatusNotFound)
	})

	t.Run("404s for non-existent agent", func(t *testing.T) {
		runGetTest(t, "", "does-not-exist", "", http.StatusNotFound)
	})

	t.Run("404s for non-existent version", func(t *testing.T) {
		runGetTest(t, "sha-999999999999999999999999999999999999", "agent1", "sha-999999999999999999999999999999999988", http.StatusNotFound)
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
	ffs := map[string]bool{
		featureflags.CopilotSWEAgentUseCustomAgents: true,
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
	h := NewHandler(obsv, ffClient, store, cf, ghTwirp, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc)

	userInfo := &requestctx.UserInfo{
		ID:        123,
		TokenInfo: &requestctx.TokenInfo{Token: "token"},
	}
	err := requestctx.AddUser(ctx, userInfo)
	if err != nil {
		t.Fatalf("failed to add user to context: %v", err)
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
			CustomAgent: jobsCustomAgent.DBRecord{
				Name:        "refactorer",
				RepoOwnerID: 1,
				RepoOwner:   "octo-org",
				RepoID:      2,
				RepoName:    "octo-repo",
				DisplayName: "Refactorer",
				Description: "Refactors code intelligently",
				Prompt:      "You are a helpful refactoring assistant.",
				Tools:       []string{"search", "write", "format"},
			},
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
				Prompt:      "You are a helpful refactoring assistant.",
				Tools:       []string{"search", "write", "format"},
				MCPServers:  []jobsCustomAgent.MCPServer{},
			}),
		}
		dto := jobDTOFromDomain(domain, availableCustomAgents, "")
		require.NotNil(t, dto)
		assert.Equal(t, domain.ID, dto.ID)
		assert.Equal(t, domain.ProblemStatement.Content, dto.ProblemStatement.Content)

		assert.Equal(t, domain.CustomAgent.Name, dto.CustomAgent.Name)
		assert.Equal(t, domain.CustomAgent.RepoOwnerID, dto.CustomAgent.RepoOwnerID)
		assert.Equal(t, domain.CustomAgent.RepoOwner, dto.CustomAgent.RepoOwner)
		assert.Equal(t, domain.CustomAgent.RepoID, dto.CustomAgent.RepoID)
		assert.Equal(t, domain.CustomAgent.RepoName, dto.CustomAgent.RepoName)
		assert.Equal(t, domain.CustomAgent.DisplayName, dto.CustomAgent.DisplayName)
		assert.Equal(t, domain.CustomAgent.Description, dto.CustomAgent.Description)
		assert.Equal(t, domain.CustomAgent.Prompt, dto.CustomAgent.Prompt)
		assert.ElementsMatch(t, domain.CustomAgent.Tools, dto.CustomAgent.Tools)
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

	t.Run("nil becomes [\"*\"]", func(t *testing.T) {
		// Case 1: nil slice
		domainNil := &jobs.Job{ID: "1-2-uuid-nil", CustomAgent: jobsCustomAgent.DBRecord{Name: "nil-agent", Tools: nil}}
		dtoNil := jobDTOFromDomain(domainNil, []sweagentd.CustomAgent{}, "")
		require.NotNil(t, dtoNil)
		assert.ElementsMatch(t, dtoNil.CustomAgent.Tools, []string{"*"}, "expected nil tools slice to become [\"*\"]")
	})

	t.Run("empty tool slice preservation", func(t *testing.T) {
		domainEmpty := &jobs.Job{ID: "1-2-uuid-empty", CustomAgent: jobsCustomAgent.DBRecord{Name: "empty-agent", Tools: []string{}}}
		dtoEmpty := jobDTOFromDomain(domainEmpty, []sweagentd.CustomAgent{}, "")
		require.NotNil(t, dtoEmpty)
		assert.NotNil(t, dtoEmpty.CustomAgent.Tools, "expected non-nil empty slice to stay non-nil")
		assert.Len(t, dtoEmpty.CustomAgent.Tools, 0)
	})

	t.Run("MCP servers mapping", func(t *testing.T) {
		// Create MCP servers configuration
		mcpServers := []jobsCustomAgent.MCPServer{
			{
				Name:    "filesystem",
				Type:    "local",
				Tools:   []string{"read_file", "write_file"},
				Command: "npx",
				Args:    []string{"-y", "@modelcontextprotocol/server-filesystem", "/tmp"},
				Env:     map[string]string{"NODE_ENV": "development"},
			},
			{
				Name:    "web-search",
				Type:    "sse",
				Tools:   []string{"web_search"},
				URL:     "https://api.example.com/mcp",
				Headers: map[string]string{"Authorization": "Bearer token"},
			},
		}

		domain := &jobs.Job{
			ID: "1-2-uuid-with-mcp",
			ProblemStatement: jobs.ProblemStatement{
				Content: "Test MCP servers functionality",
			},
			CustomAgent: jobsCustomAgent.DBRecord{
				Name:        "mcp-agent",
				RepoOwner:   "test-org",
				RepoName:    "test-repo",
				DisplayName: "MCP Test Agent",
				Description: "Agent for testing MCP servers",
				Prompt:      "You have access to MCP servers.",
				Tools:       []string{"*"},
				MCPServers:  mcpServers,
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
		dto := jobDTOFromDomain(domain, []sweagentd.CustomAgent{availableAgent}, "")
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
		assert.Equal(t, "npx", filesystemServer.Local.Command)
		assert.ElementsMatch(t, []string{"-y", "@modelcontextprotocol/server-filesystem", "/tmp"}, filesystemServer.Local.Args)
		assert.Equal(t, "development", filesystemServer.Local.Env["NODE_ENV"])
		assert.Nil(t, filesystemServer.Remote)

		// Verify web-search server details (remote type)
		webSearchServer := dto.CustomAgent.MCPServers["web-search"]
		assert.Equal(t, "sse", webSearchServer.Type)
		assert.ElementsMatch(t, []string{"web_search"}, webSearchServer.Tools)
		assert.NotNil(t, webSearchServer.Remote)
		assert.Equal(t, "https://api.example.com/mcp", webSearchServer.Remote.URL)
		assert.Equal(t, "Bearer token", webSearchServer.Remote.Headers["Authorization"])
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
		assert.Equal(t, "simple-server", simpleMCPServer.Local.Command)
	})

	t.Run("empty MCP servers", func(t *testing.T) {
		domain := &jobs.Job{
			ID: "1-2-uuid-no-mcp",
			CustomAgent: jobsCustomAgent.DBRecord{
				Name:       "no-mcp-agent",
				MCPServers: []jobsCustomAgent.MCPServer{}, // empty slice
			},
		}

		dto := jobDTOFromDomain(domain, []sweagentd.CustomAgent{}, "")
		require.NotNil(t, dto)

		// Empty MCP servers should result in empty servers map
		assert.NotNil(t, dto.CustomAgent.MCPServers)
		assert.Empty(t, dto.CustomAgent.MCPServers)
	})

	t.Run("nil MCP servers", func(t *testing.T) {
		domain := &jobs.Job{
			ID: "1-2-uuid-nil-mcp",
			CustomAgent: jobsCustomAgent.DBRecord{
				Name:       "nil-mcp-agent",
				MCPServers: nil, // nil slice
			},
		}

		dto := jobDTOFromDomain(domain, []sweagentd.CustomAgent{}, "")
		require.NotNil(t, dto)

		// Nil MCP servers should result in empty servers map
		assert.NotNil(t, dto.CustomAgent.MCPServers)
		assert.Empty(t, dto.CustomAgent.MCPServers)
	})
}

func TestHandlerGetAgentWithMCPServers(t *testing.T) {
	runTest := func(t *testing.T, repoName string, enterprisePrivileged, isPrivileged bool) {
		t.Helper()
		obsv := observability.NewNoopExporters()
		ffs := map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents: true,
		}
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

		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, featureflags.NewNoopClient(nil), store, cf, ghTwirp, &noopCallbackHandler{}, &noopCleanupHandler{}, svc)
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
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsSweagentdEnabled: true}
	agents := map[string]string{
		"agent1": "---\nkey: value\n---\nthis is agent 1",
		"agent2": "---\nkey: value\n---\nthis is agent 2",
	}
	spokes := customagenttest.MakeSpokes(t, agents)

	// Enable organization custom instructions feature flag
	ffs := map[string]bool{
		featureflags.CopilotSWEAgentOrganizationCustomInstructions: true,
	}
	ffClient := featureflags.NewNoopClient(ffs)
	customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, noopClient, ffClient)
	h := NewHandler(obsv, ffClient, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc)

	// seed job
	nonce := "nonce-val"
	job := &jobs.Job{
		ID:               "1-2-uuid",
		OwnerID:          1,
		RepoID:           2,
		RepoOwner:        "owner",
		RepoName:         "repo",
		NonceHash:        jobs.HashNonce(nonce),
		ProblemStatement: jobs.ProblemStatement{Content: "Fix the bug"},
		CustomAgent:      jobsCustomAgent.DBRecord{Name: "default", RepoOwner: "owner", RepoName: "repo", DisplayName: "Default", Description: "desc", Prompt: "prompt", Tools: []string{"tool1"}},
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

	t.Run("organization custom instructions excluded when feature flag disabled", func(t *testing.T) {
		// Disable feature flag
		ffClientDisabled := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentOrganizationCustomInstructions: false,
		})
		customAgentSvcDisabled := customagent.NewService(observability.NewNoopExporters(), spokes, noopClient, ffClientDisabled)
		hDisabled := NewHandler(obsv, ffClientDisabled, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvcDisabled)

		req := httptest.NewRequestWithContext(baseCtx, http.MethodGet, "/agent/jobs/1-2-uuid", nil)
		req = muxSetParam(req, "jobID", job.ID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		hDisabled.getJob(w, req)
		require.Equal(t, http.StatusOK, w.Code)
		var resp jobDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))

		// Verify organization custom instructions are not included
		assert.Empty(t, resp.OrganizationCustomInstructions)
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

		orgInstructions := "Follow company coding standards and write tests."
		dto := jobDTOFromDomain(domain, []sweagentd.CustomAgent{}, orgInstructions)

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

		dto := jobDTOFromDomain(domain, []sweagentd.CustomAgent{}, "")

		require.NotNil(t, dto)
		assert.Empty(t, dto.OrganizationCustomInstructions)
	})
}
