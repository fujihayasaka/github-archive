package memoryhttp

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"testing"

	authd "github.com/github/authnd/client"
	coreTwirp "github.com/github/copilot-api/proto/twirp/core/v1"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestHandleCreateMemory tests the HandleCreateMemory method of MemoryHandler.
func TestHandleCreateMemory(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			if memory == nil {
				return errors.New("memory cannot be nil")
			}
			return nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)
	memoryDTO := createTestMemoryDTO()

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/testuser/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	if status := rr.Code; status != http.StatusCreated {
		t.Errorf("expected status %d, got %d", http.StatusCreated, status)
	}

	// Verify response is MemoryDTO
	var responseDTO MemoryDTO
	err := json.NewDecoder(rr.Body).Decode(&responseDTO)
	require.NoError(t, err)
	assert.Equal(t, memoryDTO.ID, responseDTO.ID)
	assert.Equal(t, memoryDTO.Subject, responseDTO.Subject)
}

// TestHandleInvalidCreateMemory tests the HandleCreateMemory method with invalid input.
func TestHandleInvalidCreateMemory(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return errors.New("invalid memory data")
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/test/repo", "invalid json")
	rr := executeRequestAndRecord(router, req)

	if status := rr.Code; status != http.StatusBadRequest {
		t.Errorf("expected status %d, got %d", http.StatusBadRequest, status)
	}
}

// TestHandleCreateMemory_MissingCitations tests that a DTO with no citations is rejected.
func TestHandleCreateMemory_MissingCitations(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			t.Fatal("service should not be called for invalid DTO")
			return nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)
	memoryDTO := &MemoryDTO{
		ID:      "1",
		Subject: "Test Subject",
		Fact:    "Test Fact",
		Reason:  "Test Reason",
		Source: MemorySourceDTO{
			InteractionID: "interaction1",
			Agent:         "test-agent",
		},
	}

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/testuser/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "citations cannot be empty")
}

// TestHandleCreateMemory_AllEmptyCitations tests that a DTO with all-empty citations is rejected.
func TestHandleCreateMemory_AllEmptyCitations(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			t.Fatal("service should not be called for invalid DTO")
			return nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)
	memoryDTO := &MemoryDTO{
		ID:        "1",
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Reason:    "Test Reason",
		Citations: []string{"", "  "},
		Source: MemorySourceDTO{
			InteractionID: "interaction1",
			Agent:         "test-agent",
		},
	}

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/testuser/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "citations must not all be empty strings")
}

// TestUnexpectedError tests the error handling in MemoryHandler.
func TestUnexpectedError(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return errors.New("unexpected error")
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)
	memoryDTO := createTestMemoryDTO()

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/testuser/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusInternalServerError, rr.Code)
	// Unknown errors return a generic message to avoid leaking internal details
	assert.Equal(t, "An internal error occurred\n", rr.Body.String())
}

// TestCreateMemoryUnauthorizedNoUserInfo tests CreateMemory when no user info is in context.
func TestCreateMemoryUnauthorizedNoUserInfo(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return nil
		},
	}

	_, router := createTestHandlerAndRouterWithInternal(t, mockService)
	memoryDTO := createTestMemoryDTO()

	// Create context without user information
	ctx := context.Background()
	req := createTestRequest(ctx, "PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusUnauthorized, rr.Code)
	assert.Contains(t, rr.Body.String(), http.StatusText(http.StatusUnauthorized))
}

// TestCreateMemoryUnauthorizedInsufficientPermissions tests CreateMemory when user lacks push permissions.
func TestCreateMemoryUnauthorizedInsufficientPermissions(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return nil
		},
	}

	// Create a mock GitHub factory that returns a client with insufficient permissions
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
	})
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()

	// Create context with a user that has no push permissions (using -read suffix)
	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser-read", // This suffix gives only read permissions
			TrackingID: "tracking-id",
		},
	})
	req := createTestRequest(ctx, "PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusForbidden, rr.Code)
	assert.Contains(t, rr.Body.String(), "You don't have write access to this repository")
}

