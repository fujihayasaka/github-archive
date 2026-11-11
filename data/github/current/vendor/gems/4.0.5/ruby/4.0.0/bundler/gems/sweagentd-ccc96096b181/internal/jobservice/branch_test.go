package jobservice

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes/spokestest"
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

func TestCreateBranch(t *testing.T) {
	ctx := requestctx.NewContext(context.Background())
	obsv := observability.NewNoopExporters()

	t.Run("successful branch creation with spokes", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		job := &jobs.Job{
			ID:         "test-job-id",
			RepoID:     12345,
			BranchName: "fix-issue-123",
			BaseCommit: "def456",
			ActorID:    456,
		}

		commitCalled := false
		branchCalled := false
		spokesClient := spokestest.NewClient(t,
			spokestest.WithMockCreateEmptyCommit(func(ctx context.Context, opts sweagentd.CreateEmptyCommitOpts) (string, error) {
				assert.Equal(t, uint64(12345), opts.RepoID)
				assert.Equal(t, "def456", opts.BaseRef)
				assert.Equal(t, "committer-name", opts.CommitterName)
				assert.Equal(t, "committer-email", opts.CommitterEmail)
				commitCalled = true
				return "abc123", nil
			}),
			spokestest.WithMockCreateBranch(func(ctx context.Context, opts sweagentd.CreateBranchOpts) error {
				assert.Equal(t, uint64(12345), opts.RepoID)
				assert.Equal(t, "abc123", opts.CommitOID)
				assert.Equal(t, "fix-issue-123", opts.BranchName)
				assert.Equal(t, "committer-name", opts.CommitterName)
				assert.Equal(t, "committer-email", opts.CommitterEmail)
				branchCalled = true
				return nil
			}),
		)

		s := New(obsv, ffClient, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", spokesClient, agenticapptest.NewTestProvider(t), nil)

		mockCommitter := &MockCommitter{}

		commitOID, err := s.CreateEmptyCommit(ctx, mockCommitter, job)
		require.NoError(t, err)

		err = s.CreateBranch(ctx, mockCommitter, job, commitOID)
		require.NoError(t, err)
		assert.True(t, commitCalled, "Spokes CreateEmptyCommit should have been called with correct parameters")
		assert.True(t, branchCalled, "Spokes CreateBranch should have been called with correct parameters")
	})

	t.Run("creates branch with spokes", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		job := &jobs.Job{
			ID:         "test-job-id",
			RepoID:     12345,
			BranchName: "new-feature-branch",
			BaseCommit: "abc123",
			ActorID:    123,
		}

		commitCalled := false
		branchCalled := false
		spokesClient := spokestest.NewClient(t,
			spokestest.WithMockCreateEmptyCommit(func(ctx context.Context, opts sweagentd.CreateEmptyCommitOpts) (string, error) {
				assert.Equal(t, uint64(12345), opts.RepoID)
				assert.Equal(t, "abc123", opts.BaseRef)
				assert.Equal(t, "committer-name", opts.CommitterName)
				assert.Equal(t, "committer-email", opts.CommitterEmail)
				commitCalled = true
				return "def456", nil
			}),
			spokestest.WithMockCreateBranch(func(ctx context.Context, opts sweagentd.CreateBranchOpts) error {
				assert.Equal(t, uint64(12345), opts.RepoID)
				assert.Equal(t, "def456", opts.CommitOID)
				assert.Equal(t, "new-feature-branch", opts.BranchName)
				assert.Equal(t, "committer-name", opts.CommitterName)
				assert.Equal(t, "committer-email", opts.CommitterEmail)
				branchCalled = true
				return nil
			}),
		)

		s := New(obsv, ffClient, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", spokesClient, agenticapptest.NewTestProvider(t), nil)

		mockCommitter := &MockCommitter{}

		commitOID, err := s.CreateEmptyCommit(ctx, mockCommitter, job)
		require.NoError(t, err)

		err = s.CreateBranch(ctx, mockCommitter, job, commitOID)
		require.NoError(t, err)
		assert.True(t, commitCalled, "Spokes CreateEmptyCommit should have been called with correct parameters")
		assert.True(t, branchCalled, "Spokes CreateBranch should have been called with correct parameters")
	})

	t.Run("branch creation with correct parameters", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		job := &jobs.Job{
			ID:         "test-job-id",
			RepoID:     67890,
			BranchName: "fix-issue-123",
			BaseCommit: "def456",
			ActorID:    456,
		}

		commitCalled := false
		branchCalled := false
		spokesClient := spokestest.NewClient(t,
			spokestest.WithMockCreateEmptyCommit(func(ctx context.Context, opts sweagentd.CreateEmptyCommitOpts) (string, error) {
				assert.Equal(t, uint64(67890), opts.RepoID)
				assert.Equal(t, "def456", opts.BaseRef)
				assert.Equal(t, "committer-name", opts.CommitterName)
				assert.Equal(t, "committer-email", opts.CommitterEmail)
				commitCalled = true
				return "ghi789", nil
			}),
			spokestest.WithMockCreateBranch(func(ctx context.Context, opts sweagentd.CreateBranchOpts) error {
				assert.Equal(t, uint64(67890), opts.RepoID)
				assert.Equal(t, "ghi789", opts.CommitOID)
				assert.Equal(t, "fix-issue-123", opts.BranchName)
				assert.Equal(t, "committer-name", opts.CommitterName)
				assert.Equal(t, "committer-email", opts.CommitterEmail)
				branchCalled = true
				return nil
			}),
		)

		s := New(obsv, ffClient, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", spokesClient, agenticapptest.NewTestProvider(t), nil)

		mockCommitter := &MockCommitter{}

		commitOID, err := s.CreateEmptyCommit(ctx, mockCommitter, job)
		require.NoError(t, err)

		err = s.CreateBranch(ctx, mockCommitter, job, commitOID)
		require.NoError(t, err)
		assert.True(t, commitCalled, "Spokes CreateEmptyCommit should have been called with correct parameters")
		assert.True(t, branchCalled, "Spokes CreateBranch should have been called with correct parameters")
	})

	t.Run("returns error when spokes CreateEmptyCommit fails", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		job := &jobs.Job{
			ID:         "test-job-id",
			RepoID:     12345,
			BranchName: "new-feature-branch",
			BaseCommit: "abc123",
			ActorID:    123,
		}

		expectedErr := errors.New("spokes branch creation failed")
		spokesClient := spokestest.NewClient(t,
			spokestest.WithMockCreateEmptyCommit(func(ctx context.Context, opts sweagentd.CreateEmptyCommitOpts) (string, error) {
				return "", expectedErr
			}),
		)

		s := New(obsv, ffClient, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", spokesClient, agenticapptest.NewTestProvider(t), nil)

		mockCommitter := &MockCommitter{}

		_, err := s.CreateEmptyCommit(ctx, mockCommitter, job)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to create new empty commit")
	})

	t.Run("returns error when spokes CreateBranch fails", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		job := &jobs.Job{
			ID:         "test-job-id",
			RepoID:     12345,
			BranchName: "new-feature-branch",
			BaseCommit: "abc123",
			ActorID:    123,
		}

		expectedErr := errors.New("spokes branch creation failed")
		spokesClient := spokestest.NewClient(t,
			spokestest.WithMockCreateBranch(func(ctx context.Context, opts sweagentd.CreateBranchOpts) error {
				return expectedErr
			}),
		)

		s := New(obsv, ffClient, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", spokesClient, agenticapptest.NewTestProvider(t), nil)

		mockCommitter := &MockCommitter{}

		err := s.CreateBranch(ctx, mockCommitter, job, "12345")
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to create new branch")
	})
}

