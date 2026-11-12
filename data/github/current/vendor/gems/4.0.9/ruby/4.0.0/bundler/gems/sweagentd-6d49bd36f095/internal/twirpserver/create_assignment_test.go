package twirpserver

import (
	"context"
	"errors"
	"testing"

	billingProto "github.com/github/billing-platform/clients/go/v1/go-client/lib/twirp/proto"
	billingMocks "github.com/github/billing-platform/clients/go/v1/go-client/mocks"
	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	store "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func setupCreateAssignmentTestServer(t *testing.T) *Server {
	t.Helper()

	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	appProvider := agenticapptest.NewTestProvider(t)
	ffClient := featureflags.NewNoopClient(nil)

	// Set up billing mock to allow quota checks
	mockBillingClient := billingMocks.NewMockClientInterface(t)
	mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Maybe().Return(&billingProto.CanProceedWithUsageResponse{
		CanProceed: true,
	}, nil)

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopLimiterAPI:    &githubtwirp.NoopLimiterAPI{},
		NoopBillingClient: mockBillingClient,
	}

	ghClient := &github.NoopClient{}
	ghf := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return ghClient
		},
	}

	return &Server{
		obsv:        obsv,
		jobStore:    store,
		ghf:         ghf,
		ghTwirp:     mockGhTwirp,
		appProvider: appProvider,
		ffClient:    ffClient,
	}
}

func TestCreateAssignment_Success(t *testing.T) {
	server := setupCreateAssignmentTestServer(t)

	req := &jobs_pb.CreateAssignmentRequest{
		OwnerId: 123,
		RepoId:  456,
		ActorId: 789,
	}

	resp, err := server.CreateAssignment(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)

	assert.NotEmpty(t, resp.Id)
	assert.NotZero(t, resp.CreatedAt)
	assert.Equal(t, int64(123), resp.OwnerId)
	assert.Equal(t, int64(456), resp.RepoId)

	// Verify the assignment was actually stored
	store := server.jobStore.(*memory.Store)
	assignment, err := store.GetAssignment(context.Background(), 123, 456, resp.Id)
	require.NoError(t, err)
	require.NotNil(t, assignment)
	assert.Equal(t, resp.Id, assignment.ID)
	// Removed assertions for RepoOwner and RepoName as these fields no longer exist
	assert.Empty(t, assignment.Resources)
}

// TestCreateAssignment_BackwardsCompatibility_NoActorID tests that the endpoint
// works without actor_id for backwards compatibility during the migration period.
// Once all clients send actor_id, this test can be removed and actor_id made required.
func TestCreateAssignment_BackwardsCompatibility_NoActorID(t *testing.T) {
	server := setupCreateAssignmentTestServer(t)

	req := &jobs_pb.CreateAssignmentRequest{
		OwnerId: 123,
		RepoId:  456,
		// ActorId intentionally omitted for backwards compatibility test
	}

	resp, err := server.CreateAssignment(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)

	assert.NotEmpty(t, resp.Id)
	assert.NotZero(t, resp.CreatedAt)
	assert.Equal(t, int64(123), resp.OwnerId)
	assert.Equal(t, int64(456), resp.RepoId)
}

func TestCreateAssignment_ValidatesFields(t *testing.T) {
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()

	server := &Server{
		obsv:     obsv,
		jobStore: store,
	}

	testCases := []struct {
		name          string
		req           *jobs_pb.CreateAssignmentRequest
		expectedField string
	}{
		{
			name: "missing owner_id",
			req: &jobs_pb.CreateAssignmentRequest{
				RepoId:  456,
				ActorId: 789,
			},
			expectedField: "owner_id",
		},
		{
			name: "missing repo_id",
			req: &jobs_pb.CreateAssignmentRequest{
				OwnerId: 123,
				ActorId: 789,
			},
			expectedField: "repo_id",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := server.CreateAssignment(context.Background(), tc.req)
			require.Error(t, err)

			var twerr twirp.Error
			require.True(t, errors.As(err, &twerr), "expected twirp error")
			assert.Equal(t, twirp.InvalidArgument, twerr.Code())
			assert.Contains(t, twerr.Meta("argument"), tc.expectedField)
		})
	}
}

