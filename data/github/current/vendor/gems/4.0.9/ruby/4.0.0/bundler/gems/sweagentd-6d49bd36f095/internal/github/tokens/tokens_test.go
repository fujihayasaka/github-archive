package tokens

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/sweagentd"
	twirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

// Mock implementations for testing

type mockAgenticApp struct{}

func (m *mockAgenticApp) AppID() int64                 { return 1 }
func (m *mockAgenticApp) AppName() string              { return "Copilot cloud agent" }
func (m *mockAgenticApp) WorkflowRunName(_ int) string { return "" }
func (m *mockAgenticApp) MentionableSlug() string      { return "copilot" }
func (m *mockAgenticApp) ComputeSlug() string          { return "copilot" }
func (m *mockAgenticApp) EngineSlug() string           { return m.ComputeSlug() }
func (m *mockAgenticApp) BranchPrefix() string         { return "copilot" }
func (m *mockAgenticApp) BotID() int64                 { return 2 }
func (m *mockAgenticApp) BotLogin() string             { return "bot-login" }
func (m *mockAgenticApp) CommitLogin() string          { return "commit-login" }
func (m *mockAgenticApp) CommitEmail() string          { return "commit@email.com" }
func (m *mockAgenticApp) RevokeToken(ctx context.Context, api sweagentd.GitHubAPI, token string) error {
	return nil
}
func (m *mockAgenticApp) ModelVendors() []string                    { return nil }
func (m *mockAgenticApp) SetupCompute(compute sweagentd.ComputeEnv) {}

func (m *mockAgenticApp) HasSource() bool                     { return false }
func (m *mockAgenticApp) SourceURL() string                   { return "" }
func (m *mockAgenticApp) AgentSource() *sweagentd.AgentSource { return nil }
func (m *mockAgenticApp) IsGlobalApp() bool                   { return false }
func (m *mockAgenticApp) IsPartnerApp() bool                  { return false }
func (m *mockAgenticApp) IsThirdPartyApp() bool               { return true }
func (m *mockAgenticApp) Metadata() map[string]string         { return nil }

type mockUserTokenMinter struct {
	shouldReturnError       bool
	shouldReturnNilResponse bool
	shouldReturnEmptyToken  bool
	errorToReturn           error
	tokenToReturn           string
}

func (m *mockUserTokenMinter) MintUserToServerTokenForRepo(ctx context.Context, req *twirp.MintUserToServerTokenForRepoRequest) (*twirp.MintUserToServerTokenForRepoResponse, error) {
	if m.shouldReturnError {
		return nil, m.errorToReturn
	}

	if m.shouldReturnNilResponse {
		return nil, nil
	}

	token := m.tokenToReturn
	if m.shouldReturnEmptyToken {
		token = ""
	}

	return &twirp.MintUserToServerTokenForRepoResponse{
		Token: token,
	}, nil
}

type ttActorWithRepository struct {
	userID int64
	repoID int64
}

func (t ttActorWithRepository) GetRepositoryID() int64 { return t.repoID }
func (t ttActorWithRepository) GetActorID() int64      { return t.userID }

