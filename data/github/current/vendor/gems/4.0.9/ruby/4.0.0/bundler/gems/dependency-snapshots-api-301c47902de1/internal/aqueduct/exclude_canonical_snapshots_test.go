package aqueduct

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/github/dependency-snapshots-api/internal/interfaces"
	mocksnapshots "github.com/github/dependency-snapshots-api/internal/snapshots/mock"
	jobsproto "github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func TestHandleExcludeCanonicalSnapshotsJob_NoCanonicalSnapshots(t *testing.T) {
	ctx := context.Background()
	logger := log.NewNullLogger()
	statter := &stubStatsClient{}
	snapshotsSvc := &mocksnapshots.MockedSnapshotsService{}
	snapshotsSvc.On("CanonicalSnapshotsForRepository", mock.Anything, uint64(123), interfaces.DefaultQueryMode).Return([]*interfaces.Snapshot{}, nil).Once()
	job := &jobsproto.ExcludeCanonicalSnapshotsJob{RepositoryId: 123}

	require.NoError(t, HandleExcludeCanonicalSnapshotsJob(ctx, nil, logger, statter, snapshotsSvc, job))

	snapshotsSvc.AssertExpectations(t)
	requireCounter(t, statter, excludeCanonicalSnapshotsMetricPrefix+"skipped", "no_canonical_snapshots")
}

func TestHandleExcludeCanonicalSnapshotsJob_Success(t *testing.T) {
	ctx := context.Background()
	logger := log.NewNullLogger()
	statter := &stubStatsClient{}
	snapshotsSvc := &mocksnapshots.MockedSnapshotsService{}

	canonical := []*interfaces.Snapshot{{ID: 1}, {ID: 2}}
	snapshotsSvc.On("CanonicalSnapshotsForRepository", mock.Anything, uint64(123), interfaces.DefaultQueryMode).Return(canonical, nil).Once()
	snapshotsSvc.On("ExcludeDependencySnapshots", mock.Anything, uint64(123), []uint64{1, 2}).Return([]uint64{1, 2}, nil).Once()

	job := &jobsproto.ExcludeCanonicalSnapshotsJob{RepositoryId: 123}

	require.NoError(t, HandleExcludeCanonicalSnapshotsJob(ctx, nil, logger, statter, snapshotsSvc, job))

	snapshotsSvc.AssertExpectations(t)
	requireCounter(t, statter, excludeCanonicalSnapshotsMetricPrefix+"success", "removed_count", "2")
}

func TestHandleExcludeCanonicalSnapshotsJob_CanonicalFetchError(t *testing.T) {
	ctx := context.Background()
	logger := log.NewNullLogger()
	statter := &stubStatsClient{}
	snapshotsSvc := &mocksnapshots.MockedSnapshotsService{}
	snapshotsSvc.On("CanonicalSnapshotsForRepository", mock.Anything, uint64(123), interfaces.DefaultQueryMode).Return([]*interfaces.Snapshot{}, errors.New("fetch failed")).Once()
	job := &jobsproto.ExcludeCanonicalSnapshotsJob{RepositoryId: 123}

	err := HandleExcludeCanonicalSnapshotsJob(ctx, nil, logger, statter, snapshotsSvc, job)

	require.Error(t, err)
	requireCounter(t, statter, excludeCanonicalSnapshotsMetricPrefix+"error", "canonical_snapshot_fetch_failed")
}

func TestHandleExcludeCanonicalSnapshotsJob_ExcludeFailure(t *testing.T) {
	ctx := context.Background()
	logger := log.NewNullLogger()
	statter := &stubStatsClient{}
	snapshotsSvc := &mocksnapshots.MockedSnapshotsService{}

	canonical := []*interfaces.Snapshot{{ID: 1}}
	snapshotsSvc.On("CanonicalSnapshotsForRepository", mock.Anything, uint64(123), interfaces.DefaultQueryMode).Return(canonical, nil).Once()
	snapshotsSvc.On("ExcludeDependencySnapshots", mock.Anything, uint64(123), []uint64{1}).Return([]uint64{}, errors.New("exclude failed")).Once()

	job := &jobsproto.ExcludeCanonicalSnapshotsJob{RepositoryId: 123}

	err := HandleExcludeCanonicalSnapshotsJob(ctx, nil, logger, statter, snapshotsSvc, job)

	require.Error(t, err)
	requireCounter(t, statter, excludeCanonicalSnapshotsMetricPrefix+"error", "exclude_failed")
}

// stubStatsClient records counter calls for assertions.
type stubStatsClient struct {
	counters []struct {
		metric string
		tags   stats.Tags
		count  int64
	}
}

func (s *stubStatsClient) Counter(metric string, tags stats.Tags, count int64) {
	s.counters = append(s.counters, struct {
		metric string
		tags   stats.Tags
		count  int64
	}{metric, tags, count})
}

// Remaining stats.Client methods are no-ops for these tests.
func (s *stubStatsClient) ClearTags() stats.Client                                 { return s }
func (s *stubStatsClient) Distribution(string, stats.Tags, float64)                {}
func (s *stubStatsClient) DistributionMs(string, stats.Tags, time.Duration)        {}
func (s *stubStatsClient) Event(string, string, stats.Tags)                        {}
func (s *stubStatsClient) Gauge(string, stats.Tags, int64)                         {}
func (s *stubStatsClient) Histogram(string, stats.Tags, int64)                     {}
func (s *stubStatsClient) Increment(string, stats.Tags)                            {}
func (s *stubStatsClient) Report(stats.Type, string, float64, stats.Tags, float32) {}
func (s *stubStatsClient) Run()                                                    {}
func (s *stubStatsClient) Set(string, stats.Tags, string)                          {}
func (s *stubStatsClient) SetPrefix(string) stats.Client                           { return s }
func (s *stubStatsClient) Start()                                                  {}
func (s *stubStatsClient) Stop()                                                   {}
func (s *stubStatsClient) Timing(string, stats.Tags, time.Duration)                {}
func (s *stubStatsClient) WithTags(stats.Tags) stats.Client                        { return s }

func requireCounter(t *testing.T, statter *stubStatsClient, metric string, key string, value ...string) {
	t.Helper()
	for _, c := range statter.counters {
		if c.metric == metric {
			if len(value) == 0 {
				require.Equal(t, key, c.tags["reason"])
			} else {
				require.Equal(t, value[0], c.tags[key])
			}
			return
		}
	}
	require.Fail(t, "counter not found", "metric=%s key=%s", metric, key)
}
