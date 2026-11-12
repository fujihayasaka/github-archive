package jobservice

import (
	"context"
	"errors"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/jobs"
	jobExperiments "github.com/github/sweagentd/internal/jobs/experiments"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func newTestServiceForExperiments(t *testing.T, expClient experiments.Client) *Service {
	obsv := observability.NewNoopExporters()
	ff := featureflags.NewNoopClient(nil)
	capi, store, twirp, gcf, _, aq, limiter := commonServiceDependencies(obsv)
	return New(obsv, ff, store, capi, gcf, twirp, aq, limiter, expClient, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)
}

func TestSetExperimentAssignmentsForJob(t *testing.T) {
	tests := []struct {
		name      string
		expClient experiments.Client
		expectErr bool
	}{
		{
			name: "returns nil when experiments are found",
			expClient: &experiments.MockClient{
				MockAssignment: &experiments.Assignment{
					Variation: "test-variation",
					Context:   "assignment-context",
				},
				MockOK: true,
			},
			expectErr: false,
		},
		{
			name: "returns the error when the Traffic Filters aren't set",
			expClient: &experiments.MockClient{
				MockError: errors.New("traffic filter error"),
			},
			expectErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			svc := newTestServiceForExperiments(t, tt.expClient)
			ctx := context.Background()

			jobAssignment := &jobs.Assignment{}
			job := &jobs.Job{
				RepoID:                   int64(123),
				OwnerID:                  int64(456),
				ActorID:                  int64(789),
				PullRequestID:            int64(1),
				ActorAnalyticsTrackingID: "test-tracking-id",
				Experiments:              &jobExperiments.AssignmentExperiments{},
			}

			err := svc.SetExperimentAssignmentsForJob(ctx, []string{"test-feature"}, jobAssignment, job)
			if tt.expectErr {
				assert.Error(t, err)
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func TestSetExperimentAssignmentsForJob_Patching(t *testing.T) {
	tests := []struct {
		name                string
		expClient           experiments.Client
		existingAssignments *jobExperiments.AssignmentExperiments
		expectErr           bool
	}{
		{
			name: "When no assignments exist, update job assignments",
			expClient: &experiments.MockClient{
				MockAssignment: &experiments.Assignment{
					Variation: "test-variation",
					Context:   "assignment-context",
				},
				MockOK: true,
			},
			expectErr: false,
		},
		{
			name: "When assignments exist, preserve those assignments",
			expClient: &experiments.MockClient{
				MockAssignment: &experiments.Assignment{
					Variation: "test-variation",
					Context:   "assignment-context",
				},
				MockOK: true,
			},
			existingAssignments: &jobExperiments.AssignmentExperiments{
				Variations: map[string]any{
					"existing-feature": "existing-variation",
				},
			},
			expectErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			svc := newTestServiceForExperiments(t, tt.expClient)
			ctx := context.Background()
			jobAssignment := &jobs.Assignment{}

			job := &jobs.Job{
				RepoID:                   int64(123),
				OwnerID:                  int64(456),
				ActorID:                  int64(789),
				PullRequestID:            int64(1),
				PullRequestNumber:        1,
				ActorAnalyticsTrackingID: "test-tracking-id",
				Experiments:              &jobExperiments.AssignmentExperiments{},
			}

			if tt.existingAssignments != nil {
				job.Experiments = tt.existingAssignments
			}

			err := svc.SetExperimentAssignmentsForJob(ctx, []string{"test-feature"}, jobAssignment, job)
			require.NoError(t, err)
			assert.Equal(t, "test-variation", job.Experiments.Variations["test-feature"])
			assert.Equal(t, "assignment-context", job.Experiments.AssignmentContext)
			if tt.existingAssignments != nil {
				for k, v := range tt.existingAssignments.Variations {
					value, ok := job.Experiments.Variations[k]
					assert.True(t, ok)
					assert.Equal(t, value, v)
				}
			}
		})
	}
}

func TestSetExperimentAssignmentsForJob_RandomizationUnits(t *testing.T) {
	t.Run("PR-ID experiment uses GitHubPullRequestIDHeader", func(t *testing.T) {
		mockClient := &experiments.MockClient{
			MockAssignment: &experiments.Assignment{
				Variation: "test-variation",
				Context:   "assignment-context",
			},
			MockOK: true,
		}
		svc := newTestServiceForExperiments(t, mockClient)
		ctx := context.Background()

		job := &jobs.Job{
			RepoID:                   int64(123),
			OwnerID:                  int64(456),
			ActorID:                  int64(789),
			PullRequestID:            int64(42),
			ActorAnalyticsTrackingID: "test-tracking-id",
			Experiments:              &jobExperiments.AssignmentExperiments{},
		}
		jobAssignment := &jobs.Assignment{}

		// ModelCompareExperiment defaults to PR ID randomization
		err := svc.SetExperimentAssignmentsForJob(ctx, []string{experiments.ModelCompareExperiment}, jobAssignment, job)
		require.NoError(t, err)

		ru := mockClient.GetFeatureAssignmentRandomizationUnit(experiments.ModelCompareExperiment)
		require.NotNil(t, ru)
		assert.Equal(t, experiments.GitHubPullRequestIDHeader, ru.Header)
		assert.Equal(t, "42", ru.Value)
	})

	t.Run("tracking-ID experiment uses CopilotTrackingIDHeader", func(t *testing.T) {
		mockClient := &experiments.MockClient{
			MockAssignment: &experiments.Assignment{
				Variation: "test-variation",
				Context:   "assignment-context",
			},
			MockOK: true,
		}
		svc := newTestServiceForExperiments(t, mockClient)
		ctx := context.Background()

		job := &jobs.Job{
			RepoID:                   int64(123),
			OwnerID:                  int64(456),
			ActorID:                  int64(789),
			PullRequestID:            int64(42),
			ActorAnalyticsTrackingID: "user-tracking-id-123",
			Experiments:              &jobExperiments.AssignmentExperiments{},
		}
		jobAssignment := &jobs.Assignment{}

		// AutoModelExperiment is configured to use tracking ID
		err := svc.SetExperimentAssignmentsForJob(ctx, []string{experiments.AutoModelExperiment}, jobAssignment, job)
		require.NoError(t, err)

		ru := mockClient.GetFeatureAssignmentRandomizationUnit(experiments.AutoModelExperiment)
		require.NotNil(t, ru)
		assert.Equal(t, experiments.CopilotTrackingIDHeader, ru.Header)
		assert.Equal(t, "user-tracking-id-123", ru.Value)
	})

	t.Run("empty tracking ID skips tracking-ID experiment", func(t *testing.T) {
		mockClient := &experiments.MockClient{
			MockAssignment: &experiments.Assignment{
				Variation: "test-variation",
				Context:   "assignment-context",
			},
			MockOK: true,
		}
		svc := newTestServiceForExperiments(t, mockClient)
		ctx := context.Background()

		job := &jobs.Job{
			RepoID:                   int64(123),
			OwnerID:                  int64(456),
			ActorID:                  int64(789),
			PullRequestID:            int64(42),
			ActorAnalyticsTrackingID: "", // empty
			Experiments:              &jobExperiments.AssignmentExperiments{},
		}
		jobAssignment := &jobs.Assignment{}

		// AutoModelExperiment requires tracking ID — should be skipped
		err := svc.SetExperimentAssignmentsForJob(ctx, []string{experiments.AutoModelExperiment}, jobAssignment, job)
		require.NoError(t, err)

		// The experiment should not have been called since tracking ID is empty
		assert.False(t, mockClient.GetFeatureAssignmentCalledWithFeatureName(experiments.AutoModelExperiment))
		// And the variation should not be set
		_, ok := job.Experiments.Variations[experiments.AutoModelExperiment]
		assert.False(t, ok)
	})

	t.Run("empty PR ID skips PR-ID experiment", func(t *testing.T) {
		mockClient := &experiments.MockClient{
			MockAssignment: &experiments.Assignment{
				Variation: "test-variation",
				Context:   "assignment-context",
			},
			MockOK: true,
		}
		svc := newTestServiceForExperiments(t, mockClient)
		ctx := context.Background()

		job := &jobs.Job{
			RepoID:                   int64(123),
			OwnerID:                  int64(456),
			ActorID:                  int64(789),
			PullRequestID:            0,
			ActorAnalyticsTrackingID: "test-tracking-id",
			Experiments:              &jobExperiments.AssignmentExperiments{},
		}
		jobAssignment := &jobs.Assignment{}

		err := svc.SetExperimentAssignmentsForJob(ctx, []string{experiments.ModelCompareExperiment}, jobAssignment, job)
		require.NoError(t, err)

		assert.False(t, mockClient.GetFeatureAssignmentCalledWithFeatureName(experiments.ModelCompareExperiment))
		_, ok := job.Experiments.Variations[experiments.ModelCompareExperiment]
		assert.False(t, ok)
	})

	t.Run("mixed experiments use correct randomization units per feature", func(t *testing.T) {
		mockClient := &experiments.MockClient{
			MockAssignment: &experiments.Assignment{
				Variation: "test-variation",
				Context:   "assignment-context",
			},
			MockOK: true,
		}
		svc := newTestServiceForExperiments(t, mockClient)
		ctx := context.Background()

		job := &jobs.Job{
			RepoID:                   int64(123),
			OwnerID:                  int64(456),
			ActorID:                  int64(789),
			PullRequestID:            int64(42),
			ActorAnalyticsTrackingID: "user-tracking-id-456",
			Experiments:              &jobExperiments.AssignmentExperiments{},
		}
		jobAssignment := &jobs.Assignment{}

		features := []string{experiments.ModelCompareExperiment, experiments.AutoModelExperiment}
		err := svc.SetExperimentAssignmentsForJob(ctx, features, jobAssignment, job)
		require.NoError(t, err)

		// ModelCompareExperiment should use PR ID
		prRU := mockClient.GetFeatureAssignmentRandomizationUnit(experiments.ModelCompareExperiment)
		require.NotNil(t, prRU)
		assert.Equal(t, experiments.GitHubPullRequestIDHeader, prRU.Header)
		assert.Equal(t, "42", prRU.Value)

		// AutoModelExperiment should use tracking ID
		trackingRU := mockClient.GetFeatureAssignmentRandomizationUnit(experiments.AutoModelExperiment)
		require.NotNil(t, trackingRU)
		assert.Equal(t, experiments.CopilotTrackingIDHeader, trackingRU.Header)
		assert.Equal(t, "user-tracking-id-456", trackingRU.Value)
	})

	t.Run("MemoryExperiment uses GitHubPullRequestIDHeader", func(t *testing.T) {
		mockClient := &experiments.MockClient{
			MockAssignment: &experiments.Assignment{
				Variation: "test-variation",
				Context:   "assignment-context",
			},
			MockOK: true,
		}
		svc := newTestServiceForExperiments(t, mockClient)
		ctx := context.Background()

		job := &jobs.Job{
			RepoID:                   int64(123),
			OwnerID:                  int64(456),
			ActorID:                  int64(789),
			PullRequestID:            int64(42),
			ActorAnalyticsTrackingID: "test-repo-id",
			Experiments:              &jobExperiments.AssignmentExperiments{},
		}
		jobAssignment := &jobs.Assignment{}

		// MemoryExperiment defaults to PR ID randomization
		err := svc.SetExperimentAssignmentsForJob(ctx, []string{experiments.MemoryExperiment}, jobAssignment, job)
		require.NoError(t, err)

		ru := mockClient.GetFeatureAssignmentRandomizationUnit(experiments.MemoryExperiment)
		require.NotNil(t, ru)
		assert.Equal(t, experiments.GitHubPullRequestIDHeader, ru.Header)
		assert.Equal(t, "42", ru.Value)
	})
}