// TestCreateMemoryUnauthorizedGitHubError tests CreateMemory when GitHub client creation fails.
func TestCreateMemoryUnauthorizedGitHubError(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return nil
		},
	}

	// Create a mock GitHub factory that returns an error when creating client
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return nil, errors.New("failed to create GitHub client")
		},
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
	})
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()

	// Use a context without a token so the user-token fallback also fails.
	ctx := createTestContextWithoutToken()
	req := createTestRequest(ctx, "PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Could not verify access to this repository")
}

// TestCreateMemoryFallbackToUserToken tests that CreateMemory falls back to user token
// when the Copilot app installation is not found on the repository.
func TestCreateMemoryFallbackToUserToken(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return nil
		},
	}

	// Create a mock GitHub factory that:
	// 1. Fails NewClientFromRepoName (simulating app not installed)
	// 2. Returns a working client for NewClientForUser (user token fallback)
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return nil, errors.New("installation not found for repository")
		},
		// NewClientForUser uses the default implementation which returns a NoopClient
	}

	// Configure the Twirp client to grant access, so the token access check is exercised
	var capturedActions []string
	mockTwirp := githubtwirp.NewNoopClient()
	mockTwirp.NoopAuthorizationAPI.MockBatchControlAccess = func(ctx context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error) {
		decisions := make([]*coreTwirp.AuthorizationDecision, len(req.AuthorizationRequests))
		for i, authReq := range req.AuthorizationRequests {
			capturedActions = append(capturedActions, authReq.Action)
			decisions[i] = &coreTwirp.AuthorizationDecision{
				Id:       authReq.Id,
				Decision: true, // Grant access
			}
		}
		return &coreTwirp.BatchControlAccessResponse{Decisions: decisions}, nil
	}

	mockPrivilegedAppChecker := &github.MockPrivilegedAppChecker{
		MockHasCapabilityResult: false,
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:              mockService,
		GHFactory:            mockGHFactory,
		Obsv:                 observability.NewNoopExporters(),
		AppProvider:          agenticapptest.NewTestProvider(t),
		GHTwirp:              mockTwirp,
		PrivilegedAppChecker: mockPrivilegedAppChecker,
	})
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()

	// Create context with user that has a token (this enables fallback)
	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser",
			TrackingID: "tracking-id",
			TokenInfo: &requestctx.TokenInfo{
				Token: "user-token-123",
			},
		},
	})
	req := createTestRequest(ctx, "PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	// Should succeed because we fell back to user token
	assert.Equal(t, http.StatusCreated, rr.Code)

	var responseDTO MemoryDTO
	err := json.NewDecoder(rr.Body).Decode(&responseDTO)
	require.NoError(t, err)
	assert.Equal(t, memoryDTO.ID, responseDTO.ID)

	// Verify the token access check requested "push" actions for a write operation
	assert.Equal(t, []string{"push"}, capturedActions)
}

// TestCreateMemoryFallbackFailsNoUserToken tests that CreateMemory fails when
// the Copilot app installation is not found and the user has no token to fall back to.
func TestCreateMemoryFallbackFailsNoUserToken(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return nil
		},
	}

	// Create a mock GitHub factory that fails NewClientFromRepoName (simulating app not installed)
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return nil, errors.New("installation not found for repository")
		},
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
	})
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()

	// Create context with user that has NO token (fallback will fail)
	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser",
			TrackingID: "tracking-id",
			TokenInfo:  nil, // No token available for fallback
		},
	})
	req := createTestRequest(ctx, "PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	// Should fail with 404 because app installation failed and no user token fallback available
	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Could not verify access to this repository")
}

// TestCreateMemoryWithSecrets tests CreateMemory when the memory contains secrets.
func TestCreateMemoryWithSecrets(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return core.ErrMemoryContainsSecrets
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)
	memoryDTO := createTestMemoryDTO()

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/testuser/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "Memory contains secrets and cannot be saved")
}