func TestGetUserToServerToken(t *testing.T) {
	t.Run("successful token retrieval", func(t *testing.T) {
		ctx := NewContext(context.Background())
		target := sweagentd.ClientTargetForUser(0, 123)

		minter := &mockUserTokenMinter{
			tokenToReturn: "user-server-token",
		}
		token, err := GetUserToServerToken(ctx, target, 1, minter, &ttActorWithRepository{123, 456})

		if err != nil {
			t.Errorf("Unexpected error: %v", err)
		}

		if token != "user-server-token" {
			t.Errorf("Expected token 'user-server-token', got '%s'", token)
		}
	})

	t.Run("with cached token", func(t *testing.T) {
		ctx := NewContext(context.Background())
		target := sweagentd.ClientTargetForUser(0, 123)

		// Pre-populate cache
		setUserTokenInContext(ctx, target, 456, "cached-user-token")

		minter := &mockUserTokenMinter{
			tokenToReturn: "should-not-be-returned",
		}

		token, err := GetUserToServerToken(ctx, target, 1, minter, &ttActorWithRepository{123, 456})

		if err != nil {
			t.Errorf("Unexpected error: %v", err)
		}

		if token != "cached-user-token" {
			t.Errorf("Expected cached token 'cached-user-token', got '%s'", token)
		}
	})

	t.Run("API error", func(t *testing.T) {
		ctx := NewContext(context.Background())
		target := sweagentd.ClientTargetForUser(0, 123)

		minter := &mockUserTokenMinter{
			shouldReturnError: true,
			errorToReturn:     errors.New("API error"),
		}

		token, err := GetUserToServerToken(ctx, target, 1, minter, &ttActorWithRepository{123, 456})

		if err == nil {
			t.Error("Expected error when API returns error")
		}

		if token != "" {
			t.Error("Expected empty token when API returns error")
		}

		expectedError := "failed to mint user to server token for repo: API error"
		if err.Error() != expectedError {
			t.Errorf("Expected error '%s', got '%s'", expectedError, err.Error())
		}
	})

	t.Run("nil response", func(t *testing.T) {
		ctx := NewContext(context.Background())
		target := sweagentd.ClientTargetForUser(0, 123)

		minter := &mockUserTokenMinter{
			shouldReturnNilResponse: true,
		}

		token, err := GetUserToServerToken(ctx, target, 1, minter, &ttActorWithRepository{123, 456})

		if err == nil {
			t.Error("Expected error when API returns nil response")
		}

		if token != "" {
			t.Error("Expected empty token when API returns nil response")
		}

		expectedError := "failed to mint user to server token for repo. token is invalid or empty"
		if err.Error() != expectedError {
			t.Errorf("Expected error '%s', got '%s'", expectedError, err.Error())
		}
	})

	t.Run("empty token", func(t *testing.T) {
		ctx := NewContext(context.Background())
		target := sweagentd.ClientTargetForUser(0, 123)

		minter := &mockUserTokenMinter{
			shouldReturnEmptyToken: true,
		}

		token, err := GetUserToServerToken(ctx, target, 1, minter, &ttActorWithRepository{123, 456})

		if err == nil {
			t.Error("Expected error when API returns empty token")
		}

		if token != "" {
			t.Error("Expected empty token when API returns empty token")
		}

		expectedError := "failed to mint user to server token for repo. token is invalid or empty"
		if err.Error() != expectedError {
			t.Errorf("Expected error '%s', got '%s'", expectedError, err.Error())
		}
	})
}

func TestGlobalTokenRequest(t *testing.T) {
	t.Run("create request by ID", func(t *testing.T) {
		req := globalTokenRequest{
			TargetID:      123,
			RepositoryIDs: []int64{456},
		}

		if req.TargetID != 123 {
			t.Errorf("Expected TargetID 123, got %d", req.TargetID)
		}

		if len(req.RepositoryIDs) != 1 || req.RepositoryIDs[0] != 456 {
			t.Errorf("Expected RepositoryIDs [456], got %v", req.RepositoryIDs)
		}

		if req.Target != "" {
			t.Errorf("Expected empty Target, got '%s'", req.Target)
		}

		if len(req.Repositories) != 0 {
			t.Errorf("Expected empty Repositories, got %v", req.Repositories)
		}
	})

	t.Run("create request by name", func(t *testing.T) {
		req := globalTokenRequest{
			Target:       "owner",
			Repositories: []string{"repo"},
		}

		if req.Target != "owner" {
			t.Errorf("Expected Target 'owner', got '%s'", req.Target)
		}

		if len(req.Repositories) != 1 || req.Repositories[0] != "repo" {
			t.Errorf("Expected Repositories [repo], got %v", req.Repositories)
		}

		if req.TargetID != 0 {
			t.Errorf("Expected TargetID 0, got %d", req.TargetID)
		}

		if len(req.RepositoryIDs) != 0 {
			t.Errorf("Expected empty RepositoryIDs, got %v", req.RepositoryIDs)
		}
	})
}

// Integration tests that test the caching behavior

func TestIntegrationTokenCaching(t *testing.T) {
	t.Run("user token caching", func(t *testing.T) {
		ctx := NewContext(context.Background())
		target := sweagentd.ClientTargetForUser(0, 123)

		// First, manually set a token in cache
		setUserTokenInContext(ctx, target, 456, "cached-user-token")

		// Create a mock that would return a different token
		minter := &mockUserTokenMinter{
			tokenToReturn: "new-token-should-not-be-used",
		}

		// Call the function - should return cached token
		token, err := GetUserToServerToken(ctx, target, 1, minter, &ttActorWithRepository{123, 456})

		if err != nil {
			t.Errorf("Unexpected error: %v", err)
		}

		if token != "cached-user-token" {
			t.Errorf("Expected cached token 'cached-user-token', got '%s'", token)
		}
	})
}

