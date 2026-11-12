// Package jobapi provides HTTP API handlers for managing SWE Agent jobs.
package jobapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"slices"
	"strconv"

	authd "github.com/github/authnd/client"
	"github.com/github/github-telemetry-go/log"
	mark "github.com/github/go-mark"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobexecutor"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/go-chi/chi/v5"
	gg "github.com/google/go-github/v75/github"
)

const apiVersion = "2025-06-19"

// jobService defines the methods from the jobservice package that are used by
// the event handler.
type jobService interface {
	GetJobByID(ctx context.Context, ownerID, repoID int64, jobID string) (*jobs.Job, error)
	GetJobBySessionID(ctx context.Context, ownerID, repoID int64, sessionID string) (*jobs.Job, error)
	GetCustomAgent(ctx context.Context, params jobservice.GetCustomAgentParams) (sweagentd.CustomAgent, error)
	NewJobBuilder(action jobs.AgentAction, baseCommit string) *jobservice.JobBuilder
	QueueJobForProcessing(ctx context.Context, job *jobs.Job) (*aqueductJobs.APIJob, error)
	QueueJobForExecution(ctx context.Context, job *jobs.Job) (*aqueductJobs.AgentJob, error)
	CheckRules(ctx context.Context, gh jobservice.BranchRuleChecker, job *jobs.Job, branchName string) *jobservice.CheckRulesResult
}

type jobstore interface {
	ListJobsForPullRequestNumber(ctx context.Context, owner, repo int64, prNumber int) ([]*jobs.Job, error)
}

// Handler handles job API requests
type Handler struct {
	obsv                 observability.Exporters
	cf                   github.ClientFactoryInterface
	jobService           jobService
	jobsStore            jobstore
	ffClient             featureflags.Client
	jobExecutor          jobexecutor.JobExecutor
	ghTwirp              githubtwirp.ClientInterface
	githubAppID          int64
	privilegedAppChecker github.PrivilegedAppCheckerClient
}

// NewHandler creates a new job API handler
func NewHandler(
	obsv observability.Exporters,
	cf github.ClientFactoryInterface,
	jobService jobService,
	jobsStore jobstore,
	ffClient featureflags.Client,
	jobExecutor jobexecutor.JobExecutor,
	ghTwirp githubtwirp.ClientInterface,
	githubAppID int64,
) *Handler {
	return &Handler{
		obsv:                 obsv,
		cf:                   cf,
		jobService:           jobService,
		jobsStore:            jobsStore,
		ffClient:             ffClient,
		jobExecutor:          jobExecutor,
		ghTwirp:              ghTwirp,
		githubAppID:          githubAppID,
		privilegedAppChecker: &github.PrivilegedAppChecker{},
	}
}

// RegisterRoutes registers the job API routes with the provided router
func (h *Handler) RegisterRoutes(r chi.Router) {
	// API for use by external systems
	// NOTE: No update / PUT endpoints should be implemented until we have a way to ensure the agent cannot use it.
	// These endpoints should not require the nonce used for the /agent/job endpoint so we need a scope or a way to
	// block the Copilot Coding agent app from using it w/o a passed in shared secret or encrypted token.
	getRoute := h.middleware(h.HandleGetJobByIDOrSessionID)

	for _, version := range []string{"/", "/v0"} {
		r.Route(version, func(r chi.Router) { // Endpoint for 2025-06-19 version of the API
			r.Get("/jobs/{owner}/{repo}/enabled", h.middleware(h.HandleCheckEnablement))
			r.Post("/jobs/{owner}/{repo}", h.middleware(h.HandleNewJob))
			r.Post("/jobs/{owner}/{repo}/{job}/cancel", h.middleware(h.HandleCancelJob))
			r.Post("/jobs/{owner}/{repo}/session/{session}/cancel", h.middleware(h.HandleCancelJob))
			r.Get("/jobs/{owner}/{repo}/{job}", getRoute)
			r.Get("/jobs/{owner}/{repo}/{job}/status", getRoute)
			r.Get("/jobs/{owner}/{repo}/session/{session}", getRoute)
			r.Get("/jobs/{owner}/{repo}/pulls/{prNumber}", h.middleware(h.HandleListJobsForPullRequest))
		})
	}
	r.Route("/v1", func(r chi.Router) {
		r.Get("/jobs/{owner}/{repo}/enabled", h.middleware(h.HandleCheckEnablement))
		r.Post("/jobs/{owner}/{repo}", h.middleware(h.HandleNewJobAsync))
		r.Post("/jobs/{owner}/{repo}/{job}/cancel", h.middleware(h.HandleCancelJob))
		r.Post("/jobs/{owner}/{repo}/session/{session}/cancel", h.middleware(h.HandleCancelJob))
		r.Get("/jobs/{owner}/{repo}/{job}", getRoute)
		r.Get("/jobs/{owner}/{repo}/{job}/status", getRoute)
		r.Get("/jobs/{owner}/{repo}/session/{session}", getRoute)
		r.Get("/jobs/{owner}/{repo}/pulls/{prNumber}", h.middleware(h.HandleListJobsForPullRequest))
	})
}

