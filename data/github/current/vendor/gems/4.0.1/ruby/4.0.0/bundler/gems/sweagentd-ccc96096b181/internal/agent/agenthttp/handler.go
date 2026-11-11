// Package agenthttp provides HTTP handlers for APIs used by agents.
//
// APIs and handlers in this package should be limited to those used by the agent
// itself while executing jobs. APIs and handlers for other consumers should be
// placed in other packages (e.g., models).
//
// APIs should generally be designed around the job as the primary resource, with
// related resources (e.g., progress, custom agents) being accessed via the job.
// e.g., /agent/jobs/{jobID}/progress, /agent/jobs/{jobID}/new-api-endpoint
//
// Handlers in this package should depend on the agent service layer for business
// logic and data access, rather than directly accessing data stores or other services.
package agenthttp

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agent"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/api"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/progress"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"

	chi "github.com/go-chi/chi/v5"
)

// Temporary interfaces until we refactor these handlers into this package
type callbackHandler interface {
	HandleCallback(w http.ResponseWriter, r *http.Request)
}

// Temporary interfaces until we refactor these handlers into this package
type cleanupHandler interface {
	HandleCleanup(w http.ResponseWriter, r *http.Request)
}

type jobstore interface {
	GetJob(ctx context.Context, owner, repo int64, id string) (*jobs.Job, error)
	GetJobSummariesForAssignmentID(ctx context.Context, owner, repo int64, assignmentID string) ([]*jobs.JobSummary, error)
}

type progressstore interface {
	CreateProgress(ctx context.Context, progress *progress.Progress) (*progress.Progress, error)
	BatchCreateProgress(ctx context.Context, progresses []*progress.Progress) ([]*progress.Progress, error)
	ListProgress(ctx context.Context, assignmentID, jobID string) ([]*progress.Progress, error)
	ListProgressByNamespace(ctx context.Context, assignmentID, jobID string, namespaces []string) ([]*progress.Progress, error)
}

var (
	errMissingJobID           = goerrors.New("missing job ID")
	errAccessValidationFailed = goerrors.New("access validation failed")
	errCustomAgentsNotEnabled = goerrors.New("custom agents not enabled")
)

// Handler is responsible for handling agent-related HTTP requests.
type Handler struct {
	obsv        observability.Exporters
	ffs         featureflags.Client
	twirp       githubtwirp.ClientInterface
	svc         *agent.Service
	appProvider *agenticapp.Provider

	callback callbackHandler
	cleanup  cleanupHandler
}

// NewHandler creates a new Handler instance with the provided observability exporters,
// feature flags client, and GitHub client factory.
// It initializes the service layer for agent (runtime) operations.
func NewHandler(
	obsv observability.Exporters,
	ffs featureflags.Client,
	store interface {
		jobstore
		progressstore
	},
	cpf github.ClientFactoryInterface,
	twirp githubtwirp.ClientInterface,
	callback callbackHandler,
	cleanup cleanupHandler,
	customAgentSvc *customagent.Service,
	appProvider *agenticapp.Provider,
	eventEmitter agent.JobEventEmitter,
) *Handler {
	return &Handler{
		obsv:        obsv,
		ffs:         ffs,
		twirp:       twirp,
		appProvider: appProvider,

		callback: callback,
		cleanup:  cleanup,

		svc: agent.NewService(store, cpf, customAgentSvc, obsv, ffs, twirp, eventEmitter),
	}
}

// RegisterRoutes registers the agent-related routes with the provided chi router.
// It defines a group of routes under the "/agent" path.
func (h *Handler) RegisterRoutes(r chi.Router) {
	r.Route("/agent", func(r chi.Router) {
		r.Post("/cleanup", h.middleware(http.HandlerFunc(h.cleanup.HandleCleanup)))
		r.Post("/jobs", h.middleware(http.HandlerFunc(h.callback.HandleCallback)))
		r.Get("/jobs/{jobID}", h.middleware(http.HandlerFunc(h.getJob)))
		r.Get("/jobs/{jobID}/progress", h.middleware(http.HandlerFunc(h.getProgress)))
		r.Post("/jobs/{jobID}/progress", h.middleware(http.HandlerFunc(h.createProgress)))

		// The /custom-agents/{org}/{repo}/{name} endpoint is indirectly tied to the job. While
		// the list of available custom agents is returned as part of the job details, the actual
		// org and repo names may vary from those on the job itself. So, this endpoint
		// takes in org and repo names instead of the Job ID to allow this to work.
		r.Get("/custom-agents/{repoOwner}/{repoName}/{agentName}", h.middleware(http.HandlerFunc(h.getAgent)))
	})
}

