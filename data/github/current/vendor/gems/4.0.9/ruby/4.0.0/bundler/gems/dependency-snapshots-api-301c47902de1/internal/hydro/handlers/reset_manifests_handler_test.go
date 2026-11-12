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

func TestResetManifestsHandler_RedetectAction(t *testing.T) {
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
			require.Equal(t, jobs.DependabotSnapshotInitJob_TRIGGERED_BY_RESET, j.GetTriggeredBy())
			return true
		}),
	).Return(ksuid.New().String(), nil).Once()

	mockStatter.On("Counter",
		resetManifestsStatsPrefix+"success",
		mock.MatchedBy(func(t mockstatter.Tags) bool {
			return t["action"] == "RESET_ACTION_REDETECT" && t["trigger"] == "RESET_TRIGGER_UNKNOWN"
		}),
		int64(1),
	).Return().Once()

	handler := NewResetManifestsHandler(cfg, logger, &mockStatter, &mockEnqueuer)

	testEnvelope := envelope(t, newResetMsg(dependencygraphv1.ResetManifests_RESET_ACTION_REDETECT))

	err := handler.HandleEnvelope(ctx, testEnvelope)
	require.NoError(t, err)

	mockEnqueuer.AssertExpectations(t)
	mockStatter.AssertExpectations(t)
}

func TestResetManifestsHandler_ClearAction(t *testing.T) {
	ctx := context.Background()
	cfg := &config.Config{}
	logger := log.NewNullLogger()
	mockStatter := mockstatter.MockedStatter{}
	mockEnqueuer := mockenqueuer.MockedEnqueuer{}

	// Expecting job to be enqueued
	mockEnqueuer.On("Enqueue",
		mock.Anything,
		mock.MatchedBy(func(j *jobs.ExcludeCanonicalSnapshotsJob) bool {
			require.Equal(t, uint32(123), j.GetRepositoryId())
			require.Equal(t, jobs.ExcludeCanonicalSnapshotsJob_TRIGGERED_BY_CLEAR_ACTION, j.GetTriggeredBy())
			return true
		}),
	).Return(ksuid.New().String(), nil).Once()

	mockStatter.On("Counter",
		resetManifestsStatsPrefix+"success",
		mock.MatchedBy(func(t mockstatter.Tags) bool {
			return t["action"] == "RESET_ACTION_CLEAR" && t["trigger"] == "RESET_TRIGGER_UNKNOWN"
		}),
		int64(1),
	).Return()

	handler := NewResetManifestsHandler(cfg, logger, &mockStatter, &mockEnqueuer)

	testEnvelope := envelope(t, newResetMsg(dependencygraphv1.ResetManifests_RESET_ACTION_CLEAR))

	err := handler.HandleEnvelope(ctx, testEnvelope)
	require.NoError(t, err)

	mockEnqueuer.AssertExpectations(t)
	mockStatter.AssertExpectations(t)
}

func TestResetManifestsHandler_UnknownAction(t *testing.T) {
	ctx := context.Background()
	cfg := &config.Config{}
	logger := log.NewNullLogger()
	mockStatter := mockstatter.MockedStatter{}
	mockEnqueuer := mockenqueuer.MockedEnqueuer{}

	// Expecting dropped event stat increment
	mockStatter.On("Counter", mock.Anything, mock.Anything, mock.Anything).Return().Once()

	handler := NewResetManifestsHandler(cfg, logger, &mockStatter, &mockEnqueuer)

	testEnvelope := envelope(t, newResetMsg(dependencygraphv1.ResetManifests_RESET_ACTION_UNKNOWN))

	err := handler.HandleEnvelope(ctx, testEnvelope)
	require.NoError(t, err)

	mockStatter.AssertExpectations(t)

	// Expecting no job to be enqueued
	mockEnqueuer.AssertNotCalled(t, "Enqueue", mock.Anything, mock.Anything)
}

func newResetMsg(action dependencygraphv1.ResetManifests_ResetAction) *dependencygraphv1.ResetManifests {
	return &dependencygraphv1.ResetManifests{
		Repository: &entities.Repository{
			Id: 123,
		},
		Action: action,
	}
}