func TestGeneratePotentialBranchNames(t *testing.T) {
	ctx := requestctx.NewContext(context.Background())
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
	appProvider := agenticapptest.NewTestProvider(t)

	testCases := []struct {
		name             string
		branchName       string
		existingBranches []string
		refsError        bool
	}{
		{
			name:       "generates_all_branch_names",
			branchName: "fix-bug",
		},
		{
			name:             "filters_branches_that_dont_exist",
			branchName:       "fix-bug",
			existingBranches: []string{"fix-bug", fmt.Sprintf("fix-bug-%s", branchNameSuffixes[0])},
		},
		{
			name:       "handles_existing_prefix",
			branchName: fmt.Sprintf("%s/fix-bug", agenticapp.CopilotBranchPrefix),
		},
		{
			name:       "returns_all_branches_on_error",
			branchName: fmt.Sprintf("%s/fix-bug", agenticapp.CopilotBranchPrefix),
			refsError:  true,
		},
	}

	for _, tt := range testCases {
		t.Run(tt.name, func(t *testing.T) {
			existingRefs := make([]string, len(tt.existingBranches))
			for i, branch := range tt.existingBranches {
				if !strings.HasPrefix(branch, agenticapp.CopilotBranchPrefix) {
					branch = fmt.Sprintf("%s/%s", agenticapp.CopilotBranchPrefix, branch)
				}
				existingRefs[i] = fmt.Sprintf("refs/heads/%s", branch)
			}

			spokes := spokestest.NewClient(t, spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				if tt.refsError {
					return nil, errors.New("error checking refs")
				}

				results := make([]bool, len(refNames))
				for i, ref := range refNames {
					found := slices.Contains(existingRefs, ref)
					results[i] = found
				}
				return results, nil
			}))
			s := New(obsv, ffClient, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", spokes, appProvider, nil)
			names := s.GeneratePotentialBranchNames(ctx, agenticapp.CopilotBranchPrefix, tt.branchName, 12345)
			require.Equal(t, len(branchNameSuffixes)+2-len(tt.existingBranches), len(names))
			require.True(t, strings.HasPrefix(names[0], agenticapp.CopilotBranchPrefix))
			// Check against double prefix
			require.False(t, strings.HasPrefix(names[0], fmt.Sprintf("%s/%s", agenticapp.CopilotBranchPrefix, agenticapp.CopilotBranchPrefix)))
			require.Contains(t, names[0], tt.branchName)
		})
	}
}
