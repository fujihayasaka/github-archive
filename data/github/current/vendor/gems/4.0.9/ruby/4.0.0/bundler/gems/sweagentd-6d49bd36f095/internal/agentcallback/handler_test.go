package agentcallback

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	authd "github.com/github/authnd/client"
	billingProto "github.com/github/billing-platform/clients/go/v1/go-client/lib/twirp/proto"
	billingMocks "github.com/github/billing-platform/clients/go/v1/go-client/mocks"
	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/firewall"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/command"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/launcher"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/testutils"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

// copilotBotLogin is the GitHub login used by the Copilot bot in tests.
// The test provider (appID=1) uses this as its bot login.
const copilotBotLogin = "github-copilot-bot"

// mockJobService is a simple mock implementation of the jobservice interface
type mockJobService struct {
	store                         jobstore
	mockUpdateFromExecutionResult func(context.Context, *jobs.Job, jobs.JobStatus, time.Time) error
	mockUpdateSession             func(context.Context, *jobs.Job, capi.SessionUpdate) error
	mockFinalizeJob               func(context.Context, *jobs.Job, jobs.JobStatus, *jobs.JobError, int64) error
}

func (m *mockJobService) GetJobByID(ctx context.Context, ownerID, repoID int64, jobID string) (*jobs.Job, error) {
	return m.store.GetJob(ctx, ownerID, repoID, jobID)
}

func (m *mockJobService) UpdateFromExecutionResult(ctx context.Context, job *jobs.Job, newStatus jobs.JobStatus, runningAt time.Time) error {
	if m.mockUpdateFromExecutionResult != nil {
		return m.mockUpdateFromExecutionResult(ctx, job, newStatus, runningAt)
	}
	return nil
}

func (m *mockJobService) UpdateSession(ctx context.Context, job *jobs.Job, update capi.SessionUpdate) error {
	if m.mockUpdateSession != nil {
		return m.mockUpdateSession(ctx, job, update)
	}
	return nil
}

func (m *mockJobService) FinalizeJob(ctx context.Context, job *jobs.Job, jobStatus jobs.JobStatus, jobError *jobs.JobError, completedAt int64) error {
	if m.mockFinalizeJob != nil {
		return m.mockFinalizeJob(ctx, job, jobStatus, jobError, completedAt)
	}
	return nil
}

func TestAgentCallbackBadRequests(t *testing.T) {
	ffClient := featureflags.NewNoopClient(nil)
	obsv := observability.NewNoopExporters()
	jobStore := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
		IsAgentEnabled: true,
	})
	jobService := &mockJobService{store: jobStore}
	capiClient := capi.NewNoopClient()
	appProvider := agenticapptest.NewTestProviderWithID(t, 12345)
	h := NewHandler(obsv, jobService, capiClient, jobStore, cf, ffClient, noopClient, 1, appProvider)

	t.Run("bad request", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs", http.NoBody)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("job already complete", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()
		// setup job
		job := &jobs.Job{
			ID:           "job-id",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			Status:       jobs.JobStatusCompleted,
			ActorID:      1,
			NonceHash:    nonceHash,
		}
		jobStore.CreateJob(ctx, job)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "job-id",
			Kind:        AgentUpdateKindProgress,
		}
		b, _ := json.Marshal(update)
		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("invalid kind", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		// setup job
		job := &jobs.Job{
			ID:           "job-id",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      1,
			NonceHash:    nonceHash,
		}
		jobStore.CreateJob(ctx, job)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "job-id",
			Kind:        "invalid",
		}
		b, _ := json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("wrong actor is authed", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		// setup job
		job := &jobs.Job{
			ID:           "job-id",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      2,
			NonceHash:    nonceHash,
		}
		jobStore.CreateJob(ctx, job)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "job-id",
			Kind:        AgentUpdateKindResult,
		}
		b, _ := json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("s2s token skips enablement check and uses job actor ID", func(t *testing.T) {
		// Configure the mock to return IsAgentEnabled=false. With a U2S token
		// this would 404, but S2S tokens should bypass the enablement check.
		disabledClient := githubtwirp.NewNoopClient()
		disabledClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: false,
		})
		disabledHandler := NewHandler(obsv, jobService, capi.NewNoopClient(), jobStore, cf, ffClient, disabledClient, 1, appProvider)

		ctx := addS2SUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		// ActorID (77777) differs from user.ID (99999) to verify S2S uses job's ActorID.
		job := &jobs.Job{
			ID:           "s2s-job-id",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      77777,
			NonceHash:    nonceHash,
			Action:       jobs.AgentActionFix,
		}
		jobStore.CreateJob(ctx, job)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "s2s-job-id",
			Kind:        AgentUpdateKindProgress,
			Content:     `{"message":"working on it"}`,
		}
		b, _ := json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		disabledHandler.HandleCallback(w, req)
		// Should succeed (200) because S2S bypasses enablement AND uses job.ActorID
		require.NotEqual(t, http.StatusNotFound, w.Code, "S2S token should skip enablement check and use job actor ID")
	})
}

func TestAgentCallbackHandleFixResult(t *testing.T) {
	ffClient := featureflags.NewNoopClient(nil)
	obsv := observability.NewNoopExporters()
	jobStore := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
		IsAgentEnabled: true,
	})
	jobService := &mockJobService{store: jobStore}
	capiClient := capi.NewNoopClient()
	appProvider := agenticapptest.NewTestProviderWithID(t, 12345)
	h := NewHandler(obsv, jobService, capiClient, jobStore, cf, ffClient, noopClient, 1, appProvider)

	t.Run("invalid content", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		assignment := &jobs.Assignment{
			ID:                "assignment-id",
			RepoID:            2,
			OwnerID:           1,
			PullRequestID:     1,
			PullRequestNumber: 1,
		}
		jobStore.CreateAssignment(ctx, assignment)

		// setup job
		job := &jobs.Job{
			ID:           "job-id",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      1,
			NonceHash:    nonceHash,
			Action:       jobs.AgentActionFix,
		}
		jobStore.CreateJob(ctx, job)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "job-id",
			Kind:        AgentUpdateKindResult,
		}
		b, _ := json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusInternalServerError, w.Code)
	})

	t.Run("invalid PR description", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		// setup job
		job := &jobs.Job{
			ID:           "job-id",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      1,
			NonceHash:    nonceHash,
			Action:       jobs.AgentActionFix,
		}
		jobStore.CreateJob(ctx, job)

		u := fixResultUpdate{}
		b, _ := json.Marshal(u)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "job-id",
			Kind:        AgentUpdateKindResult,
			Content:     string(b),
		}
		b, _ = json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusInternalServerError, w.Code)
	})

	t.Run("successful run", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		// setup job
		job := &jobs.Job{
			ID:           "job-id",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      1,
			NonceHash:    nonceHash,
			Action:       jobs.AgentActionFix,
		}
		jobStore.CreateJob(ctx, job)

		u := fixResultUpdate{
			PRTitle:       "hello",
			PRDescription: "world",
		}
		b, _ := json.Marshal(u)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "job-id",
			Kind:        AgentUpdateKindResult,
			Content:     string(b),
		}
		b, _ = json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusOK, w.Code)
	})
}