// HandleNewJob is the New job endpoint handler, non-versioned.
//
// NOTE: Since things like skills need to be able to tell the difference between auth failures and feature flag failures,
// response codes are as follows:
//
//	201 - Created - job was successfully created and queued for execution
//	400 - Bad Request - user did not provide valid info to do the work
//	401 - Unauthorized - user is not authorized to call this endpoint or does not have push rights to the repo
//	402 - Payment Required - user has no remaining quota for premium requests
//	403 - Forbidden - user is authorized to call this endpoint, but the user or repository does not have the Coding Agent enabled.
//	404 - Not Found - repository or other resource not found. Also used when an app or user is on the "disallow" list to obfuscate.
//	409 - Conflict - A PR already exists for the specified base and head refs
//	422 - Unprocessable Entity - repository is not initialized
//	422 - Unprocessable Entity - repository rules violation
//	500 - Internal Server Error - something went wrong on the server side
//
//nolint:nestif // complexity with if/else is acceptable with the temporary feature flag
func (h *Handler) HandleNewJob(userInfo *requestctx.UserInfo, gh github.ClientInterface, repo *gg.Repository) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, span := h.obsv.Tracer.Start(r.Context(), "jobapi.HandleNewJob")
		defer span.End()
		r = r.WithContext(ctx)

		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)
		logger.Info("handling new job request")

		var request NewJobAPIRequest
		err := json.NewDecoder(r.Body).Decode(&request)
		if err != nil {
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "")
			return
		}

		err = request.validate(repo)
		if err != nil {
			logger.WithError(err).Error("invalid API request")
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		baseRef := repo.GetDefaultBranch()
		if request.Features.PullRequest != nil && request.Features.PullRequest.BaseRef != "" {
			baseRef = request.Features.PullRequest.BaseRef
		} else if request.Features.Branch != nil && request.Features.Branch.BaseRef != "" {
			baseRef = request.Features.Branch.BaseRef
		}

		if baseRef != "" {
			exists, err := gh.CheckIfRefExists(ctx, repo.GetOwner().GetLogin(), repo.GetName(), baseRef)
			if err != nil {
				// Log the error but don't block the request - best effort check
				logger.WithError(err).Warn("failed to check if base ref exists, allowing request to proceed")
			} else if !exists {
				logger.Error("base ref does not exist")
				_ = h.errorResponse(w, "base ref does not exist", http.StatusUnprocessableEntity)
				return
			}
		}
		logger.Info("API request is valid")

		agent, err := h.getCustomAgent(ctx, int64(userInfo.ID), gh, repo, &request)
		if err != nil {
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to get custom agent")
			return
		}

		_, job, err := h.createJob(ctx, gh, &request, userInfo, agent, repo, false)
		if err != nil {
			var rulesErr *jobservice.RulesViolationError
			if errors.As(err, &rulesErr) {
				logger.WithError(err).Error("job creation failed due to branch protection rules")
				_ = h.errorResponse(w, err.Error(), http.StatusUnprocessableEntity)
				return
			}

			_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to draft job")
			return
		}

		_, err = h.jobService.QueueJobForExecution(ctx, job)
		if err != nil {
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to queue job")
			return
		}

		logger.Info("job queued")

		jobResponse := &BaseJobResponse{}
		err = h.hydrateBaseJobResponse(ctx, gh, job, jobResponse, true)
		if err != nil {
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to generate job details")
			return
		}
		logger.Info("job details gathered")

		json, err := json.Marshal(jobResponse)
		if err != nil {
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to marshal job details")
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Pragma", "no-cache")
		w.Header().Set("X-GitHub-Api-Version", apiVersion)
		w.WriteHeader(http.StatusCreated)
		_, err = w.Write(json)
		if err != nil {
			logger.WithError(err).Error("failed to write response")
		}

		logger.Info("new job api request successful")
	}
}

