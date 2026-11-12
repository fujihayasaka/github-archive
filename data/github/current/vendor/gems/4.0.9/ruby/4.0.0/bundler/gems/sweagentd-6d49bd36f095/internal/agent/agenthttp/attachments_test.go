package agenthttp

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	authd "github.com/github/authnd/client"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/customagenttest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/plugins"
	"github.com/github/sweagentd/internal/requestctx"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	chi "github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// setAttachmentURLParams sets both jobID and guid chi URL params on a request.
func setAttachmentURLParams(r *http.Request, jobID, guid string) *http.Request {
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("jobID", jobID)
	rctx.URLParams.Add("guid", guid)
	return r.WithContext(context.WithValue(r.Context(), chi.RouteCtxKey, rctx))
}

func TestDownloadAttachment(t *testing.T) {
	obsv := observability.NewNoopExporters()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	ffClient := featureflags.NewNoopClient(nil)
	spokes := customagenttest.MakeSpokes(t, map[string]string{})
	customAgentSvc := customagent.NewService(obsv, spokes, noopClient, ffClient)
	pluginsSvc := plugins.NewService(obsv, spokes, noopClient, "https://github.com")

	nonce := "test-nonce"
	validGUID := "12345678-1234-1234-1234-123456789abc"
	newJob := func() *jobs.Job {
		return &jobs.Job{
			ID:        "1-2-attach-uuid",
			OwnerID:   1,
			RepoID:    2,
			NonceHash: jobs.HashNonce(nonce),
			Action:    jobs.AgentActionFix,
		}
	}
	newUserCtx := func() context.Context {
		return requestctx.AddData(context.Background(), &requestctx.CtxData{
			UserInfo: &requestctx.UserInfo{
				ID:        123,
				TokenInfo: &requestctx.TokenInfo{ApplicationID: uint64(cf.AppID()), Type: string(authd.CredentialTypeUserToServerToken)},
			},
		})
	}
	userCtx := newUserCtx()

	t.Run("returns 401 when not authenticated", func(t *testing.T) {
		store := memory.NewStore()
		h := NewHandler(obsv, ffClient, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginsSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

		req := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
		req = setAttachmentURLParams(req, "1-2-attach-uuid", validGUID)
		rr := httptest.NewRecorder()
		h.downloadAttachment(rr, req)

		assert.Equal(t, http.StatusUnauthorized, rr.Code)
	})

	t.Run("returns 401 for invalid nonce", func(t *testing.T) {
		store := memory.NewStore()
		job := newJob()
		_, err := store.CreateJob(userCtx, job)
		require.NoError(t, err)

		h := NewHandler(obsv, ffClient, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginsSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "")

		req := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
		req = req.WithContext(userCtx)
		req = setAttachmentURLParams(req, job.ID, validGUID)
		req.Header.Set(jobs.JobNonceHeader, "wrong-nonce")
		rr := httptest.NewRecorder()
		h.downloadAttachment(rr, req)

		assert.Equal(t, http.StatusUnauthorized, rr.Code)
	})

	t.Run("returns 400 for invalid GUID format", func(t *testing.T) {
		store := memory.NewStore()
		job := newJob()
		_, err := store.CreateJob(userCtx, job)
		require.NoError(t, err)

		h := NewHandler(obsv, ffClient, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginsSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, "https://api.github.com/internal/user-attachments/assets")

		req := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
		req = req.WithContext(userCtx)
		req = setAttachmentURLParams(req, job.ID, "not-a-uuid")
		req.Header.Set(jobs.JobNonceHeader, nonce)
		rr := httptest.NewRecorder()
		h.downloadAttachment(rr, req)

		assert.Equal(t, http.StatusBadRequest, rr.Code)
		assert.Contains(t, rr.Body.String(), "invalid attachment GUID")
	})

	t.Run("proxies attachment URL on success", func(t *testing.T) {
		signedURL := "https://private-user-images.githubusercontent.com/12345/image.png?jwt=abc123"
		upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			assert.Contains(t, r.URL.Path, validGUID)
			assert.Equal(t, "application/vnd.github+json", r.Header.Get("Accept"))
			assert.NotEmpty(t, r.Header.Get("Authorization"))

			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]string{"url": signedURL})
		}))
		defer upstream.Close()

		store := memory.NewStore()
		job := newJob()
		_, err := store.CreateJob(userCtx, job)
		require.NoError(t, err)

		h := NewHandler(obsv, ffClient, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginsSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, upstream.URL)

		req := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
		req = req.WithContext(userCtx)
		req = setAttachmentURLParams(req, job.ID, validGUID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		rr := httptest.NewRecorder()
		h.downloadAttachment(rr, req)

		assert.Equal(t, http.StatusOK, rr.Code)

		var resp downloadAttachmentResponseDTO
		err = json.NewDecoder(rr.Body).Decode(&resp)
		require.NoError(t, err)
		assert.Equal(t, signedURL, resp.URL)
	})

	t.Run("returns 502 when upstream returns error", func(t *testing.T) {
		upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			http.Error(w, "not found", http.StatusNotFound)
		}))
		defer upstream.Close()

		store := memory.NewStore()
		job := newJob()
		_, err := store.CreateJob(userCtx, job)
		require.NoError(t, err)

		h := NewHandler(obsv, ffClient, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginsSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, upstream.URL)

		req := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
		req = req.WithContext(userCtx)
		req = setAttachmentURLParams(req, job.ID, validGUID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		rr := httptest.NewRecorder()
		h.downloadAttachment(rr, req)

		assert.Equal(t, http.StatusBadGateway, rr.Code)
	})

	t.Run("uses user-to-server token for user-billed job", func(t *testing.T) {
		const userToken = "u2s-token-for-user-billed-job"
		const appID int64 = 9001
		var s2sCalls int
		twirp := githubtwirp.NewNoopClient()
		twirp.NoopSweagentdAPI.MockMintUserToServerTokenForRepo = func(_ context.Context, req *sweagentdTwirp.MintUserToServerTokenForRepoRequest) (*sweagentdTwirp.MintUserToServerTokenForRepoResponse, error) {
			assert.Equal(t, uint64(7777), req.UserId, "user-to-server token must be minted for the job's actor")
			assert.Equal(t, uint64(2), req.RepositoryId)
			assert.Equal(t, appID, req.AgentId, "agent ID must come from the resolved app, not the (possibly zero) job.AgentID")
			return &sweagentdTwirp.MintUserToServerTokenForRepoResponse{Token: userToken}, nil
		}
		twirp.NoopSweagentdAPI.MockMintServerToServerTokenForRepo = func(_ context.Context, _ *sweagentdTwirp.MintServerToServerTokenForRepoRequest) (*sweagentdTwirp.MintServerToServerTokenForRepoResponse, error) {
			s2sCalls++
			return &sweagentdTwirp.MintServerToServerTokenForRepoResponse{Token: "s2s-should-not-be-used"}, nil
		}

		upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			assert.Equal(t, "Bearer "+userToken, r.Header.Get("Authorization"))
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]string{"url": "https://signed.example/asset"})
		}))
		defer upstream.Close()

		store := memory.NewStore()
		job := newJob()
		job.ActorID = 7777
		job.ActorType = jobs.ActorTypeUser
		ctx := newUserCtx()
		_, err := store.CreateJob(ctx, job)
		require.NoError(t, err)

		h := NewHandler(obsv, ffClient, store, cf, twirp, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginsSvc, agenticapptest.NewTestProviderWithID(t, appID), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, upstream.URL)

		req := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
		req = req.WithContext(ctx)
		req = setAttachmentURLParams(req, job.ID, validGUID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		rr := httptest.NewRecorder()
		h.downloadAttachment(rr, req)

		assert.Equal(t, http.StatusOK, rr.Code)
		assert.Equal(t, 0, s2sCalls, "user-billed jobs must not mint server-to-server tokens for attachment downloads")
	})

	t.Run("falls back to server-to-server token for org-billed job", func(t *testing.T) {
		const s2sToken = "s2s-token-for-org-billed-job"
		const appID int64 = 9002
		var u2sCalls int
		twirp := githubtwirp.NewNoopClient()
		twirp.NoopSweagentdAPI.MockMintUserToServerTokenForRepo = func(_ context.Context, _ *sweagentdTwirp.MintUserToServerTokenForRepoRequest) (*sweagentdTwirp.MintUserToServerTokenForRepoResponse, error) {
			u2sCalls++
			return &sweagentdTwirp.MintUserToServerTokenForRepoResponse{Token: "u2s-should-not-be-used"}, nil
		}
		twirp.NoopSweagentdAPI.MockMintServerToServerTokenForRepo = func(_ context.Context, req *sweagentdTwirp.MintServerToServerTokenForRepoRequest) (*sweagentdTwirp.MintServerToServerTokenForRepoResponse, error) {
			assert.Equal(t, uint64(2), req.RepositoryId)
			assert.Equal(t, appID, req.AgentId, "agent ID must come from the resolved app, not the (possibly zero) job.AgentID")
			return &sweagentdTwirp.MintServerToServerTokenForRepoResponse{Token: s2sToken}, nil
		}

		upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			assert.Equal(t, "Bearer "+s2sToken, r.Header.Get("Authorization"))
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]string{"url": "https://signed.example/asset"})
		}))
		defer upstream.Close()

		store := memory.NewStore()
		job := newJob()
		job.ActorID = 4242
		job.ActorType = jobs.ActorTypeOrg
		ctx := newUserCtx()
		_, err := store.CreateJob(ctx, job)
		require.NoError(t, err)

		h := NewHandler(obsv, ffClient, store, cf, twirp, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginsSvc, agenticapptest.NewTestProviderWithID(t, appID), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, upstream.URL)

		req := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
		req = req.WithContext(ctx)
		req = setAttachmentURLParams(req, job.ID, validGUID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		rr := httptest.NewRecorder()
		h.downloadAttachment(rr, req)

		assert.Equal(t, http.StatusOK, rr.Code)
		assert.Equal(t, 0, u2sCalls, "org-billed jobs must not mint user-to-server tokens for attachment downloads")
	})

	t.Run("returns 502 when token minting fails", func(t *testing.T) {
		var upstreamCalls int
		upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			upstreamCalls++
			w.WriteHeader(http.StatusOK)
		}))
		defer upstream.Close()

		twirp := githubtwirp.NewNoopClient()
		twirp.NoopSweagentdAPI.MockMintUserToServerTokenForRepo = func(_ context.Context, _ *sweagentdTwirp.MintUserToServerTokenForRepoRequest) (*sweagentdTwirp.MintUserToServerTokenForRepoResponse, error) {
			return nil, goerrors.New("simulated mint failure")
		}

		store := memory.NewStore()
		job := newJob()
		job.ActorID = 7777
		job.ActorType = jobs.ActorTypeUser
		ctx := newUserCtx()
		_, err := store.CreateJob(ctx, job)
		require.NoError(t, err)

		h := NewHandler(obsv, ffClient, store, cf, twirp, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginsSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), nil, upstream.URL)

		req := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
		req = req.WithContext(ctx)
		req = setAttachmentURLParams(req, job.ID, validGUID)
		req.Header.Set(jobs.JobNonceHeader, nonce)
		rr := httptest.NewRecorder()
		h.downloadAttachment(rr, req)

		assert.Equal(t, http.StatusBadGateway, rr.Code)
		assert.Equal(t, 0, upstreamCalls, "upstream must not be called when token minting fails")
	})
}

func TestAttachmentGUIDRegex(t *testing.T) {
	tests := []struct {
		guid  string
		valid bool
	}{
		{"12345678-1234-1234-1234-123456789abc", true},
		{"ABCDEF01-2345-6789-abcd-ef0123456789", true},
		{"not-a-uuid", false},
		{"12345678-1234-1234-1234-123456789ab", false},
		{"12345678-1234-1234-1234-123456789abcd", false},
		{"../../../etc/passwd", false},
		{"12345678-1234-1234-1234-123456789abc/../../etc", false},
		{"", false},
	}

	for _, tt := range tests {
		t.Run(tt.guid, func(t *testing.T) {
			assert.Equal(t, tt.valid, attachmentGUIDRegex.MatchString(tt.guid))
		})
	}
}
