package handlers

import (
	"context"
	"testing"

	actionsv0 "github.com/github/dependency-snapshots-api/hydro/schemas/github/actions/v0"
	mockenqueuer "github.com/github/dependency-snapshots-api/internal/aqueduct/mock"
	"github.com/github/dependency-snapshots-api/internal/config"
	mockstatter "github.com/github/dependency-snapshots-api/internal/testutil/mock"
	"github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/segmentio/ksuid"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func TestComputeUsageHandlerForUpdateGraphEvent(t *testing.T) {
	ctx := context.Background()
	cfg := &config.Config{}
	logger := log.NewNullLogger()
	mockStatter := mockstatter.MockedStatter{}
	mockEnqueuer := mockenqueuer.MockedEnqueuer{}

	// Expecting job to be enqueued
	mockEnqueuer.On("Enqueue",
		mock.Anything,
		mock.MatchedBy(func(j *jobs.UpdateGraphComputeUsageJob) bool {
			require.Equal(t, uint64(456), j.GetRepositoryId())
			require.Equal(t, jobs.UpdateGraphComputeUsageJob_CONCLUSION_FAILURE, j.GetConclusion())
			return true
		}),
	).Return(ksuid.New().String(), nil).Once()

	mockStatter.On("Counter", mock.Anything, mock.Anything, mock.Anything).Return().Once()

	handler := NewActionsComputeUsageHandler(cfg, logger, &mockStatter, &mockEnqueuer)

	testMsg := newWorkflowMsg(t, "dynamic/dependabot/update-graph", actionsv0.ComputeUsage_RESULT_FAILURE)
	testEnvelope := envelope(t, &testMsg)

	err := handler.HandleEnvelope(ctx, testEnvelope)
	require.NoError(t, err)

	mockEnqueuer.AssertExpectations(t)
	mockStatter.AssertExpectations(t)
}

func TestComputeUsageHandlerForUnrelatedEvents(t *testing.T) {
	ctx := context.Background()
	cfg := &config.Config{}
	logger := log.NewNullLogger()
	mockStatter := mockstatter.MockedStatter{}
	mockEnqueuer := mockenqueuer.MockedEnqueuer{}

	// Expecting dropped event stat increment
	mockStatter.On("Counter", mock.Anything, mock.Anything, mock.Anything).Return().Once()

	handler := NewActionsComputeUsageHandler(cfg, logger, &mockStatter, &mockEnqueuer)

	testMsg := newWorkflowMsg(t, "dynamic/dependency-graph/auto-submission", actionsv0.ComputeUsage_RESULT_SUCCESS)
	testEnvelope := envelope(t, &testMsg)

	err := handler.HandleEnvelope(ctx, testEnvelope)
	require.NoError(t, err)

	mockStatter.AssertExpectations(t)

	// Expecting no job to be enqueued
	mockEnqueuer.AssertNotCalled(t, "Enqueue", mock.Anything, mock.Anything)
}

func TestGetConclusionFromMsg(t *testing.T) {
	tests := []struct {
		conclusion actionsv0.ComputeUsage_Conclusion
		expected   jobs.UpdateGraphComputeUsageJob_Conclusion
	}{
		{
			conclusion: actionsv0.ComputeUsage_RESULT_SUCCESS,
			expected:   jobs.UpdateGraphComputeUsageJob_CONCLUSION_SUCCESS,
		},
		{
			conclusion: actionsv0.ComputeUsage_RESULT_FAILURE,
			expected:   jobs.UpdateGraphComputeUsageJob_CONCLUSION_FAILURE,
		},
		{
			conclusion: actionsv0.ComputeUsage_RESULT_SKIPPED,
			expected:   jobs.UpdateGraphComputeUsageJob_CONCLUSION_SKIPPED,
		},
		{
			conclusion: actionsv0.ComputeUsage_RESULT_CANCELLED,
			expected:   jobs.UpdateGraphComputeUsageJob_CONCLUSION_CANCELLED,
		},
		{
			conclusion: actionsv0.ComputeUsage_RESULT_UNKNOWN,
			expected:   jobs.UpdateGraphComputeUsageJob_CONCLUSION_UNKNOWN,
		},
		{
			conclusion: actionsv0.ComputeUsage_Conclusion(999),
			expected:   jobs.UpdateGraphComputeUsageJob_CONCLUSION_UNKNOWN,
		},
	}

	for _, test := range tests {
		t.Run(test.conclusion.String(), func(t *testing.T) {
			cfg := &config.Config{}
			logger := log.NewNullLogger()
			mockStatter := stats.NullClient{}
			mockEnqueuer := mockenqueuer.MockedEnqueuer{}

			handler := NewActionsComputeUsageHandler(cfg, logger, &mockStatter, &mockEnqueuer)

			msg := &actionsv0.ComputeUsage{
				CheckRunConclusion: test.conclusion,
			}

			require.Equal(t, test.expected, handler.getConclusionFromMsg(msg, logger))
		})
	}
}

func TestGetRunnerRuntimeFromMsg(t *testing.T) {
	tests := []struct {
		runtime  actionsv0.ComputeUsage_RunnerRuntime
		expected string
	}{
		{
			runtime:  actionsv0.ComputeUsage_RUNNER_RUNTIME_LINUX,
			expected: "linux",
		},
		{
			runtime:  actionsv0.ComputeUsage_RUNNER_RUNTIME_MACOS,
			expected: "macos",
		},
		{
			runtime:  actionsv0.ComputeUsage_RUNNER_RUNTIME_WINDOWS,
			expected: "windows",
		},
		{
			runtime:  actionsv0.ComputeUsage_RunnerRuntime(999),
			expected: "unknown",
		},
	}

	for _, test := range tests {
		t.Run(test.runtime.String(), func(t *testing.T) {
			cfg := &config.Config{}
			logger := log.NewNullLogger()
			mockStatter := stats.NullClient{}
			mockEnqueuer := mockenqueuer.MockedEnqueuer{}

			handler := NewActionsComputeUsageHandler(cfg, logger, &mockStatter, &mockEnqueuer)

			msg := &actionsv0.ComputeUsage{
				RunnerRuntime: test.runtime,
			}

			require.Equal(t, test.expected, handler.getRunnerRuntimeFromMsg(msg, logger))
		})
	}
}

func TestGetRunnerTypeFromMsg(t *testing.T) {
	tests := []struct {
		runnerType actionsv0.ComputeUsage_RunnerType
		expected   string
	}{
		{
			runnerType: actionsv0.ComputeUsage_RUNNER_TYPE_SELF_HOSTED,
			expected:   "self-hosted",
		},
		{
			runnerType: actionsv0.ComputeUsage_RUNNER_TYPE_HOSTED,
			expected:   "hosted",
		},
		{
			runnerType: actionsv0.ComputeUsage_RUNNER_TYPE_HOSTED_LARGER,
			expected:   "hosted-large",
		},
		{
			runnerType: actionsv0.ComputeUsage_RunnerType(999),
			expected:   "unknown",
		},
	}

	for _, test := range tests {
		t.Run(test.runnerType.String(), func(t *testing.T) {
			cfg := &config.Config{}
			logger := log.NewNullLogger()
			mockStatter := stats.NullClient{}
			mockEnqueuer := mockenqueuer.MockedEnqueuer{}

			handler := NewActionsComputeUsageHandler(cfg, logger, &mockStatter, &mockEnqueuer)

			msg := &actionsv0.ComputeUsage{
				RunnerType: test.runnerType,
			}

			require.Equal(t, test.expected, handler.getRunnerTypeFromMsg(msg, logger))
		})
	}
}

func newWorkflowMsg(t *testing.T, workflowFilePath string, conclusion actionsv0.ComputeUsage_Conclusion) actionsv0.ComputeUsage {
	t.Helper()

	return actionsv0.ComputeUsage{
		CheckRunConclusion: conclusion,
		InvokingUserId:     123,
		InvokingEventType:  "dynamic",
		JobUserIdentifier:  "dependabot",
		JobName:            []byte("submit-maven"),
		RepositoryId:       456,
		RepositoryOwnerId:  789,
		WorkflowFilePath:   []byte(workflowFilePath),
		WorkflowJobId:      "fake-workflow-jid",
		WorkflowRunId:      1111,
		WorkflowRunAttempt: 1,
		RunnerRuntime:      actionsv0.ComputeUsage_RUNNER_RUNTIME_MACOS,
		RunnerType:         actionsv0.ComputeUsage_RUNNER_TYPE_HOSTED_LARGER,
	}
}
