package agenthttp

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"

	"github.com/github/sweagentd/internal/agent"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"

	"github.com/go-chi/chi/v5"
)

// Temporary interfaces until we refactor these handlers into this package
type callbackHandler interface {
	HandleCallback(w http.ResponseWriter, r *http.Request)
}

// Temporary interfaces until we refactor these handlers into this package
type cleanupHandler interface {
	HandleCleanup(w http.ResponseWriter, r *http.Request)
}

type appInfoProvider interface {
	AppID() int64
}

type jobstore interface {
	GetJob(ctx context.Context, owner, repo int64, id string) (*jobs.Job, error)
}

// Handler is responsible for handling agent-related HTTP requests.
type Handler struct {
	obsv  observability.Exporters
	ffs   featureflags.Client
	twirp githubtwirp.ClientInterface
	svc   *agent.Service
	app   appInfoProvider

	callback callbackHandler
	cleanup  cleanupHandler
}

// NewHandler creates a new Handler instance with the provided observability exporters,
// feature flags client, and GitHub client factory.
// It initializes the service layer for agent (runtime) operations.
func NewHandler(
	obsv observability.Exporters,
	ffs featureflags.Client,
	store jobstore,
	cpf github.ClientFactoryInterface,
	twirp githubtwirp.ClientInterface,
	callback callbackHandler,
	cleanup cleanupHandler,
	customAgentSvc *customagent.Service) *Handler {
	return &Handler{
		obsv:  obsv,
		ffs:   ffs,
		twirp: twirp,
		app:   cpf,

		callback: callback,
		cleanup:  cleanup,

		svc: agent.NewService(store, cpf, customAgentSvc, obsv, ffs, twirp),
	}
}

// RegisterRoutes registers the agent-related routes with the provided chi router.
// It defines a group of routes under the "/agent" path.
func (h *Handler) RegisterRoutes(r chi.Router) {
	r.Route("/agent", func(r chi.Router) {
		r.Post("/cleanup", h.cleanup.HandleCleanup)
		r.Post("/jobs", h.callback.HandleCallback)
		r.Get("/jobs/{jobID}", h.getJob)

		// The /custom-agents/{org}/{repo}/{name} endpoint is indirectly tied to the job. While
		// the list of available custom agents is returned as part of the job details, the actual
		// org and repo names may vary from those on the job itself. So, this endpoint
		// takes in org and repo names instead of the Job ID to allow this to work.
		r.Get("/custom-agents/{repoOwner}/{repoName}/{agentName}", h.getAgent)

		// TODO: Remove /subagents endpoint once runtime has been deployed - need to keep this for now due to deployment order
		r.Get("/subagents/{repoOwner}/{repoName}/{agentName}", h.getAgent)
	})
}

// handleDomainError resolves expected errors to their appropriate HTTP responses.
// If the error is not recognized, it returns a generic internal server error.
// The expected error codes are:
// - ErrInvalidJobID: returns a 400 Bad Request.
// - ErrJobNotFound: returns a 404 Not Found.
// Other errors will return a 500 Internal Server Error.
func (h *Handler) handleDomainError(w http.ResponseWriter, err error) {
	if errors.Is(err, agent.ErrInvalidJobIDFormat) {
		http.Error(w, "invalid job_id", http.StatusBadRequest)
		return
	}
	if errors.Is(err, agent.ErrInvalidJobIDOwner) {
		http.Error(w, "invalid owner in job_id", http.StatusBadRequest)
		return
	}
	if errors.Is(err, agent.ErrInvalidJobIDRepo) {
		http.Error(w, "invalid repo in job_id", http.StatusBadRequest)
		return
	}
	if errors.Is(err, agent.ErrJobNotFound) {
		w.WriteHeader(http.StatusNotFound)
		return
	}

	// Unrecognized error, return a generic internal server error
	http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
}