// mockJobStoreForAssignment is a minimal mock for testing CreateAssignment
type mockJobStoreForAssignment struct {
	createErr error
}

func (m *mockJobStoreForAssignment) GetAssignmentForPR(ctx context.Context, owner, repo int64, id *int64, number *int) (*jobs.Assignment, error) {
	return nil, nil
}

func (m *mockJobStoreForAssignment) GetLatestAssignmentForPR(ctx context.Context, owner, repo int64, id *int64, number *int) (*jobs.Assignment, error) {
	return nil, nil
}

func (m *mockJobStoreForAssignment) GetAssignmentForResource(ctx context.Context, owner, repo int64, resource jobs.AssignmentResource) (*jobs.Assignment, error) {
	return nil, nil
}

func (m *mockJobStoreForAssignment) GetJobsForAssignment(ctx context.Context, assignment *jobs.Assignment) ([]*jobs.Job, error) {
	return nil, nil
}

func (m *mockJobStoreForAssignment) ListJobsForPullRequestNumber(ctx context.Context, owner, repo int64, prNumber int) ([]*jobs.Job, error) {
	return nil, nil
}

func (m *mockJobStoreForAssignment) CreateAssignment(ctx context.Context, assignment *jobs.Assignment) (*jobs.Assignment, error) {
	if m.createErr != nil {
		return nil, m.createErr
	}
	return assignment, nil
}

func (m *mockJobStoreForAssignment) GetAssignment(ctx context.Context, owner, repo int64, id string) (*jobs.Assignment, error) {
	return nil, nil
}

func (m *mockJobStoreForAssignment) PatchAssignment(ctx context.Context, assignment *jobs.Assignment, patch store.AssignmentPatch, opts ...store.PatchAssignmentOption) error {
	return nil
}

// errorReturningGitHubClient is a client that returns an error for GetRepositoryByID
type errorReturningGitHubClient struct {
	*github.NoopClient
}

//nolint:revive // Method name must match interface
func (c *errorReturningGitHubClient) GetRepositoryByID(ctx context.Context, id int64) (*gg.Repository, error) {
	return nil, assert.AnError
}

func TestCreateAssignment_StoreError(t *testing.T) {
	obsv := observability.NewNoopExporters()
	mockStore := &mockJobStoreForAssignment{
		createErr: assert.AnError,
	}
	appProvider := agenticapptest.NewTestProvider(t)
	ffClient := featureflags.NewNoopClient(nil)

	// Set up billing mock to allow quota checks
	mockBillingClient := billingMocks.NewMockClientInterface(t)
	mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Maybe().Return(&billingProto.CanProceedWithUsageResponse{
		CanProceed: true,
	}, nil)

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopLimiterAPI:    &githubtwirp.NoopLimiterAPI{},
		NoopBillingClient: mockBillingClient,
	}

	ghClient := &github.NoopClient{}
	ghf := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return ghClient
		},
	}

	server := &Server{
		obsv:        obsv,
		jobStore:    mockStore,
		ghf:         ghf,
		ghTwirp:     mockGhTwirp,
		appProvider: appProvider,
		ffClient:    ffClient,
	}

	req := &jobs_pb.CreateAssignmentRequest{
		OwnerId: 123,
		RepoId:  456,
		ActorId: 789,
	}

	_, err := server.CreateAssignment(context.Background(), req)
	require.Error(t, err)

	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr), "expected twirp error")
	assert.Equal(t, twirp.Internal, twerr.Code())
}

