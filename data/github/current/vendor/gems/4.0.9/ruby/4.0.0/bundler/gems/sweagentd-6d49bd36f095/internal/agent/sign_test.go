package agent

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/customagenttest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestServiceSignCommit(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	cf := &github.NoopClientFactory{}
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	spokes := customagenttest.MakeSpokes(t, map[string]string{})

	job := &jobs.Job{
		ID:      "1-2-sign-uuid",
		OwnerID: 1,
		RepoID:  2,
		ActorID: 42,
		AgentID: 7,
		Status:  jobs.JobStatusRunning,
	}
	_, err := store.CreateJob(ctx, job)
	require.NoError(t, err)

	t.Run("success passes correct fields to twirp", func(t *testing.T) {
		var capturedReq *sweagentdTwirp.SignCommitRequest
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.MockSignCommit = func(ctx context.Context, req *sweagentdTwirp.SignCommitRequest) (*sweagentdTwirp.SignCommitResponse, error) {
			capturedReq = req
			return &sweagentdTwirp.SignCommitResponse{Signature: "test-sig"}, nil
		}
		customAgentSvc := customagent.NewService(obsv, spokes, noopClient, ffClient)
		svc := NewService(store, cf, customAgentSvc, nil, obsv, ffClient, noopClient, &mockEmitter{}, agenticapptest.NewTestProvider(t), nil, nil)

		sig, err := svc.SignCommit(ctx, job, "test-payload")
		require.NoError(t, err)
		assert.Equal(t, "test-sig", sig)

		require.NotNil(t, capturedReq)
		assert.Equal(t, uint64(2), capturedReq.RepositoryId)
		assert.Equal(t, "test-payload", capturedReq.Payload)
		assert.Equal(t, int64(7), capturedReq.AgentId)
		assert.Equal(t, uint64(42), capturedReq.AttributionUserId)
	})

	t.Run("returns error from twirp", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.MockSignCommit = func(ctx context.Context, req *sweagentdTwirp.SignCommitRequest) (*sweagentdTwirp.SignCommitResponse, error) {
			return nil, goerrors.New("signing failed")
		}
		customAgentSvc := customagent.NewService(obsv, spokes, noopClient, ffClient)
		svc := NewService(store, cf, customAgentSvc, nil, obsv, ffClient, noopClient, &mockEmitter{}, agenticapptest.NewTestProvider(t), nil, nil)

		sig, err := svc.SignCommit(ctx, job, "test-payload")
		require.Error(t, err)
		assert.Empty(t, sig)
		assert.Contains(t, err.Error(), "signing failed")
	})
}