// Benchmark tests to ensure caching provides performance benefits

func BenchmarkGetUserTokenFromContext(b *testing.B) {
	ctx := context.Background()
	ctx = NewContext(ctx)
	target := sweagentd.ClientTargetForUser(0, 123)

	setUserTokenInContext(ctx, target, 456, "benchmark-user-token")

	b.ResetTimer()
	for b.Loop() {
		_ = getUserTokenFromContext(ctx, target, 456)
	}
}

type mockServerTokenMinter struct {
	token string
	err   error
	// captures the last request for assertions
	lastReq *twirp.MintServerToServerTokenForRepoRequest
}

func (m *mockServerTokenMinter) MintServerToServerTokenForRepo(ctx context.Context, req *twirp.MintServerToServerTokenForRepoRequest) (*twirp.MintServerToServerTokenForRepoResponse, error) {
	m.lastReq = req
	if m.err != nil {
		return nil, m.err
	}
	if m.token == "" {
		return &twirp.MintServerToServerTokenForRepoResponse{}, nil
	}
	return &twirp.MintServerToServerTokenForRepoResponse{Token: m.token}, nil
}

type mockRepoResolver struct {
	repoID int64
	err    error
}

func (m *mockRepoResolver) GetRepoByName(ctx context.Context, owner, name string) (int64, error) {
	if m.err != nil {
		return 0, m.err
	}
	return m.repoID, nil
}

type mockCache struct {
	store map[string]string
}

func newMockCache() *mockCache {
	return &mockCache{store: make(map[string]string)}
}

func (c *mockCache) Get(key string) (string, error) {
	if v, ok := c.store[key]; ok {
		return v, nil
	}
	return "", errors.New("cache miss")
}

func (c *mockCache) Set(key, token string, expiresAt time.Time) error {
	c.store[key] = token
	return nil
}

func (c *mockCache) Delete(key string) error {
	delete(c.store, key)
	return nil
}

type ttRepository struct {
	repoID  int64
	ownerID int64
}

func (r *ttRepository) GetRepositoryID() int64 { return r.repoID }
func (r *ttRepository) GetOwnerID() int64      { return r.ownerID }

func TestGetServerToServerTokenByRepoID(t *testing.T) {
	t.Run("successful token minting", func(t *testing.T) {
		ctx := NewContext(context.Background())
		minter := &mockServerTokenMinter{token: "twirp-token-123"}
		app := &mockAgenticApp{}
		target := sweagentd.ClientTargetForInstallationByOwnerID(1, 123)

		token, err := GetServerToServerTokenByRepoID(ctx, target, minter, app, 456, 123, &NoopCache{})

		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if token != "twirp-token-123" {
			t.Errorf("expected token 'twirp-token-123', got '%s'", token)
		}
		if minter.lastReq.RepositoryId != 456 {
			t.Errorf("expected repository_id 456, got %d", minter.lastReq.RepositoryId)
		}
		if minter.lastReq.AgentId != 1 {
			t.Errorf("expected agent_id 1, got %d", minter.lastReq.AgentId)
		}
	})

	t.Run("minting error", func(t *testing.T) {
		ctx := NewContext(context.Background())
		minter := &mockServerTokenMinter{err: errors.New("connection failed")}
		app := &mockAgenticApp{}
		target := sweagentd.ClientTargetForInstallationByOwnerID(1, 123)

		token, err := GetServerToServerTokenByRepoID(ctx, target, minter, app, 456, 123, &NoopCache{})

		if err == nil {
			t.Fatal("expected error")
		}
		if token != "" {
			t.Errorf("expected empty token, got '%s'", token)
		}
	})

	t.Run("empty token response", func(t *testing.T) {
		ctx := NewContext(context.Background())
		minter := &mockServerTokenMinter{token: ""}
		app := &mockAgenticApp{}
		target := sweagentd.ClientTargetForInstallationByOwnerID(1, 123)

		token, err := GetServerToServerTokenByRepoID(ctx, target, minter, app, 456, 123, &NoopCache{})

		if err == nil {
			t.Fatal("expected error for empty token")
		}
		if token != "" {
			t.Errorf("expected empty token, got '%s'", token)
		}
	})

	t.Run("redis-cached token", func(t *testing.T) {
		ctx := NewContext(context.Background())
		target := sweagentd.ClientTargetForInstallationByOwnerID(1, 123)
		cache := newMockCache()
		cacheKey := makeGlobalTokenCacheKey(target, globalTokenRequest{
			TargetID:      123,
			RepositoryIDs: []int64{456},
		})
		cache.store[cacheKey] = "redis-cached-token"

		minter := &mockServerTokenMinter{token: "should-not-be-used"}
		app := &mockAgenticApp{}

		token, err := GetServerToServerTokenByRepoID(ctx, target, minter, app, 456, 123, cache)

		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if token != "redis-cached-token" {
			t.Errorf("expected cached token 'redis-cached-token', got '%s'", token)
		}
		if minter.lastReq != nil {
			t.Error("minter should not have been called when token was cached")
		}
	})

	t.Run("sets redis cache after minting", func(t *testing.T) {
		ctx := NewContext(context.Background())
		target := sweagentd.ClientTargetForInstallationByOwnerID(1, 123)
		cache := newMockCache()
		minter := &mockServerTokenMinter{token: "new-token"}
		app := &mockAgenticApp{}

		token, err := GetServerToServerTokenByRepoID(ctx, target, minter, app, 456, 123, cache)

		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if token != "new-token" {
			t.Errorf("expected 'new-token', got '%s'", token)
		}
		cacheKey := makeGlobalTokenCacheKey(target, globalTokenRequest{
			TargetID:      123,
			RepositoryIDs: []int64{456},
		})
		if cached, ok := cache.store[cacheKey]; !ok || cached != "new-token" {
			t.Errorf("expected token to be cached, got '%s'", cached)
		}
	})
}