func TestCreateAssignment_GetRepoError(t *testing.T) {
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	appProvider := agenticapptest.NewTestProvider(t)
	ffClient := featureflags.NewNoopClient(nil)

	// Set up billing mock to allow quota checks
	mockBillingClient := billingMocks.NewMockClientInterface(t)
	mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Maybe().Return(&billingProto.CanProceedWithUsageResponse{
		CanProceed: true,
	}, nil)

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopLimiterAPI:    &githubtwirp.NoopLimiterAPI{},
		NoopBillingClient: mockBillingClient,
	}

	ghClient := &errorReturningGitHubClient{NoopClient: &github.NoopClient{}}
	ghf := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return ghClient
		},
	}

	server := &Server{
		obsv:        obsv,
		jobStore:    store,
		ghf:         ghf,
		ghTwirp:     mockGhTwirp,
		appProvider: appProvider,
		ffClient:    ffClient,
	}

	req := &jobs_pb.CreateAssignmentRequest{
		OwnerId: 123,
		RepoId:  456,
		ActorId: 789,
	}

	_, err := server.CreateAssignment(context.Background(), req)
	require.Error(t, err)

	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr), "expected twirp error")
	assert.Equal(t, twirp.Internal, twerr.Code())
}

func TestCreateAssignment_InsufficientQuota(t *testing.T) {
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	appProvider := agenticapptest.NewTestProvider(t)
	ffClient := featureflags.NewNoopClient(nil)

	// Set up billing mock to deny quota
	mockBillingClient := billingMocks.NewMockClientInterface(t)
	mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Return(&billingProto.CanProceedWithUsageResponse{
		CanProceed: false,
	}, nil)

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				return &copilotLimitersTwirp.GetQuotaRemainingResponse{
					QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
						{
							Entitlement:      1000,
							Remaining:        0,
							QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
							PercentRemaining: 0.0,
							OveragePermitted: false,
						},
					},
				}, nil
			},
		},
		NoopBillingClient: mockBillingClient,
	}

	ghClient := &github.NoopClient{}
	ghf := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return ghClient
		},
	}

	server := &Server{
		obsv:        obsv,
		jobStore:    store,
		ghf:         ghf,
		ghTwirp:     mockGhTwirp,
		appProvider: appProvider,
		ffClient:    ffClient,
	}

	req := &jobs_pb.CreateAssignmentRequest{
		OwnerId: 123,
		RepoId:  456,
		ActorId: 789,
	}

	_, err := server.CreateAssignment(context.Background(), req)
	require.Error(t, err)

	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr), "expected twirp error")
	assert.Equal(t, twirp.FailedPrecondition, twerr.Code())
	assert.Contains(t, twerr.Msg(), "insufficient premium quota to create assignment")
}

func TestCreateAssignment_QuotaCheckError(t *testing.T) {
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	appProvider := agenticapptest.NewTestProvider(t)
	ffClient := featureflags.NewNoopClient(nil)

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				return nil, errors.New("limiter service unavailable")
			},
		},
	}

	ghClient := &github.NoopClient{}
	ghf := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return ghClient
		},
	}

	server := &Server{
		obsv:        obsv,
		jobStore:    store,
		ghf:         ghf,
		ghTwirp:     mockGhTwirp,
		appProvider: appProvider,
		ffClient:    ffClient,
	}

	req := &jobs_pb.CreateAssignmentRequest{
		OwnerId: 123,
		RepoId:  456,
		ActorId: 789,
	}

	_, err := server.CreateAssignment(context.Background(), req)
	require.Error(t, err)
	require.Contains(t, err.Error(), "failed to check quota")
}

