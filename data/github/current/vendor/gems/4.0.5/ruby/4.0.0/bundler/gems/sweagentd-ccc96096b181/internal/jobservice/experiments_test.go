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
	return New(obsv, ff, store, capi, gcf, twirp, aq, limiter, expClient, nil, "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)
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
				RepoID:        int64(123),
				OwnerID:       int64(456),
				ActorID:       int64(789),
				PullRequestID: int64(1),
				Experiments:   &jobExperiments.AssignmentExperiments{},
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
				RepoID:            int64(123),
				OwnerID:           int64(456),
				ActorID:           int64(789),
				PullRequestID:     int64(1),
				PullRequestNumber: 1,
				Experiments:       &jobExperiments.AssignmentExperiments{},
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
