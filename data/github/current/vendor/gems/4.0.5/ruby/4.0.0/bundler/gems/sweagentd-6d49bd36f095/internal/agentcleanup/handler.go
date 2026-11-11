// Package agentcleanup provides functionality for cleaning up agent tokens after job completion.
package agentcleanup

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
)

const copilotCleanupListHeader = "X-GitHub-Copilot-Cleanup-List"

type jobstore interface {
	GetJobForComputeID(ctx context.Context, owner, repo int64, computeID string) (*jobs.Job, error)
}

// Handler provides HTTP handlers for agent cleanup operations.
type Handler struct {
	obsv          observability.Exporters
	gh            sweagentd.GitHubAPI
	jobs          jobstore
	ffClient      featureflags.Client
	ghTwirp       githubtwirp.ClientInterface
	isDevelopment bool
	appProvider   *agenticapp.Provider
}

// NewHandler creates a new Handler instance with the provided dependencies.
func NewHandler(obsv observability.Exporters, jobsStore jobstore, gh sweagentd.GitHubAPI, ffClient featureflags.Client, ghTwirp githubtwirp.ClientInterface, isDevelopment bool, appProvider *agenticapp.Provider) *Handler {
	return &Handler{obsv, gh, jobsStore, ffClient, ghTwirp, isDevelopment, appProvider}
}

type cleanupRequest struct {
	OwnerID int64 `json:"oid"`
	RepoID  int64 `json:"rid"`
	RunID   int64 `json:"wid"`
}

// HandleCleanup handles agent token cleanup requests.
// Note that in prod, this is authed via CAPI and proxied to this endpoint internally
func (h *Handler) HandleCleanup(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "agentcleanup.HandleCleanup")
	defer span.End()
	r = r.WithContext(ctx)

	var cleanUp cleanupRequest
	err := json.NewDecoder(r.Body).Decode(&cleanUp)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)

	tokensToRevoke := r.Header.Get(copilotCleanupListHeader)
	if tokensToRevoke == "" {
		logger.Error("failed to get GitHub Copilot tokens for cleanup")
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	// Require that a user is logged in to process the request
	user, ok := requestctx.User(ctx)
	if !ok {
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	// AuthZ: This endpoint should only be called by the runtime, so make sure it's for our GitHub App
	app, err := h.appProvider.FindByID(ctx, int64(user.TokenInfo.ApplicationID))
	if err != nil {
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	jobservice.SetCtxAgent(ctx, h.obsv, h.ffClient, app, app.AppID())

	// S2S tokens use installation IDs, not user IDs; skip user-based enablement check.
	if !user.TokenInfo.IsServerToServerToken() && !h.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentSkipCallbackEnablementCheck, int64(user.ID)) {
		enabled, _, err := h.ghTwirp.IsAgentEnabled(ctx, app.AppID(), int64(user.ID), cleanUp.RepoID)
		if err != nil {
			logger.WithError(err).Error("Failed to check enablement")
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
			return
		}
		if !enabled {
			logger.Error("Copilot coder agent not enabled")
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
			return
		}
	}

	computeID := strconv.FormatInt(cleanUp.RunID, 10)
	job, err := h.jobs.GetJobForComputeID(ctx, cleanUp.OwnerID, cleanUp.RepoID, computeID)
	switch {
	case err != nil:
		logger.WithError(err).Error("Failed to get job by computeID for token cleanup")
	case job == nil:
		logger.Error("No job found for computeID during token cleanup")
	default:
		jobutils.UpdateRequestContextJob(ctx, h.obsv, job) //nolint:staticcheck // temporary during migration to jobservice
		logger = h.obsv.LoggerWithRequestTelemetry(ctx, r)
	}

	tokens := strings.Split(tokensToRevoke, ",")
	success := true

	failedTokens, err := agenticapp.RevokeTokens(ctx, h.ghTwirp, app, tokens)
	if err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to revoke tokens via twirp")
		success = false
	}
	if len(failedTokens) > 0 {
		logger.Warn("some tokens failed to revoke via twirp")
		success = false
	} else {
		logger.Info("successfully revoked all tokens via twirp")
	}

	// Always return success, even if we failed to revoke some tokens -- we do not want to tip anyone off that we are doing cleanup
	w.WriteHeader(http.StatusOK)
	_, _ = fmt.Fprintf(w, "Success=%v", success)
}
