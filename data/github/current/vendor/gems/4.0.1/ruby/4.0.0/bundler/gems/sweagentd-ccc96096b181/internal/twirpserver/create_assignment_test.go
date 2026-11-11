package twirpserver

import (
	"context"
	"errors"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestCreateAssignment_Success(t *testing.T) {
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	appProvider := agenticapptest.NewTestProvider(t)
	ffClient := featureflags.NewNoopClient(nil)

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
		appProvider: appProvider,
		ffClient:    ffClient,
	}

	req := &jobs_pb.CreateAssignmentRequest{
		OwnerId: 123,
		RepoId:  456,
	}

	resp, err := server.CreateAssignment(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)

	assert.NotEmpty(t, resp.Id)
	assert.NotZero(t, resp.CreatedAt)
	assert.Equal(t, int64(123), resp.OwnerId)
	assert.Equal(t, int64(456), resp.RepoId)

	// Verify the assignment was actually stored
	assignment, err := store.GetAssignment(context.Background(), 123, 456, resp.Id)
	require.NoError(t, err)
	require.NotNil(t, assignment)
	assert.Equal(t, resp.Id, assignment.ID)
	// Removed assertions for RepoOwner and RepoName as these fields no longer exist
	assert.Empty(t, assignment.Resources)
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
				RepoId: 456,
			},
			expectedField: "owner_id",
		},
		{
			name: "missing repo_id",
			req: &jobs_pb.CreateAssignmentRequest{
				OwnerId: 123,
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

func (m *mockJobStoreForAssignment) GetAssignmentForResource(ctx context.Context, owner, repo int64, resource jobs.AssignmentResource) (*jobs.Assignment, error) {
	return nil, nil
}

func (m *mockJobStoreForAssignment) GetJobsForAssignment(ctx context.Context, assignment *jobs.Assignment) ([]*jobs.Job, error) {
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
		appProvider: appProvider,
		ffClient:    ffClient,
	}

	req := &jobs_pb.CreateAssignmentRequest{
		OwnerId: 123,
		RepoId:  456,
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
		appProvider: appProvider,
		ffClient:    ffClient,
	}

	req := &jobs_pb.CreateAssignmentRequest{
		OwnerId: 123,
		RepoId:  456,
	}

	_, err := server.CreateAssignment(context.Background(), req)
	require.Error(t, err)

	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr), "expected twirp error")
	assert.Equal(t, twirp.Internal, twerr.Code())
}