func TestHandleFixResultPR(t *testing.T) {
	t.Run("update PR if job has PR", func(t *testing.T) {
		gh := &github.NoopClient{}
		cf := &github.NoopClientFactory{MockNewClientFromRepo: func(ctx context.Context, repoID, ownerID int64) (github.ClientInterface, error) {
			return gh, nil
		}}
		jm := &jobManager{
			obsv:        observability.NewNoopExporters(),
			clients:     cf,
			ffClient:    featureflags.NewNoopClient(nil),
			appProvider: agenticapptest.NewTestProvider(t),
			jobService:  &mockJobService{},
		}
		update := JobUpdate{
			Content: `{"prTitle":"hello","prDescription":"world"}`,
		}
		ctx := context.Background()
		job := &jobs.Job{
			PullRequestID:     1,
			PullRequestNumber: 2,
		}
		_, err := jm.handleFixResult(ctx, nil, job, update)

		require.NoError(t, err)
		require.NotZero(t, gh.MethodCalls)
	})

	t.Run("does not update PR if job has no PR", func(t *testing.T) {
		gh := &github.NoopClient{}
		cf := &github.NoopClientFactory{MockNewClientFromRepo: func(ctx context.Context, repoID, ownerID int64) (github.ClientInterface, error) {
			return gh, nil
		}}
		jm := &jobManager{
			obsv:        observability.NewNoopExporters(),
			clients:     cf,
			ffClient:    featureflags.NewNoopClient(nil),
			appProvider: agenticapptest.NewTestProvider(t),
			jobService:  &mockJobService{},
		}
		update := JobUpdate{
			Content: `{"prTitle":"hello","prDescription":"world"}`,
		}
		ctx := context.Background()
		job := &jobs.Job{}
		_, err := jm.handleFixResult(ctx, nil, job, update)

		require.NoError(t, err)
		require.Zero(t, gh.MethodCalls)
	})

	t.Run("does not update PR for code_review_fix_with_copilot when flag enabled", func(t *testing.T) {
		gh := &github.NoopClient{}
		cf := &github.NoopClientFactory{MockNewClientFromRepo: func(ctx context.Context, repoID, ownerID int64) (github.ClientInterface, error) {
			return gh, nil
		}}
		jm := &jobManager{
			obsv:    observability.NewNoopExporters(),
			clients: cf,
			ffClient: featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForCodeReviewFixJobs: true,
			}),
			appProvider: agenticapptest.NewTestProvider(t),
			jobService:  &mockJobService{},
		}
		update := JobUpdate{
			Content: `{"prTitle":"hello","prDescription":"world"}`,
		}
		ctx := context.Background()
		job := &jobs.Job{
			PullRequestID:     1,
			PullRequestNumber: 2,
			EventType:         jobs.EventTypeCodeReviewFixWithCopilot,
		}
		_, err := jm.handleFixResult(ctx, nil, job, update)

		require.NoError(t, err)
		require.Zero(t, gh.MethodCalls)
	})

	t.Run("stores PR title and description on job for Hydro event", func(t *testing.T) {
		jm := &jobManager{
			obsv:       observability.NewNoopExporters(),
			jobService: &mockJobService{},
		}
		job := &jobs.Job{UseAsyncSessions: true}
		update := JobUpdate{Content: `{"prTitle":"fix title","prDescription":"fix description"}`}

		_, err := jm.handleFixResult(context.Background(), nil, job, update)
		require.NoError(t, err)
		require.Equal(t, "fix title", job.PullRequestTitle)
		require.Equal(t, "fix description", job.PullRequestDescription)
	})

	t.Run("updates session via CAPI when non-async", func(t *testing.T) {
		var receivedUpdate capi.SessionUpdate
		called := false
		jm := &jobManager{
			obsv: observability.NewNoopExporters(),
			jobService: &mockJobService{mockUpdateSession: func(_ context.Context, _ *jobs.Job, update capi.SessionUpdate) error {
				called = true
				receivedUpdate = update
				return nil
			}},
		}
		job := &jobs.Job{UseAsyncSessions: false}
		update := JobUpdate{Content: `{"prTitle":"fix title","prDescription":"fix description"}`}

		_, err := jm.handleFixResult(context.Background(), nil, job, update)
		require.NoError(t, err)
		require.True(t, called)
		require.Equal(t, "fix title", receivedUpdate.GeneratedPullData.Title)
		require.Equal(t, "fix description", receivedUpdate.GeneratedPullData.Description)
	})

	t.Run("does not update session when async sessions are enabled", func(t *testing.T) {
		called := false
		jm := &jobManager{
			obsv: observability.NewNoopExporters(),
			jobService: &mockJobService{mockUpdateSession: func(_ context.Context, _ *jobs.Job, _ capi.SessionUpdate) error {
				called = true
				return nil
			}},
		}
		job := &jobs.Job{UseAsyncSessions: true}
		update := JobUpdate{Content: `{"prTitle":"fix title","prDescription":"fix description"}`}

		_, err := jm.handleFixResult(context.Background(), nil, job, update)
		require.NoError(t, err)
		require.False(t, called)
	})
}

func TestAgentCallbackHandleFixResultPRComment(t *testing.T) {
	ffClient := featureflags.NewNoopClient(nil)
	obsv := observability.NewNoopExporters()
	jobStore := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
		IsAgentEnabled: true,
	})
	jobService := &mockJobService{store: jobStore}
	capiClient := capi.NewNoopClient()
	appProvider := agenticapptest.NewTestProviderWithID(t, 12345)
	h := NewHandler(obsv, jobService, capiClient, jobStore, cf, ffClient, noopClient, 1, appProvider)

	t.Run("invalid content", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		assignment := &jobs.Assignment{
			ID:                "assignment-id",
			OwnerID:           1,
			RepoID:            2,
			PullRequestID:     1,
			PullRequestNumber: 1,
		}
		jobStore.CreateAssignment(ctx, assignment)

		// setup job
		job := &jobs.Job{
			ID:           "job-id",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      1,
			NonceHash:    nonceHash,
			Action:       jobs.AgentActionFixPRComment,
		}
		jobStore.CreateJob(ctx, job)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "job-id",
			Kind:        AgentUpdateKindResult,
		}
		b, _ := json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusInternalServerError, w.Code)
	})

	t.Run("successful run", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		// setup job
		job := &jobs.Job{
			ActorID:      1,
			ID:           "job-id",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			Args: launcher.LaunchAgentOpts{
				ActorLogin:  "actor",
				IssueNumber: 1,
				PRNumber:    3,
			},
			NonceHash: nonceHash,
			Action:    jobs.AgentActionFixPRComment,
		}
		jobStore.CreateJob(ctx, job)

		u := fixResultUpdate{}
		b, _ := json.Marshal(u)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "job-id",
			Kind:        AgentUpdateKindResult,
			Content:     string(b),
		}
		b, _ = json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusOK, w.Code)
	})
}

