package memoryhttp

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	coreTwirp "github.com/github/copilot-api/proto/twirp/core/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/experiments/exp"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// --- VerboseFromDomain unit tests ---

func TestVerboseFromDomain_IncludesAllFields(t *testing.T) {
	now := time.Now().UTC()
	memory := &core.Memory{
		ID:        core.MemoryID("mem-1"),
		Subject:   "subject",
		Fact:      "fact",
		Citations: []string{"c1"},
		Reason:    "reason",
		Scope:     core.MemoryScopeRepository,
		CreatedAt: now.Add(-time.Hour),
		UpdatedAt: now.Add(-30 * time.Minute),
		ExpiresAt: now.Add(27 * 24 * time.Hour),
		Source: core.MemorySource{
			InteractionID: "int-1",
			Agent:         "agent",
			CommitSHA:     "sha1",
			BaseModel:     "gpt-4",
		},
		Votes: []core.Vote{
			{
				Direction: core.UpVote,
				Timestamp: now.Add(-time.Hour),
				Source: core.VoteSource{
					Agent:     "agent",
					RepoNWO:   core.RepoNWO{Owner: "o", Repo: "r"},
					UserID:    1,
					UserLogin: "u",
					Reason:    "initial",
				},
			},
			{
				Direction: core.DownVote,
				Timestamp: now.Add(-30 * time.Minute),
				Source: core.VoteSource{
					Agent:     "other-agent",
					UserID:    2,
					UserLogin: "u2",
					Reason:    "disagree",
				},
			},
		},
		BillingOrganizationID: 42,
		BillingEnterpriseID:   99,
	}

	dto := VerboseFromDomain(memory)

	// Embedded base DTO fields
	assert.Equal(t, "mem-1", dto.ID)
	assert.Equal(t, "subject", dto.Subject)
	assert.Equal(t, "fact", dto.Fact)
	assert.Equal(t, []string{"c1"}, dto.Citations)
	assert.Equal(t, "reason", dto.Reason)
	assert.Equal(t, "agent", dto.Source.Agent)
	assert.Equal(t, "sha1", dto.Source.CommitSHA)
	assert.Equal(t, "gpt-4", dto.Source.BaseModel)

	// Verbose-only fields
	assert.Equal(t, memory.CreatedAt, dto.CreatedAt)
	assert.Equal(t, memory.UpdatedAt, dto.UpdatedAt)
	assert.Equal(t, memory.ExpiresAt, dto.ExpiresAt)
	assert.Equal(t, "repository", dto.Scope)
	assert.Equal(t, uint64(42), dto.BillingOrganizationID)
	assert.Equal(t, uint64(99), dto.BillingEnterpriseID)

	// Score is non-zero for a memory with votes
	assert.NotZero(t, dto.Score)

	// Votes
	require.Len(t, dto.Votes, 2)
	assert.Equal(t, "upvote", dto.Votes[0].Direction)
	assert.Equal(t, "o/r", dto.Votes[0].Source.RepoNWO)
	assert.Equal(t, uint64(1), dto.Votes[0].Source.UserID)
	assert.Equal(t, "initial", dto.Votes[0].Source.Reason)

	assert.Equal(t, "downvote", dto.Votes[1].Direction)
	assert.Equal(t, uint64(2), dto.Votes[1].Source.UserID)
	assert.Equal(t, "disagree", dto.Votes[1].Source.Reason)
}

func TestVerboseFromDomain_EmptyVotes(t *testing.T) {
	memory := &core.Memory{
		ID:      core.MemoryID("mem-2"),
		Subject: "s",
		Fact:    "f",
		Scope:   core.MemoryScopeUser,
	}

	dto := VerboseFromDomain(memory)

	assert.Equal(t, "user", dto.Scope)
	assert.Empty(t, dto.Votes)
}