// TestCreateMemoryPermissionMatrix verifies create memory authorization across roles.
func TestCreateMemoryPermissionMatrix(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return nil
		},
	}

	// Factory returning our custom client.
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &CustomPermsClient{&github.NoopClient{}}, nil
		},
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
	})
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()
	body := marshalToJSON(t, memoryDTO)

	testCases := []struct {
		login       string
		expectCode  int
		shouldPass  bool
		description string
	}{
		{"matrix-read", http.StatusForbidden, false, "read-only user should fail (no push/admin/maintain)"},
		{"matrix-push", http.StatusCreated, true, "push user succeeds"},
		{"matrix-admin", http.StatusCreated, true, "admin user succeeds"},
		{"matrix-maintain", http.StatusCreated, true, "maintain user succeeds"},
	}

	for _, tc := range testCases {
		t.Run(tc.description, func(t *testing.T) {
			ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
				UserInfo: &requestctx.UserInfo{
					ID:         42,
					Login:      tc.login,
					TrackingID: "tracking-id",
				},
			})

			req := createTestRequest(ctx, "PUT", fmt.Sprintf("/internal/memory/v0/%s/repo", tc.login), body)
			rr := executeRequestAndRecord(router, req)

			assert.Equal(t, tc.expectCode, rr.Code)

			if tc.shouldPass {
				var resp MemoryDTO
				err := json.NewDecoder(rr.Body).Decode(&resp)
				require.NoError(t, err)
				assert.Equal(t, memoryDTO.ID, resp.ID)
			}
		})
	}
}

// TestCreateMemoryTokenAccessDenied tests that CreateMemory returns 404 when
// the user's token does not have access to the repository.
func TestCreateMemoryTokenAccessDenied(t *testing.T) {
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

	// Configure the Twirp client to deny access and capture the requested actions
	var capturedActions []string
	mockTwirp := githubtwirp.NewNoopClient()
	mockTwirp.NoopAuthorizationAPI.MockBatchControlAccess = func(ctx context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error) {
		decisions := make([]*coreTwirp.AuthorizationDecision, len(req.AuthorizationRequests))
		for i, authReq := range req.AuthorizationRequests {
			capturedActions = append(capturedActions, authReq.Action)
			decisions[i] = &coreTwirp.AuthorizationDecision{
				Id:       authReq.Id,
				Decision: false, // Deny access
			}
		}
		return &coreTwirp.BatchControlAccessResponse{Decisions: decisions}, nil
	}

	// Use a non-privileged app checker to exercise the full token access code path
	mockPrivilegedAppChecker := &github.MockPrivilegedAppChecker{
		MockHasCapabilityResult: false,
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:              mockService,
		GHFactory:            mockGHFactory,
		Obsv:                 observability.NewNoopExporters(),
		AppProvider:          agenticapptest.NewTestProvider(t),
		GHTwirp:              mockTwirp,
		PrivilegedAppChecker: mockPrivilegedAppChecker,
	})
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()

	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser",
			TrackingID: "tracking-id",
			TokenInfo: &requestctx.TokenInfo{
				Token: "user-token-123",
			},
		},
	})
	req := createTestRequest(ctx, "PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Could not verify access to this repository")
	// Verify the token access check requested "push" actions for a write operation
	assert.Equal(t, []string{"push"}, capturedActions)
}

// TestCreateMemoryTokenAccessGranted tests that CreateMemory succeeds when
// the user's token has access to the repository.
func TestCreateMemoryTokenAccessGranted(t *testing.T) {
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

	// Configure the Twirp client to grant access and capture the requested actions
	var capturedActions []string
	mockTwirp := githubtwirp.NewNoopClient()
	mockTwirp.NoopAuthorizationAPI.MockBatchControlAccess = func(ctx context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error) {
		decisions := make([]*coreTwirp.AuthorizationDecision, len(req.AuthorizationRequests))
		for i, authReq := range req.AuthorizationRequests {
			capturedActions = append(capturedActions, authReq.Action)
			decisions[i] = &coreTwirp.AuthorizationDecision{
				Id:       authReq.Id,
				Decision: true, // Grant access
			}
		}
		return &coreTwirp.BatchControlAccessResponse{Decisions: decisions}, nil
	}

	// Use a non-privileged app checker to exercise the full token access code path
	mockPrivilegedAppChecker := &github.MockPrivilegedAppChecker{
		MockHasCapabilityResult: false,
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:              mockService,
		GHFactory:            mockGHFactory,
		Obsv:                 observability.NewNoopExporters(),
		AppProvider:          agenticapptest.NewTestProvider(t),
		GHTwirp:              mockTwirp,
		PrivilegedAppChecker: mockPrivilegedAppChecker,
	})
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()

	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser",
			TrackingID: "tracking-id",
			TokenInfo: &requestctx.TokenInfo{
				Token: "user-token-123",
			},
		},
	})
	req := createTestRequest(ctx, "PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusCreated, rr.Code)

	var responseDTO MemoryDTO
	err := json.NewDecoder(rr.Body).Decode(&responseDTO)
	require.NoError(t, err)
	assert.Equal(t, memoryDTO.ID, responseDTO.ID)
	// Verify the token access check requested "push" actions for a write operation
	assert.Equal(t, []string{"push"}, capturedActions)
}