func TestAgentCallbackHandleTaskResult(t *testing.T) {
	ffClient := featureflags.NewNoopClient(nil)
	obsv := observability.NewNoopExporters()
	jobStore := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
		IsAgentEnabled: true,
	})
	jobService := &mockJobService{store: jobStore}
	capiClient := capi.NewNoopClient()
	appProvider := agenticapptest.NewTestProviderWithID(t, 12345)
	h := NewHandler(obsv, jobService, capiClient, jobStore, cf, ffClient, noopClient, 1, appProvider)

	t.Run("invalid content", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		assignment := &jobs.Assignment{
			ID:                "assignment-id",
			RepoID:            2,
			OwnerID:           1,
			PullRequestID:     0,
			PullRequestNumber: 0,
		}
		jobStore.CreateAssignment(ctx, assignment)

		// setup job
		job := &jobs.Job{
			ID:           "job-id",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      1,
			NonceHash:    nonceHash,
			Action:       jobs.AgentActionTask,
		}
		jobStore.CreateJob(ctx, job)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "job-id",
			Kind:        AgentUpdateKindResult,
		}
		b, _ := json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusInternalServerError, w.Code)
	})

	t.Run("successful run", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		// setup job
		job := &jobs.Job{
			ID:           "job-id",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      1,
			NonceHash:    nonceHash,
			Action:       jobs.AgentActionTask,
		}
		jobStore.CreateJob(ctx, job)

		u := taskResult{}
		b, _ := json.Marshal(u)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "job-id",
			Kind:        AgentUpdateKindResult,
			Content:     string(b),
		}
		b, _ = json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusOK, w.Code)
	})

	t.Run("successful run with blocked requests", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		// setup job
		job := &jobs.Job{
			ID:           "job-id",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      1,
			NonceHash:    nonceHash,
			Action:       jobs.AgentActionTask,
		}
		jobStore.CreateJob(ctx, job)

		u := taskResult{
			BlockedRequests: []firewall.BlockedRequest{
				{URL: "https://example.com"},
			},
		}
		b, _ := json.Marshal(u)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "job-id",
			Kind:        AgentUpdateKindResult,
			Content:     string(b),
		}
		b, _ = json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusOK, w.Code)
	})
}

func TestHandleTaskResultPRTitleDescription(t *testing.T) {
	t.Run("sets PR title and description on job and result", func(t *testing.T) {
		jm := &jobManager{
			obsv:       observability.NewNoopExporters(),
			jobService: &mockJobService{},
		}

		job := &jobs.Job{}
		update := JobUpdate{Content: `{"prTitle":"new title","prDescription":"new description"}`}

		res, err := jm.handleTaskResult(context.Background(), nil, job, update)
		require.NoError(t, err)
		require.Equal(t, "new title", job.PullRequestTitle)
		require.Equal(t, "new description", job.PullRequestDescription)

		tr, ok := res.Result.(*taskResult)
		require.True(t, ok)
		require.Equal(t, "new title", tr.PRTitle)
		require.Equal(t, "new description", tr.PRDescription)
	})

	t.Run("updates session when non-async and title or description is present", func(t *testing.T) {
		var receivedUpdate capi.SessionUpdate
		called := false
		jm := &jobManager{
			obsv: observability.NewNoopExporters(),
			jobService: &mockJobService{mockUpdateSession: func(_ context.Context, _ *jobs.Job, update capi.SessionUpdate) error {
				called = true
				receivedUpdate = update
				return nil
			}},
		}

		job := &jobs.Job{UseAsyncSessions: false}
		update := JobUpdate{Content: `{"prTitle":"title only","prDescription":""}`}

		_, err := jm.handleTaskResult(context.Background(), nil, job, update)
		require.NoError(t, err)
		require.True(t, called)
		require.Equal(t, "title only", receivedUpdate.GeneratedPullData.Title)
		require.Equal(t, "", receivedUpdate.GeneratedPullData.Description)
	})

	t.Run("does not update session when async sessions are enabled", func(t *testing.T) {
		called := false
		jm := &jobManager{
			obsv: observability.NewNoopExporters(),
			jobService: &mockJobService{mockUpdateSession: func(_ context.Context, _ *jobs.Job, _ capi.SessionUpdate) error {
				called = true
				return nil
			}},
		}

		job := &jobs.Job{UseAsyncSessions: true}
		update := JobUpdate{Content: `{"prTitle":"new title","prDescription":"new description"}`}

		_, err := jm.handleTaskResult(context.Background(), nil, job, update)
		require.NoError(t, err)
		require.False(t, called)
	})

	t.Run("does not update session when both title and description are empty", func(t *testing.T) {
		called := false
		jm := &jobManager{
			obsv: observability.NewNoopExporters(),
			jobService: &mockJobService{mockUpdateSession: func(_ context.Context, _ *jobs.Job, _ capi.SessionUpdate) error {
				called = true
				return nil
			}},
		}

		job := &jobs.Job{UseAsyncSessions: false}
		update := JobUpdate{Content: `{"prTitle":"","prDescription":""}`}

		_, err := jm.handleTaskResult(context.Background(), nil, job, update)
		require.NoError(t, err)
		require.False(t, called)
	})
}