func TestCreateAssignment_AdditionalRepositories(t *testing.T) {
	tests := []struct {
		name                   string
		additionalRepositories []*gg.Repository
		wantCount              int
		wantRefs               []jobs.RepositoryRef
	}{
		{
			name: "populates additional repositories on assignment",
			additionalRepositories: []*gg.Repository{
				{
					ID:     gg.Ptr(int64(1001)),
					NodeID: gg.Ptr("extra-repo-1-node"),
					Owner: &gg.User{
						ID:     gg.Ptr(int64(2001)),
						NodeID: gg.Ptr("extra-owner-1-node"),
					},
				},
				{
					ID:     gg.Ptr(int64(1002)),
					NodeID: gg.Ptr("extra-repo-2-node"),
					Owner: &gg.User{
						ID:     gg.Ptr(int64(2002)),
						NodeID: gg.Ptr("extra-owner-2-node"),
					},
				},
			},
			wantCount: 2,
			wantRefs: []jobs.RepositoryRef{
				{RepoID: 1001, OwnerID: 2001, RepoNodeID: "extra-repo-1-node", OwnerNodeID: "extra-owner-1-node"},
				{RepoID: 1002, OwnerID: 2002, RepoNodeID: "extra-repo-2-node", OwnerNodeID: "extra-owner-2-node"},
			},
		},
		{
			name:                   "nil additional repositories leaves field empty",
			additionalRepositories: nil,
			wantCount:              0,
			wantRefs:               nil,
		},
		{
			name:                   "empty slice additional repositories leaves field empty",
			additionalRepositories: []*gg.Repository{},
			wantCount:              0,
			wantRefs:               nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			server := setupCreateAssignmentTestServer(t)

			repo := &gg.Repository{
				ID:            gg.Ptr(int64(456)),
				Name:          gg.Ptr("test-repo"),
				NodeID:        gg.Ptr("repo-node-id"),
				DefaultBranch: gg.Ptr("main"),
				Owner: &gg.User{
					ID:     gg.Ptr(int64(123)),
					Login:  gg.Ptr("test-owner"),
					NodeID: gg.Ptr("owner-node-id"),
				},
			}

			resp, err := server.createAssignment(context.Background(), int64(123), int64(456), repo, tt.additionalRepositories)
			require.NoError(t, err)
			require.NotNil(t, resp)

			memStore := server.jobStore.(*memory.Store)
			assignment, err := memStore.GetAssignment(context.Background(), 123, 456, resp.Id)
			require.NoError(t, err)
			require.Len(t, assignment.AdditionalRepositories, tt.wantCount)

			if tt.wantRefs != nil {
				for i, want := range tt.wantRefs {
					assert.Equal(t, want.RepoID, assignment.AdditionalRepositories[i].RepoID)
					assert.Equal(t, want.OwnerID, assignment.AdditionalRepositories[i].OwnerID)
					assert.Equal(t, want.RepoNodeID, assignment.AdditionalRepositories[i].RepoNodeID)
					assert.Equal(t, want.OwnerNodeID, assignment.AdditionalRepositories[i].OwnerNodeID)
				}
			}
		})
	}
}

func TestCreateAssignment_RepoNotFound(t *testing.T) {
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	appProvider := agenticapptest.NewTestProvider(t)
	ffClient := featureflags.NewNoopClient(nil)

	// Set up billing mock to allow quota checks
	mockBillingClient := billingMocks.NewMockClientInterface(t)
	mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Maybe().Return(&billingProto.CanProceedWithUsageResponse{
		CanProceed: true,
	}, nil)

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopLimiterAPI:    &githubtwirp.NoopLimiterAPI{},
		NoopBillingClient: mockBillingClient,
	}

	ghf := &github.NoopClientFactory{
		MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
			return nil, twirp.NotFoundError("repository not found")
		},
	}

	server := &Server{
		obsv:        obsv,
		jobStore:    store,
		ghf:         ghf,
		ghTwirp:     mockGhTwirp,
		appProvider: appProvider,
		ffClient:    ffClient,
	}

	req := &jobs_pb.CreateAssignmentRequest{
		OwnerId: 123,
		RepoId:  456,
		ActorId: 789,
	}

	_, err := server.CreateAssignment(context.Background(), req)
	require.Error(t, err)

	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr), "expected twirp error")
	assert.Equal(t, twirp.NotFound, twerr.Code())
}