func TestVerboseFromDomain_CapsVotesAtMaxVerboseVotes(t *testing.T) {
	now := time.Now().UTC()

	// Create 15 votes (exceeds maxVerboseVotes of 10).
	allVotes := make([]core.Vote, 15)
	for i := range allVotes {
		allVotes[i] = core.Vote{
			Direction: core.UpVote,
			Timestamp: now.Add(time.Duration(i) * time.Minute),
			Source: core.VoteSource{
				Agent:  "agent",
				UserID: uint64(i + 1),
			},
		}
	}

	memory := &core.Memory{
		ID:      core.MemoryID("mem-cap"),
		Subject: "s",
		Fact:    "f",
		Scope:   core.MemoryScopeRepository,
		Votes:   allVotes,
	}

	dto := VerboseFromDomain(memory)

	// Should only return the most recent 10 votes.
	require.Len(t, dto.Votes, maxVerboseVotes)
	// TotalVoteCount reports the full count.
	assert.Equal(t, 15, dto.TotalVoteCount)
	// Verify we got the most recent votes (last 10 of 15 → userIDs 6..15).
	assert.Equal(t, uint64(6), dto.Votes[0].Source.UserID)
	assert.Equal(t, uint64(15), dto.Votes[9].Source.UserID)
}

func TestVerboseFromDomain_FewVotesReturnsAll(t *testing.T) {
	now := time.Now().UTC()
	memory := &core.Memory{
		ID:      core.MemoryID("mem-few"),
		Subject: "s",
		Fact:    "f",
		Scope:   core.MemoryScopeRepository,
		Votes: []core.Vote{
			{Direction: core.UpVote, Timestamp: now, Source: core.VoteSource{Agent: "a"}},
			{Direction: core.DownVote, Timestamp: now.Add(time.Minute), Source: core.VoteSource{Agent: "b"}},
		},
	}

	dto := VerboseFromDomain(memory)

	require.Len(t, dto.Votes, 2)
	assert.Equal(t, 2, dto.TotalVoteCount)
}

func TestVerboseFromDomain_JSONIncludesVerboseFields(t *testing.T) {
	now := time.Now().UTC()
	memory := &core.Memory{
		ID:        core.MemoryID("mem-3"),
		Subject:   "s",
		Fact:      "f",
		Citations: []string{},
		Reason:    "r",
		Scope:     core.MemoryScopeRepository,
		CreatedAt: now,
		UpdatedAt: now,
		ExpiresAt: now.Add(core.VoteWindow),
		Votes: []core.Vote{{
			Direction: core.UpVote,
			Timestamp: now,
			Source:    core.VoteSource{Agent: "a"},
		}},
	}

	dto := VerboseFromDomain(memory)
	data, err := json.Marshal(dto)
	require.NoError(t, err)

	var raw map[string]json.RawMessage
	require.NoError(t, json.Unmarshal(data, &raw))

	// Verify verbose-specific keys are present in JSON
	for _, key := range []string{"score", "votes", "totalVoteCount", "createdAt", "updatedAt", "expiresAt", "scope"} {
		_, ok := raw[key]
		assert.True(t, ok, "expected key %q in JSON output", key)
	}
	// Verify base DTO keys are also present (not nested)
	for _, key := range []string{"id", "subject", "fact", "reason", "source"} {
		_, ok := raw[key]
		assert.True(t, ok, "expected key %q in JSON output", key)
	}
}

// --- isVerboseRequest unit tests ---

func newStaffTwirpClient(staffOrgID uint64) *githubtwirp.NoopClient {
	mockTwirp := githubtwirp.NewNoopClient()
	mockTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: &copilotUsersTwirp.CopilotUserDetails{
				Id:                    req.Id,
				BillingEntityResolved: true,
				CopilotOrganizations: []*copilotUsersTwirp.CopilotOrganization{
					{Id: staffOrgID},
				},
			},
		}, nil
	}
	// Grant token access so repo-scoped authorization passes.
	mockTwirp.NoopAuthorizationAPI.MockBatchControlAccess = func(ctx context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error) {
		decisions := make([]*coreTwirp.AuthorizationDecision, len(req.AuthorizationRequests))
		for i, authReq := range req.AuthorizationRequests {
			decisions[i] = &coreTwirp.AuthorizationDecision{
				Id:       authReq.Id,
				Decision: true,
			}
		}
		return &coreTwirp.BatchControlAccessResponse{Decisions: decisions}, nil
	}
	return mockTwirp
}