func TestAgentCallbackHandleProgress(t *testing.T) {
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	obsv := observability.NewNoopExporters()
	jobStore := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
		IsAgentEnabled: true,
	})
	jobService := &mockJobService{store: jobStore}
	capiClient := capi.NewNoopClient()
	appProvider := agenticapptest.NewTestProviderWithID(t, 12345)
	h := NewHandler(obsv, jobService, capiClient, jobStore, cf, ffClient, noopClient, 1, appProvider)

	t.Run("successful run", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		// setup job
		job := &jobs.Job{
			ID:           "job-id",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      1,
			NonceHash:    nonceHash,
		}
		jobStore.CreateJob(ctx, job)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "job-id",
			Kind:        AgentUpdateKindProgress,
		}
		b, _ := json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusOK, w.Code)
	})

	t.Run("successful run with telemetry", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		// setup job
		job := &jobs.Job{
			ID:           "job-id",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      1,
			NonceHash:    nonceHash,
		}
		jobStore.CreateJob(ctx, job)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "job-id",
			Kind:        AgentUpdateKindProgress,
			Content:     testutils.ReadFixture("../testutils/fixtures/job-event-message-user.json"),
		}
		b, _ := json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusOK, w.Code)
	})

	// Integration tests for SKU-based restricted telemetry
	testCases := []struct {
		name         string
		setupMock    func(*githubtwirp.NoopClient)
		eventFixture string
		description  string
	}{
		{
			name: "successful progress with telemetry event",
			setupMock: func(client *githubtwirp.NoopClient) {
				// Default success case - user API works
				client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
					return &copilotUsersTwirp.GetCopilotUserResponse{
						UserDetails: &copilotUsersTwirp.CopilotUserDetails{
							CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
						},
					}, nil
				}
			},
			eventFixture: "job-event-message-tool.json",
			description:  "Should handle telemetry events successfully",
		},
		{
			name: "handles user API failure gracefully",
			setupMock: func(client *githubtwirp.NoopClient) {
				// Simulate API failure
				client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
					return nil, errors.New("API error")
				}
			},
			eventFixture: "job-event-model_call_success.json",
			description:  "Should handle user API failures without failing the request",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			ctx := addUserToContext(context.Background(), t)
			nonce, nonceHash := jobNonce()

			obsv := observability.NewNoopExporters()

			ffClient := featureflags.NewNoopClient(map[string]bool{
				"sweagentd_publish_telemetry_events_to_hydro": true,
			})

			mockClient := githubtwirp.NewNoopClient()
			mockClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
				IsAgentEnabled: true,
			})

			// Setup mock based on test case
			tc.setupMock(mockClient)

			jobStore := memory.NewStore()
			jobService := &mockJobService{store: jobStore}
			capiClient := capi.NewNoopClient()
			appProvider := agenticapptest.NewTestProviderWithID(t, 12345)
			h := NewHandler(obsv, jobService, capiClient, jobStore, &github.NoopClientFactory{}, ffClient, mockClient, 1, appProvider)

			jobID := "test-job-id"
			job := &jobs.Job{
				ID:           jobID,
				AssignmentID: "assignment-id",
				OwnerID:      1,
				RepoID:       2,
				ActorID:      1,
				NonceHash:    nonceHash,
			}
			jobStore.CreateJob(ctx, job)

			update := JobUpdate{
				RepoID:      job.RepoID,
				RepoOwnerID: job.OwnerID,
				JobID:       jobID, // Use the same job ID
				Kind:        AgentUpdateKindProgress,
				Content:     testutils.ReadFixture("../testutils/fixtures/" + tc.eventFixture),
			}
			b, _ := json.Marshal(update)

			req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
			req.Header.Set(jobs.JobNonceHeader, nonce)
			w := httptest.NewRecorder()

			// Execute the request
			h.HandleCallback(w, req)

			// Verify the request succeeded
			require.Equal(t, http.StatusOK, w.Code, tc.description)
		})
	}

	t.Run("successful run with commands", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		actorID := int64(1)
		// setup job
		job := &jobs.Job{
			ID:           "job-id",
			SessionID:    "session-id",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      actorID,
			NonceHash:    nonceHash,
		}
		jobStore.CreateJob(ctx, job)

		command := job.NewCommand("external-id", actorID, "summarize everything into a doc", command.TypeUserMessage, time.Now().Unix())
		jobStore.CreateCommand(ctx, command)

		update := JobUpdate{
			RepoID:              job.RepoID,
			RepoOwnerID:         job.OwnerID,
			JobID:               "job-id",
			Kind:                AgentUpdateKindProgress,
			AcceptsUserMessages: true,
		}
		b, _ := json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusOK, w.Code)

		// Parse the response body to verify it contains the command
		var responseBody map[string]any
		err := json.Unmarshal(w.Body.Bytes(), &responseBody)
		require.NoError(t, err)

		// Verify the response contains content with user messages
		userMessages, exists := responseBody["user_messages"]
		require.True(t, exists, "Response should contain 'user_messages' field")

		// Convert content to slice and verify command details
		userMessageSlice, ok := userMessages.([]any)
		require.True(t, ok, "user_messages should be an array")
		require.Len(t, userMessageSlice, 1, "Should have exactly one userMessage")

		// Verify the userMessage content
		msg := userMessageSlice[0].(map[string]any)
		require.Equal(t, "summarize everything into a doc", msg["content"], "UserMessage content should match expected value")
		require.Equal(t, actorID, int64(msg["actor_id"].(float64)), "Actor ID should match")
	})

	t.Run("successful run with commands but callback doesn't accept commands", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		actorID := int64(1)
		// setup job
		job := &jobs.Job{
			ID:           "job-id-2",
			SessionID:    "session-id-2",
			AssignmentID: "assignment-id-3",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      actorID,
			NonceHash:    nonceHash,
		}
		jobStore.CreateJob(ctx, job)

		newCommand := job.NewCommand("external-id", actorID, "summarize everything into a doc", command.TypeUserMessage, time.Now().Unix())
		jobStore.CreateCommand(ctx, newCommand)

		update := JobUpdate{
			RepoID:              job.RepoID,
			RepoOwnerID:         job.OwnerID,
			JobID:               "job-id",
			Kind:                AgentUpdateKindProgress,
			AcceptsUserMessages: false,
		}
		b, _ := json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusOK, w.Code)

		// Expect empty response body
		require.Equal(t, "", w.Body.String(), "Response body should be empty")

		cmd, err := jobStore.GetCommand(ctx, newCommand.AssignmentID, newCommand.JobID, newCommand.ID)
		require.NoError(t, err)
		require.Equal(t, command.StatusPending, cmd.Status, "Command status should remain pending")
	})

	t.Run("successful run with empty commands", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		actorID := int64(1)
		// setup job
		job := &jobs.Job{
			ID:           "job-id-3",
			AssignmentID: "assignment-id-3",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      actorID,
			NonceHash:    nonceHash,
		}
		jobStore.CreateJob(ctx, job)

		update := JobUpdate{
			RepoID:              job.RepoID,
			RepoOwnerID:         job.OwnerID,
			JobID:               "job-id",
			Kind:                AgentUpdateKindProgress,
			AcceptsUserMessages: true,
		}
		b, _ := json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusOK, w.Code)

		// Parse the response body to verify it contains the command
		var responseBody map[string]any
		err := json.Unmarshal(w.Body.Bytes(), &responseBody)
		require.NoError(t, err)

		// Verify the response contains content with user messages
		userMessages, exists := responseBody["user_messages"]
		require.True(t, exists, "Response should contain 'user_messages' field")

		// Convert userMessages to slice and verify command details
		userMessageSlice, ok := userMessages.([]any)
		require.True(t, ok, "user_messages should be an array")
		require.Len(t, userMessageSlice, 0, "Should be empty")
	})
}

