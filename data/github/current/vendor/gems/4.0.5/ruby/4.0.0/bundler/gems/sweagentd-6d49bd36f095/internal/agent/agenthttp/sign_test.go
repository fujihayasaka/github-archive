package agenthttp

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agent"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/customagenttest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/jobevents"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/plugins"
	"github.com/github/sweagentd/internal/requestctx"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestHandlerSignCommit(t *testing.T) {
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
	noopClient.NoopSweagentdAPI.MockSignCommit = func(ctx context.Context, req *sweagentdTwirp.SignCommitRequest) (*sweagentdTwirp.SignCommitResponse, error) {
		return &sweagentdTwirp.SignCommitResponse{
			Signature: "-----BEGIN PGP SIGNATURE-----\ntest-signature\n-----END PGP SIGNATURE-----",
		}, nil
	}
	spokes := customagenttest.MakeSpokes(t, map[string]string{})
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, noopClient, ffClient)
	pluginSvc := plugins.NewService(obsv, spokes, noopClient, "https://github.com")
	h := NewHandler(obsv, ffClient, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

	nonce := "test-nonce"
	activeJob := &jobs.Job{
		ID:           "1-2-sign-uuid",
		OwnerID:      1,
		RepoID:       2,
		NonceHash:    jobs.HashNonce(nonce),
		ActorID:      42,
		ActorLogin:   "testuser",
		AgentID:      1,
		Status:       jobs.JobStatusRunning,
		AssignmentID: "1-2-sign-assignment",
	}
	terminalJob := &jobs.Job{
		ID:           "1-2-terminal-uuid",
		OwnerID:      1,
		RepoID:       2,
		NonceHash:    jobs.HashNonce(nonce),
		ActorID:      42,
		ActorLogin:   "testuser",
		AgentID:      1,
		Status:       jobs.JobStatusCompleted,
		AssignmentID: "1-2-sign-assignment",
	}
	assignment := &jobs.Assignment{
		ID:      "1-2-sign-assignment",
		OwnerID: 1,
		RepoID:  2,
	}
	_, _ = store.CreateAssignment(context.Background(), assignment)
	_, _ = store.CreateJob(context.Background(), activeJob)
	_, _ = store.CreateJob(context.Background(), terminalJob)

	baseCtx := requestctx.AddData(context.Background(), &requestctx.CtxData{UserInfo: &requestctx.UserInfo{ID: 123, TokenInfo: &requestctx.TokenInfo{ApplicationID: uint64(cf.AppID())}}})

	t.Run("success", func(t *testing.T) {
		message := "tree abc123\nparent def456\n\nFix the bug\n\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>"
		body := fmt.Sprintf(`{"author":"Test <test@test.com>","message":%q,"verification_token":%q}`, message, nonce)
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-sign-uuid/sign", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", activeJob.ID)
		w := httptest.NewRecorder()
		h.signCommit(w, req)
		require.Equal(t, http.StatusOK, w.Code)

		var resp signCommitResponse
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		assert.Contains(t, resp.Signature, "PGP SIGNATURE")
	})

	t.Run("passes correct fields to twirp", func(t *testing.T) {
		var capturedReq *sweagentdTwirp.SignCommitRequest
		clientWithCapture := githubtwirp.NewNoopClient()
		clientWithCapture.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
		clientWithCapture.NoopSweagentdAPI.MockSignCommit = func(ctx context.Context, req *sweagentdTwirp.SignCommitRequest) (*sweagentdTwirp.SignCommitResponse, error) {
			capturedReq = req
			return &sweagentdTwirp.SignCommitResponse{Signature: "sig"}, nil
		}
		hCapture := NewHandler(obsv, ffClient, store, cf, clientWithCapture, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

		message := "test-message\n\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>"
		body := fmt.Sprintf(`{"author":"test-author","message":%q,"verification_token":%q}`, message, nonce)
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-sign-uuid/sign", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", activeJob.ID)
		w := httptest.NewRecorder()
		hCapture.signCommit(w, req)
		require.Equal(t, http.StatusOK, w.Code)

		require.NotNil(t, capturedReq)
		assert.Equal(t, uint64(2), capturedReq.RepositoryId)
		assert.Equal(t, message, capturedReq.Payload)
		assert.Equal(t, int64(1), capturedReq.AgentId)
		assert.Equal(t, uint64(42), capturedReq.AttributionUserId)
	})

	t.Run("missing job id", func(t *testing.T) {
		body := `{"message":"test"}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs//sign", strings.NewReader(body)).WithContext(baseCtx)
		w := httptest.NewRecorder()
		h.signCommit(w, req)
		require.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("missing verification token", func(t *testing.T) {
		message := "tree abc123\n\nFix\n\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>"
		body := fmt.Sprintf(`{"message":%q}`, message)
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-sign-uuid/sign", strings.NewReader(body)).WithContext(baseCtx)
		req = muxSetParam(req, "jobID", activeJob.ID)
		w := httptest.NewRecorder()
		h.signCommit(w, req)
		require.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("invalid verification token", func(t *testing.T) {
		message := "tree abc123\n\nFix\n\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>"
		body := fmt.Sprintf(`{"message":%q,"verification_token":"wrong-token"}`, message)
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-sign-uuid/sign", strings.NewReader(body)).WithContext(baseCtx)
		req = muxSetParam(req, "jobID", activeJob.ID)
		w := httptest.NewRecorder()
		h.signCommit(w, req)
		require.Equal(t, http.StatusUnauthorized, w.Code)
	})

	t.Run("unauthorized", func(t *testing.T) {
		badCtx := requestctx.AddData(context.Background(), &requestctx.CtxData{UserInfo: &requestctx.UserInfo{ID: 123, TokenInfo: &requestctx.TokenInfo{ApplicationID: 999}}})
		body := fmt.Sprintf(`{"message":"test","verification_token":%q}`, nonce)
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-sign-uuid/sign", strings.NewReader(body)).WithContext(badCtx)
		req = muxSetParam(req, "jobID", activeJob.ID)
		w := httptest.NewRecorder()
		h.signCommit(w, req)
		require.Equal(t, http.StatusUnauthorized, w.Code)
	})

	t.Run("job not found", func(t *testing.T) {
		nfSvc := agent.NewService(&notFoundStore{}, cf, customAgentSvc, nil, obsv, ffClient, noopClient, &jobevents.NoopEmitter{}, agenticapptest.NewTestProvider(t), nil, nil)
		hnf := *h
		hnf.svc = nfSvc
		message := "tree abc123\n\nFix\n\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>"
		body := fmt.Sprintf(`{"message":%q,"verification_token":"some-token"}`, message)
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-missing/sign", strings.NewReader(body)).WithContext(baseCtx)
		req = muxSetParam(req, "jobID", "1-2-missing")
		w := httptest.NewRecorder()
		hnf.signCommit(w, req)
		require.Equal(t, http.StatusNotFound, w.Code)
		assert.Contains(t, w.Body.String(), http.StatusText(http.StatusNotFound))
	})

	t.Run("job is terminal returns 409", func(t *testing.T) {
		message := "tree abc123\n\nFix\n\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>"
		body := fmt.Sprintf(`{"message":%q,"verification_token":%q}`, message, nonce)
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-terminal-uuid/sign", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", terminalJob.ID)
		w := httptest.NewRecorder()
		h.signCommit(w, req)
		require.Equal(t, http.StatusConflict, w.Code)
		assert.Contains(t, w.Body.String(), http.StatusText(http.StatusConflict))
	})

	t.Run("pending job is allowed", func(t *testing.T) {
		pendingJob := &jobs.Job{
			ID:           "1-2-pending-uuid",
			OwnerID:      1,
			RepoID:       2,
			NonceHash:    jobs.HashNonce(nonce),
			ActorID:      42,
			ActorLogin:   "testuser",
			AgentID:      1,
			Status:       jobs.JobStatusPending,
			AssignmentID: "1-2-sign-assignment",
		}
		_, _ = store.CreateJob(baseCtx, pendingJob)

		message := "tree abc123\n\nFix\n\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>"
		body := fmt.Sprintf(`{"message":%q,"verification_token":%q}`, message, nonce)
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-pending-uuid/sign", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", pendingJob.ID)
		w := httptest.NewRecorder()
		h.signCommit(w, req)
		require.Equal(t, http.StatusOK, w.Code)
	})

	t.Run("invalid request body", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-sign-uuid/sign", strings.NewReader("not json")).WithContext(baseCtx)
		req = muxSetParam(req, "jobID", activeJob.ID)
		w := httptest.NewRecorder()
		h.signCommit(w, req)
		require.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("missing message", func(t *testing.T) {
		body := fmt.Sprintf(`{"verification_token":%q}`, nonce)
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-sign-uuid/sign", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", activeJob.ID)
		w := httptest.NewRecorder()
		h.signCommit(w, req)
		require.Equal(t, http.StatusBadRequest, w.Code)
		assert.Contains(t, w.Body.String(), http.StatusText(http.StatusBadRequest))
	})

	t.Run("upstream twirp failure returns 502", func(t *testing.T) {
		failClient := githubtwirp.NewNoopClient()
		failClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
		failClient.NoopSweagentdAPI.MockSignCommit = func(ctx context.Context, req *sweagentdTwirp.SignCommitRequest) (*sweagentdTwirp.SignCommitResponse, error) {
			return nil, twirp.NewError(twirp.Internal, "signing service unavailable")
		}
		hFail := NewHandler(obsv, ffClient, store, cf, failClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

		message := "test\n\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>"
		body := fmt.Sprintf(`{"message":%q,"verification_token":%q}`, message, nonce)
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-sign-uuid/sign", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", activeJob.ID)
		w := httptest.NewRecorder()
		hFail.signCommit(w, req)
		require.Equal(t, http.StatusBadGateway, w.Code)
	})

	t.Run("twirp invalid argument", func(t *testing.T) {
		failClient := githubtwirp.NewNoopClient()
		failClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
		failClient.NoopSweagentdAPI.MockSignCommit = func(ctx context.Context, req *sweagentdTwirp.SignCommitRequest) (*sweagentdTwirp.SignCommitResponse, error) {
			return nil, twirp.NewError(twirp.InvalidArgument, "invalid commit payload")
		}
		hFail := NewHandler(obsv, ffClient, store, cf, failClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

		message := "bad-message\n\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>"
		body := fmt.Sprintf(`{"message":%q,"verification_token":%q}`, message, nonce)
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-sign-uuid/sign", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", activeJob.ID)
		w := httptest.NewRecorder()
		hFail.signCommit(w, req)
		require.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("twirp permission denied", func(t *testing.T) {
		failClient := githubtwirp.NewNoopClient()
		failClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
		failClient.NoopSweagentdAPI.MockSignCommit = func(ctx context.Context, req *sweagentdTwirp.SignCommitRequest) (*sweagentdTwirp.SignCommitResponse, error) {
			return nil, twirp.NewError(twirp.PermissionDenied, "GPG signing not enabled")
		}
		hFail := NewHandler(obsv, ffClient, store, cf, failClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

		message := "test\n\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>"
		body := fmt.Sprintf(`{"message":%q,"verification_token":%q}`, message, nonce)
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-sign-uuid/sign", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", activeJob.ID)
		w := httptest.NewRecorder()
		hFail.signCommit(w, req)
		require.Equal(t, http.StatusForbidden, w.Code)
	})

	t.Run("twirp not found", func(t *testing.T) {
		failClient := githubtwirp.NewNoopClient()
		failClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
		failClient.NoopSweagentdAPI.MockSignCommit = func(ctx context.Context, req *sweagentdTwirp.SignCommitRequest) (*sweagentdTwirp.SignCommitResponse, error) {
			return nil, twirp.NewError(twirp.NotFound, "repository not found")
		}
		hFail := NewHandler(obsv, ffClient, store, cf, failClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

		message := "test\n\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>"
		body := fmt.Sprintf(`{"message":%q,"verification_token":%q}`, message, nonce)
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-sign-uuid/sign", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", activeJob.ID)
		w := httptest.NewRecorder()
		hFail.signCommit(w, req)
		require.Equal(t, http.StatusNotFound, w.Code)
	})

	coAuthorTests := []struct {
		name         string
		message      string
		wantStatus   int
		wantBodyText string // if non-empty, assert response body contains this
	}{
		{
			name:       "valid co-author with matching actor ID",
			message:    "tree abc123\nparent def456\nauthor Copilot <copilot@github.com> 1234567890 +0000\ncommitter Copilot <copilot@github.com> 1234567890 +0000\n\nFix the bug\n\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>",
			wantStatus: http.StatusOK,
		},
		{
			name:       "valid co-author with matching id but different login",
			message:    "tree abc123\n\nFix the bug\n\nCo-authored-by: oldlogin <42+oldlogin@users.noreply.github.com>",
			wantStatus: http.StatusOK,
		},
		{
			name:         "non-noreply email is rejected",
			message:      "tree abc123\n\nFix the bug\n\nCo-authored-by: testuser <testuser@example.com>",
			wantStatus:   http.StatusBadRequest,
			wantBodyText: http.StatusText(http.StatusBadRequest),
		},
		{
			name:         "legacy noreply email without numeric ID returns 400",
			message:      "tree abc123\n\nFix the bug\n\nCo-authored-by: testuser <testuser@users.noreply.github.com>",
			wantStatus:   http.StatusBadRequest,
			wantBodyText: http.StatusText(http.StatusBadRequest),
		},
		{
			name:         "co-author with mismatched actor ID returns 400",
			message:      "tree abc123\n\nFix the bug\n\nCo-authored-by: attacker <99+attacker@users.noreply.github.com>",
			wantStatus:   http.StatusBadRequest,
			wantBodyText: http.StatusText(http.StatusBadRequest),
		},
		{
			name:         "non-noreply email alone is rejected",
			message:      "tree abc123\n\nFix the bug\n\nCo-authored-by: someone <someone@example.com>",
			wantStatus:   http.StatusBadRequest,
			wantBodyText: http.StatusText(http.StatusBadRequest),
		},
		{
			name:       "no co-author passes (org billing)",
			message:    "tree abc123\n\nFix the bug",
			wantStatus: http.StatusOK,
		},
		{
			name:         "multiple GitHub noreply co-authors with different users returns 400",
			message:      "tree abc123\n\nFix the bug\n\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>\nCo-authored-by: attacker <99+attacker@users.noreply.github.com>",
			wantStatus:   http.StatusBadRequest,
			wantBodyText: http.StatusText(http.StatusBadRequest),
		},
		{
			name:       "GitHub noreply co-author plus AI attribution trailer passes",
			message:    "tree abc123\n\nFix the bug\n\nCo-authored-by: Claude Sonnet 4.5 <noreply@anthropic.com>\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>",
			wantStatus: http.StatusOK,
		},
		{
			name:       "only AI attribution trailers passes (no GitHub co-author)",
			message:    "tree abc123\n\nFix the bug\n\nCo-authored-by: Claude Sonnet 4.5 <noreply@anthropic.com>",
			wantStatus: http.StatusOK,
		},
		{
			name:       "Copilot bot noreply co-author is treated as informational and passes",
			message:    "tree abc123\n\nFix the bug\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>",
			wantStatus: http.StatusOK,
		},
		{
			name:       "Copilot bot plus matching human co-author passes",
			message:    "tree abc123\n\nFix the bug\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>",
			wantStatus: http.StatusOK,
		},
		{
			name:       "[bot] suffixed co-author plus matching human passes",
			message:    "tree abc123\n\nFix the bug\n\nCo-authored-by: google-labs-jules[bot] <161369871+google-labs-jules[bot]@users.noreply.github.com>\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>",
			wantStatus: http.StatusOK,
		},
		{
			name:       "duplicate identical co-author trailers passes",
			message:    "tree abc123\n\nFix the bug\n\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>",
			wantStatus: http.StatusOK,
		},
	}

	for _, tc := range coAuthorTests {
		t.Run(tc.name, func(t *testing.T) {
			body := fmt.Sprintf(`{"message":%q,"verification_token":%q}`, tc.message, nonce)
			req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-sign-uuid/sign", strings.NewReader(body)).WithContext(baseCtx)
			req.Header.Set("Content-Type", "application/json")
			req = muxSetParam(req, "jobID", activeJob.ID)
			w := httptest.NewRecorder()
			h.signCommit(w, req)
			require.Equal(t, tc.wantStatus, w.Code)
			if tc.wantBodyText != "" {
				assert.Contains(t, w.Body.String(), tc.wantBodyText)
			}
		})
	}

	t.Run("mismatched co-author returns 400 and SignCommit is not called", func(t *testing.T) {
		signCalled := false
		noCallClient := githubtwirp.NewNoopClient()
		noCallClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
		noCallClient.NoopSweagentdAPI.MockSignCommit = func(ctx context.Context, req *sweagentdTwirp.SignCommitRequest) (*sweagentdTwirp.SignCommitResponse, error) {
			signCalled = true
			return &sweagentdTwirp.SignCommitResponse{Signature: "sig"}, nil
		}
		hNoCall := NewHandler(obsv, ffClient, store, cf, noCallClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

		message := "tree abc123\n\nFix the bug\n\nCo-authored-by: attacker <99+attacker@users.noreply.github.com>"
		body := fmt.Sprintf(`{"message":%q,"verification_token":%q}`, message, nonce)
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-sign-uuid/sign", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", activeJob.ID)
		w := httptest.NewRecorder()
		hNoCall.signCommit(w, req)
		require.Equal(t, http.StatusBadRequest, w.Code)
		assert.False(t, signCalled, "SignCommit should not have been called")
	})
}

func TestParseCoAuthorTrailers(t *testing.T) {
	t.Run("parses noreply email with numeric ID", func(t *testing.T) {
		payload := "tree abc123\n\nFix the bug\n\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>"
		trailers, err := parseCoAuthorTrailers(payload)
		require.NoError(t, err)
		require.Len(t, trailers, 1)
		assert.Equal(t, int64(42), trailers[0].userID)
		assert.Equal(t, "testuser", trailers[0].name)
		assert.Equal(t, "42+testuser@users.noreply.github.com", trailers[0].email)
		assert.Equal(t, "testuser", trailers[0].login)
	})

	t.Run("parses non-noreply email", func(t *testing.T) {
		payload := "tree abc123\n\nFix the bug\n\nCo-authored-by: testuser <testuser@example.com>"
		trailers, err := parseCoAuthorTrailers(payload)
		require.NoError(t, err)
		require.Len(t, trailers, 1)
		assert.Equal(t, int64(0), trailers[0].userID)
		assert.Equal(t, "testuser", trailers[0].name)
	})

	t.Run("returns empty slice when no trailers", func(t *testing.T) {
		payload := "tree abc123\n\nFix the bug"
		trailers, err := parseCoAuthorTrailers(payload)
		require.NoError(t, err)
		assert.Empty(t, trailers)
	})

	t.Run("malformed trailer returns error", func(t *testing.T) {
		payload := "tree abc123\n\nCo-authored-by: malformed without angle brackets"
		_, err := parseCoAuthorTrailers(payload)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "malformed")
	})

	t.Run("legacy noreply email returns error", func(t *testing.T) {
		payload := "tree abc123\n\nCo-authored-by: testuser <testuser@users.noreply.github.com>"
		_, err := parseCoAuthorTrailers(payload)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "legacy format")
	})

	t.Run("multiple angle-bracket pairs rejected", func(t *testing.T) {
		payload := "tree abc123\n\nCo-authored-by: name <fake@x.com> <42+user@users.noreply.github.com>"
		_, err := parseCoAuthorTrailers(payload)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "unexpected content after email")
	})

	t.Run("trailing text after email rejected", func(t *testing.T) {
		payload := "tree abc123\n\nCo-authored-by: user <42+user@users.noreply.github.com> extra"
		_, err := parseCoAuthorTrailers(payload)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "unexpected content after email")
	})

	t.Run("trailing whitespace after email is allowed", func(t *testing.T) {
		payload := "tree abc123\n\nCo-authored-by: user <42+user@users.noreply.github.com>   "
		trailers, err := parseCoAuthorTrailers(payload)
		require.NoError(t, err)
		require.Len(t, trailers, 1)
		assert.Equal(t, int64(42), trailers[0].userID)
	})

	t.Run("ignores co-author-like lines outside trailing footer block", func(t *testing.T) {
		payload := "tree abc123\n\nDocument the trailer format\n\nCo-authored-by: example <999+example@users.noreply.github.com>\nThis line is still part of the body.\n\nCo-authored-by: real <42+real@users.noreply.github.com>"
		trailers, err := parseCoAuthorTrailers(payload)
		require.NoError(t, err)
		require.Len(t, trailers, 1)
		assert.Equal(t, int64(42), trailers[0].userID)
		assert.Equal(t, "real", trailers[0].name)
	})

	t.Run("ignores indented co-author-like lines in the body", func(t *testing.T) {
		payload := "tree abc123\n\nDocument the trailer format\n\n  Co-authored-by: example <999+example@users.noreply.github.com>\n\nCo-authored-by: real <42+real@users.noreply.github.com>"
		trailers, err := parseCoAuthorTrailers(payload)
		require.NoError(t, err)
		require.Len(t, trailers, 1)
		assert.Equal(t, int64(42), trailers[0].userID)
		assert.Equal(t, "real", trailers[0].name)
	})

	t.Run("ignores malformed co-author-like lines outside trailing footer block", func(t *testing.T) {
		payload := "tree abc123\n\nNotes about trailers\n\nCo-authored-by: malformed without angle brackets\n\nCo-authored-by: real <42+real@users.noreply.github.com>"
		trailers, err := parseCoAuthorTrailers(payload)
		require.NoError(t, err)
		require.Len(t, trailers, 1)
		assert.Equal(t, int64(42), trailers[0].userID)
		assert.Equal(t, "real", trailers[0].name)
	})
}

func TestValidateSingleCoAuthor(t *testing.T) {
	t.Run("zero trailers passes", func(t *testing.T) {
		err := validateSingleCoAuthor(nil)
		require.NoError(t, err)
	})

	t.Run("one trailer passes", func(t *testing.T) {
		err := validateSingleCoAuthor([]coAuthorTrailer{{name: "user", email: "u@e.com"}})
		require.NoError(t, err)
	})

	t.Run("multiple non-noreply trailers passes (informational)", func(t *testing.T) {
		err := validateSingleCoAuthor([]coAuthorTrailer{
			{name: "a", email: "a@e.com"},
			{name: "b", email: "b@e.com"},
		})
		require.NoError(t, err)
	})

	t.Run("multiple GitHub noreply trailers with different IDs returns error", func(t *testing.T) {
		err := validateSingleCoAuthor([]coAuthorTrailer{
			{name: "a", email: "42+a@users.noreply.github.com", userID: 42},
			{name: "b", email: "99+b@users.noreply.github.com", userID: 99},
		})
		require.Error(t, err)
		assert.Contains(t, err.Error(), "at most one GitHub Co-authored-by trailer is allowed")
	})

	t.Run("GitHub noreply plus non-noreply trailer passes", func(t *testing.T) {
		err := validateSingleCoAuthor([]coAuthorTrailer{
			{name: "Claude", email: "noreply@anthropic.com", userID: 0},
			{name: "user", email: "42+user@users.noreply.github.com", userID: 42, login: "user"},
		})
		require.NoError(t, err)
	})

	t.Run("Copilot bot trailer is not counted toward single co-author limit", func(t *testing.T) {
		err := validateSingleCoAuthor([]coAuthorTrailer{
			{name: "Copilot", email: "223556219+Copilot@users.noreply.github.com", userID: 223556219, login: "Copilot"},
			{name: "user", email: "42+user@users.noreply.github.com", userID: 42, login: "user"},
		})
		require.NoError(t, err)
	})

	t.Run("[bot] suffixed trailer is not counted toward single co-author limit", func(t *testing.T) {
		err := validateSingleCoAuthor([]coAuthorTrailer{
			{name: "google-labs-jules[bot]", email: "161369871+google-labs-jules[bot]@users.noreply.github.com", userID: 161369871, login: "google-labs-jules[bot]"},
			{name: "user", email: "42+user@users.noreply.github.com", userID: 42, login: "user"},
		})
		require.NoError(t, err)
	})

	t.Run("duplicate trailers with identical email passes", func(t *testing.T) {
		err := validateSingleCoAuthor([]coAuthorTrailer{
			{name: "user", email: "42+user@users.noreply.github.com", userID: 42},
			{name: "user", email: "42+user@users.noreply.github.com", userID: 42},
		})
		require.NoError(t, err)
	})

	t.Run("duplicate trailers with same email but different case passes", func(t *testing.T) {
		err := validateSingleCoAuthor([]coAuthorTrailer{
			{name: "user", email: "42+User@users.noreply.github.com", userID: 42},
			{name: "user", email: "42+user@users.noreply.github.com", userID: 42},
		})
		require.NoError(t, err)
	})
}

func TestHandlerSignCommitMetrics(t *testing.T) {
	type counterCall struct {
		key  string
		tags stats.Tags
	}

	makeHandlerWithMockCounter := func(t *testing.T, store interface {
		jobstore
		progressstore
		assignmentstore
	}, mockSignCommit func(ctx context.Context, req *sweagentdTwirp.SignCommitRequest) (*sweagentdTwirp.SignCommitResponse, error)) (*Handler, *[]counterCall) {
		t.Helper()
		obsv := observability.NewNoopExporters()
		calls := &[]counterCall{}
		obsv.Statter = &observability.MockStatter{
			MockCounter: func(key string, tags stats.Tags, value int64) {
				*calls = append(*calls, counterCall{key: key, tags: tags})
			},
		}
		cf := &github.NoopClientFactory{}
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
		noopClient.NoopSweagentdAPI.MockSignCommit = mockSignCommit
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		customAgentSvc := customagent.NewService(obsv, spokes, noopClient, ffClient)
		pluginSvc := plugins.NewService(obsv, spokes, noopClient, "https://github.com")
		h := NewHandler(obsv, ffClient, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")
		return h, calls
	}

	nonce := "metric-test-nonce"
	baseCtx := requestctx.AddData(context.Background(), &requestctx.CtxData{UserInfo: &requestctx.UserInfo{ID: 123, TokenInfo: &requestctx.TokenInfo{ApplicationID: 0}}})

	successMockSignCommit := func(_ context.Context, _ *sweagentdTwirp.SignCommitRequest) (*sweagentdTwirp.SignCommitResponse, error) {
		return &sweagentdTwirp.SignCommitResponse{Signature: "sig"}, nil
	}

	// Store and job setup is done here (outside t.Run) rather than inside each subtest
	// because the contextcheck linter flags context.Background() calls inside the anonymous
	// functions that t.Run creates, treating them as new goroutine boundaries.
	// Using context.Background() at the test function level is accepted by the linter.
	storeNoRSC := memory.NewStore()
	_, _ = storeNoRSC.CreateAssignment(context.Background(), &jobs.Assignment{ID: "1-2-metrics-assignment", OwnerID: 1, RepoID: 2})
	jobNoRSC := &jobs.Job{
		ID:                   "1-2-metrics-uuid",
		OwnerID:              1,
		RepoID:               2,
		NonceHash:            jobs.HashNonce(nonce),
		ActorID:              42,
		ActorLogin:           "testuser",
		AgentID:              1,
		Status:               jobs.JobStatusRunning,
		AssignmentID:         "1-2-metrics-assignment",
		RequireSignedCommits: false,
	}
	_, _ = storeNoRSC.CreateJob(context.Background(), jobNoRSC)

	storeRSC := memory.NewStore()
	_, _ = storeRSC.CreateAssignment(context.Background(), &jobs.Assignment{ID: "1-2-rsc-assignment", OwnerID: 1, RepoID: 2})
	jobRSC := &jobs.Job{
		ID:                   "1-2-rsc-uuid",
		OwnerID:              1,
		RepoID:               2,
		NonceHash:            jobs.HashNonce(nonce),
		ActorID:              42,
		ActorLogin:           "testuser",
		AgentID:              1,
		Status:               jobs.JobStatusRunning,
		AssignmentID:         "1-2-rsc-assignment",
		RequireSignedCommits: true,
	}
	_, _ = storeRSC.CreateJob(context.Background(), jobRSC)

	storeErr := memory.NewStore()
	_, _ = storeErr.CreateAssignment(context.Background(), &jobs.Assignment{ID: "1-2-err-assignment", OwnerID: 1, RepoID: 2})
	jobErr := &jobs.Job{
		ID:                   "1-2-err-uuid",
		OwnerID:              1,
		RepoID:               2,
		NonceHash:            jobs.HashNonce(nonce),
		ActorID:              42,
		ActorLogin:           "testuser",
		AgentID:              1,
		Status:               jobs.JobStatusRunning,
		AssignmentID:         "1-2-err-assignment",
		RequireSignedCommits: true,
	}
	_, _ = storeErr.CreateJob(context.Background(), jobErr)

	t.Run("success with require_signed_commits=false emits correct tags", func(t *testing.T) {
		h, calls := makeHandlerWithMockCounter(t, storeNoRSC, successMockSignCommit)

		message := "tree abc123\n\nFix the bug\n\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>"
		body := fmt.Sprintf(`{"message":%q,"verification_token":%q}`, message, nonce)
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-metrics-uuid/sign", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", jobNoRSC.ID)
		w := httptest.NewRecorder()
		h.signCommit(w, req)
		require.Equal(t, http.StatusOK, w.Code)

		var successCall *counterCall
		for i := range *calls {
			if (*calls)[i].key == "agenthttp.handler.sign_commit" {
				successCall = &(*calls)[i]
				break
			}
		}
		require.NotNil(t, successCall, "expected agenthttp.handler.sign_commit counter to be emitted")
		assert.Equal(t, "sign_commit", successCall.tags["endpoint"])
		assert.Equal(t, "false", successCall.tags["require_signed_commits"])
		assert.Equal(t, "true", successCall.tags["success"])
	})

	t.Run("success with require_signed_commits=true emits correct tags", func(t *testing.T) {
		h, calls := makeHandlerWithMockCounter(t, storeRSC, successMockSignCommit)

		message := "tree abc123\n\nFix the bug\n\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>"
		body := fmt.Sprintf(`{"message":%q,"verification_token":%q}`, message, nonce)
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-rsc-uuid/sign", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", jobRSC.ID)
		w := httptest.NewRecorder()
		h.signCommit(w, req)
		require.Equal(t, http.StatusOK, w.Code)

		var successCall *counterCall
		for i := range *calls {
			if (*calls)[i].key == "agenthttp.handler.sign_commit" {
				successCall = &(*calls)[i]
				break
			}
		}
		require.NotNil(t, successCall, "expected agenthttp.handler.sign_commit counter to be emitted")
		assert.Equal(t, "sign_commit", successCall.tags["endpoint"])
		assert.Equal(t, "true", successCall.tags["require_signed_commits"])
		assert.Equal(t, "true", successCall.tags["success"])
	})

	t.Run("error after job load includes require_signed_commits tag (not unknown)", func(t *testing.T) {
		h, calls := makeHandlerWithMockCounter(t, storeErr, successMockSignCommit)

		// Use a wrong token to trigger an error after the job is loaded
		message := "tree abc123\n\nFix the bug\n\nCo-authored-by: testuser <42+testuser@users.noreply.github.com>"
		body := fmt.Sprintf(`{"message":%q,"verification_token":"wrong-token"}`, message)
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-err-uuid/sign", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", jobErr.ID)
		w := httptest.NewRecorder()
		h.signCommit(w, req)
		require.Equal(t, http.StatusUnauthorized, w.Code)

		var errorCall *counterCall
		for i := range *calls {
			if (*calls)[i].key == "agenthttp.handler.errors" {
				errorCall = &(*calls)[i]
				break
			}
		}
		require.NotNil(t, errorCall, "expected agenthttp.handler.errors counter to be emitted")
		assert.Equal(t, "sign_commit", errorCall.tags["endpoint"])
		assert.Equal(t, "true", errorCall.tags["require_signed_commits"], "require_signed_commits should be true, not unknown")
		assert.Equal(t, "false", errorCall.tags["success"])
		assert.Equal(t, "access_validation_failed", errorCall.tags["error_type"])
	})

	t.Run("error before job load uses unknown for require_signed_commits tag", func(t *testing.T) {
		store := memory.NewStore()
		h, calls := makeHandlerWithMockCounter(t, store, successMockSignCommit)

		// Invalid JSON to trigger an error before GetJob
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-nojob/sign", strings.NewReader("not json")).WithContext(baseCtx)
		req = muxSetParam(req, "jobID", "1-2-nojob")
		w := httptest.NewRecorder()
		h.signCommit(w, req)
		require.Equal(t, http.StatusBadRequest, w.Code)

		var errorCall *counterCall
		for i := range *calls {
			if (*calls)[i].key == "agenthttp.handler.errors" {
				errorCall = &(*calls)[i]
				break
			}
		}
		require.NotNil(t, errorCall, "expected agenthttp.handler.errors counter to be emitted")
		assert.Equal(t, "sign_commit", errorCall.tags["endpoint"])
		assert.Equal(t, "unknown", errorCall.tags["require_signed_commits"], "require_signed_commits should be unknown before job is loaded")
	})
}

func TestValidateCoAuthorMatchesInitiator(t *testing.T) {
	job := &jobs.Job{
		ActorID:    42,
		ActorLogin: "testuser",
	}

	t.Run("no trailers skips validation", func(t *testing.T) {
		err := validateCoAuthorMatchesInitiator(nil, job)
		require.NoError(t, err)
	})

	t.Run("noreply email with matching ActorID passes", func(t *testing.T) {
		trailers := []coAuthorTrailer{{name: "testuser", email: "42+testuser@users.noreply.github.com", userID: 42}}
		err := validateCoAuthorMatchesInitiator(trailers, job)
		require.NoError(t, err)
	})

	t.Run("noreply email with wrong ID returns error", func(t *testing.T) {
		trailers := []coAuthorTrailer{{name: "attacker", email: "99+attacker@users.noreply.github.com", userID: 99}}
		err := validateCoAuthorMatchesInitiator(trailers, job)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "co-author exists but not matching the job initiator")
		assert.Contains(t, err.Error(), "co-author user IDs [99]")
		assert.Contains(t, err.Error(), "expected actor ID 42")
	})

	t.Run("non-noreply email is rejected", func(t *testing.T) {
		trailers := []coAuthorTrailer{{name: "testuser", email: "testuser@example.com", userID: 0}}
		err := validateCoAuthorMatchesInitiator(trailers, job)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "does not conform to the @users.noreply.github.com format")
		assert.Contains(t, err.Error(), "testuser@example.com")
	})

	t.Run("allowlisted AI attribution plus matching noreply passes", func(t *testing.T) {
		trailers := []coAuthorTrailer{
			{name: "Claude", email: "noreply@anthropic.com", userID: 0},
			{name: "testuser", email: "42+testuser@users.noreply.github.com", userID: 42},
		}
		err := validateCoAuthorMatchesInitiator(trailers, job)
		require.NoError(t, err)
	})

	t.Run("allowlisted AI attribution plus mismatched noreply returns error", func(t *testing.T) {
		trailers := []coAuthorTrailer{
			{name: "Claude", email: "noreply@anthropic.com", userID: 0},
			{name: "attacker", email: "99+attacker@users.noreply.github.com", userID: 99, login: "attacker"},
		}
		err := validateCoAuthorMatchesInitiator(trailers, job)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "co-author exists but not matching the job initiator")
	})

	t.Run("allowlisted AI attribution email alone passes", func(t *testing.T) {
		trailers := []coAuthorTrailer{
			{name: "Claude", email: "noreply@anthropic.com", userID: 0},
		}
		err := validateCoAuthorMatchesInitiator(trailers, job)
		require.NoError(t, err)
	})

	t.Run("non-noreply plus allowlisted is rejected", func(t *testing.T) {
		trailers := []coAuthorTrailer{
			{name: "Claude", email: "noreply@anthropic.com", userID: 0},
			{name: "someone", email: "someone@example.com", userID: 0},
		}
		err := validateCoAuthorMatchesInitiator(trailers, job)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "does not conform to the @users.noreply.github.com format")
		assert.Contains(t, err.Error(), "someone@example.com")
	})

	t.Run("Copilot bot noreply trailer is skipped as informational", func(t *testing.T) {
		trailers := []coAuthorTrailer{
			{name: "Copilot", email: "223556219+Copilot@users.noreply.github.com", userID: 223556219, login: "Copilot"},
		}
		err := validateCoAuthorMatchesInitiator(trailers, job)
		require.NoError(t, err)
	})

	t.Run("Copilot bot plus matching human co-author passes", func(t *testing.T) {
		trailers := []coAuthorTrailer{
			{name: "Copilot", email: "223556219+Copilot@users.noreply.github.com", userID: 223556219, login: "Copilot"},
			{name: "testuser", email: "42+testuser@users.noreply.github.com", userID: 42, login: "testuser"},
		}
		err := validateCoAuthorMatchesInitiator(trailers, job)
		require.NoError(t, err)
	})

	t.Run("Copilot bot plus mismatched human co-author returns error", func(t *testing.T) {
		trailers := []coAuthorTrailer{
			{name: "Copilot", email: "223556219+Copilot@users.noreply.github.com", userID: 223556219, login: "Copilot"},
			{name: "attacker", email: "99+attacker@users.noreply.github.com", userID: 99, login: "attacker"},
		}
		err := validateCoAuthorMatchesInitiator(trailers, job)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "co-author exists but not matching the job initiator")
	})

	t.Run("non-noreply email plus matching noreply is rejected", func(t *testing.T) {
		trailers := []coAuthorTrailer{
			{name: "testuser", email: "testuser@corp.example.com", userID: 0},
			{name: "testuser", email: "42+testuser@users.noreply.github.com", userID: 42, login: "testuser"},
		}
		err := validateCoAuthorMatchesInitiator(trailers, job)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "does not conform to the @users.noreply.github.com format")
		assert.Contains(t, err.Error(), "testuser@corp.example.com")
	})

	t.Run("[bot] suffixed noreply trailer is skipped as informational", func(t *testing.T) {
		trailers := []coAuthorTrailer{
			{name: "google-labs-jules[bot]", email: "161369871+google-labs-jules[bot]@users.noreply.github.com", userID: 161369871, login: "google-labs-jules[bot]"},
		}
		err := validateCoAuthorMatchesInitiator(trailers, job)
		require.NoError(t, err)
	})

	t.Run("[bot] suffixed trailer plus matching human co-author passes", func(t *testing.T) {
		trailers := []coAuthorTrailer{
			{name: "google-labs-jules[bot]", email: "161369871+google-labs-jules[bot]@users.noreply.github.com", userID: 161369871, login: "google-labs-jules[bot]"},
			{name: "testuser", email: "42+testuser@users.noreply.github.com", userID: 42, login: "testuser"},
		}
		err := validateCoAuthorMatchesInitiator(trailers, job)
		require.NoError(t, err)
	})
}