// TestCreateMemoryTokenAccessError tests that CreateMemory returns 404 when
// the token access check encounters an error.
func TestCreateMemoryTokenAccessError(t *testing.T) {
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

	// Configure the Twirp client to return an error
	mockTwirp := githubtwirp.NewNoopClient()
	mockTwirp.NoopAuthorizationAPI.MockBatchControlAccess = func(ctx context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error) {
		return nil, errors.New("authorization service unavailable")
	}

	// Use a non-privileged app checker to exercise the full token access code path
	mockPrivilegedAppChecker := &github.MockPrivilegedAppChecker{
		MockHasCapabilityResult: false,
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:              mockService,
		GHFactory:            mockGHFactory,
		Obsv:                 observability.NewNoopExporters(),
		AppProvider:          agenticapptest.NewTestProvider(t),
		GHTwirp:              mockTwirp,
		PrivilegedAppChecker: mockPrivilegedAppChecker,
	})
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()

	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser",
			TrackingID: "tracking-id",
			TokenInfo: &requestctx.TokenInfo{
				Token: "user-token-123",
			},
		},
	})
	req := createTestRequest(ctx, "PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Could not verify access to this repository")
}

// TestCreateMemoryTokenAccessDeniedWithoutToken tests that the token access check
// denies access when the user has no token, since access cannot be verified.
func TestCreateMemoryTokenAccessDeniedWithoutToken(t *testing.T) {
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

	// Configure the Twirp client to deny access - but it shouldn't be called since there's no token
	mockTwirp := githubtwirp.NewNoopClient()
	mockTwirp.NoopAuthorizationAPI.MockBatchControlAccess = func(ctx context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error) {
		t.Fatal("TokenHasAccess should not be called when user has no token")
		return nil, nil
	}

	// Use a non-privileged app checker to exercise the full token access code path;
	// it should not be invoked since the token-nil check short-circuits first.
	mockPrivilegedAppChecker := &github.MockPrivilegedAppChecker{
		MockHasCapabilityResult: false,
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:              mockService,
		GHFactory:            mockGHFactory,
		Obsv:                 observability.NewNoopExporters(),
		AppProvider:          agenticapptest.NewTestProvider(t),
		GHTwirp:              mockTwirp,
		PrivilegedAppChecker: mockPrivilegedAppChecker,
	})
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()

	// User without a token - should be denied since we cannot verify token access
	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser",
			TrackingID: "tracking-id",
			TokenInfo:  nil,
		},
	})
	req := createTestRequest(ctx, "PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	// Should be denied because we cannot verify access without a token
	assert.Equal(t, http.StatusNotFound, rr.Code)
}