// HandleNewJobAsync is the New job endpoint handler, which asynchronously creates a new job after the request returns
//
// NOTE: Since things like skills need to be able to tell the difference between auth failures and feature flag failures,
// response codes are as follows:
//
//	201 - Created - job was successfully created and queued for execution
//	400 - Bad Request - user did not provide valid info to do the work
//	401 - Unauthorized - user is not authorized to call this endpoint or does not have push rights to the repo
//	402 - Payment Required - user has no remaining quota for premium requests
//	403 - Forbidden - user is authorized to call this endpoint, but the user or repository does not have the Coding Agent enabled.
//	404 - Not Found - repository or other resource not found. Also used when an app or user is on the "disallow" list to obfuscate.
//	422 - Unprocessable Entity - repository is not initialized
//	422 - Unprocessable Entity - repository rules violation
//	500 - Internal Server Error - something went wrong on the server side
//
//nolint:nestif // complexity with if/else is acceptable with the temporary feature flag
func (h *Handler) HandleNewJobAsync(userInfo *requestctx.UserInfo, gh github.ClientInterface, repo *gg.Repository) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, span := h.obsv.Tracer.Start(r.Context(), "jobapi.HandleNewJobAsync")
		defer span.End()
		r = r.WithContext(ctx)

		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)
		logger.Info("handling new job request")

		var request NewJobAPIRequest
		err := json.NewDecoder(r.Body).Decode(&request)
		if err != nil {
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "")
			return
		}

		err = request.validate(repo)
		if err != nil {
			logger.WithError(err).Error("invalid API request")
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		baseRef := repo.GetDefaultBranch()
		if request.Features.PullRequest != nil && request.Features.PullRequest.BaseRef != "" {
			baseRef = request.Features.PullRequest.BaseRef
		} else if request.Features.Branch != nil && request.Features.Branch.BaseRef != "" {
			baseRef = request.Features.Branch.BaseRef
		}

		if baseRef != "" {
			exists, err := gh.CheckIfRefExists(ctx, repo.GetOwner().GetLogin(), repo.GetName(), baseRef)
			if err != nil {
				// Log the error but don't block the request - best effort check
				logger.WithError(err).Warn("failed to check if base ref exists, allowing request to proceed")
			} else if !exists {
				logger.Error("base ref does not exist")
				_ = h.errorResponse(w, "base ref does not exist", http.StatusUnprocessableEntity)
				return
			}
		}
		logger.Info("API request is valid")

		agent, err := h.getCustomAgent(ctx, int64(userInfo.ID), gh, repo, &request)
		if err != nil {
			if errors.Is(err, customagent.ErrRequestedAgentNotFound) {
				logger.WithError(err).Error("invalid API request, custom agent not found")
				_ = h.errorResponse(w, "specified custom agent not found", http.StatusNotFound)
				return
			}
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to get custom agent")
			return
		}

		_, job, err := h.createJob(ctx, gh, &request, userInfo, agent, repo, true)
		if err != nil {
			var rulesErr *jobservice.RulesViolationError
			if errors.As(err, &rulesErr) {
				logger.WithError(err).Error("job creation failed due to branch protection rules")
				_ = h.errorResponse(w, err.Error(), http.StatusUnprocessableEntity)
				return
			}

			_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to draft job")
			return
		}

		_, err = h.jobService.QueueJobForProcessing(ctx, job)
		if err != nil {
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to queue job")
			return
		}
		logger.Info("job queued for processing")

		jobResponse := &BaseJobResponse{}
		err = h.hydrateBaseJobResponse(ctx, gh, job, jobResponse, false)
		if err != nil {
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to generate job details")
			return
		}
		logger.Info("job details gathered")

		json, err := json.Marshal(jobResponse)
		if err != nil {
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to marshal job details")
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Pragma", "no-cache")
		w.WriteHeader(http.StatusCreated)
		_, err = w.Write(json)
		if err != nil {
			logger.WithError(err).Error("failed writing http response")
			return
		}

		logger.Info("new job api request successful")
	}
}