func newNonStaffTwirpClient() *githubtwirp.NoopClient {
	mockTwirp := githubtwirp.NewNoopClient()
	mockTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: &copilotUsersTwirp.CopilotUserDetails{
				Id:                    req.Id,
				BillingEntityResolved: true,
				CopilotOrganizations: []*copilotUsersTwirp.CopilotOrganization{
					{Id: 12345}, // not a staff org
				},
			},
		}, nil
	}
	// Grant token access so repo-scoped authorization passes.
	mockTwirp.NoopAuthorizationAPI.MockBatchControlAccess = func(ctx context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error) {
		decisions := make([]*coreTwirp.AuthorizationDecision, len(req.AuthorizationRequests))
		for i, authReq := range req.AuthorizationRequests {
			decisions[i] = &coreTwirp.AuthorizationDecision{
				Id:       authReq.Id,
				Decision: true,
			}
		}
		return &coreTwirp.BatchControlAccessResponse{Decisions: decisions}, nil
	}
	return mockTwirp
}

func newHandlerWithTwirp(t *testing.T, twirp githubtwirp.ClientInterface) *MemoryHandler {
	t.Helper()
	return NewMemoryHandler(MemoryHandlerOpts{
		Service: &MockMemoryService{},
		GHFactory: &github.NoopClientFactory{
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{}, nil
			},
		},
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
		GHTwirp:     twirp,
	})
}

func TestIsVerboseRequest_StaffWithHeader(t *testing.T) {
	handler := newHandlerWithTwirp(t, newStaffTwirpClient(exp.GHOrgID))
	ctx := context.Background()
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, "/", http.NoBody)
	req.Header.Set(staffVerboseHeader, "true")

	assert.True(t, handler.isVerboseRequest(ctx, req, 1, handler.obsv.Logger))
}

func TestIsVerboseRequest_NonStaffWithHeader(t *testing.T) {
	handler := newHandlerWithTwirp(t, newNonStaffTwirpClient())
	ctx := context.Background()
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, "/", http.NoBody)
	req.Header.Set(staffVerboseHeader, "true")

	assert.False(t, handler.isVerboseRequest(ctx, req, 1, handler.obsv.Logger))
}

func TestIsVerboseRequest_StaffWithoutHeader(t *testing.T) {
	handler := newHandlerWithTwirp(t, newStaffTwirpClient(exp.GHOrgID))
	ctx := context.Background()
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, "/", http.NoBody)

	assert.False(t, handler.isVerboseRequest(ctx, req, 1, handler.obsv.Logger))
}

func TestIsVerboseRequest_NoTwirpClient(t *testing.T) {
	handler := newHandlerWithTwirp(t, nil)
	ctx := context.Background()
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, "/", http.NoBody)
	req.Header.Set(staffVerboseHeader, "true")

	assert.False(t, handler.isVerboseRequest(ctx, req, 1, handler.obsv.Logger))
}

func TestIsVerboseRequest_HeaderWrongValue(t *testing.T) {
	handler := newHandlerWithTwirp(t, newStaffTwirpClient(exp.GHOrgID))
	ctx := context.Background()
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, "/", http.NoBody)
	req.Header.Set(staffVerboseHeader, "yes") // not "true"

	assert.False(t, handler.isVerboseRequest(ctx, req, 1, handler.obsv.Logger))
}

// --- Dev mode tests ---

func newDevModeHandler(t *testing.T) *MemoryHandler {
	t.Helper()
	return NewMemoryHandler(MemoryHandlerOpts{
		Service: &MockMemoryService{},
		GHFactory: &github.NoopClientFactory{
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{}, nil
			},
		},
		Obsv:          observability.NewNoopExporters(),
		AppProvider:   agenticapptest.NewTestProvider(t),
		GHTwirp:       nil, // no twirp client — staff check would fail
		IsDevelopment: true,
	})
}

