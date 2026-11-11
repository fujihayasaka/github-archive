package handlers

import (
	"context"
	"testing"

	dependencygraphv1 "github.com/github/dependency-snapshots-api/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/dependency-snapshots-api/hydro/schemas/github/v1/entities"
	mockenqueuer "github.com/github/dependency-snapshots-api/internal/aqueduct/mock"
	"github.com/github/dependency-snapshots-api/internal/config"
	mockstatter "github.com/github/dependency-snapshots-api/internal/testutil/mock"
	"github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/github-telemetry-go/log"
	"github.com/segmentio/ksuid"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func TestEnrollManifestsHandler(t *testing.T) {
	ctx := context.Background()
	cfg := &config.Config{}
	logger := log.NewNullLogger()
	mockStatter := mockstatter.MockedStatter{}
	mockEnqueuer := mockenqueuer.MockedEnqueuer{}

	// Expecting job to be enqueued
	mockEnqueuer.On("Enqueue",
		mock.Anything,
		mock.MatchedBy(func(j *jobs.DependabotSnapshotInitJob) bool {
			require.Equal(t, uint32(123), j.GetRepository().GetId())
			require.Equal(t, "refs/heads/main", j.GetRef())
			require.Equal(t, true, j.GetIsDefaultBranch())
			require.Equal(t, jobs.DependabotSnapshotInitJob_TRIGGERED_BY_ENROLLMENT, j.GetTriggeredBy())
			return true
		}),
	).Return(ksuid.New().String(), nil).Once()

	mockStatter.On("Counter", mock.Anything, mock.Anything, mock.Anything).Return().Once()

	handler := NewEnrollManifestsHandler(cfg, logger, &mockStatter, &mockEnqueuer)

	testEnvelope := envelope(t,
		&dependencygraphv1.EnrollManifests{
			Repository: &entities.Repository{
				Id: 123,
			},
		})

	err := handler.HandleEnvelope(ctx, testEnvelope)
	require.NoError(t, err)

	mockEnqueuer.AssertExpectations(t)
	mockStatter.AssertExpectations(t)
}
