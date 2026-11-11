package jobservice

import (
	"context"
	"errors"
	"testing"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// MockCommitter implements the Committer interface for testing
type MockCommitter struct{}

func (m *MockCommitter) Committer() *gg.CommitAuthor {
	return &gg.CommitAuthor{
		Name:  gg.Ptr("committer-name"),
		Email: gg.Ptr("committer-email"),
	}
}

// MockSpokes implements the Spokes interface for testing
type MockSpokes struct {
	MockCreateEmptyBranch func(ctx context.Context, opts sweagentd.CreateEmptyBranchOpts) (string, error)
}

func (m *MockSpokes) ReadBlob(ctx context.Context, repoID uint64, path string) ([]byte, string, error) {
	return nil, "", nil
}

func (m *MockSpokes) ListTrees(ctx context.Context, repoID uint64, path string) ([]*sweagentd.SpokesObject, string, error) {
	return nil, "", nil
}

func (m *MockSpokes) ReadBlobObjects(ctx context.Context, repoID uint64, oids []string) ([][]byte, error) {
	return nil, nil
}

func (m *MockSpokes) ReadBlobByObjectIDPath(ctx context.Context, repoID uint64, oid, path string) ([]byte, error) {
	return nil, nil
}

func (m *MockSpokes) CreateEmptyBranch(ctx context.Context, opts sweagentd.CreateEmptyBranchOpts) (string, error) {
	if m.MockCreateEmptyBranch != nil {
		return m.MockCreateEmptyBranch(ctx, opts)
	}
	return "abc123", nil
}

func TestCreateBranch(t *testing.T) {
	ctx := requestctx.NewContext(context.Background())
	obsv := observability.NewNoopExporters()

	t.Run("successful branch creation with spokes", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		job := &jobs.Job{
			ID:         "test-job-id",
			RepoID:     12345,
			RepoOwner:  "test-owner",
			RepoName:   "test-repo",
			BranchName: "new-feature-branch",
			BaseCommit: "abc123",
			ActorID:    123,
		}

		spokesCalled := false
		mockSpokes := &MockSpokes{
			MockCreateEmptyBranch: func(ctx context.Context, opts sweagentd.CreateEmptyBranchOpts) (string, error) {
				assert.Equal(t, uint64(12345), opts.RepoID)
				assert.Equal(t, "abc123", opts.BaseRef)
				assert.Equal(t, "new-feature-branch", opts.BranchName)
				assert.Equal(t, "committer-name", opts.CommitterName)
				assert.Equal(t, "committer-email", opts.CommitterEmail)
				spokesCalled = true
				return "def456", nil
			},
		}

		s := New(obsv, ffClient, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", mockSpokes)

		mockCommitter := &MockCommitter{}

		err := s.CreateBranch(ctx, mockCommitter, job)
		require.NoError(t, err)
		assert.True(t, spokesCalled, "Spokes CreateEmptyBranch should have been called")
	})

	t.Run("branch creation with correct parameters", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		job := &jobs.Job{
			ID:         "test-job-id",
			RepoID:     67890,
			RepoOwner:  "my-org",
			RepoName:   "my-repo",
			BranchName: "fix-issue-123",
			BaseCommit: "def456",
			ActorID:    456,
		}

		paramsCaptured := false
		mockSpokes := &MockSpokes{
			MockCreateEmptyBranch: func(ctx context.Context, opts sweagentd.CreateEmptyBranchOpts) (string, error) {
				assert.Equal(t, uint64(67890), opts.RepoID)
				assert.Equal(t, "def456", opts.BaseRef)
				assert.Equal(t, "fix-issue-123", opts.BranchName)
				assert.Equal(t, "committer-name", opts.CommitterName)
				assert.Equal(t, "committer-email", opts.CommitterEmail)
				paramsCaptured = true
				return "ghi789", nil
			},
		}

		s := New(obsv, ffClient, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", mockSpokes)

		mockCommitter := &MockCommitter{}

		err := s.CreateBranch(ctx, mockCommitter, job)
		require.NoError(t, err)
		assert.True(t, paramsCaptured, "Spokes CreateEmptyBranch should have been called with correct parameters")
	})

	t.Run("returns error when spokes CreateEmptyBranch fails", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		job := &jobs.Job{
			ID:         "test-job-id",
			RepoID:     12345,
			RepoOwner:  "test-owner",
			RepoName:   "test-repo",
			BranchName: "new-feature-branch",
			BaseCommit: "abc123",
			ActorID:    123,
		}

		expectedErr := errors.New("spokes branch creation failed")
		mockSpokes := &MockSpokes{
			MockCreateEmptyBranch: func(ctx context.Context, opts sweagentd.CreateEmptyBranchOpts) (string, error) {
				return "", expectedErr
			},
		}

		s := New(obsv, ffClient, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", mockSpokes)

		mockCommitter := &MockCommitter{}

		err := s.CreateBranch(ctx, mockCommitter, job)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to create new empty branch")
	})
}