func TestAgentCallbackHandleProgress_SandboxFinalization(t *testing.T) {
	obsv := observability.NewNoopExporters()
	jobStore := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
		IsAgentEnabled: true,
	})
	capiClient := capi.NewNoopClient()
	appProvider := agenticapptest.NewTestProviderWithID(t, 12345)

	tests := []struct {
		name           string
		launcher       launcher.Type
		shutdownType   string
		expectedStatus jobs.JobStatus
	}{
		{
			name:           "sandbox job finalized on normal shutdown",
			launcher:       launcher.TypeSandbox,
			shutdownType:   "normal",
			expectedStatus: jobs.JobStatusCompleted,
		},
		{
			name:           "sandbox job failed on error shutdown",
			launcher:       launcher.TypeSandbox,
			shutdownType:   "error",
			expectedStatus: jobs.JobStatusFailed,
		},
		{
			name:           "actions job ignores shutdown telemetry",
			launcher:       launcher.TypeActions,
			shutdownType:   "normal",
			expectedStatus: jobs.JobStatusRunning,
		},
		{
			name:           "empty launcher ignores shutdown telemetry",
			launcher:       "",
			shutdownType:   "normal",
			expectedStatus: jobs.JobStatusRunning,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ffClient := featureflags.NewNoopClient(map[string]bool{})
			var finalizedStatus jobs.JobStatus
			var finalizeCalled bool
			var updateResultStatus jobs.JobStatus
			jobService := &mockJobService{
				store: jobStore,
				mockFinalizeJob: func(_ context.Context, _ *jobs.Job, status jobs.JobStatus, _ *jobs.JobError, _ int64) error {
					finalizeCalled = true
					finalizedStatus = status
					return nil
				},
				mockUpdateFromExecutionResult: func(_ context.Context, _ *jobs.Job, status jobs.JobStatus, _ time.Time) error {
					updateResultStatus = status
					return nil
				},
			}
			h := NewHandler(obsv, jobService, capiClient, jobStore, cf, ffClient, noopClient, 1, appProvider)

			ctx := addUserToContext(context.Background(), t)
			nonce, nonceHash := jobNonce()

			job := &jobs.Job{
				ID:           "job-" + tt.name,
				AssignmentID: "assignment-id",
				OwnerID:      1,
				RepoID:       2,
				ActorID:      1,
				NonceHash:    nonceHash,
				Launcher:     tt.launcher,
			}
			jobStore.CreateJob(ctx, job)

			content := fmt.Sprintf(`{"kind":"telemetry","telemetry":{"event":"cca_session_shutdown","properties":{"shutdownType":%q,"agent":"cca-sdk-v3"}}}`, tt.shutdownType)
			update := JobUpdate{
				RepoID:      job.RepoID,
				RepoOwnerID: job.OwnerID,
				JobID:       job.ID,
				Kind:        AgentUpdateKindProgress,
				Content:     content,
			}
			b, _ := json.Marshal(update)

			req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
			req.Header.Set(jobs.JobNonceHeader, nonce)
			w := httptest.NewRecorder()
			h.HandleCallback(w, req)
			require.Equal(t, http.StatusOK, w.Code)

			if tt.expectedStatus == jobs.JobStatusRunning {
				assert.False(t, finalizeCalled, "FinalizeJob should not be called for non-sandbox jobs")
				// UpdateFromExecutionResult should receive "running" (normal progress)
				assert.Equal(t, jobs.JobStatusRunning, updateResultStatus)
			} else {
				assert.True(t, finalizeCalled, "FinalizeJob should be called for sandbox jobs")
				assert.Equal(t, tt.expectedStatus, finalizedStatus)
				// After FinalizeJob, UpdateFromExecutionResult must receive the
				// terminal status (not "running"), otherwise it would revert the
				// job back to running via PatchJob.
				assert.Equal(t, tt.expectedStatus, updateResultStatus,
					"UpdateFromExecutionResult must receive terminal status to prevent revert")
			}
		})
	}

	t.Run("sandbox error shutdown includes errorReason in job error", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		var capturedJobError *jobs.JobError
		jobService := &mockJobService{
			store: jobStore,
			mockFinalizeJob: func(_ context.Context, _ *jobs.Job, _ jobs.JobStatus, jobErr *jobs.JobError, _ int64) error {
				capturedJobError = jobErr
				return nil
			},
			mockUpdateFromExecutionResult: func(_ context.Context, _ *jobs.Job, _ jobs.JobStatus, _ time.Time) error {
				return nil
			},
		}
		h := NewHandler(obsv, jobService, capiClient, jobStore, cf, ffClient, noopClient, 1, appProvider)

		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		job := &jobs.Job{
			ID:           "job-error-reason",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      1,
			NonceHash:    nonceHash,
			Launcher:     launcher.TypeSandbox,
		}
		jobStore.CreateJob(ctx, job)

		content := `{"kind":"telemetry","telemetry":{"event":"cca_session_shutdown","properties":{"shutdownType":"error","agent":"cca-sdk-v3"},"restrictedProperties":{"errorReason":"context window exhausted"}}}`
		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       job.ID,
			Kind:        AgentUpdateKindProgress,
			Content:     content,
		}
		b, _ := json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusOK, w.Code)
		require.NotNil(t, capturedJobError, "FinalizeJob should receive a job error with errorReason")
		assert.Equal(t, "context window exhausted", capturedJobError.Message)
	})
}

func TestAgentCallbackHandleCheckQuota(t *testing.T) {
	ffClient := featureflags.NewNoopClient(nil)
	obsv := observability.NewNoopExporters()
	jobStore := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
		IsAgentEnabled: true,
	})
	jobService := &mockJobService{store: jobStore}
	capiClient := capi.NewNoopClient()
	appProvider := agenticapptest.NewTestProviderWithID(t, 12345)
	h := NewHandler(obsv, jobService, capiClient, jobStore, cf, ffClient, noopClient, 1, appProvider)

	t.Run("returns has_enough_quota=true when quota is sufficient", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		mockBillingClient := billingMocks.NewMockClientInterface(t)
		mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Return(&billingProto.CanProceedWithUsageResponse{
			CanProceed: true,
		}, nil)
		noopClient.NoopBillingClient = mockBillingClient

		noopClient.NoopLimiterAPI.MockGetQuotaRemaining = func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
			return &copilotLimitersTwirp.GetQuotaRemainingResponse{
				QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{{
					Entitlement:      1000,
					Remaining:        100,
					QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
					PercentRemaining: 10.0,
				}},
			}, nil
		}

		job := &jobs.Job{
			ID:           "job-id-check-quota-1",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      1,
			NonceHash:    nonceHash,
		}
		jobStore.CreateJob(ctx, job)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       job.ID,
			Kind:        AgentUpdateKindCheckQuota,
			Content:     `{}`,
		}
		b, _ := json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusOK, w.Code)

		var responseBody map[string]any
		err := json.Unmarshal(w.Body.Bytes(), &responseBody)
		require.NoError(t, err)
		require.Equal(t, true, responseBody["has_enough_quota"])
	})

	t.Run("returns has_enough_quota=false when quota is insufficient", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		mockBillingClient := billingMocks.NewMockClientInterface(t)
		mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Return(&billingProto.CanProceedWithUsageResponse{
			CanProceed: false,
		}, nil)
		noopClient.NoopBillingClient = mockBillingClient

		noopClient.NoopLimiterAPI.MockGetQuotaRemaining = func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
			return &copilotLimitersTwirp.GetQuotaRemainingResponse{
				QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{{
					Entitlement:      1000,
					Remaining:        0,
					QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
					PercentRemaining: 0.0,
					OveragePermitted: false,
				}},
			}, nil
		}

		job := &jobs.Job{
			ID:           "job-id-check-quota-2",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      1,
			NonceHash:    nonceHash,
		}
		jobStore.CreateJob(ctx, job)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       job.ID,
			Kind:        AgentUpdateKindCheckQuota,
			Content:     `{}`,
		}
		b, _ := json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusOK, w.Code)

		var responseBody map[string]any
		err := json.Unmarshal(w.Body.Bytes(), &responseBody)
		require.NoError(t, err)
		require.Equal(t, false, responseBody["has_enough_quota"])
	})

	t.Run("returns has_enough_quota=true when quota check errors", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		noopClient.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return nil, errors.New("upstream user details unavailable")
		}

		job := &jobs.Job{
			ID:           "job-id-check-quota-3",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      1,
			NonceHash:    nonceHash,
		}
		jobStore.CreateJob(ctx, job)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       job.ID,
			Kind:        AgentUpdateKindCheckQuota,
			Content:     `{}`,
		}
		b, _ := json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusOK, w.Code)

		var responseBody map[string]any
		err := json.Unmarshal(w.Body.Bytes(), &responseBody)
		require.NoError(t, err)
		require.Equal(t, true, responseBody["has_enough_quota"])
	})
}