func (h *Handler) middleware(route http.Handler) http.HandlerFunc {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		ctx, span := h.obsv.Tracer.Start(r.Context(), "agenthttp.middleware")
		defer span.End()

		r = r.WithContext(ctx)
		rw := api.NewResponseWrapper(w)
		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)
		logger.Info("request start")

		defer func() {
			duration := time.Since(start)
			logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)
			// Get logger with all context data that was added during request processing.
			logKvps := []kvp.Field{
				kvp.Int64("duration_ms", duration.Milliseconds()),
				kvp.Int("http.status_code", rw.StatusCode),
			}
			if rw.ErrMsg != "" {
				logKvps = append(logKvps,
					kvp.String("exception.message", rw.ErrMsg),
				)
			}
			logger.WithFields(logKvps...).Info("request end")
		}()
		route.ServeHTTP(rw, r)
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
	ctx, span := h.obsv.Tracer.Start(r.Context(), "agenthttp.Handler.getJob")
	defer span.End()
	r = r.WithContext(ctx)
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

	app, err := h.appProvider.FindByID(job.AgentID)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to find app by ID")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}

	_, err = h.checkEnablement(ctx, app.AppID(), int64(userInfo.ID), job.RepoID)
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

	var agent sweagentd.CustomAgent
	if h.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCustomAgentPermissions, job) {
		var err error
		agent, err = h.svc.GetAgentForJob(ctx, job)
		if err != nil {
			logger.WithContext(ctx).WithError(err).Error("failed to get custom agent")
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
			return
		}
	} else {
		// TODO (chuxel): Remove this legacy path once feature flags rolled out
		agentFromJob := customagent.FromDB(job.CustomAgent)
		agent = agentFromJob
		if _, isCopilot := agentFromJob.(*customagent.CopilotAgent); !isCopilot {
			// If not Copilot, fetch the full agent details so we can include the prompt in the DTO
			// If it is Copilot, there's no prompt so we can just use the DBRecord conversion
			agent, err = h.svc.GetAgentByRepoID(ctx, userInfo, uint64(job.CustomAgent.RepoID), job.CustomAgent.Name, job.CustomAgent.Version)
			if err != nil {
				logger.WithContext(ctx).WithError(err).Error("failed to get custom agent")
				http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
				return
			}
		}
	}

	// Since we'll only return valid agents for the repository for the job, we can skip the custom agent authz check
	availableCustomAgents, err := h.svc.ListAgentsByRepoID(ctx, userInfo, job, true)
	// We do not want to 404 when no custom agents are found since we still want to return job details
	if err != nil && !errors.Is(err, customagent.ErrNoAgentsFound) {
		logger.WithContext(ctx).WithError(err).Error("failed to list available custom agents")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}

	organizationCustomInstructions, _ := h.svc.GetOrganizationCustomInstructions(ctx, int64(userInfo.ID), job)

	jobDTO := jobDTOFromDomain(job, agent, availableCustomAgents, organizationCustomInstructions)

	w.Header().Set("Content-Type", "application/json")
	err = json.NewEncoder(w).Encode(jobDTO)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to encode job response")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}
}