func TestIsVerboseRequest_DevModeWithHeader(t *testing.T) {
	handler := newDevModeHandler(t)
	ctx := context.Background()
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, "/", http.NoBody)
	req.Header.Set(staffVerboseHeader, "true")

	assert.True(t, handler.isVerboseRequest(ctx, req, 1, handler.obsv.Logger))
}

func TestIsVerboseRequest_DevModeWithoutHeader(t *testing.T) {
	handler := newDevModeHandler(t)
	ctx := context.Background()
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, "/", http.NoBody)

	assert.False(t, handler.isVerboseRequest(ctx, req, 1, handler.obsv.Logger))
}

func TestIsVerboseRequest_DevModeSkipsStaffCheck(t *testing.T) {
	// Even with a non-staff twirp client, dev mode should return true
	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service: &MockMemoryService{},
		GHFactory: &github.NoopClientFactory{
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{}, nil
			},
		},
		Obsv:          observability.NewNoopExporters(),
		AppProvider:   agenticapptest.NewTestProvider(t),
		GHTwirp:       newNonStaffTwirpClient(),
		IsDevelopment: true,
	})
	ctx := context.Background()
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, "/", http.NoBody)
	req.Header.Set(staffVerboseHeader, "true")

	assert.True(t, handler.isVerboseRequest(ctx, req, 1, handler.obsv.Logger))
}

// --- Handler integration tests: verbose responses ---

func createStaffHandlerAndRouter(t *testing.T, mockService *MockMemoryService) (*MemoryHandler, *chi.Mux) {
	t.Helper()
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}
	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
		GHTwirp:     newStaffTwirpClient(exp.GHOrgID),
	})
	router := createTestRouter(handler)
	return handler, router
}

func createStaffUserHandlerAndRouter(t *testing.T, mockService *MockMemoryService) (*MemoryHandler, *chi.Mux) {
	t.Helper()
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}
	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
		GHTwirp:     newStaffTwirpClient(exp.GHOrgID),
	})
	router := createTestUserRouter(handler)
	return handler, router
}

func addStaffHeader(req *http.Request) {
	req.Header.Set(staffVerboseHeader, "true")
}

func TestHandleCreateMemory_VerboseStaffResponse(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return nil
		},
	}
	_, router := createStaffHandlerAndRouter(t, mockService)

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, "PUT", "/memory/v0/testuser/repo", marshalToJSON(t, createTestMemoryDTO()))
	addStaffHeader(req)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusCreated, rr.Code)

	var verbose VerboseMemoryDTO
	err := json.NewDecoder(rr.Body).Decode(&verbose)
	require.NoError(t, err)

	// Verbose fields should be present
	assert.NotZero(t, verbose.Score)
	require.NotEmpty(t, verbose.Votes)
	assert.False(t, verbose.CreatedAt.IsZero())
	assert.False(t, verbose.UpdatedAt.IsZero())
	assert.False(t, verbose.ExpiresAt.IsZero())

	// Base fields still populated
	assert.Equal(t, "1", verbose.ID)
	assert.Equal(t, "Test Subject", verbose.Subject)
}

func TestHandleCreateMemory_NonStaffWithHeaderGetsNormalResponse(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return nil
		},
	}
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}
	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
		GHTwirp:     newNonStaffTwirpClient(),
	})
	router := createTestRouter(handler)

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, "PUT", "/memory/v0/testuser/repo", marshalToJSON(t, createTestMemoryDTO()))
	addStaffHeader(req) // non-staff sends the header
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusCreated, rr.Code)

	// Should decode as normal MemoryDTO (no verbose fields)
	var raw map[string]json.RawMessage
	require.NoError(t, json.Unmarshal(rr.Body.Bytes(), &raw))
	_, hasScore := raw["score"]
	assert.False(t, hasScore, "non-staff response should not contain 'score'")
	_, hasVotes := raw["votes"]
	assert.False(t, hasVotes, "non-staff response should not contain 'votes'")
}