func TestAgentCallbackHandlePartialResult(t *testing.T) {
	ffClient := featureflags.NewNoopClient(nil)
	obsv := observability.NewNoopExporters()
	jobStore := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
		IsAgentEnabled: true,
	})
	jobService := &mockJobService{store: jobStore}
	capiClient := capi.NewNoopClient()
	appProvider := agenticapptest.NewTestProviderWithID(t, 12345)
	h := NewHandler(obsv, jobService, capiClient, jobStore, cf, ffClient, noopClient, 1, appProvider)

	t.Run("invalid content", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		// setup job
		job := &jobs.Job{
			ID:           "job-id",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      1,
			NonceHash:    nonceHash,
		}
		jobStore.CreateJob(ctx, job)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "job-id",
			Kind:        AgentUpdateKindPartialResult,
		}
		b, _ := json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusInternalServerError, w.Code)
	})

	t.Run("successful run", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		// setup job
		job := &jobs.Job{
			ActorID:      1,
			ID:           "job-id",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			Args: launcher.LaunchAgentOpts{
				PRNumber: 3,
			},
			NonceHash: nonceHash,
		}
		jobStore.CreateJob(ctx, job)

		u := partialResultUpdate{
			Message: "hello world",
		}
		b, _ := json.Marshal(u)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "job-id",
			Kind:        AgentUpdateKindPartialResult,
			Content:     string(b),
		}
		b, _ = json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusOK, w.Code)
	})
}

func TestHandlePartialResultPR(t *testing.T) {
	t.Run("update PR if job has PR and is initial fix action", func(t *testing.T) {
		var called bool
		mockNewClientFromRepo := func(ctx context.Context, repoID, ownerID int64) (github.ClientInterface, error) {
			called = true
			return &github.NoopClient{}, nil
		}
		cf := &github.NoopClientFactory{
			MockNewClientFromRepo: mockNewClientFromRepo,
		}
		jm := &jobManager{
			obsv:    observability.NewNoopExporters(),
			clients: cf,
			ffClient: featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentSkipPRBodyUpdateForSubsequentJobs: true,
			}),
			appProvider: agenticapptest.NewTestProvider(t),
		}
		update := JobUpdate{
			Content: `{}`,
		}
		ctx := context.Background()
		job := &jobs.Job{
			PullRequestID:     1,
			PullRequestNumber: 2,
			Action:            jobs.AgentActionFix,
		}
		_, err := jm.handlePartialResult(ctx, nil, job, update)

		require.NoError(t, err)
		require.True(t, called)
	})

	t.Run("update PR if job has PR and is task action", func(t *testing.T) {
		var called bool
		mockNewClientFromRepo := func(ctx context.Context, repoID, ownerID int64) (github.ClientInterface, error) {
			called = true
			return &github.NoopClient{}, nil
		}
		cf := &github.NoopClientFactory{
			MockNewClientFromRepo: mockNewClientFromRepo,
		}
		jm := &jobManager{
			obsv:    observability.NewNoopExporters(),
			clients: cf,
			ffClient: featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentSkipPRBodyUpdateForSubsequentJobs: true,
			}),
			appProvider: agenticapptest.NewTestProvider(t),
		}
		update := JobUpdate{
			Content: `{}`,
		}
		ctx := context.Background()
		job := &jobs.Job{
			PullRequestID:     1,
			PullRequestNumber: 2,
			Action:            jobs.AgentActionTask,
		}
		_, err := jm.handlePartialResult(ctx, nil, job, update)

		require.NoError(t, err)
		require.True(t, called)
	})

	t.Run("does not update PR for subsequent fix-pr-comment jobs when flag enabled", func(t *testing.T) {
		var called bool
		mockNewClientFromRepo := func(ctx context.Context, repoID, ownerID int64) (github.ClientInterface, error) {
			called = true
			return &github.NoopClient{}, nil
		}
		cf := &github.NoopClientFactory{
			MockNewClientFromRepo: mockNewClientFromRepo,
		}
		jm := &jobManager{
			obsv:    observability.NewNoopExporters(),
			clients: cf,
			ffClient: featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentSkipPRBodyUpdateForSubsequentJobs: true,
			}),
			appProvider: agenticapptest.NewTestProvider(t),
		}
		update := JobUpdate{
			Content: `{}`,
		}
		ctx := context.Background()
		job := &jobs.Job{
			PullRequestID:     1,
			PullRequestNumber: 2,
			Action:            jobs.AgentActionFixPRComment,
		}
		_, err := jm.handlePartialResult(ctx, nil, job, update)

		require.NoError(t, err)
		require.False(t, called)
	})

	t.Run("does not update PR for code_review_fix_with_copilot when flag enabled", func(t *testing.T) {
		var called bool
		mockNewClientFromRepo := func(ctx context.Context, repoID, ownerID int64) (github.ClientInterface, error) {
			called = true
			return &github.NoopClient{}, nil
		}
		cf := &github.NoopClientFactory{
			MockNewClientFromRepo: mockNewClientFromRepo,
		}
		jm := &jobManager{
			obsv:    observability.NewNoopExporters(),
			clients: cf,
			ffClient: featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForCodeReviewFixJobs: true,
			}),
			appProvider: agenticapptest.NewTestProvider(t),
		}
		update := JobUpdate{
			Content: `{}`,
		}
		ctx := context.Background()
		job := &jobs.Job{
			PullRequestID:     1,
			PullRequestNumber: 2,
			EventType:         jobs.EventTypeCodeReviewFixWithCopilot,
		}
		_, err := jm.handlePartialResult(ctx, nil, job, update)

		require.NoError(t, err)
		require.False(t, called)
	})

	t.Run("updates PR for fix-pr-comment jobs when flag disabled", func(t *testing.T) {
		var called bool
		mockNewClientFromRepo := func(ctx context.Context, repoID, ownerID int64) (github.ClientInterface, error) {
			called = true
			return &github.NoopClient{}, nil
		}
		cf := &github.NoopClientFactory{
			MockNewClientFromRepo: mockNewClientFromRepo,
		}
		jm := &jobManager{
			obsv:        observability.NewNoopExporters(),
			clients:     cf,
			ffClient:    featureflags.NewNoopClient(nil),
			appProvider: agenticapptest.NewTestProvider(t),
		}
		update := JobUpdate{
			Content: `{}`,
		}
		ctx := context.Background()
		job := &jobs.Job{
			PullRequestID:     1,
			PullRequestNumber: 2,
			Action:            jobs.AgentActionFixPRComment,
		}
		_, err := jm.handlePartialResult(ctx, nil, job, update)

		require.NoError(t, err)
		require.True(t, called)
	})

	t.Run("does not update PR if job has no PR", func(t *testing.T) {
		var called bool
		mockNewClientFromRepo := func(ctx context.Context, repoID, ownerID int64) (github.ClientInterface, error) {
			called = true
			return &github.NoopClient{}, nil
		}
		cf := &github.NoopClientFactory{
			MockNewClientFromRepo: mockNewClientFromRepo,
		}
		jm := &jobManager{
			obsv:        observability.NewNoopExporters(),
			clients:     cf,
			ffClient:    featureflags.NewNoopClient(nil),
			appProvider: agenticapptest.NewTestProvider(t),
		}
		update := JobUpdate{
			Content: `{}`,
		}
		ctx := context.Background()
		job := &jobs.Job{}
		_, err := jm.handlePartialResult(ctx, nil, job, update)

		require.NoError(t, err)
		require.False(t, called)
	})

	t.Run("skips PR update during partial result for non-agent PR", func(t *testing.T) {
		var called bool
		mockNewClientFromRepo := func(ctx context.Context, repoID, ownerID int64) (github.ClientInterface, error) {
			called = true
			return &github.NoopClient{}, nil
		}
		cf := &github.NoopClientFactory{
			MockNewClientFromRepo: mockNewClientFromRepo,
		}
		jm := &jobManager{
			obsv:        observability.NewNoopExporters(),
			clients:     cf,
			ffClient:    featureflags.NewNoopClient(map[string]bool{}),
			appProvider: agenticapptest.NewTestProvider(t),
		}
		update := JobUpdate{
			Content: `{"message": "partial update"}`,
		}
		ctx := context.Background()
		job := &jobs.Job{
			PullRequestID:     1,
			PullRequestNumber: 2,
			EventType:         jobs.EventTypePullRequestCommentNonCopilotPullRequest,
		}
		_, err := jm.handlePartialResult(ctx, nil, job, update)

		require.NoError(t, err)
		require.False(t, called, "should not create GitHub client when skipping PR update")
	})

	t.Run("updates PR during partial result for agent-authored PR", func(t *testing.T) {
		var clientCreated bool
		var capturedClient *github.NoopClient
		cf := &github.NoopClientFactory{
			MockPullRequest: &gg.PullRequest{
				User: &gg.User{Login: gg.Ptr(copilotBotLogin)},
			},
			MockNewClientFromRepo: func(_ context.Context, _, _ int64) (github.ClientInterface, error) {
				clientCreated = true
				capturedClient = &github.NoopClient{
					MockPullRequest: &gg.PullRequest{
						User: &gg.User{Login: gg.Ptr(copilotBotLogin)},
					},
				}
				return capturedClient, nil
			},
		}
		jm := &jobManager{
			obsv:        observability.NewNoopExporters(),
			clients:     cf,
			ffClient:    featureflags.NewNoopClient(map[string]bool{}),
			appProvider: agenticapptest.NewTestProvider(t),
		}
		update := JobUpdate{
			Content: `{"message": "partial update"}`,
		}
		ctx := context.Background()
		job := &jobs.Job{
			PullRequestID:     1,
			PullRequestNumber: 2,
			EventType:         jobs.EventTypePullRequestComment,
		}
		_, err := jm.handlePartialResult(ctx, nil, job, update)

		require.NoError(t, err)
		require.True(t, clientCreated, "should still update PR for agent-authored PRs")
		require.NotNil(t, capturedClient, "expected a GitHub client to be created")
		require.True(t, capturedClient.HasMethodCall("UpdatePullRequest"), "expected UpdatePullRequest to be called for agent-authored PRs")

		var updatedPR *gg.PullRequest
		for _, call := range capturedClient.MethodCalls {
			if call.Method == "UpdatePullRequest" {
				updatedPR, _ = call.Args[1].(*gg.PullRequest)
				break
			}
		}
		require.NotNil(t, updatedPR, "expected UpdatePullRequest to receive a pull request payload")
		require.NotNil(t, updatedPR.Body, "expected updated pull request body to be set")
		require.Contains(t, *updatedPR.Body, "partial update")
	})
}