// HandleCancelJob is the Cancel job endpoint handler - non-versioned.
//
// Response codes:
//
//	204 - No Content - job was successfully canceled
//	400 - Bad Request - user did not provide valid info to do the work
//	401 - Unauthorized - user is not authorized to call this endpoint or does not have push rights to the repo
//	404 - Not Found - repository or job not found. Also used when an app or user is on the "disallow" list to obfuscate.
//	500 - Internal Server Error - something went wrong on the server side
func (h *Handler) HandleCancelJob(userInfo *requestctx.UserInfo, gh github.ClientInterface, repo *gg.Repository) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, span := h.obsv.Tracer.Start(r.Context(), "jobapi.HandleCancelJob")
		defer span.End()
		r = r.WithContext(ctx)

		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)
		logger.Info("handling cancel job request")

		jobID := chi.URLParam(r, "job")
		sessionID := chi.URLParam(r, "session")

		var err error
		var job *jobs.Job

		switch {
		case jobID != "":
			job, err = h.jobService.GetJobByID(ctx, repo.Owner.GetID(), repo.GetID(), jobID)
		case sessionID != "":
			job, err = h.jobService.GetJobBySessionID(ctx, repo.Owner.GetID(), repo.GetID(), sessionID)
		default:
			err = errors.New("API call missing required parameters: job or session ID")
		}

		if err != nil {
			logger.Error(err.Error())
			if jobservice.IsJobNotFound(err) {
				http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
				return
			}
			http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
			return
		}

		// Actually do the cancellation
		err = h.jobExecutor.CancelJob(ctx, gh, job)
		if err != nil {
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "") // Upstream error already mentions its failed to cancel the job
			return
		}

		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Pragma", "no-cache")
		w.Header().Set("X-GitHub-Api-Version", apiVersion)
		w.WriteHeader(http.StatusNoContent)
		logger.Info("cancel job api request successful")
	}
}

// HandleGetJobByIDOrSessionID is the Get job endpoint - job ID or session ID is required - non-versioned.
//
// Response codes:
//
//	200 - OK - Job was successfully retrieved
//	400 - Bad Request - user did not provide valid info to do the work
//	401 - Unauthorized - user is not authorized to call this endpoint or does not have push rights to the repo
//	404 - Not Found - repository or job not found. Also used when an app or user is on the "disallow" list to obfuscate.
//	500 - Internal Server Error - something went wrong on the server side
func (h *Handler) HandleGetJobByIDOrSessionID(userInfo *requestctx.UserInfo, gh github.ClientInterface, repo *gg.Repository) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, span := h.obsv.Tracer.Start(r.Context(), "jobapi.HandleGetJob")
		defer span.End()
		r = r.WithContext(ctx)

		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)
		logger.Info("handling get job request")

		jobID := chi.URLParam(r, "job")
		sessionID := chi.URLParam(r, "session")

		var err error
		var job *jobs.Job

		switch {
		case jobID != "":
			job, err = h.jobService.GetJobByID(ctx, repo.Owner.GetID(), repo.GetID(), jobID)
		case sessionID != "":
			job, err = h.jobService.GetJobBySessionID(ctx, repo.Owner.GetID(), repo.GetID(), sessionID)
		default:
			err = errors.New("API call missing required parameters: job or session ID")
		}

		if err != nil {
			logger.Error(err.Error())
			if jobservice.IsJobNotFound(err) {
				http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
				return
			}
			http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
			return
		}

		jobResponse := &FullJobResponse{}
		err = h.hydrateFullJobResponse(ctx, gh, job, jobResponse)
		if err != nil {
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to generate job details")
			return
		}
		logger.Info("job details gathered")

		json, err := json.Marshal(jobResponse)
		if err != nil {
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to marshal job details")
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Pragma", "no-cache")
		w.Header().Set("X-GitHub-Api-Version", apiVersion)
		w.WriteHeader(http.StatusOK)
		_, err = w.Write(json)
		if err != nil {
			logger.WithError(err).Error("failed to write response")
		}

		logger.Info("get job api request successful")
	}
}

