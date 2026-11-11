package agentcleanup

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	authd "github.com/github/authnd/client"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/require"
)

func TestAgentCleanupBadRequests(t *testing.T) {
	ctx := addUserToContext(context.Background(), t)
	obsv := observability.NewNoopExporters()
	jobStore := memory.NewStore()
	cf := &github.NoopClientFactory{}
	ffClient := featureflags.NewNoopClient(nil)
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
		IsSweagentdEnabled: true,
	})
	h := NewHandler(obsv, jobStore, cf, ffClient, noopClient, true, 1)
	jobStore.CreateJob(ctx, &jobs.Job{
		ID:        "job1",
		OwnerID:   1,
		RepoID:    1,
		ComputeID: "1",
		Status:    jobs.JobStatusCompleted,
	})
	jobStore.CreateJob(ctx, &jobs.Job{
		ID:        "job3",
		OwnerID:   1,
		RepoID:    1,
		ComputeID: "3",
		Status:    jobs.JobStatusRunning,
	})

	t.Run("clean up", func(t *testing.T) {
		bodyContent := `{"oid": 1, "rid": 1, "wid": 1}`
		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/cleanup", strings.NewReader(bodyContent))
		req.Header.Add("Authorization", "Bearer token")
		req.Header.Add(copilotCleanupListHeader, "ghu_token1,ghs_token2")
		w := httptest.NewRecorder()
		h.HandleCleanup(w, req)
		if w.Code != http.StatusOK {
			t.Errorf("expected status code %d, got %d", http.StatusOK, w.Code)
		}
		body := w.Body.String()
		require.Contains(t, body, "processed 1 user token(s) and 1 server token(s) for workflow run 1")
		require.Contains(t, body, "Job exists: true")
	})

	t.Run("clean up on job that does not exist", func(t *testing.T) {
		bodyContent := `{"oid": 1, "rid": 1, "wid": 2}`
		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/cleanup", strings.NewReader(bodyContent))
		req.Header.Add("Authorization", "Bearer token")
		req.Header.Add(copilotCleanupListHeader, "ghu_token1,ghs_token2")
		w := httptest.NewRecorder()
		h.HandleCleanup(w, req)
		if w.Code != http.StatusOK {
			t.Errorf("expected status code %d, got %d", http.StatusOK, w.Code)
		}
		body := w.Body.String()
		require.Contains(t, body, "processed 1 user token(s) and 1 server token(s) for workflow run 2")
		require.Contains(t, body, "Job exists: false")
	})

	t.Run("bad request", func(t *testing.T) {
		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/cleanup", nil)
		w := httptest.NewRecorder()
		h.HandleCleanup(w, req)
		if w.Code != http.StatusBadRequest {
			t.Errorf("expected status code %d, got %d", http.StatusBadRequest, w.Code)
		}
	})
}

func addUserToContext(ctx context.Context, t *testing.T) context.Context {
	t.Helper()
	return requestctx.AddData(ctx, &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "user-login",
			TrackingID: "tracking-id",
			TokenInfo: &requestctx.TokenInfo{
				Type:          string(authd.CredentialTypeUserToServerToken),
				ApplicationID: 1,
				Token:         "test-token",
			},
		},
	})
}