func TestAgentCallbackHandleError(t *testing.T) {
	ffClient := featureflags.NewNoopClient(nil)
	obsv := observability.NewNoopExporters()
	jobStore := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
		IsAgentEnabled: true,
	})
	jobService := &mockJobService{store: jobStore}
	capiClient := capi.NewNoopClient()
	appProvider := agenticapptest.NewTestProviderWithID(t, 12345)
	h := NewHandler(obsv, jobService, capiClient, jobStore, cf, ffClient, noopClient, 1, appProvider)

	t.Run("successful run", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		nonce, nonceHash := jobNonce()

		// setup assignment
		assignment := &jobs.Assignment{
			ID:      "assignment-id",
			OwnerID: 1,
			RepoID:  2,
		}
		jobStore.CreateAssignment(ctx, assignment)

		// setup job
		job := &jobs.Job{
			ID:           "job-id",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      1,
			NonceHash:    nonceHash,
		}
		jobStore.CreateJob(ctx, job)

		u := map[string]any{"hello": "world"}
		b, _ := json.Marshal(u)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "job-id",
			Kind:        AgentUpdateKindError,
			Content:     string(b),
		}
		b, _ = json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusOK, w.Code)
	})
}

func TestAgentCallbackWithNonce(t *testing.T) {
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	obsv := observability.NewNoopExporters()
	jobStore := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
		IsAgentEnabled: true,
	})
	jobService := &mockJobService{store: jobStore}
	capiClient := capi.NewNoopClient()
	appProvider := agenticapptest.NewTestProviderWithID(t, 12345)
	h := NewHandler(obsv, jobService, capiClient, jobStore, cf, ffClient, noopClient, 1, appProvider)

	t.Run("missing nonce header", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)

		// setup job with nonce hash
		job := &jobs.Job{
			ID:           "job-id-nonce",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      1,
		}
		jobStore.CreateJob(ctx, job)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "job-id-nonce",
			Kind:        AgentUpdateKindProgress,
		}
		b, _ := json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("invalid nonce header", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)

		// setup job with nonce hash
		job := &jobs.Job{
			ID:           "job-id-nonce-2",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      1,
		}
		jobStore.CreateJob(ctx, job)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "job-id-nonce-2",
			Kind:        AgentUpdateKindProgress,
		}
		b, _ := json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, "wrong-nonce-value")
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("valid nonce header", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)

		// For a test where we're manually setting up the nonce/hash relationship,
		// we need to create the job record directly rather than going through CreateJob
		// because CreateJob would generate its own nonce/hash
		job := &jobs.Job{
			ID:           "job-id-nonce-3",
			AssignmentID: "assignment-id",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      1,
			Status:       jobs.JobStatusPending,
		}

		_, err := jobStore.CreateJob(ctx, job)
		require.NoError(t, err)

		nonce, err := jobs.GenerateNonce()
		require.NoError(t, err)
		job.NonceHash = jobs.HashNonce(nonce)

		job, err = jobStore.UpdateJob(ctx, job)
		require.NoError(t, err)

		update := JobUpdate{
			RepoID:      job.RepoID,
			RepoOwnerID: job.OwnerID,
			JobID:       "job-id-nonce-3",
			Kind:        AgentUpdateKindProgress,
		}
		b, _ := json.Marshal(update)

		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs", bytes.NewReader(b))
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.HandleCallback(w, req)
		require.Equal(t, http.StatusOK, w.Code)
	})
}