// HandleListJobsForPullRequest is the list jobs for pull request endpoint handler.
//
// Response codes:
//
//	200 - OK - Jobs were successfully retrieved
//	400 - Bad Request - user did not provide valid info to do the work
//	401 - Unauthorized - user is not authorized to call this endpoint or does not have push rights to the repo
//	404 - Not Found - repository not found. Also used when an app or user is on the "disallow" list to obfuscate.
//	500 - Internal Server Error - something went wrong on the server side
func (h *Handler) HandleListJobsForPullRequest(userInfo *requestctx.UserInfo, gh github.ClientInterface, repo *gg.Repository) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, span := h.obsv.Tracer.Start(r.Context(), "jobapi.HandleListJobsForPullRequest")
		defer span.End()
		r = r.WithContext(ctx)

		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)
		logger.Info("handling list jobs for pull requests")

		prNumberStr := chi.URLParam(r, "prNumber")
		if prNumberStr == "" {
			logger.Error("API call missing required parameter: prNumber")
			http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
			return
		}

		prNumber, err := strconv.Atoi(prNumberStr)
		if err != nil {
			logger.WithError(err).Error("invalid pull request number")
			http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
			return
		}

		jobsList, err := h.jobsStore.ListJobsForPullRequestNumber(ctx, repo.Owner.GetID(), repo.GetID(), prNumber)
		if err != nil {
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to get jobs for pull request")
			return
		}

		var jobResponses []*FullJobResponse
		for _, job := range jobsList {
			jobResponse := &FullJobResponse{}
			err = h.hydrateFullJobResponse(ctx, gh, job, jobResponse)
			if err != nil {
				_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to generate job details")
				return
			}
			jobResponses = append(jobResponses, jobResponse)
		}

		jsonData, err := json.Marshal(jobResponses)
		if err != nil {
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to marshal job details")
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Pragma", "no-cache")
		w.Header().Set("X-GitHub-Api-Version", apiVersion)
		w.WriteHeader(http.StatusOK)
		_, err = w.Write(jsonData)
		if err != nil {
			logger.WithError(err).Error("failed to write response")
		}

		logger.Info("list jobs for pull requests successful")
	}
}

// HandleCheckEnablement checks repository rules to ensure that an eventual job will be able to start successfully.
//
// Possible HTTP response codes:
//
//	200 - OK - CCA is enabled and repository rules pass.
//	401 - Unauthorized - Unauthenticated request (handled by middleware).
//	403 - Forbidden - CCA disabled.
//	422 - Unprocessable entity - Repository rules violation.
func (h *Handler) HandleCheckEnablement(userInfo *requestctx.UserInfo, gh github.ClientInterface, repo *gg.Repository) http.HandlerFunc {
	// `h.middleware` already checks if CCA is enabled for this user and repo, so we just need to check
	// other conditions here.
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, span := h.obsv.Tracer.Start(r.Context(), "jobapi.HandleCheckEnablement")
		defer span.End()
		r = r.WithContext(ctx)

		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)
		logger.Info("handling check enablement request")

		// Create a temp Job, just to check rules
		job := &jobs.Job{
			OwnerID:    repo.Owner.GetID(),
			RepoID:     repo.GetID(),
			RepoNodeID: repo.GetNodeID(),
			RepoName:   repo.GetName(),
			RepoOwner:  repo.Owner.GetLogin(),
			// We just need to check that any branch starting with `copilot/` is allowed
			BranchName: github.CopilotBranchPrefix + "/not-a-real-branch",
		}
		rulesResult := h.jobService.CheckRules(ctx, gh, job, job.BranchName)
		if len(rulesResult.Rules) > 0 {
			e := fmt.Errorf("repository rules violation: %v", rulesResult.Rules)
			logger.WithError(e).Error("repository rule violation")
			_ = h.errorResponse(w, e.Error(), http.StatusUnprocessableEntity)
			return
		}

		logger.Info("ready for jobs")

		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Pragma", "no-cache")
		w.Header().Set("X-GitHub-Api-Version", apiVersion)
		w.WriteHeader(http.StatusOK)
	}
}

