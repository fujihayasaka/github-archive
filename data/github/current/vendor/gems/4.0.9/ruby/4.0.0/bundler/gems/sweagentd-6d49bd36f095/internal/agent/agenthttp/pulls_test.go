package agenthttp

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

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
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/plugins"
	"github.com/github/sweagentd/internal/requestctx"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestHandlerCreatePullRequest(t *testing.T) {
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
	spokes := customagenttest.MakeSpokes(t, map[string]string{})
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	customAgentSvc := customagent.NewService(obsv, spokes, noopClient, ffClient)
	pluginSvc := plugins.NewService(obsv, spokes, noopClient, "https://github.com")
	h := NewHandler(obsv, ffClient, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

	nonce := "test-nonce"
	job := &jobs.Job{
		ID:           "1-2-pr-uuid",
		OwnerID:      1,
		RepoID:       2,
		NonceHash:    jobs.HashNonce(nonce),
		BranchName:   "copilot/fix-123",
		BaseCommit:   "main",
		ActorID:      42,
		SessionID:    "session-123",
		AgentID:      1,
		AssignmentID: "1-2-assignment-uuid",
	}
	assignment := &jobs.Assignment{
		ID:      "1-2-assignment-uuid",
		OwnerID: 1,
		RepoID:  2,
	}
	_, _ = store.CreateAssignment(context.Background(), assignment)
	_, _ = store.CreateJob(context.Background(), job)

	// Second job/assignment pair for error-path tests (no PR set on assignment).
	errJob := &jobs.Job{
		ID:           "1-2-err-uuid",
		OwnerID:      1,
		RepoID:       2,
		NonceHash:    jobs.HashNonce(nonce),
		AssignmentID: "1-2-err-assignment",
	}
	errAssignment := &jobs.Assignment{
		ID:      "1-2-err-assignment",
		OwnerID: 1,
		RepoID:  2,
	}
	_, _ = store.CreateAssignment(context.Background(), errAssignment)
	_, _ = store.CreateJob(context.Background(), errJob)

	baseCtx := requestctx.AddData(context.Background(), &requestctx.CtxData{UserInfo: &requestctx.UserInfo{ID: 123, TokenInfo: &requestctx.TokenInfo{ApplicationID: uint64(cf.AppID())}}})

	t.Run("success", func(t *testing.T) {
		body := `{"title":"Fix bug","description":"This fixes the bug","draft":true}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-pr-uuid/pulls", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", job.ID)
		w := httptest.NewRecorder()
		h.createPullRequest(w, req)
		require.Equal(t, http.StatusCreated, w.Code)

		var resp createPullRequestResponseDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		assert.Equal(t, int64(123), resp.ID)
		assert.Equal(t, 789, resp.GithubNumber)
	})

	t.Run("assignment already has pull request", func(t *testing.T) {
		storeWithPR := memory.NewStore()
		existingAssignment := &jobs.Assignment{
			ID:                "1-2-existing-pr-assignment",
			OwnerID:           1,
			RepoID:            2,
			PullRequestID:     42,
			PullRequestNumber: 100,
		}
		existingJob := &jobs.Job{
			ID:           "1-2-existing-pr-job",
			OwnerID:      1,
			RepoID:       2,
			NonceHash:    jobs.HashNonce(nonce),
			AssignmentID: existingAssignment.ID,
		}
		_, _ = storeWithPR.CreateAssignment(baseCtx, existingAssignment)
		_, _ = storeWithPR.CreateJob(baseCtx, existingJob)
		hWithPR := NewHandler(obsv, ffClient, storeWithPR, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

		body := `{"title":"Fix bug"}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-existing-pr-job/pulls", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", existingJob.ID)
		w := httptest.NewRecorder()
		hWithPR.createPullRequest(w, req)
		require.Equal(t, http.StatusConflict, w.Code)

		var resp createPullRequestResponseDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		assert.Equal(t, int64(42), resp.ID)
		assert.Equal(t, 100, resp.GithubNumber)
	})

	t.Run("missing job id", func(t *testing.T) {
		body := `{"title":"Fix bug"}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs//pulls", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		w := httptest.NewRecorder()
		h.createPullRequest(w, req)
		require.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("missing nonce", func(t *testing.T) {
		body := `{"title":"Fix bug"}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-pr-uuid/pulls", strings.NewReader(body)).WithContext(baseCtx)
		req = muxSetParam(req, "jobID", job.ID)
		w := httptest.NewRecorder()
		h.createPullRequest(w, req)
		require.Equal(t, http.StatusUnauthorized, w.Code)
	})

	t.Run("invalid nonce", func(t *testing.T) {
		body := `{"title":"Fix bug"}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-pr-uuid/pulls", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, "wrong-nonce")
		req = muxSetParam(req, "jobID", job.ID)
		w := httptest.NewRecorder()
		h.createPullRequest(w, req)
		require.Equal(t, http.StatusUnauthorized, w.Code)
	})

	t.Run("job in terminal state", func(t *testing.T) {
		terminalJob := &jobs.Job{
			ID:           "1-2-terminal-uuid",
			OwnerID:      1,
			RepoID:       2,
			NonceHash:    jobs.HashNonce(nonce),
			AssignmentID: "1-2-assignment-uuid",
			Status:       jobs.JobStatusCompleted,
		}
		_, _ = store.CreateJob(baseCtx, terminalJob)

		body := `{"title":"Fix bug"}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-terminal-uuid/pulls", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", terminalJob.ID)
		w := httptest.NewRecorder()
		h.createPullRequest(w, req)
		require.Equal(t, http.StatusForbidden, w.Code)
		assert.Contains(t, w.Body.String(), "job is not running")
	})

	t.Run("missing title", func(t *testing.T) {
		body := `{"description":"No title provided"}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-pr-uuid/pulls", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", job.ID)
		w := httptest.NewRecorder()
		h.createPullRequest(w, req)
		require.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("invalid request body", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-pr-uuid/pulls", strings.NewReader("not json")).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req = muxSetParam(req, "jobID", job.ID)
		w := httptest.NewRecorder()
		h.createPullRequest(w, req)
		require.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("unauthorized", func(t *testing.T) {
		badCtx := requestctx.AddData(context.Background(), &requestctx.CtxData{UserInfo: &requestctx.UserInfo{ID: 123, TokenInfo: &requestctx.TokenInfo{ApplicationID: 999}}})
		body := `{"title":"Fix bug"}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-pr-uuid/pulls", strings.NewReader(body)).WithContext(badCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req = muxSetParam(req, "jobID", job.ID)
		w := httptest.NewRecorder()
		h.createPullRequest(w, req)
		require.Equal(t, http.StatusUnauthorized, w.Code)
	})

	t.Run("job not found", func(t *testing.T) {
		nfSvc := agent.NewService(&notFoundStore{}, cf, customAgentSvc, nil, obsv, ffClient, noopClient, &jobevents.NoopEmitter{}, agenticapptest.NewTestProvider(t), nil, nil)
		hnf := *h
		hnf.svc = nfSvc
		body := `{"title":"Fix bug"}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-missing/pulls", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req = muxSetParam(req, "jobID", "1-2-missing")
		w := httptest.NewRecorder()
		hnf.createPullRequest(w, req)
		require.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("pull request already exists", func(t *testing.T) {
		hConflict := *h
		hConflict.jobService = &noopPullRequestOpener{err: jobservice.ErrPullRequestExists}
		body := `{"title":"Fix bug"}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-err-uuid/pulls", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", errJob.ID)
		w := httptest.NewRecorder()
		hConflict.createPullRequest(w, req)
		require.Equal(t, http.StatusConflict, w.Code)
	})

	t.Run("twirp invalid argument", func(t *testing.T) {
		hErr := *h
		hErr.jobService = &noopPullRequestOpener{err: twirp.NewError(twirp.InvalidArgument, "base branch not found")}
		body := `{"title":"Fix bug"}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-err-uuid/pulls", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", errJob.ID)
		w := httptest.NewRecorder()
		hErr.createPullRequest(w, req)
		require.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("twirp not found", func(t *testing.T) {
		hErr := *h
		hErr.jobService = &noopPullRequestOpener{err: twirp.NewError(twirp.NotFound, "repository not found")}
		body := `{"title":"Fix bug"}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-err-uuid/pulls", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", errJob.ID)
		w := httptest.NewRecorder()
		hErr.createPullRequest(w, req)
		require.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("twirp permission denied", func(t *testing.T) {
		hErr := *h
		hErr.jobService = &noopPullRequestOpener{err: twirp.NewError(twirp.PermissionDenied, "insufficient permissions")}
		body := `{"title":"Fix bug"}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-err-uuid/pulls", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", errJob.ID)
		w := httptest.NewRecorder()
		hErr.createPullRequest(w, req)
		require.Equal(t, http.StatusForbidden, w.Code)
	})

	t.Run("twirp already exists", func(t *testing.T) {
		hErr := *h
		hErr.jobService = &noopPullRequestOpener{err: twirp.NewError(twirp.AlreadyExists, "pull request already exists")}
		body := `{"title":"Fix bug"}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-err-uuid/pulls", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", errJob.ID)
		w := httptest.NewRecorder()
		hErr.createPullRequest(w, req)
		require.Equal(t, http.StatusConflict, w.Code)
	})
}