func TestGetServerToServerTokenByRepo(t *testing.T) {
	t.Run("successful token minting", func(t *testing.T) {
		ctx := NewContext(context.Background())
		minter := &mockServerTokenMinter{token: "repo-twirp-token"}
		app := &mockAgenticApp{}
		target := sweagentd.ClientTargetForInstallationByOwnerID(1, 100)
		repo := &ttRepository{repoID: 200, ownerID: 100}

		token, err := GetServerToServerTokenByRepo(ctx, target, minter, app, repo, &NoopCache{})

		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if token != "repo-twirp-token" {
			t.Errorf("expected 'repo-twirp-token', got '%s'", token)
		}
		if minter.lastReq.RepositoryId != 200 {
			t.Errorf("expected repository_id 200, got %d", minter.lastReq.RepositoryId)
		}
	})
}

// mockOrgBillableJob implements OrgBillableJob for testing GetTokenForJob.
type mockOrgBillableJob struct {
	actorID int64
	repoID  int64
	ownerID int64
	billOrg bool
}

func (m *mockOrgBillableJob) GetActorID() int64      { return m.actorID }
func (m *mockOrgBillableJob) GetRepositoryID() int64 { return m.repoID }
func (m *mockOrgBillableJob) GetOwnerID() int64      { return m.ownerID }
func (m *mockOrgBillableJob) IsBillToOrg() bool      { return m.billOrg }

func TestGetTokenForJob(t *testing.T) {
	tests := []struct {
		name          string
		billToOrg     bool
		userToken     string
		s2sToken      string
		expectedToken string
	}{
		{
			name:          "user-billed job uses user-to-server token",
			billToOrg:     false,
			userToken:     "user-token-abc",
			s2sToken:      "s2s-should-not-be-used",
			expectedToken: "user-token-abc",
		},
		{
			name:          "org-billed job uses server-to-server token",
			billToOrg:     true,
			userToken:     "user-should-not-be-used",
			s2sToken:      "s2s-token-xyz",
			expectedToken: "s2s-token-xyz",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := NewContext(context.Background())
			app := &mockAgenticApp{}

			userMinter := &mockUserTokenMinter{tokenToReturn: tt.userToken}
			s2sMinter := &mockServerTokenMinter{token: tt.s2sToken}

			job := &mockOrgBillableJob{
				actorID: 42,
				repoID:  456,
				ownerID: 100,
				billOrg: tt.billToOrg,
			}

			var target sweagentd.ClientTarget
			if tt.billToOrg {
				target = sweagentd.ClientTargetForInstallationByOwnerID(1, job.ownerID)
			} else {
				target = sweagentd.ClientTargetForUser(1, job.actorID)
			}

			token, err := GetTokenForJob(ctx, target, 1, userMinter, s2sMinter, app, job, &NoopCache{})

			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if token != tt.expectedToken {
				t.Errorf("expected token '%s', got '%s'", tt.expectedToken, token)
			}
		})
	}
}

func (m *mockAgenticApp) IsQuotaExempt() bool   { return false }
func (m *mockAgenticApp) UsesExperiments() bool { return true }
