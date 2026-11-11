package handlers

import (
	"context"
	"testing"

	dependencygraphv1 "github.com/github/dependency-snapshots-api/hydro/schemas/github/dependencygraph/v1"
	mockenqueuer "github.com/github/dependency-snapshots-api/internal/aqueduct/mock"
	mockstatter "github.com/github/dependency-snapshots-api/internal/testutil/mock"
	"github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/segmentio/ksuid"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

func TestSnapshotProcessedHandler_EnqueuesWhenDependencyChangeTrue(t *testing.T) {
	ctx := context.Background()
	logger := log.NewNullLogger()
	mockStatter := mockstatter.MockedStatter{}
	mockEnqueuer := mockenqueuer.MockedEnqueuer{}

	mockEnqueuer.On("Enqueue",
		mock.Anything,
		mock.MatchedBy(func(j *jobs.DenormalizeSnapshotDependenciesJob) bool {
			return j.GetRepositoryId() == 42
		}),
	).Return(ksuid.New().String(), nil).Once()

	mockStatter.On("Counter", snapshotProcessedStatsPrefix+"enqueued", mock.Anything, mock.Anything).Return().Once()

	handler := NewSnapshotProcessedHandler(logger, &mockStatter, &mockEnqueuer)

	testEnvelope := envelope(t, &dependencygraphv1.SnapshotProcessed{
		RepositoryId:     42,
		SnapshotId:       100,
		DependencyChange: wrapperspb.Bool(true),
	})

	err := handler.HandleEnvelope(ctx, testEnvelope)
	require.NoError(t, err)

	mockEnqueuer.AssertExpectations(t)
	mockStatter.AssertExpectations(t)
}

func TestSnapshotProcessedHandler_SkipsWhenDependencyChangeFalse(t *testing.T) {
	ctx := context.Background()
	logger := log.NewNullLogger()
	statter := stats.NullStatter
	mockEnqueuer := mockenqueuer.MockedEnqueuer{}

	handler := NewSnapshotProcessedHandler(logger, statter, &mockEnqueuer)

	testEnvelope := envelope(t, &dependencygraphv1.SnapshotProcessed{
		RepositoryId:     42,
		SnapshotId:       100,
		DependencyChange: wrapperspb.Bool(false),
	})

	err := handler.HandleEnvelope(ctx, testEnvelope)
	require.NoError(t, err)

	mockEnqueuer.AssertNotCalled(t, "Enqueue", mock.Anything, mock.Anything)
}

func TestSnapshotProcessedHandler_SkipsWhenDependencyChangeNil(t *testing.T) {
	ctx := context.Background()
	logger := log.NewNullLogger()
	statter := stats.NullStatter
	mockEnqueuer := mockenqueuer.MockedEnqueuer{}

	handler := NewSnapshotProcessedHandler(logger, statter, &mockEnqueuer)

	testEnvelope := envelope(t, &dependencygraphv1.SnapshotProcessed{
		RepositoryId: 42,
		SnapshotId:   100,
		// DependencyChange intentionally nil
	})

	err := handler.HandleEnvelope(ctx, testEnvelope)
	require.NoError(t, err)

	mockEnqueuer.AssertNotCalled(t, "Enqueue", mock.Anything, mock.Anything)
}
