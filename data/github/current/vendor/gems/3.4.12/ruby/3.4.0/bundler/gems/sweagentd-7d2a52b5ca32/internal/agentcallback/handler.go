package agentcallback

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/github/go-mark"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/command"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
)

// Handler handles agent callback requests
type Handler struct {
	obsv        observability.Exporters
	manager     *jobManager
	ffClient    featureflags.Client
	ghTwirp     githubtwirp.ClientInterface
	githubAppID int64
}

type jobservice interface {
	GetJobByID(ctx context.Context, ownerID, repoID int64, jobID string) (*jobs.Job, error)
}

type jobstore interface {
	GetJob(ctx context.Context, owner, repo int64, id string) (*jobs.Job, error)
	PatchJob(ctx context.Context, job *jobs.Job, patch db.JobPatch) error
	BatchPatchCommands(ctx context.Context, cmd []*command.Command, patch db.CommandPatch) error
	GetCommandsWithStatus(ctx context.Context, assignmentID, jobID string, status command.Status) ([]*command.Command, error)
	CreateJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error) // For testing purposes only
}

// NewHandler creates a new agent callback handler with the provided dependencies.
func NewHandler(
	obsv observability.Exporters,
	jobService jobservice,
	capiClient capi.Client,
	jobsStore jobstore,
	clients github.ClientFactoryInterface,
	ffClient featureflags.Client,
	ghTwirp githubtwirp.ClientInterface,
	githubAppID int64) *Handler {
	return &Handler{obsv, newManager(obsv, jobService, jobsStore, clients, ghTwirp, ffClient), ffClient, ghTwirp, githubAppID}
}

// HandleCallback handles agent callback HTTP requests
func (h *Handler) HandleCallback(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "agentcallback.HandleJobs")
	defer span.End()
	r = r.WithContext(ctx)

	var update JobUpdate
	err := json.NewDecoder(r.Body).Decode(&update)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if update.CreatedAt.IsZero() {
		update.CreatedAt = time.Now().UTC()
	}

	tags := h.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"kind": string(update.Kind),
		// "action":                string(update.Action),
		"accepts_user_messages": strconv.FormatBool(update.AcceptsUserMessages),
	})
	start := time.Now()
	h.obsv.Statter.Counter("agentcallback.requests", tags, 1)

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

	enabled, err := githubtwirp.IsCopilotSweEnabled(ctx, h.ghTwirp, int64(user.ID), update.RepoID)
	if err != nil {
		h.obsv.Logger.WithError(err).Error("Failed to check enablement")
		http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
		return
	}
	if !enabled {
		h.obsv.Logger.Info("Copilot coder agent not enabled")
		http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
		return
	}

	// Get the job to validate nonce
	job, err := h.manager.jobService.GetJobByID(ctx, update.RepoOwnerID, update.RepoID, update.JobID)
	if err != nil {
		// Don't reveal too much information in the error message
		http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
		return
	}

	err = requestctx.AddJobUpdate(ctx, &requestctx.CtxJobUpdate{
		Kind:      string(update.Kind),
		CreatedAt: update.CreatedAt.Unix(),
	})
	if err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to add job update to context")
	}

	logger := h.obsv.LoggerWithTelemetry(ctx)

	// Validate nonce header if job has a nonce hash
	if h.ffClient.IsEnabledForUser(ctx, "sweagentd_enforce_job_nonce", int64(user.ID)) {
		nonce := r.Header.Get(jobs.JobNonceHeader)
		if nonce == "" || jobs.HashNonce(nonce) != job.NonceHash {
			logger.Info("Invalid or missing nonce header")
			http.Error(w, "Invalid or missing job nonce", http.StatusBadRequest)
			return
		}
	}

	resp, err := h.manager.HandleJobUpdate(ctx, r, job, update, int64(user.ID))
	if err != nil {
		var badRequestErr *badRequestError
		if errors.As(err, &badRequestErr) {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		if errors.Is(err, mark.ErrNotFound) {
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
			return
		}

		h.obsv.LogAndReportError(ctx, err, "failed to process agent callback")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
		return
	}

	logger.Info("processed agent callback")
	h.obsv.Statter.DistributionMs("agentcallback.request_duration", tags, time.Since(start))
	if resp == nil {
		w.WriteHeader(http.StatusOK)
		return
	}

	jsonResp, err := json.Marshal(resp)
	if err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to marshal response")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
		return
	}
	_, err = w.Write(jsonResp)
	if err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to write response")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusOK)
}

type badRequestError struct {
	message string
}

func (e *badRequestError) Error() string {
	return e.message
}