func (h *Handler) getCustomAgent(
	ctx context.Context,
	userID int64,
	gh github.ClientInterface,
	repo *gg.Repository,
	request *NewJobAPIRequest,
) (sweagentd.CustomAgent, error) {
	customAgent := request.CustomAgent
	customAgentAttrs := request.CustomAgentAttributes

	var attrs *jobservice.GetCustomAgentParamsAttributes
	if customAgentAttrs != nil {
		attrs = &jobservice.GetCustomAgentParamsAttributes{
			DisplayName: customAgentAttrs.DisplayName,
			Description: customAgentAttrs.Description,
			Prompt:      customAgentAttrs.Prompt,
			Tools:       customAgentAttrs.Tools,
		}
	}

	params := jobservice.GetCustomAgentParams{
		UserID:     userID,
		GHClient:   gh,
		GHRepo:     repo,
		Name:       customAgent,
		Attributes: attrs,
	}

	return h.jobService.GetCustomAgent(ctx, params)
}

type jobRoute func(userInfo *requestctx.UserInfo, gh github.ClientInterface, repo *gg.Repository) http.HandlerFunc

func (h *Handler) middleware(route jobRoute) http.HandlerFunc {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx, span := h.obsv.Tracer.Start(r.Context(), "jobapi.middleware")
		defer span.End()

		r = r.WithContext(ctx)
		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)
		logger.Info("handling job api request in middleware")

		repoName := chi.URLParam(r, "repo")
		repoOwner := chi.URLParam(r, "owner")

		if repoName == "" || repoOwner == "" {
			logger.Error("API call requires repo_owner and repo_name")
			http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
			return
		}

		user, ok := requestctx.User(ctx)
		if !ok {
			http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
			return
		}
		logger.Info("user authenticated")

		// User is authorized to call the API (note that whether the repo has the coding agent and user has quota is later)
		err := h.authorizeUser(ctx, logger, repoOwner, repoName, user)
		if err != nil {
			// A "not found" marked error means that the user was explicitly blocked by a feature flag likely for abuse.
			// So, if this is the case, or we hit some sort of internal server error, report. Otherwise, just log the error.
			statusCode := joberrors.StatusCodeFromMarkedError(err)
			if statusCode == http.StatusNotFound || statusCode == http.StatusInternalServerError {
				h.obsv.LogAndReportError(ctx, err, "authorization failed for user or app")
			} else {
				logger.WithError(err).Error("authorization failed for user or app")
			}
			http.Error(w, http.StatusText(statusCode), statusCode)
			return
		}

		// Get an installation client for all GitHub API calls
		// TODO(josebalius): should we be using the user's token here to create a client
		// instead of an app installation token?
		gh, err := h.cf.NewClientFromRepoName(ctx, repoName, repoOwner)
		if err != nil {
			logger.WithError(err).Error("unable to create client")
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
			return
		}

		// TODO: Make this a twirp call to just get essential repo details - mainly IDs
		repo, err := gh.GetRepository(ctx, repoOwner, repoName)
		if err != nil {
			errResp := h.errorResponseWithError(ctx, w, r, logger, err, "invalid repository")
			if errResp != nil {
				logger.WithError(errResp).Error("failed to send error response")
			}
			return
		}
		logger.Info("got repository for request")

		// Next verify the repository actually has Copilot coding agent enabled
		enabled, err := githubtwirp.IsCopilotSweEnabled(ctx, h.ghTwirp, int64(user.ID), repo.GetID())
		if err != nil {
			errResp := h.errorResponseWithError(ctx, w, r, logger, err, "failed to check whether copilot is enabled")
			if errResp != nil {
				logger.WithError(errResp).Error("failed to send error response")
			}
			return
		}
		if !enabled {
			logger.Error("Copilot coding agent not enabled for user or repo")
			http.Error(w, http.StatusText(http.StatusForbidden), http.StatusForbidden)
			return
		}
		logger.Info("copilot coding agent enabled")

		route(user, gh, repo)(w, r)
	})
}