func addUserToContext(ctx context.Context, t *testing.T) context.Context {
	t.Helper()
	return requestctx.AddData(ctx, &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID: 1,
			TokenInfo: &requestctx.TokenInfo{
				Type:          string(authd.CredentialTypeUserToServerToken),
				ApplicationID: 12345, // Match the test Copilot app ID
			},
			Login:      "testuser",
			TrackingID: "tracking-id",
		},
	})
}

func addS2SUserToContext(ctx context.Context, t *testing.T) context.Context {
	t.Helper()
	return requestctx.AddData(ctx, &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID: 99999, // Installation ID, not a real user
			TokenInfo: &requestctx.TokenInfo{
				Type:          string(authd.CredentialTypeServerToServerToken),
				ApplicationID: 12345, // Match the test Copilot app ID
			},
			TrackingID: "tracking-id",
		},
	})
}

// Generate a nonce and its hash
func jobNonce() (nonce, nonceHash string) {
	nonce = "test-nonce-value"
	nonceHash = jobs.HashNonce(nonce)
	return nonce, nonceHash
}

func TestUpdatePullRequestSkipsDescriptionOnNonAgentPR(t *testing.T) {
	tests := []struct {
		name                       string
		agentAuthoredPR            bool
		expectPRDescriptionUpdated bool
		expectPRTitleUpdated       bool
		providedTitle              *string
		providedBody               *string
	}{
		{
			name:                       "human-authored PR: should not update title or body",
			agentAuthoredPR:            false,
			expectPRDescriptionUpdated: false,
			expectPRTitleUpdated:       false,
			providedTitle:              to.Ptr("New Title"),
			providedBody:               to.Ptr("New body content"),
		},
		{
			name:                       "agent-authored PR: should update both title and body",
			agentAuthoredPR:            true,
			expectPRDescriptionUpdated: true,
			expectPRTitleUpdated:       true,
			providedTitle:              to.Ptr("New Title"),
			providedBody:               to.Ptr("New body content"),
		},
		{
			name:                       "agent-authored PR: body only provided",
			agentAuthoredPR:            true,
			expectPRDescriptionUpdated: true,
			expectPRTitleUpdated:       false,
			providedTitle:              nil,
			providedBody:               to.Ptr("New body content"),
		},
		{
			name:                       "agent-authored PR: title only provided",
			agentAuthoredPR:            true,
			expectPRDescriptionUpdated: false,
			expectPRTitleUpdated:       true,
			providedTitle:              to.Ptr("New Title"),
			providedBody:               nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			actorID := int64(123)

			ffClient := featureflags.NewNoopClient(map[string]bool{})

			initialPRTitle := "Original Title"
			initialPRBody := "Original body"

			// Set the PR author login based on whether it is agent-authored.
			// Here we use Copilot (appID=1, bot login "github-copilot-bot") as an example agent.
			prAuthorLogin := "human-user"
			if tt.agentAuthoredPR {
				prAuthorLogin = copilotBotLogin
			}
			mockPR := &gg.PullRequest{
				Number: to.Ptr(1),
				Title:  &initialPRTitle,
				Body:   &initialPRBody,
				User:   &gg.User{Login: &prAuthorLogin},
			}

			noopClient := &github.NoopClient{
				MockPullRequest: mockPR,
			}

			repoOwner := "owner"
			repoName := "repo"
			mockRepo := &gg.Repository{
				Owner: &gg.User{
					Login: &repoOwner,
				},
				Name: &repoName,
			}

			manager := &jobManager{
				obsv:        observability.NewNoopExporters(),
				ffClient:    ffClient,
				appProvider: agenticapptest.NewTestProviderWithID(t, 1),
			}

			job := &jobs.Job{
				ActorID:           actorID,
				RepoID:            123,
				PullRequestNumber: 1,
				AgentID:           1,
			}

			err := manager.updatePullRequest(ctx, noopClient, job, mockRepo, tt.providedTitle, tt.providedBody)
			require.NoError(t, err)

			// Check if UpdatePullRequest was called
			wasCalled := noopClient.HasMethodCall("UpdatePullRequest")

			// Find the UpdatePullRequest call if it was made
			var updatedPR *gg.PullRequest
			if wasCalled {
				for _, call := range noopClient.MethodCalls {
					if call.Method == "UpdatePullRequest" {
						updatedPR = call.Args[1].(*gg.PullRequest)
						break
					}
				}
			}

			// Verify expectations based on test case
			if tt.expectPRTitleUpdated || tt.expectPRDescriptionUpdated {
				require.True(t, wasCalled, "UpdatePullRequest should have been called")
				require.NotNil(t, updatedPR, "UpdatePullRequest call should have a PR argument")

				// Verify title
				verifyTitle(t, tt, updatedPR, initialPRTitle)

				// Verify body
				verifyBody(t, tt, updatedPR, initialPRBody)
			} else {
				require.False(t, wasCalled, "UpdatePullRequest should not have been called")
			}
		})
	}
}

func verifyTitle(t *testing.T, tt struct {
	name                       string
	agentAuthoredPR            bool
	expectPRDescriptionUpdated bool
	expectPRTitleUpdated       bool
	providedTitle              *string
	providedBody               *string
}, updatedPR *gg.PullRequest, initialPRTitle string) {
	t.Helper()
	if tt.expectPRTitleUpdated && tt.providedTitle != nil {
		require.NotEqual(t, initialPRTitle, *updatedPR.Title, "PR title should have been updated")
		require.Equal(t, *tt.providedTitle, *updatedPR.Title, "PR title should match provided title")
	} else {
		require.Equal(t, initialPRTitle, *updatedPR.Title, "PR title should not have been updated")
	}
}

func verifyBody(t *testing.T, tt struct {
	name                       string
	agentAuthoredPR            bool
	expectPRDescriptionUpdated bool
	expectPRTitleUpdated       bool
	providedTitle              *string
	providedBody               *string
}, updatedPR *gg.PullRequest, initialPRBody string) {
	t.Helper()
	if tt.expectPRDescriptionUpdated && tt.providedBody != nil {
		require.NotEqual(t, initialPRBody, *updatedPR.Body, "PR body should have been updated")
	} else if !tt.expectPRDescriptionUpdated && tt.providedBody != nil {
		require.Equal(t, initialPRBody, *updatedPR.Body, "PR body should not have been updated")
	}
}
