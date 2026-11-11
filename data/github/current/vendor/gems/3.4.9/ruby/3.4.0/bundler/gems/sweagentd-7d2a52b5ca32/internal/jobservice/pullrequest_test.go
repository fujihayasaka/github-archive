package jobservice

import (
	"context"
	"errors"
	"testing"

	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

// MockPullRequestCreator implements the PullRequestCreator interface for testing
type MockPullRequestCreator struct {
	MockCreatePullRequest func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error)
}

func (m *MockPullRequestCreator) CreatePullRequest(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
	if m.MockCreatePullRequest != nil {
		return m.MockCreatePullRequest(ctx, req)
	}
	return &sweagentdTwirp.CreatePullRequestResponse{
		PullRequest: &sweagentdTwirp.PullRequest{
			Id:           12345,
			GithubNumber: 1,
		},
	}, nil
}

func TestOpenPullRequest(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	// Create a basic service with minimal dependencies - feature flag enabled by default for backward compatibility

	service := &Service{
		obsv: obsv,
	}

	tests := []struct {
		name                      string
		mockCreatePullRequest     func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error)
		expectError               bool
		expectedErrorContains     string
		expectedPullRequestID     int64
		expectedPullRequestNumber int
		verifyRequestParams       bool
	}{
		{
			name: "successful pull request creation",
			mockCreatePullRequest: func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
				return &sweagentdTwirp.CreatePullRequestResponse{
					PullRequest: &sweagentdTwirp.PullRequest{
						Id:           12345,
						GithubNumber: 1,
					},
				}, nil
			},
			expectError:               false,
			expectedPullRequestID:     12345,
			expectedPullRequestNumber: 1,
			verifyRequestParams:       true,
		},
		{
			name: "handles AlreadyExists error - should succeed",
			mockCreatePullRequest: func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
				// Return a response with valid PR data but also an AlreadyExists error
				return &sweagentdTwirp.CreatePullRequestResponse{
					PullRequest: &sweagentdTwirp.PullRequest{
						Id:           67890,
						GithubNumber: 2,
					},
				}, twirp.NewError(twirp.AlreadyExists, "pull request already exists")
			},
			expectError:               false,
			expectedPullRequestID:     67890,
			expectedPullRequestNumber: 2,
		},
		{
			name: "handles non-AlreadyExists error - should fail",
			mockCreatePullRequest: func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
				return nil, twirp.NewError(twirp.Internal, "internal error occurred")
			},
			expectError:           true,
			expectedErrorContains: "failed to create pull request",
		},
		{
			name: "handles non-twirp error - should fail",
			mockCreatePullRequest: func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
				return nil, errors.New("generic error")
			},
			expectError:           true,
			expectedErrorContains: "failed to create pull request",
		},
		{
			name: "passes session ID correctly",
			mockCreatePullRequest: func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
				// Verify the session ID is passed correctly
				require.Equal(t, "test-session-id", req.SessionId)
				return &sweagentdTwirp.CreatePullRequestResponse{
					PullRequest: &sweagentdTwirp.PullRequest{
						Id:           11111,
						GithubNumber: 3,
					},
				}, nil
			},
			expectError:               false,
			expectedPullRequestID:     11111,
			expectedPullRequestNumber: 3,
		},
		{
			name: "handles empty session ID correctly",
			mockCreatePullRequest: func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
				// Verify empty session ID is passed as empty string
				require.Equal(t, "", req.SessionId)
				return &sweagentdTwirp.CreatePullRequestResponse{
					PullRequest: &sweagentdTwirp.PullRequest{
						Id:           22222,
						GithubNumber: 4,
					},
				}, nil
			},
			expectError:               false,
			expectedPullRequestID:     22222,
			expectedPullRequestNumber: 4,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Create fresh assignment and job for each test case
			testAssignment := &jobs.Assignment{
				ID:      "test-assignment",
				RepoID:  123,
				OwnerID: 456,
			}

			testJob := &jobs.Job{
				ID:           "test-job",
				RepoID:       123,
				ActorID:      789,
				BranchName:   "test-branch",
				BaseCommit:   "main",
				AssignmentID: testAssignment.ID,
				SessionID:    "test-session-id",
			}

			// Special case for the empty session ID test
			if tt.name == "handles empty session ID correctly" {
				testJob.SessionID = ""
			}

			mockCreator := &MockPullRequestCreator{
				MockCreatePullRequest: func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
					if tt.verifyRequestParams {
						// Verify the request parameters
						require.Equal(t, uint64(123), req.RepositoryId)
						require.Equal(t, "Test Title", req.PrName)
						require.Equal(t, "Test Body", req.PrDescription)
						require.Equal(t, "test-branch", req.HeadBranchName)
						require.Equal(t, "main", req.BaseBranchName)
						require.Equal(t, true, req.Draft)
						require.Equal(t, uint64(789), req.AttributionUserId)
						require.Equal(t, "test-session-id", req.SessionId)
					}
					return tt.mockCreatePullRequest(ctx, req)
				},
			}

			err := service.OpenPullRequest(ctx, mockCreator, testAssignment, testJob, "Test Title", "Test Body")

			if tt.expectError {
				require.Error(t, err)
				if tt.expectedErrorContains != "" {
					require.Contains(t, err.Error(), tt.expectedErrorContains)
				}
			} else {
				require.NoError(t, err)
				// Verify that the assignment and job are updated with PR details
				require.Equal(t, tt.expectedPullRequestID, testAssignment.PullRequestID)
				require.Equal(t, tt.expectedPullRequestNumber, testAssignment.PullRequestNumber)
				require.Equal(t, tt.expectedPullRequestID, testJob.PullRequestID)
				require.Equal(t, tt.expectedPullRequestNumber, testJob.PullRequestNumber)
			}
		})
	}
}