func (h *Handler) getProgress(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "agenthttp.Handler.getProgress")
	defer span.End()
	r = r.WithContext(ctx)
	logger := h.obsv.Logger.Named("agenthttp.Handler.getProgress")

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

	_, err = h.checkEnablement(ctx, job.AgentID, int64(userInfo.ID), job.RepoID)
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

	history := parseBoolQueryParam(r.URL, "history")
	namespaces := parseQueryParam(r.URL, "namespace")

	progressList, err := h.svc.GetProgress(ctx, job, namespaces, history)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to get progress")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}

	progressDTOs := make([]progressDTO, 0, len(progressList))
	for _, p := range progressList {
		dto := progressDTOFromDomain(p)
		progressDTOs = append(progressDTOs, dto)
	}

	w.Header().Set("Content-Type", "application/json")
	err = json.NewEncoder(w).Encode(progressDTOs)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to encode progress response")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}
}

func (h *Handler) createProgress(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "agenthttp.Handler.createProgress")
	defer span.End()
	r = r.WithContext(ctx)
	logger := h.obsv.Logger.Named("agenthttp.Handler.createProgress")

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

	_, err = h.checkEnablement(ctx, job.AgentID, int64(userInfo.ID), job.RepoID)
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

	var progressReq progressRequest
	err = json.NewDecoder(r.Body).Decode(&progressReq)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to decode progress request")
		http.Error(w, "invalid request body", http.StatusBadRequest)

		return
	}

	if len(progressReq.Items) == 0 {
		logger.WithContext(ctx).Info("no progress items provided")
		http.Error(w, "no progress items provided", http.StatusBadRequest)

		return
	}

	// validate that all items have required fields
	missingFields := []string{}
	for _, item := range progressReq.Items {
		if item.Namespace == "" {
			missingFields = append(missingFields, "namespace")
		}
		if item.Kind == "" {
			missingFields = append(missingFields, "kind")
		}
		if item.Content == "" {
			missingFields = append(missingFields, "content")
		}
		if len(missingFields) > 0 {
			break
		}
	}

	if len(missingFields) > 0 {
		logger.WithContext(ctx).Info("missing required fields in progress items", kvp.Strings("progress.missing_fields", missingFields))
		http.Error(w, "missing required fields in progress items: "+strings.Join(missingFields, ", "), http.StatusBadRequest)

		return
	}

	progressList := make([]*progress.Progress, 0, len(progressReq.Items))
	for _, item := range progressReq.Items {
		var content any
		if item.Content != "" {
			err = json.Unmarshal([]byte(item.Content), &content)
			if err != nil {
				logger.WithContext(ctx).WithError(err).Error("failed to unmarshal progress content")
				http.Error(w, "invalid progress content", http.StatusBadRequest)

				return
			}
		}

		progressList = append(progressList, job.NewProgress(item.Namespace, item.Kind, item.Version, content))
	}

	createdProgressList, err := h.svc.CreateProgress(ctx, job, progressList)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to create progress")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}

	progressDTOs := make([]progressDTO, 0, len(createdProgressList))
	for _, p := range createdProgressList {
		dto := progressDTOFromDomain(p)
		progressDTOs = append(progressDTOs, dto)
	}

	w.Header().Set("Content-Type", "application/json")

	// if the request body was a single object, return a single object in response
	if len(progressDTOs) == 1 {
		w.WriteHeader(http.StatusCreated)
		err = json.NewEncoder(w).Encode(progressDTOs[0])
		if err != nil {
			logger.WithContext(ctx).WithError(err).Error("failed to encode progress response")
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

			return
		}

		return
	}

	w.WriteHeader(http.StatusCreated)
	err = json.NewEncoder(w).Encode(progressDTOs)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to encode progress response")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}
}