func TestCreatePullRequestSucceedsWithConcurrentModification(t *testing.T) {
	obsv := observability.NewNoopExporters()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
	spokes := customagenttest.MakeSpokes(t, map[string]string{})
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentAgenticAppDisableEtagOnPRLinkage: true,
	})
	customAgentSvc := customagent.NewService(obsv, spokes, noopClient, ffClient)
	pluginSvc := plugins.NewService(obsv, spokes, noopClient, "https://github.com")
	nonce := "test-nonce"

	baseCtx := requestctx.AddData(context.Background(), &requestctx.CtxData{UserInfo: &requestctx.UserInfo{ID: 123, TokenInfo: &requestctx.TokenInfo{ApplicationID: uint64(cf.AppID())}}})

	t.Run("succeeds despite concurrent assignment modification", func(t *testing.T) {
		testStore := memory.NewStore()
		job := &jobs.Job{
			ID:           "1-2-retry-uuid",
			OwnerID:      1,
			RepoID:       2,
			NonceHash:    jobs.HashNonce(nonce),
			AssignmentID: "1-2-retry-assignment",
		}
		assignment := &jobs.Assignment{
			ID:      "1-2-retry-assignment",
			OwnerID: 1,
			RepoID:  2,
		}
		_, _ = testStore.CreateAssignment(baseCtx, assignment)
		_, _ = testStore.CreateJob(baseCtx, job)

		// Use a PR opener that stales the assignment ETag by patching it mid-flight.
		// With WithDisableAssignmentEtagCheck, this should still succeed.
		opener := &etagStalingPullRequestOpener{store: testStore, assignment: assignment}
		h := NewHandler(obsv, ffClient, testStore, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", opener, capi.NewNoopClient(), nil, "")

		body := `{"title":"Fix bug"}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-retry-uuid/pulls", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", job.ID)
		w := httptest.NewRecorder()
		h.createPullRequest(w, req)

		require.Equal(t, http.StatusCreated, w.Code)
		var resp createPullRequestResponseDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		assert.Equal(t, int64(123), resp.ID)
		assert.Equal(t, 789, resp.GithubNumber)
	})
}

// etagStalingPullRequestOpener simulates a concurrent modification that stales
// the assignment ETag during OpenPullRequest.
type etagStalingPullRequestOpener struct {
	store      *memory.Store
	assignment *jobs.Assignment
}

func (o *etagStalingPullRequestOpener) OpenPullRequest(ctx context.Context, gh jobservice.PullRequestCreator, assignment *jobs.Assignment, job *jobs.Job, title, body string) error {
	// Simulate a concurrent update that changes the assignment's ETag.
	freshAssignment, _ := o.store.GetAssignment(ctx, o.assignment.OwnerID, o.assignment.RepoID, o.assignment.ID)
	prID := int64(0)
	prNumber := 0
	_ = o.store.PatchAssignment(ctx, freshAssignment, db.AssignmentPatch{
		PullRequestID:     &prID,
		PullRequestNumber: &prNumber,
	})

	// Set PR fields on the in-memory objects (same as the real opener).
	job.PullRequestID = 123
	job.PullRequestNumber = 789
	assignment.PullRequestID = 123
	assignment.PullRequestNumber = 789
	return nil
}

func (o *etagStalingPullRequestOpener) StoreGeneratedPullData(ctx context.Context, job *jobs.Job, title, description string) error {
	return nil
}

func TestCreatePullRequestConcurrentPRLinkage(t *testing.T) {
	obsv := observability.NewNoopExporters()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
	spokes := customagenttest.MakeSpokes(t, map[string]string{})
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentAgenticAppDisableEtagOnPRLinkage: true,
	})
	customAgentSvc := customagent.NewService(obsv, spokes, noopClient, ffClient)
	pluginSvc := plugins.NewService(obsv, spokes, noopClient, "https://github.com")
	nonce := "test-nonce"
	baseCtx := requestctx.AddData(context.Background(), &requestctx.CtxData{UserInfo: &requestctx.UserInfo{ID: 123, TokenInfo: &requestctx.TokenInfo{ApplicationID: uint64(cf.AppID())}}})

	t.Run("succeeds when concurrent process already linked same PR", func(t *testing.T) {
		testStore := memory.NewStore()
		job := &jobs.Job{
			ID:           "1-2-race-job",
			OwnerID:      1,
			RepoID:       2,
			NonceHash:    jobs.HashNonce(nonce),
			AssignmentID: "1-2-race-assignment",
		}
		assignment := &jobs.Assignment{
			ID:      "1-2-race-assignment",
			OwnerID: 1,
			RepoID:  2,
		}
		_, _ = testStore.CreateAssignment(baseCtx, assignment)
		_, _ = testStore.CreateJob(baseCtx, job)

		// The opener links the same PR in the store (simulating the hydro
		// consumer calling UpdateAssignment before we persist).
		opener := &prLinkingOpener{
			store:      testStore,
			assignment: assignment,
			prID:       456,
			prNumber:   42,
		}
		h := NewHandler(obsv, ffClient, testStore, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", opener, capi.NewNoopClient(), nil, "")

		body := `{"title":"Fix bug"}`
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/1-2-race-job/pulls", strings.NewReader(body)).WithContext(baseCtx)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		req.Header.Set("Content-Type", "application/json")
		req = muxSetParam(req, "jobID", job.ID)
		w := httptest.NewRecorder()
		h.createPullRequest(w, req)

		require.Equal(t, http.StatusCreated, w.Code)
		var resp createPullRequestResponseDTO
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		assert.Equal(t, int64(456), resp.ID)
		assert.Equal(t, 42, resp.GithubNumber)
	})
}

// prLinkingOpener simulates a concurrent process (e.g. copilot-mission-control's
// hydro consumer) that links the same PR to the assignment in the store during
// OpenPullRequest. With the IN condition on pull_request_id, the subsequent
// PatchAssignment should still succeed because it accepts the PR ID we created.
type prLinkingOpener struct {
	store      *memory.Store
	assignment *jobs.Assignment
	prID       int64
	prNumber   int
}

func (o *prLinkingOpener) OpenPullRequest(ctx context.Context, gh jobservice.PullRequestCreator, assignment *jobs.Assignment, job *jobs.Job, title, body string) error {
	// Simulate a concurrent process linking the same PR to the assignment in the store.
	freshAssignment, _ := o.store.GetAssignment(ctx, o.assignment.OwnerID, o.assignment.RepoID, o.assignment.ID)
	prID := o.prID
	prNumber := o.prNumber
	_ = o.store.PatchAssignment(ctx, freshAssignment, db.AssignmentPatch{
		PullRequestID:     &prID,
		PullRequestNumber: &prNumber,
	})

	// Set PR fields on the in-memory objects (same as the real opener).
	job.PullRequestID = o.prID
	job.PullRequestNumber = o.prNumber
	assignment.PullRequestID = o.prID
	assignment.PullRequestNumber = o.prNumber
	return nil
}

func (o *prLinkingOpener) StoreGeneratedPullData(ctx context.Context, job *jobs.Job, title, description string) error {
	return nil
}
