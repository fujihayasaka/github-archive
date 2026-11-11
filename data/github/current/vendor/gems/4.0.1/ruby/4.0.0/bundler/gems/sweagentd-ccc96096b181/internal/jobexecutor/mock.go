package jobexecutor

import (
	"context"

	"github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/github"
	jobsinternal "github.com/github/sweagentd/internal/jobs"
	"github.com/stretchr/testify/mock"
)

// MockJobExecutor is a mock implementation of JobExecutor interface using testify/mock
type MockJobExecutor struct {
	mock.Mock
}

var _ JobExecutor = (*MockJobExecutor)(nil)

// NewMockJobExecutor creates a new mock JobExecutor
func NewMockJobExecutor(t mock.TestingT) *MockJobExecutor {
	m := &MockJobExecutor{}
	if t != nil {
		if cleanup, ok := t.(interface{ Cleanup(func()) }); ok {
			cleanup.Cleanup(func() { m.AssertExpectations(t) })
		}
	}
	return m
}

// ProcessJob processes a queued job.
func (m *MockJobExecutor) ProcessJob(ctx context.Context, queueJob *jobs.AgentJob) error {
	args := m.Called(ctx, queueJob)
	return args.Error(0)
}

// ExecuteJob executes a job with the provided GitHub client and session client.
func (m *MockJobExecutor) ExecuteJob(ctx context.Context, gh github.ClientInterface, sessionClient capi.SessionClient, job *jobsinternal.Job) error {
	args := m.Called(ctx, gh, sessionClient, job)
	return args.Error(0)
}

// CancelJob cancels a running or pending job.
func (m *MockJobExecutor) CancelJob(ctx context.Context, gh github.ClientInterface, job *jobsinternal.Job, repoOwner, repoName string) error {
	args := m.Called(ctx, gh, job, repoOwner, repoName)
	return args.Error(0)
}

// GetPremiumQuotaStatus checks if the user has sufficient premium quota.
func (m *MockJobExecutor) GetPremiumQuotaStatus(ctx context.Context, ownerID, repoID, userID int64) (bool, int32, error) {
	args := m.Called(ctx, ownerID, repoID, userID)
	quota, ok := args.Get(1).(int32)
	if !ok {
		quota = 0
	}
	return args.Bool(0), quota, args.Error(2)
}