// getAgent is largely the same as customagenthttp.getAgent but has been kept
// separate to allow inputs and outputs to diverge in the future if needed.
func (h *Handler) getAgent(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "agenthttp.Handler.getAgent")
	defer span.End()
	start := time.Now()
	r = r.WithContext(ctx)
	logger := h.obsv.Logger.Named("agenthttp.Handler.getAgent")
	baseTags := h.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"endpoint": "get_agent",
	})
	h.obsv.Increment(ctx, "agenthttp.handler.requests", baseTags)

	userInfo, err := h.authorize(ctx)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("authorization failed")
		h.recordError(ctx, baseTags, "authorization_failed")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)

		return
	}

	repoOwner, repoName, agentName := chi.URLParam(r, "repoOwner"), chi.URLParam(r, "repoName"), chi.URLParam(r, "agentName")
	if repoOwner == "" || repoName == "" || agentName == "" {
		http.Error(w, "repository owner, name, and agent name cannot be empty", http.StatusBadRequest)
		h.recordError(ctx, baseTags, "missing_params")
		return
	}

	// Version can be a SHA, tag, or branch name - if empty, uses the default branch
	version := r.URL.Query().Get("version")

	// Since we are able to return agent details from multiple repos and the runtime uses a repo scoped token,
	// we cannot rely on the token alone to authorize access to the agent details. We need to validate the job
	// and job nonce. The underlying service then takes care of whether the user in question actually has read access.
	//
	// TODO: Create new dedicated endpoint for doing this by job ID as we need to do this for permissions support anyway,
	// but keeping things here for backwards compatibility during initial rollout.
	//
	var customAgentErr error
	var customAgentDetails sweagentd.CustomAgent
	if h.ffs.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentCustomAgentValidateJobNonce, int64(userInfo.ID)) {
		customAgentDetails, customAgentErr = h.getAgentWithJobValidation(ctx, r, userInfo, agentName, version)
	} else {
		customAgentDetails, customAgentErr = h.getAgentLegacy(ctx, userInfo, repoOwner, repoName, agentName, version)
	}
	if customAgentErr != nil {
		if errors.Is(customAgentErr, errMissingJobID) {
			logger.WithContext(ctx).Info("job ID not provided in header")
			h.recordError(ctx, baseTags, "missing_job_id")
			http.Error(w, "X-GitHub-Job-ID header is required", http.StatusBadRequest)

			return
		}
		if errors.Is(customAgentErr, errAccessValidationFailed) {
			logger.WithContext(ctx).WithError(customAgentErr).Error("access validation failed")
			h.recordError(ctx, baseTags, "access_validation_failed")
			http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)

			return
		}
		if errors.Is(customAgentErr, errCustomAgentsNotEnabled) {
			logger.WithContext(ctx).Info("custom agents not enabled for repository")
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

			return
		}
		if errors.Is(customAgentErr, agent.ErrInvalidJobIDFormat) ||
			errors.Is(customAgentErr, agent.ErrInvalidJobIDOwner) ||
			errors.Is(customAgentErr, agent.ErrInvalidJobIDRepo) ||
			errors.Is(customAgentErr, agent.ErrJobNotFound) {
			h.handleDomainError(w, customAgentErr)

			return
		}
		if errors.Is(customAgentErr, customagent.ErrRepoNotFound) {
			logger.WithContext(ctx).Info("repository not found")
			h.recordError(ctx, baseTags, "repo_not_found")
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

			return
		}
		if errors.Is(customAgentErr, customagent.ErrRequestedAgentNotFound) {
			logger.WithContext(ctx).Info("agent not found for repository")
			h.recordError(ctx, baseTags, "agent_not_found")
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

			return
		}

		logger.WithContext(ctx).WithError(customAgentErr).Error("failed to get agent")
		h.recordError(ctx, baseTags, "get_agent_failed")
		h.obsv.LogAndReportError(ctx, customAgentErr, "agenthttp.Handler failed to get agent")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}
	h.obsv.DistributionMs(ctx, "agenthttp.Handler.request_duration", baseTags, time.Since(start))

	w.Header().Set("Content-Type", "application/json")

	err = json.NewEncoder(w).Encode(makeCustomAgentDTO(customAgentDetails, true))
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to encode response")
		h.recordError(ctx, baseTags, "encoding_failed")
		h.obsv.LogAndReportError(ctx, err, "agenthttp.Handler failed to encode getAgent response")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}

	h.obsv.Increment(ctx, "agenthttp.handler.requests.success", baseTags)
}