// Returns a response code based on authorization result and a related error if applicable.
// Does *NOT* check whether Copilot coding agent is enabled for the repo for the user has quota.
//
// If authorization fails, a error with a go-mark will be returned:
//
//	mark.ErrNotFound - User is on the disallow list, so we obfuscate the fact that they are blocked - should report and log
//	mark.ErrUnauthorized - user is not authorized to call this endpoint or does not have push rights to the repo
//	mark.ErrForbidden - user is authorized to call this endpoint, but the user or repository does not have the Coding Agent enabled.
func (h *Handler) authorizeUser(ctx context.Context, logger log.Logger, repoOwner, repoName string, user *requestctx.UserInfo) error {
	// See if the user or app has been blocked
	requestAppID := int64(user.TokenInfo.ApplicationID)
	if h.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentAPIDisallow, int64(user.ID)) ||
		h.ffClient.IsEnabledForGitHubApp(ctx, featureflags.CopilotSWEAgentAPIDisallow, requestAppID) ||
		h.ffClient.IsEnabledForOAuthApp(ctx, featureflags.CopilotSWEAgentAPIDisallow, requestAppID) {
		return mark.With(mark.ErrNotFound, errors.New("user or app is not allowed to use the API")) // Use 404 to obfuscate the fact that the user or app is blocked
	}

	// Verify token has appropriate privs
	credentialType := authd.CredentialType(user.TokenInfo.Type)
	if !slices.Contains(allowedAPICredentialTypes, credentialType) {
		return mark.With(mark.ErrUnauthorized, errors.New("API was passed unsupported token type"))
	}

	hasAccess, err := h.verifyTokenAccess(ctx, user, repoOwner, repoName, requiredAccessActionsDefault)
	if err != nil {
		return fmt.Errorf("API failed to verify token's access: %w", err)
	}
	if !hasAccess {
		return mark.With(mark.ErrUnauthorized, errors.New("user does not have access to create PRs or push to the specified repository"))
	}
	logger.Info("user token has appropriate permissions to use API")

	// Even if the token has the correct permissions we **still** want to verify that the user
	// actually has push rights regardless of what the token says out of an abundance of caution.
	// We will use the token passed in to call this endpoint since it only needs "metadata" and this
	// will also ensure per-user **rate limits** are also applied based on calls to GitHub itself.
	userTokenGH := h.cf.NewClientForUser(user.TokenInfo.Token, user.ID)
	permission, err := userTokenGH.GetUserPermissionsForRepository(ctx, repoOwner, repoName, user.Login)
	if err != nil {
		// Possible we will hit a rate limit, so get the response code so we use the right one for the response
		var githubErr *github.GitHubAPIError
		if errors.As(err, &githubErr) {
			if githubErr.Response != nil {
				return joberrors.MarkExistingError(githubErr, githubErr.Response.Status)
			}
		}
		return err
	}
	// If people can push, they can also create PRs. So we do not need to do a separate check for this bit.
	if !permission.Push {
		return mark.With(mark.ErrUnauthorized, errors.New("user does not have write permissions to specified repository"))
	}
	logger.Info("user has push rights")
	return nil
}