func TestHandleGetRecentMemories_VerboseStaffResponse(t *testing.T) {
	mockMemories := []*core.Memory{
		{
			ID:      core.MemoryID("m1"),
			Subject: "s1",
			Scope:   core.MemoryScopeRepository,
			Votes: []core.Vote{{
				Direction: core.UpVote,
				Timestamp: time.Now().UTC(),
				Source:    core.VoteSource{Agent: "a"},
			}},
		},
	}
	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return mockMemories, nil
		},
	}
	_, router := createStaffHandlerAndRouter(t, mockService)

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/recent", "")
	addStaffHeader(req)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result []VerboseMemoryDTO
	require.NoError(t, json.Unmarshal(rr.Body.Bytes(), &result))
	require.Len(t, result, 1)
	assert.Equal(t, "m1", result[0].ID)
	assert.Equal(t, "repository", result[0].Scope)
	require.Len(t, result[0].Votes, 1)
}

func TestHandleGetTopMemories_VerboseStaffResponse(t *testing.T) {
	mockMemories := []*core.Memory{
		{
			ID:    core.MemoryID("m1"),
			Scope: core.MemoryScopeRepository,
		},
	}
	mockService := &MockMemoryService{
		GetTopMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return mockMemories, nil
		},
	}
	_, router := createStaffHandlerAndRouter(t, mockService)

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/top", "")
	addStaffHeader(req)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result []VerboseMemoryDTO
	require.NoError(t, json.Unmarshal(rr.Body.Bytes(), &result))
	require.Len(t, result, 1)
	assert.Equal(t, "repository", result[0].Scope)
}

func TestHandleCreateUserMemory_VerboseStaffResponse(t *testing.T) {
	mockService := &MockMemoryService{
		CreateUserMemoryFunc: func(memory *core.Memory, user core.User) error {
			return nil
		},
	}
	_, router := createStaffUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/user", marshalToJSON(t, createTestMemoryDTO()))
	addStaffHeader(req)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusCreated, rr.Code)

	var verbose VerboseMemoryDTO
	require.NoError(t, json.NewDecoder(rr.Body).Decode(&verbose))
	assert.NotZero(t, verbose.Score)
	require.NotEmpty(t, verbose.Votes)
	assert.Equal(t, "1", verbose.ID)
}

func TestHandleGetRecentUserMemories_VerboseStaffResponse(t *testing.T) {
	mockMemories := []*core.Memory{
		{ID: core.MemoryID("u1"), Scope: core.MemoryScopeUser},
	}
	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return mockMemories, nil
		},
	}
	_, router := createStaffUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/user/recent", "")
	addStaffHeader(req)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result []VerboseMemoryDTO
	require.NoError(t, json.Unmarshal(rr.Body.Bytes(), &result))
	require.Len(t, result, 1)
	assert.Equal(t, "user", result[0].Scope)
}

func TestHandleGetTopUserMemories_VerboseStaffResponse(t *testing.T) {
	mockMemories := []*core.Memory{
		{ID: core.MemoryID("u1"), Scope: core.MemoryScopeUser},
	}
	mockService := &MockMemoryService{
		GetTopUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return mockMemories, nil
		},
	}
	_, router := createStaffUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/user/top", "")
	addStaffHeader(req)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result []VerboseMemoryDTO
	require.NoError(t, json.Unmarshal(rr.Body.Bytes(), &result))
	require.Len(t, result, 1)
	assert.Equal(t, "user", result[0].Scope)
}

func TestHandleGetRecentMemories_WithoutHeaderGetsNormalResponse(t *testing.T) {
	mockMemories := []*core.Memory{
		{ID: core.MemoryID("m1"), Subject: "s1"},
	}
	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return mockMemories, nil
		},
	}
	_, router := createStaffHandlerAndRouter(t, mockService)

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/recent", "")
	// No staff header
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var raw []map[string]json.RawMessage
	require.NoError(t, json.Unmarshal(rr.Body.Bytes(), &raw))
	require.Len(t, raw, 1)
	_, hasScore := raw[0]["score"]
	assert.False(t, hasScore, "non-verbose response should not contain 'score'")
}

