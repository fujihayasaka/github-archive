// Package agentcleanup provides functionality for cleaning up agent tokens after job completion.
package agentcleanup

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
)

const copilotCleanupListHeader = "X-GitHub-Copilot-Cleanup-List"

type jobstore interface {
	GetJobForComputeID(ctx context.Context, owner, repo int64, computeID string) (*jobs.Job, error)
}

// Handler provides HTTP handlers for agent cleanup operations.
type Handler struct {
	obsv          observability.Exporters
	clients       github.ClientFactoryInterface
	jobs          jobstore
	ffClient      featureflags.Client
	ghTwirp       githubtwirp.ClientInterface
	isDevelopment bool
	githubAppID   int64
}

// NewHandler creates a new Handler instance with the provided dependencies.
func NewHandler(obsv observability.Exporters, jobsStore jobstore, clients github.ClientFactoryInterface, ffClient featureflags.Client, ghTwirp githubtwirp.ClientInterface, isDevelopment bool, githubAppID int64) *Handler {
	return &Handler{obsv, clients, jobsStore, ffClient, ghTwirp, isDevelopment, githubAppID}
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
	if user.TokenInfo.ApplicationID != uint64(h.githubAppID) {
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	enabled, err := githubtwirp.IsCopilotSweEnabled(ctx, h.ghTwirp, int64(user.ID), cleanUp.RepoID)
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

	// Log if the job state is unexpected, but continue with invalidating the tokens
	jobExists := true
	computeID := strconv.FormatInt(cleanUp.RunID, 10)
	job, err := h.jobs.GetJobForComputeID(ctx, cleanUp.OwnerID, cleanUp.RepoID, computeID)
	if err != nil || job == nil {
		logger.WithError(err).Error("Failed to find job for cleanup")
		jobExists = false
	} else {
		jobutils.UpdateRequestContextJob(ctx, h.obsv, job) //nolint:staticcheck // temporary during migration to jobservice
		logger = h.obsv.LoggerWithRequestTelemetry(ctx, r)
	}

	gh := h.clients.NewClientForUser(user.TokenInfo.Token, user.ID)

	userTokenCount := 0
	serverTokenCount := 0
	tokens := strings.Split(tokensToRevoke, ",")
	success := true
	for _, token := range tokens {
		// user-to-server token
		if strings.HasPrefix(token, "ghu_") {
			userTokenCount++
			err := gh.RevokeUserToken(ctx, token)
			if err != nil {
				h.obsv.LogAndReportError(ctx, err, "failed to revoke user token")
				success = false
			}
		} else {
			// server-to-server token
			serverTokenCount++
			err := gh.RevokeInstallationToken(ctx, token)
			if err != nil {
				h.obsv.LogAndReportError(ctx, err, "failed to revoke installation token")
				success = false
			}
		}
	}

	if success {
		logger.Info("successfully revoked tokens for job")
	}

	// Always return success, even if we failed to revoke some tokens -- we do not want to tip anyone off that we are doing cleanup
	w.WriteHeader(http.StatusOK)
	if h.isDevelopment {
		// Output more data in development mode for automated testing
		_, _ = fmt.Fprintf(w, "Success=%v\n\nJob exists: %v, agent processed %d user token(s) and %d server token(s) for workflow run %s.", success, jobExists, userTokenCount, serverTokenCount, computeID)
	} else {
		_, _ = fmt.Fprintf(w, "Success=%v", success)
	}
}