// TestCreateMemoryPrivilegedAppTokenRelaxesAccessActions tests that a User-to-Server token
// from a privileged app has its required access actions relaxed to "pull" only,
// allowing the request to succeed even when the token would not pass a "push" check.
func TestCreateMemoryPrivilegedAppTokenRelaxesAccessActions(t *testing.T) {
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

	// Configure the Twirp client to grant access only for "pull" actions,
	// denying "push" actions. This simulates a U2S token that has pull but not push.
	var capturedActions []string
	mockTwirp := githubtwirp.NewNoopClient()
	mockTwirp.NoopAuthorizationAPI.MockBatchControlAccess = func(ctx context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error) {
		decisions := make([]*coreTwirp.AuthorizationDecision, len(req.AuthorizationRequests))
		for i, authReq := range req.AuthorizationRequests {
			capturedActions = append(capturedActions, authReq.Action)
			// Only grant access for "pull" actions
			decisions[i] = &coreTwirp.AuthorizationDecision{
				Id:       authReq.Id,
				Decision: authReq.Action == "pull",
			}
		}
		return &coreTwirp.BatchControlAccessResponse{Decisions: decisions}, nil
	}

	mockPrivilegedAppChecker := &github.MockPrivilegedAppChecker{
		MockHasCapabilityResult: true,
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:              mockService,
		GHFactory:            mockGHFactory,
		Obsv:                 observability.NewNoopExporters(),
		AppProvider:          agenticapptest.NewTestProvider(t),
		GHTwirp:              mockTwirp,
		PrivilegedAppChecker: mockPrivilegedAppChecker,
	})
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()

	// User-to-Server token from a privileged app
	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser",
			TrackingID: "tracking-id",
			TokenInfo: &requestctx.TokenInfo{
				Token:           "user-token-123",
				Type:            string(authd.CredentialTypeUserToServerToken),
				ApplicationID:   12345,
				ApplicationType: "GithubApplication",
			},
		},
	})
	req := createTestRequest(ctx, "PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	// Should succeed because the privileged app check relaxes "push" to "pull"
	// and the user has pull access
	assert.Equal(t, http.StatusCreated, rr.Code)
	// Verify that the privileged relaxation replaced "push" with "pull"
	assert.Equal(t, []string{"pull"}, capturedActions, "privileged app should relax write actions to pull-only")
}

// TestCreateMemoryNonPrivilegedAppTokenDeniedForPush tests that a User-to-Server token
// from a non-privileged app is NOT relaxed, so a token that only has "pull" access
// is denied for write operations that require "push".
func TestCreateMemoryNonPrivilegedAppTokenDeniedForPush(t *testing.T) {
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

	// Configure the Twirp client to deny "push" actions and capture the requested actions
	var capturedActions []string
	mockTwirp := githubtwirp.NewNoopClient()
	mockTwirp.NoopAuthorizationAPI.MockBatchControlAccess = func(ctx context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error) {
		decisions := make([]*coreTwirp.AuthorizationDecision, len(req.AuthorizationRequests))
		for i, authReq := range req.AuthorizationRequests {
			capturedActions = append(capturedActions, authReq.Action)
			// Only grant access for "pull" actions, deny "push"
			decisions[i] = &coreTwirp.AuthorizationDecision{
				Id:       authReq.Id,
				Decision: authReq.Action == "pull",
			}
		}
		return &coreTwirp.BatchControlAccessResponse{Decisions: decisions}, nil
	}

	// Non-privileged app — should NOT relax access actions
	mockPrivilegedAppChecker := &github.MockPrivilegedAppChecker{
		MockHasCapabilityResult: false,
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:              mockService,
		GHFactory:            mockGHFactory,
		Obsv:                 observability.NewNoopExporters(),
		AppProvider:          agenticapptest.NewTestProvider(t),
		GHTwirp:              mockTwirp,
		PrivilegedAppChecker: mockPrivilegedAppChecker,
	})
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()

	// User-to-Server token from a non-privileged app
	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser",
			TrackingID: "tracking-id",
			TokenInfo: &requestctx.TokenInfo{
				Token:           "user-token-123",
				Type:            string(authd.CredentialTypeUserToServerToken),
				ApplicationID:   99999,
				ApplicationType: "OAuthApplication",
			},
		},
	})
	req := createTestRequest(ctx, "PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	// Should be denied — non-privileged app, token doesn't have "push"
	assert.Equal(t, http.StatusNotFound, rr.Code)
	// Verify that no relaxation occurred: "push" was requested (and denied)
	assert.Equal(t, []string{"push"}, capturedActions, "non-privileged app should NOT relax write actions")
}

