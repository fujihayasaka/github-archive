package jobservice

import (
	"context"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/command"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/require"
)

func newMockTwirpClient() *githubtwirp.NoopClient {
	client := githubtwirp.NewNoopClient()
	client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
			},
		}, nil
	}
	return client
}

func TestCreateCommandForJob_Success(t *testing.T) {
	store := memory.NewStore()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	obsv := observability.NewNoopExporters()
	twirp := newMockTwirpClient()
	service := &Service{
		store: store,
		obsv:  obsv,
		ffs:   ffClient,
		twirp: twirp,
	}

	job := &jobs.Job{
		ID:        "job-id",
		SessionID: "session-id",
		OwnerID:   1,
		RepoID:    2,
		RepoOwner: "owner",
		RepoName:  "repo",
		Status:    jobs.JobStatusRunning,
	}

	ctx := context.Background()
	job, err := store.CreateJob(ctx, job)
	require.NoError(t, err)

	externalID := "external-id"
	actorID := int64(42)
	content := "This is a test command"
	timestamp := int64(1234567890)

	cmd, err := service.CreateCommandForJob(ctx, job, externalID, actorID, content, timestamp)
	require.NoError(t, err)
	require.NotNil(t, cmd)
	require.Equal(t, job.SessionID, cmd.SessionID)
	require.Equal(t, externalID, cmd.ExternalID)
	require.Equal(t, actorID, cmd.ActorID)
	require.Equal(t, content, cmd.Content)
	require.Equal(t, command.TypeUserMessage, cmd.Type)
	require.Equal(t, command.StatusPending, cmd.Status)
	require.Equal(t, timestamp, cmd.ExternalTimestamp)
}

func TestCreateCommandForJob_Terminal(t *testing.T) {
	store := memory.NewStore()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	twirp := newMockTwirpClient()
	service := &Service{
		store: store,
		obsv:  obsv,
		ffs:   ffClient,
		twirp: twirp,
	}

	job := &jobs.Job{
		ID:        "job-id",
		SessionID: "session-id",
		OwnerID:   1,
		RepoID:    2,
		RepoOwner: "owner",
		RepoName:  "repo",
		Status:    jobs.JobStatusCompleted,
	}

	ctx := context.Background()
	job, err := store.CreateJob(ctx, job)
	require.NoError(t, err)

	externalID := "external-id"
	actorID := int64(42)
	content := "This is a test command"
	timestamp := int64(1234567890)

	cmd, err := service.CreateCommandForJob(ctx, job, externalID, actorID, content, timestamp)
	require.Error(t, err)
	require.Nil(t, cmd)
	require.ErrorIs(t, err, command.ErrJobIsTerminal)
}