func (h *Handler) getJob(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.obsv.Logger.Named("agenthttp.Handler.getJob")

	userInfo, err := h.authorize(ctx)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("authorization failed")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)

		return
	}

	jobID := chi.URLParam(r, "jobID")
	if jobID == "" {
		logger.WithContext(ctx).Info("job ID not provided")
		http.Error(w, "job_id is required", http.StatusBadRequest)

		return
	}

	job, err := h.svc.GetJob(ctx, jobID)
	if err != nil {
		h.handleDomainError(w, err)

		return
	}

	_, err = h.checkEnablement(ctx, int64(userInfo.ID), job.RepoID)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("enablement check failed")
		http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

		return
	}

	err = h.validateNonce(r, job.NonceHash)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("access validation failed")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)

		return
	}

	availableCustomAgents, err := h.svc.ListAgents(ctx, userInfo, job)
	// We do not want to 404 when no custom agents are found since we still want to return job details
	if err != nil && !errors.Is(err, customagent.ErrNoAgentsFound) {
		logger.WithContext(ctx).WithError(err).Error("failed to list available custom agents")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}

	organizationCustomInstructions, _ := h.svc.GetOrganizationCustomInstructions(ctx, int64(userInfo.ID), job)

	jobDTO := jobDTOFromDomain(job, availableCustomAgents, organizationCustomInstructions)

	w.Header().Set("Content-Type", "application/json")
	err = json.NewEncoder(w).Encode(jobDTO)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to encode job response")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}
}

// getAgent is largely the same as customagenthttp.getAgent but has been kept
// separate to allow inputs and outputs to diverge in the future if needed.
func (h *Handler) getAgent(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.obsv.Logger.Named("agenthttp.Handler.getAgent")

	userInfo, err := h.authorize(ctx)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("authorization failed")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)

		return
	}

	repoOwner, repoName, agentName := chi.URLParam(r, "repoOwner"), chi.URLParam(r, "repoName"), chi.URLParam(r, "agentName")
	if repoOwner == "" || repoName == "" || agentName == "" {
		http.Error(w, "repository owner, name, and agent name cannot be empty", http.StatusBadRequest)
		return
	}

	// Get the repository info for feature flag check
	enabled, err := h.svc.CustomAgentsEnabledForRepoByName(ctx, int64(userInfo.ID), repoOwner, repoName)
	if err != nil {
		if errors.Is(err, customagent.ErrRepoNotFound) {
			logger.WithContext(ctx).Info("repository not found")
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
			return
		}
		logger.WithContext(ctx).WithError(err).Error("failed to get repository info")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}
	if !enabled {
		logger.WithContext(ctx).Info("custom agents not enabled for repository")
		http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

		return
	}
	// Version can be a SHA, tag, or branch name - if empty, uses the default branch
	version := r.URL.Query().Get("version")
	customAgentDetails, err := h.svc.GetAgent(ctx, userInfo, repoOwner, repoName, agentName, version)
	if err != nil {
		if errors.Is(err, customagent.ErrRepoNotFound) {
			logger.WithContext(ctx).Info("repository not found")
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

			return
		}
		if errors.Is(err, customagent.ErrRequestedAgentNotFound) {
			logger.WithContext(ctx).Info("agent not found for repository")
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

			return
		}

		logger.WithContext(ctx).WithError(err).Error("failed to get agent")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}

	w.Header().Set("Content-Type", "application/json")

	err = json.NewEncoder(w).Encode(makeCustomAgentDTO(customAgentDetails, true))
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to encode response")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}
}

func (h *Handler) authorize(ctx context.Context) (*requestctx.UserInfo, error) {
	// extract user info from request context
	userInfo, ok := requestctx.User(ctx)
	if !ok || userInfo == nil {
		return userInfo, errors.New("user information not found in context")
	}

	// should only be called by agents using a GitHub App token
	if userInfo.TokenInfo.ApplicationID != uint64(h.app.AppID()) {
		return userInfo, errors.New("invalid application ID in token")
	}

	return userInfo, nil
}

func (h *Handler) checkEnablement(ctx context.Context, userID, repoID int64) (bool, error) {
	// make sure CCA is enabled for the user or repo
	enabled, err := githubtwirp.IsCopilotSweEnabled(ctx, h.twirp, userID, repoID)
	if err != nil {
		return false, errors.New("failed to check enablement")
	}
	if !enabled {
		return false, errors.New("copilot coder agent not enabled")
	}

	return true, nil
}

func (h *Handler) validateNonce(r *http.Request, nonceHash string) error {
	nonce := r.Header.Get(jobs.JobNonceHeader)
	if nonce == "" {
		return errors.New("missing nonce header")
	}
	if jobs.HashNonce(nonce) != nonceHash {
		return errors.New("invalid nonce header")
	}
	return nil
}