// TestCreateMemoryPrivilegedAppCheckerErrorFallsThrough tests that when the
// privileged app capability check fails, the handler logs the error and falls
// through to the original (tighter) access actions instead of hard-failing.
// This ensures a transient privileged-app-service outage does not block tokens
// that already satisfy the stricter "push" check.
func TestCreateMemoryPrivilegedAppCheckerErrorFallsThrough(t *testing.T) {
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

	// Configure the Twirp client to grant access for all actions and capture them.
	var capturedActions []string
	mockTwirp := githubtwirp.NewNoopClient()
	mockTwirp.NoopAuthorizationAPI.MockBatchControlAccess = func(ctx context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error) {
		decisions := make([]*coreTwirp.AuthorizationDecision, len(req.AuthorizationRequests))
		for i, authReq := range req.AuthorizationRequests {
			capturedActions = append(capturedActions, authReq.Action)
			decisions[i] = &coreTwirp.AuthorizationDecision{
				Id:       authReq.Id,
				Decision: true, // Grant access
			}
		}
		return &coreTwirp.BatchControlAccessResponse{Decisions: decisions}, nil
	}

	// Simulate a privileged app checker that returns an error (e.g. service unavailable)
	mockPrivilegedAppChecker := &github.MockPrivilegedAppChecker{
		MockHasCapabilityError: errors.New("privileged app service unavailable"),
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:              mockService,
		GHFactory:            mockGHFactory,
		Obsv:                 observability.NewNoopExporters(),
		AppProvider:          agenticapptest.NewTestProvider(t),
		GHTwirp:              mockTwirp,
		PrivilegedAppChecker: mockPrivilegedAppChecker,
	})
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()

	// User-to-Server token — would normally be relaxed if the check succeeded
	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser",
			TrackingID: "tracking-id",
			TokenInfo: &requestctx.TokenInfo{
				Token:           "user-token-123",
				Type:            string(authd.CredentialTypeUserToServerToken),
				ApplicationID:   12345,
				ApplicationType: "GithubApplication",
			},
		},
	})
	req := createTestRequest(ctx, "PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	// Should succeed because the token has "push" access and the handler
	// falls through to the original (un-relaxed) access actions.
	assert.Equal(t, http.StatusCreated, rr.Code)
	// Verify that the original "push" action was used (no relaxation to "pull")
	assert.Equal(t, []string{"push"}, capturedActions, "privileged check error should fall through to original push actions")
}

func TestCreateMemoryBillingEntityUnresolved(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return core.ErrBillingEntityUnresolved
		},
	}

	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}

	mockTwirp := githubtwirp.NewNoopClient()
	mockTwirp.NoopAuthorizationAPI.MockBatchControlAccess = func(ctx context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error) {
		decisions := make([]*coreTwirp.AuthorizationDecision, len(req.AuthorizationRequests))
		for i, authReq := range req.AuthorizationRequests {
			decisions[i] = &coreTwirp.AuthorizationDecision{Id: authReq.Id, Decision: true}
		}
		return &coreTwirp.BatchControlAccessResponse{Decisions: decisions}, nil
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		GHTwirp:     mockTwirp,
		AppProvider: agenticapptest.NewTestProvider(t),
	})
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()

	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:    1,
			Login: "testuser",
			TokenInfo: &requestctx.TokenInfo{
				Token: "user-token-123",
			},
		},
	})
	req := createTestRequest(ctx, "PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusUnprocessableEntity, rr.Code)
	assert.Contains(t, rr.Body.String(), "billing entity has not been selected")
}

func TestCreateMemoryBillingEntityResolutionFailed(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return core.ErrBillingEntityResolutionFailed
		},
	}

	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}

	mockTwirp := githubtwirp.NewNoopClient()
	mockTwirp.NoopAuthorizationAPI.MockBatchControlAccess = func(ctx context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error) {
		decisions := make([]*coreTwirp.AuthorizationDecision, len(req.AuthorizationRequests))
		for i, authReq := range req.AuthorizationRequests {
			decisions[i] = &coreTwirp.AuthorizationDecision{Id: authReq.Id, Decision: true}
		}
		return &coreTwirp.BatchControlAccessResponse{Decisions: decisions}, nil
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		GHTwirp:     mockTwirp,
		AppProvider: agenticapptest.NewTestProvider(t),
	})
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()

	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:    1,
			Login: "testuser",
			TokenInfo: &requestctx.TokenInfo{
				Token: "user-token-123",
			},
		},
	})
	req := createTestRequest(ctx, "PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusInternalServerError, rr.Code)
	assert.Contains(t, rr.Body.String(), "failed to resolve billing entity")
}
