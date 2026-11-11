package aqueduct

import (
	"context"
	"testing"
	"time"

	jobs_proto "github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestHandleUpdateGraphComputeUsageJob_RetryIgnored(t *testing.T) {
	ctx := context.Background()
	logger := log.NewNullLogger()
	st := &captureStatsClient{}

	job := newUpdateGraphComputeUsageJob(jobs_proto.UpdateGraphComputeUsageJob_CONCLUSION_FAILURE)
	job.WorkflowRunAttempt = 2

	require.NoError(t, HandleUpdateGraphComputeUsageJob(ctx, nil, logger, st, job))

	require.Len(t, st.counterCalls, 1)
	require.Equal(t, updateGraphMetricsPrefix+"complete", st.counterCalls[0].metric)
	require.Equal(t, "ignored", st.counterCalls[0].tags["outcome"])
	require.Equal(t, "retry", st.counterCalls[0].tags["ignore_reason"])
	require.Equal(t, 2, len(st.distributionMsCalls))
}

func TestHandleUpdateGraphComputeUsageJob_SuccessAndFailureMetrics(t *testing.T) {
	ctx := context.Background()
	logger := log.NewNullLogger()

	// Success case
	successStats := &captureStatsClient{}
	successJob := newUpdateGraphComputeUsageJob(jobs_proto.UpdateGraphComputeUsageJob_CONCLUSION_SUCCESS)
	require.NoError(t, HandleUpdateGraphComputeUsageJob(ctx, nil, logger, successStats, successJob))
	require.Len(t, successStats.counterCalls, 1)
	require.Equal(t, "success", successStats.counterCalls[0].tags["outcome"])
	require.Equal(t, 2, len(successStats.distributionMsCalls))
	require.Equal(t, time.Minute, successStats.distributionMsCalls[0].duration)
	require.Equal(t, time.Minute, successStats.distributionMsCalls[1].duration)
	require.Equal(t, "maven", successStats.counterCalls[0].tags["ecosystem"])

	// Failure case
	failureStats := &captureStatsClient{}
	failureJob := newUpdateGraphComputeUsageJob(jobs_proto.UpdateGraphComputeUsageJob_CONCLUSION_FAILURE)
	require.NoError(t, HandleUpdateGraphComputeUsageJob(ctx, nil, logger, failureStats, failureJob))
	require.Len(t, failureStats.counterCalls, 1)
	require.Equal(t, "failed", failureStats.counterCalls[0].tags["outcome"])
	require.Equal(t, "run_dependabot", failureStats.counterCalls[0].tags["failure_reason"])
}

func newUpdateGraphComputeUsageJob(conclusion jobs_proto.UpdateGraphComputeUsageJob_Conclusion) *jobs_proto.UpdateGraphComputeUsageJob {
	queued := timestamppb.New(time.Unix(0, 0))
	started := timestamppb.New(time.Unix(int64(time.Minute.Seconds()), 0))
	completed := timestamppb.New(time.Unix(int64((2 * time.Minute).Seconds()), 0))

	return &jobs_proto.UpdateGraphComputeUsageJob{
		Conclusion:         conclusion,
		RepositoryId:       123,
		RepositoryOwnerId:  456,
		WorkflowJobId:      "job-1",
		WorkflowRunId:      789,
		WorkflowRunAttempt: 1,
		QueuedAt:           queued,
		StartedAt:          started,
		CompletedAt:        completed,
		RunnerRuntime:      "linux",
		RunnerType:         "hosted",
		JobName:            "update-maven-graph",
	}
}

type ugCounterCall struct {
	metric string
	tags   stats.Tags
	count  int64
}

type ugDistributionMsCall struct {
	metric   string
	tags     stats.Tags
	duration time.Duration
}

type captureStatsClient struct {
	counterCalls        []ugCounterCall
	distributionMsCalls []ugDistributionMsCall
}

func (m *captureStatsClient) Counter(metric string, tags stats.Tags, count int64) {
	m.counterCalls = append(m.counterCalls, ugCounterCall{metric, tags, count})
}

func (m *captureStatsClient) DistributionMs(metric string, tags stats.Tags, duration time.Duration) {
	m.distributionMsCalls = append(m.distributionMsCalls, ugDistributionMsCall{metric, tags, duration})
}

// Remaining stats.Client methods are no-ops for these tests.
func (m *captureStatsClient) ClearTags() stats.Client                                 { return m }
func (m *captureStatsClient) Distribution(string, stats.Tags, float64)                {}
func (m *captureStatsClient) Event(string, string, stats.Tags)                        {}
func (m *captureStatsClient) Gauge(string, stats.Tags, int64)                         {}
func (m *captureStatsClient) Histogram(string, stats.Tags, int64)                     {}
func (m *captureStatsClient) Increment(string, stats.Tags)                            {}
func (m *captureStatsClient) Report(stats.Type, string, float64, stats.Tags, float32) {}
func (m *captureStatsClient) Run()                                                    {}
func (m *captureStatsClient) Set(string, stats.Tags, string)                          {}
func (m *captureStatsClient) SetPrefix(string) stats.Client                           { return m }
func (m *captureStatsClient) Start()                                                  {}
func (m *captureStatsClient) Stop()                                                   {}
func (m *captureStatsClient) Timing(string, stats.Tags, time.Duration)                {}
func (m *captureStatsClient) WithTags(stats.Tags) stats.Client                        { return m }

func assertAnError(t *testing.T) error {
	t.Helper()
	return assert.AnError
}