// TODO: Merge this with the main function once ff rolled out
func (h *Handler) getAgentWithJobValidation(ctx context.Context, r *http.Request, userInfo *requestctx.UserInfo, agentName, version string) (sweagentd.CustomAgent, error) {
	jobID := r.Header.Get("X-GitHub-Job-ID")
	if jobID == "" {
		return nil, errMissingJobID
	}
	job, err := h.svc.GetJob(ctx, jobID)
	if err != nil {
		return nil, err
	}
	err = h.validateNonce(r, job.NonceHash)
	if err != nil {
		return nil, errAccessValidationFailed
	}

	enabled := h.svc.CustomAgentsEnabledForJob(ctx, int64(userInfo.ID), job)
	if !enabled {
		return nil, errCustomAgentsNotEnabled
	}

	return h.svc.ResolveAgentForJob(ctx, userInfo, job, agentName, version)
}

// TODO: Remove this once ff rolled out
func (h *Handler) getAgentLegacy(ctx context.Context, userInfo *requestctx.UserInfo, repoOwner, repoName, agentName, version string) (sweagentd.CustomAgent, error) {
	enabled, err := h.svc.CustomAgentsEnabledForRepoByName(ctx, int64(userInfo.ID), repoOwner, repoName)
	if err != nil {
		return nil, err
	}
	if !enabled {
		return nil, errCustomAgentsNotEnabled
	}

	return h.svc.GetAgent(ctx, userInfo, repoOwner, repoName, agentName, version)
}

func (h *Handler) authorize(ctx context.Context) (*requestctx.UserInfo, error) {
	// extract user info from request context
	userInfo, ok := requestctx.User(ctx)
	if !ok || userInfo == nil {
		return userInfo, goerrors.New("user information not found in context")
	}

	// should only be called by agents using a GitHub App token
	_, err := h.appProvider.FindByID(int64(userInfo.TokenInfo.ApplicationID))
	if err != nil {
		h.obsv.Logger.WithContext(ctx).WithError(err).
			Error("failed to find app by ID during authorization", kvp.Uint64("application_id", userInfo.TokenInfo.ApplicationID))

		return userInfo, goerrors.New("invalid application ID in token")
	}

	return userInfo, nil
}

func (h *Handler) checkEnablement(ctx context.Context, agentID, userID, repoID int64) (bool, error) {
	// make sure the Agent is enabled for the user or repo
	enabled, _, err := h.twirp.IsAgentEnabled(ctx, agentID, userID, repoID)
	if err != nil {
		return false, goerrors.New("failed to check enablement")
	}
	if !enabled {
		return false, goerrors.New("copilot coder agent not enabled")
	}

	return true, nil
}

func (h *Handler) validateNonce(r *http.Request, nonceHash string) error {
	nonce := r.Header.Get(jobs.JobNonceHeader)
	if nonce == "" {
		return goerrors.New("missing nonce header")
	}
	if jobs.HashNonce(nonce) != nonceHash {
		return goerrors.New("invalid nonce header")
	}
	return nil
}

// recordError is ah helper function to consistnetly record error metrics
func (h *Handler) recordError(ctx context.Context, baseTags stats.Tags, errorType string) {
	tags := baseTags.Merge(stats.Tags{
		"success":    "false",
		"error_type": errorType,
	})
	h.obsv.Increment(ctx, "agenthttp.handler.errors", tags)
}

// parseQueryParam extracts all values for a given query parameter key from the URL.
// It handles comma-separated values and multiple occurrences of the same key
// and returns a slice of values.
//
// examples:
//   - ?key=value1 (single value)
//   - ?key=value1,value2 (comma-separated values)
//   - ?key=value1&key=value2 (multiple occurrences)
func parseQueryParam(u *url.URL, key string) []string {
	params := u.Query()[key]
	values := []string{}
	for _, param := range params {
		// Split comma-separated values
		for v := range strings.SplitSeq(param, ",") {
			trimmed := strings.TrimSpace(v)
			if trimmed != "" {
				values = append(values, trimmed)
			}
		}
	}
	return values
}

// parseBoolQueryParam extracts a boolean query parameter from the URL.
// It returns true if the parameter value is "true", "1", or "yes"
// (case-insensitive). Otherwise, it returns false.
func parseBoolQueryParam(u *url.URL, key string) bool {
	param := u.Query().Get(key)
	lowered := strings.ToLower(strings.TrimSpace(param))
	return lowered == "true" || lowered == "1" || lowered == "yes"
}
