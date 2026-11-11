package agentcallback

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	authd "github.com/github/authnd/client"
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
	"github.com/stretchr/testify/require"
)

// mockJobService is a simple mock implementation of the jobservice interface
type mockJobService struct {
	store                         jobstore
	mockUpdateFromExecutionResult func(context.Context, *jobs.Job, jobs.JobStatus) error
}

func (m *mockJobService) GetJobByID(ctx context.Context, ownerID, repoID int64, jobID string) (*jobs.Job, error) {
	return m.store.GetJob(ctx, ownerID, repoID, jobID)
}

func (m *mockJobService) UpdateFromExecutionResult(ctx context.Context, job *jobs.Job, newStatus jobs.JobStatus) error {
	if m.mockUpdateFromExecutionResult != nil {
		return m.mockUpdateFromExecutionResult(ctx, job, newStatus)
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
	t.Run("update PR if job has PR", func(t *testing.T) {
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
	ffClient := featureflags.NewNoopClient(map[string]bool{
		"sweagentd_enforce_job_nonce": true,
	})
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

		nonce := jobs.GenerateNonce()
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

// Generate a nonce and its hash
func jobNonce() (nonce, nonceHash string) {
	nonce = "test-nonce-value"
	nonceHash = jobs.HashNonce(nonce)
	return nonce, nonceHash
}
