package twirpserver

import (
	"context"
	"errors"
	"testing"

	"github.com/github/go-mark"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobexecutor"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/observability"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

type mockJobCanceller struct {
	err          error
	cancelCalled bool
}

func (m *mockJobCanceller) CancelJob(_ context.Context, _ github.ClientInterface, _ *jobs.Job, _, _ string) error {
	m.cancelCalled = true
	return m.err
}

func (m *mockJobCanceller) ProcessJob(_ context.Context, _ *aqueductJobs.AgentJob) error {
	return nil
}

func (m *mockJobCanceller) GetQuotaStatus(_ context.Context, _, _, _ int64) (bool, int32, bool, error) {
	return false, 0, false, nil
}

func newCancelJobTestServer(t *testing.T, jobStore *memory.Store, canceller jobexecutor.JobExecutor) *Server {
	t.Helper()

	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	ghf := &github.NoopClientFactory{}
	mockGhTwirp := &githubtwirp.NoopClient{}
	appProvider := agenticapptest.NewTestProvider(t)

	jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, nil, nil, nil, nil, "test", "test@example.com", nil, appProvider, nil)

	return NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, appProvider, canceller, nil, nil, nil)
}

func TestCancelJob_Validation(t *testing.T) {
	tests := []struct {
		name    string
		req     *jobs_pb.CancelJobRequest
		wantArg string
	}{
		{
			name:    "missing session_id",
			req:     &jobs_pb.CancelJobRequest{OwnerId: 1, RepoId: 2},
			wantArg: "session_id",
		},
		{
			name:    "missing owner_id",
			req:     &jobs_pb.CancelJobRequest{SessionId: "s1", RepoId: 2},
			wantArg: "owner_id",
		},
		{
			name:    "missing repo_id",
			req:     &jobs_pb.CancelJobRequest{SessionId: "s1", OwnerId: 1},
			wantArg: "repo_id",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			jobStore := memory.NewStore()
			server := newCancelJobTestServer(t, jobStore, &mockJobCanceller{})

			_, err := server.CancelJob(t.Context(), tt.req)
			require.Error(t, err)
			var twerr twirp.Error
			require.True(t, errors.As(err, &twerr))
			require.Equal(t, twirp.InvalidArgument, twerr.Code())
			require.Contains(t, twerr.Meta("argument"), tt.wantArg)
		})
	}
}

func TestCancelJob_JobNotFound(t *testing.T) {
	jobStore := memory.NewStore()
	server := newCancelJobTestServer(t, jobStore, &mockJobCanceller{})

	_, err := server.CancelJob(t.Context(), &jobs_pb.CancelJobRequest{
		SessionId: "nonexistent",
		OwnerId:   1,
		RepoId:    2,
	})

	require.Error(t, err)
	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr))
	require.Equal(t, twirp.NotFound, twerr.Code())
}

func TestCancelJob_Success(t *testing.T) {
	ctx := t.Context()
	jobStore := memory.NewStore()
	canceller := &mockJobCanceller{}
	server := newCancelJobTestServer(t, jobStore, canceller)

	_, _ = jobStore.CreateJob(ctx, &jobs.Job{
		ID:        "job-1",
		SessionID: "session-1",
		OwnerID:   1,
		RepoID:    2,
		Status:    jobs.JobStatusRunning,
		AgentID:   0,
	})

	resp, err := server.CancelJob(ctx, &jobs_pb.CancelJobRequest{
		SessionId: "session-1",
		OwnerId:   1,
		RepoId:    2,
	})

	require.NoError(t, err)
	require.NotNil(t, resp)
	require.True(t, canceller.cancelCalled, "expected CancelJob to be called on the executor")
}

func TestCancelJob_AlreadyTerminal(t *testing.T) {
	ctx := t.Context()
	jobStore := memory.NewStore()
	canceller := &mockJobCanceller{
		err: mark.With(mark.ErrAlreadyExists, errors.New("cannot cancel a job that is completed")),
	}
	server := newCancelJobTestServer(t, jobStore, canceller)

	_, _ = jobStore.CreateJob(ctx, &jobs.Job{
		ID:        "job-1",
		SessionID: "session-1",
		OwnerID:   1,
		RepoID:    2,
		Status:    jobs.JobStatusCompleted,
		AgentID:   0,
	})

	_, err := server.CancelJob(ctx, &jobs_pb.CancelJobRequest{
		SessionId: "session-1",
		OwnerId:   1,
		RepoId:    2,
	})

	require.Error(t, err)
	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr))
	require.Equal(t, twirp.FailedPrecondition, twerr.Code())
}