func TestHandleGetRecentMemories_NonStaffWithHeaderGetsNormalResponse(t *testing.T) {
	mockMemories := []*core.Memory{
		{ID: core.MemoryID("m1"), Subject: "s1"},
	}
	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return mockMemories, nil
		},
	}
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}
	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
		GHTwirp:     newNonStaffTwirpClient(),
	})
	router := createTestRouter(handler)

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/recent", "")
	addStaffHeader(req)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var raw []map[string]json.RawMessage
	require.NoError(t, json.Unmarshal(rr.Body.Bytes(), &raw))
	require.Len(t, raw, 1)
	_, hasScore := raw[0]["score"]
	assert.False(t, hasScore, "non-staff response should not contain 'score'")
	_, hasVotes := raw[0]["votes"]
	assert.False(t, hasVotes, "non-staff response should not contain 'votes'")
}

func TestHandleGetTopMemories_NonStaffWithHeaderGetsNormalResponse(t *testing.T) {
	mockMemories := []*core.Memory{
		{ID: core.MemoryID("m1"), Subject: "s1"},
	}
	mockService := &MockMemoryService{
		GetTopMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return mockMemories, nil
		},
	}
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}
	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
		GHTwirp:     newNonStaffTwirpClient(),
	})
	router := createTestRouter(handler)

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/top", "")
	addStaffHeader(req)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var raw []map[string]json.RawMessage
	require.NoError(t, json.Unmarshal(rr.Body.Bytes(), &raw))
	require.Len(t, raw, 1)
	_, hasScore := raw[0]["score"]
	assert.False(t, hasScore, "non-staff response should not contain 'score'")
	_, hasVotes := raw[0]["votes"]
	assert.False(t, hasVotes, "non-staff response should not contain 'votes'")
}

func TestHandleGetRecentUserMemories_NonStaffWithHeaderGetsNormalResponse(t *testing.T) {
	mockMemories := []*core.Memory{
		{ID: core.MemoryID("u1"), Scope: core.MemoryScopeUser},
	}
	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return mockMemories, nil
		},
	}
	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service: mockService,
		Obsv:    observability.NewNoopExporters(),
		GHTwirp: newNonStaffTwirpClient(),
	})
	router := createTestUserRouter(handler)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/user/recent", "")
	addStaffHeader(req)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var raw []map[string]json.RawMessage
	require.NoError(t, json.Unmarshal(rr.Body.Bytes(), &raw))
	require.Len(t, raw, 1)
	_, hasScore := raw[0]["score"]
	assert.False(t, hasScore, "non-staff response should not contain 'score'")
	_, hasVotes := raw[0]["votes"]
	assert.False(t, hasVotes, "non-staff response should not contain 'votes'")
}

func TestHandleGetTopUserMemories_NonStaffWithHeaderGetsNormalResponse(t *testing.T) {
	mockMemories := []*core.Memory{
		{ID: core.MemoryID("u1"), Scope: core.MemoryScopeUser},
	}
	mockService := &MockMemoryService{
		GetTopUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return mockMemories, nil
		},
	}
	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service: mockService,
		Obsv:    observability.NewNoopExporters(),
		GHTwirp: newNonStaffTwirpClient(),
	})
	router := createTestUserRouter(handler)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/user/top", "")
	addStaffHeader(req)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var raw []map[string]json.RawMessage
	require.NoError(t, json.Unmarshal(rr.Body.Bytes(), &raw))
	require.Len(t, raw, 1)
	_, hasScore := raw[0]["score"]
	assert.False(t, hasScore, "non-staff response should not contain 'score'")
	_, hasVotes := raw[0]["votes"]
	assert.False(t, hasVotes, "non-staff response should not contain 'votes'")
}
