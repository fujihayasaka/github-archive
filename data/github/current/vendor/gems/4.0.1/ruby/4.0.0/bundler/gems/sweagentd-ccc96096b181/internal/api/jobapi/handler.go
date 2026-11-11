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
	"strings"
	"time"

	authd "github.com/github/authnd/client"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	mark "github.com/github/go-mark"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/api"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
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
	NewJobBuilder(action jobs.AgentAction, repo *gg.Repository, baseCommit string) *jobservice.JobBuilder
	QueueJobForProcessing(ctx context.Context, job *jobs.Job) (*aqueductJobs.APIJob, error)
	QueueJobForExecution(ctx context.Context, job *jobs.Job) (*aqueductJobs.AgentJob, error)
	CheckRules(ctx context.Context, gh jobservice.BranchRuleChecker, agent sweagentd.AgenticApp, job *jobs.Job, repoOwner, repoName, branchName string) *jobservice.CheckRulesResult
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
	privilegedAppChecker github.PrivilegedAppCheckerClient
	appProvider          *agenticapp.Provider
	spokes               sweagentd.Spokes
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
	appProvider *agenticapp.Provider,
	spokes sweagentd.Spokes,
) *Handler {
	return &Handler{
		obsv:                 obsv,
		cf:                   cf,
		jobService:           jobService,
		jobsStore:            jobsStore,
		ffClient:             ffClient,
		jobExecutor:          jobExecutor,
		ghTwirp:              ghTwirp,
		privilegedAppChecker: &github.PrivilegedAppChecker{},
		appProvider:          appProvider,
		spokes:               spokes,
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
func (h *Handler) HandleNewJob(userInfo *requestctx.UserInfo, repo *gg.Repository) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, span := h.obsv.Tracer.Start(r.Context(), "jobapi.HandleNewJob")
		defer span.End()
		r = r.WithContext(ctx)

		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)
		logger.Info("handling new job request")

		var request NewJobAPIRequest
		err := json.NewDecoder(r.Body).Decode(&request)
		if err != nil {
			h.obsv.LogAndReportError(ctx, err, "decoding new job request", observability.WithRequest(r))
			_ = h.errorResponse(w, err.Error(), http.StatusBadRequest)
			return
		}
		repoName := chi.URLParam(r, "repo")
		repoOwner := chi.URLParam(r, "owner")

		gh, repo, err := h.getClientWithRepo(ctx, logger, userInfo, int64(request.AgentID), repoOwner, repoName, repo, w)
		if err != nil {
			if errors.Is(err, ErrAgentNotEnabled) {
				_ = h.errorResponse(w, http.StatusText(http.StatusForbidden), http.StatusForbidden)
				return
			}
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "invalid API request for repo")
			return
		}

		err = request.validate(repo)
		if err != nil {
			_ = h.errorResponse(w, err.Error(), http.StatusBadRequest)
			return
		}

		baseRef := repo.GetDefaultBranch()
		if request.Features != nil {
			if request.Features.PullRequest != nil && request.Features.PullRequest.BaseRef != "" {
				baseRef = request.Features.PullRequest.BaseRef
			} else if request.Features.Branch != nil && request.Features.Branch.BaseRef != "" {
				baseRef = request.Features.Branch.BaseRef
			}
		}

		// Validate that the requested baseRef actually exists
		baseRefExists, err := h.checkProvidedRefExists(ctx, uint64(repo.GetID()), baseRef)
		if err != nil {
			h.obsv.LogAndReportError(ctx, err, "checking base ref", observability.WithRequest(r))
			_ = h.errorResponse(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
			return
		}
		if !baseRefExists {
			logger.Warn("base ref does not exist")
			_ = h.errorResponse(w, fmt.Sprintf("base ref does not exist: %s", baseRef), http.StatusUnprocessableEntity)
			return
		}

		logger.Info("API request is valid")

		agent, err := h.getCustomAgent(ctx, int64(userInfo.ID), gh, repo, &request)
		if err != nil {
			if errors.Is(err, customagent.ErrRequestedAgentNotFound) {
				_ = h.errorResponse(w, "specified custom agent not found", http.StatusNotFound)
				return
			}
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to get custom agent")
			return
		}

		_, job, err := h.createJob(ctx, gh, &request, userInfo, agent, repo, false)
		if err != nil {
			var rulesErr *jobservice.RulesViolationError
			if errors.As(err, &rulesErr) {
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
func (h *Handler) HandleNewJobAsync(userInfo *requestctx.UserInfo, repo *gg.Repository) http.HandlerFunc {
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

		repoName := chi.URLParam(r, "repo")
		repoOwner := chi.URLParam(r, "owner")

		gh, repo, err := h.getClientWithRepo(ctx, logger, userInfo, int64(request.AgentID), repoOwner, repoName, repo, w)
		if err != nil {
			if errors.Is(err, ErrAgentNotEnabled) {
				_ = h.errorResponse(w, http.StatusText(http.StatusForbidden), http.StatusForbidden)
				return
			}
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "unable to initialize clientWithRepo")
			return
		}

		err = request.validate(repo)
		if err != nil {
			_ = h.errorResponse(w, err.Error(), http.StatusBadRequest)
			return
		}

		baseRef := repo.GetDefaultBranch()
		if request.Features != nil {
			if request.Features.PullRequest != nil && request.Features.PullRequest.BaseRef != "" {
				baseRef = request.Features.PullRequest.BaseRef
			} else if request.Features.Branch != nil && request.Features.Branch.BaseRef != "" {
				baseRef = request.Features.Branch.BaseRef
			}
		}

		// Validate that the requested baseRef actually exists
		baseRefExists, err := h.checkProvidedRefExists(ctx, uint64(repo.GetID()), baseRef)
		if err != nil {
			h.obsv.LogAndReportError(ctx, err, "checking base ref", observability.WithRequest(r))
			_ = h.errorResponse(w, "failed to check base ref existence", http.StatusInternalServerError)
			return
		}
		if !baseRefExists {
			logger.Warn("base ref does not exist")
			_ = h.errorResponse(w, fmt.Sprintf("base ref does not exist: %s", baseRef), http.StatusUnprocessableEntity)
			return
		}

		logger.Info("API request is valid")

		agent, err := h.getCustomAgent(ctx, int64(userInfo.ID), gh, repo, &request)
		if err != nil {
			if errors.Is(err, customagent.ErrRequestedAgentNotFound) {
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
func (h *Handler) HandleCancelJob(userInfo *requestctx.UserInfo, repo *gg.Repository) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, span := h.obsv.Tracer.Start(r.Context(), "jobapi.HandleCancelJob")
		defer span.End()
		r = r.WithContext(ctx)

		var err error
		var ownerID, repoID int64

		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)
		logger.Info("handling cancel job request")

		jobID := chi.URLParam(r, "job")
		sessionID := chi.URLParam(r, "session")

		repoName := chi.URLParam(r, "repo")
		repoOwner := chi.URLParam(r, "owner")
		repoInfo, err := h.ghTwirp.GetRepoByName(ctx, repoOwner, repoName)
		if err != nil {
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to get repo by name")
			return
		}
		ownerID = repoInfo.OwnerId
		repoID = repoInfo.Id

		var job *jobs.Job

		switch {
		case jobID != "":
			job, err = h.jobService.GetJobByID(ctx, ownerID, repoID, jobID)
		case sessionID != "":
			job, err = h.jobService.GetJobBySessionID(ctx, ownerID, repoID, sessionID)
		default:
			err = goerrors.New("API call missing required parameters: job or session ID")
		}

		if err != nil {
			if jobservice.IsJobNotFound(err) {
				_ = h.errorResponse(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
				return
			}
			_ = h.errorResponse(w, err.Error(), http.StatusBadRequest)
			return
		}

		gh, _, err := h.getClientWithRepo(ctx, logger, userInfo, job.AgentID, repoOwner, repoName, repo, w)
		if err != nil {
			if errors.Is(err, ErrAgentNotEnabled) {
				_ = h.errorResponse(w, http.StatusText(http.StatusForbidden), http.StatusForbidden)
				return
			}
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "unable to create new client with repo")
			return
		}

		// Actually do the cancellation
		err = h.jobExecutor.CancelJob(ctx, gh, job, repoOwner, repoName)
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
func (h *Handler) HandleGetJobByIDOrSessionID(userInfo *requestctx.UserInfo, repo *gg.Repository) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, span := h.obsv.Tracer.Start(r.Context(), "jobapi.HandleGetJob")
		defer span.End()
		r = r.WithContext(ctx)

		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)
		logger.Info("handling get job request")

		jobID := chi.URLParam(r, "job")
		sessionID := chi.URLParam(r, "session")

		var ownerID, repoID int64
		repoName := chi.URLParam(r, "repo")
		repoOwner := chi.URLParam(r, "owner")
		repoInfo, err := h.ghTwirp.GetRepoByName(ctx, repoOwner, repoName)
		if err != nil {
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to get repo by name")
			return
		}
		ownerID = repoInfo.OwnerId
		repoID = repoInfo.Id

		var job *jobs.Job

		switch {
		case jobID != "":
			job, err = h.jobService.GetJobByID(ctx, ownerID, repoID, jobID)
		case sessionID != "":
			job, err = h.jobService.GetJobBySessionID(ctx, ownerID, repoID, sessionID)
		default:
			err = goerrors.New("API call missing required parameters: job or session ID")
		}

		if err != nil {
			if jobservice.IsJobNotFound(err) {
				_ = h.errorResponse(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
				return
			}
			_ = h.errorResponse(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
			return
		}

		gh, _, err := h.getClientWithRepo(ctx, logger, userInfo, job.AgentID, repoOwner, repoName, repo, w)
		if err != nil {
			if errors.Is(err, ErrAgentNotEnabled) {
				_ = h.errorResponse(w, http.StatusText(http.StatusForbidden), http.StatusForbidden)
				return
			}
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "unable to create new client with repo")
			return
		}
		logger.Info("copilot coding agent enabled")

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
func (h *Handler) HandleListJobsForPullRequest(userInfo *requestctx.UserInfo, repo *gg.Repository) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, span := h.obsv.Tracer.Start(r.Context(), "jobapi.HandleListJobsForPullRequest")
		defer span.End()
		r = r.WithContext(ctx)

		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)
		logger.Info("handling list jobs for pull requests")

		prNumberStr := chi.URLParam(r, "prNumber")
		if prNumberStr == "" {
			_ = h.errorResponse(w, "API call missing required parameter: prNumber", http.StatusBadRequest)
			return
		}

		prNumber, err := strconv.Atoi(prNumberStr)
		if err != nil {
			_ = h.errorResponse(w, "invalid pull request number", http.StatusBadRequest)
			return
		}

		repoName := chi.URLParam(r, "repo")
		repoOwner := chi.URLParam(r, "owner")
		repoInfo, err := h.ghTwirp.GetRepoByName(ctx, repoOwner, repoName)
		if err != nil {
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to get repo by name")
			return
		}

		jobsList, err := h.jobsStore.ListJobsForPullRequestNumber(ctx, repoInfo.OwnerId, repoInfo.Id, prNumber)
		if err != nil {
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to get jobs for pull request")
			return
		}

		var jobResponses []*FullJobResponse
		if len(jobsList) > 0 {
			gh, _, err := h.getClientWithRepo(ctx, logger, userInfo, jobsList[0].AgentID, repoOwner, repoName, repo, w)
			if err != nil {
				if errors.Is(err, ErrAgentNotEnabled) {
					_ = h.errorResponse(w, http.StatusText(http.StatusForbidden), http.StatusForbidden)
					return
				}
				_ = h.errorResponseWithError(ctx, w, r, logger, err, "unable to create new client with repo")
				return
			}
			logger.Info("copilot coding agent enabled")

			for _, job := range jobsList {
				jobResponse := &FullJobResponse{}
				err = h.hydrateFullJobResponse(ctx, gh, job, jobResponse)
				if err != nil {
					_ = h.errorResponseWithError(ctx, w, r, logger, err, "failed to generate job details")
					return
				}
				jobResponses = append(jobResponses, jobResponse)
			}
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
func (h *Handler) HandleCheckEnablement(userInfo *requestctx.UserInfo, repo *gg.Repository) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, span := h.obsv.Tracer.Start(r.Context(), "jobapi.HandleCheckEnablement")
		defer span.End()
		r = r.WithContext(ctx)
		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)
		logger.Info("handling check enablement request")

		// TODO: Support any agenticapp branch prefix here by taking an agent ID
		agent := h.appProvider.CopilotApp()

		var err error
		repoName := chi.URLParam(r, "repo")
		repoOwner := chi.URLParam(r, "owner")
		gh, repo, err := h.getClientWithRepo(ctx, logger, userInfo, agent.AppID(), repoOwner, repoName, repo, w)
		if err != nil {
			if errors.Is(err, ErrAgentNotEnabled) {
				_ = h.errorResponse(w, http.StatusText(http.StatusForbidden), http.StatusForbidden)
				return
			}
			_ = h.errorResponseWithError(ctx, w, r, logger, err, "unable to create new client for repo")
			return
		}

		// Create a temp Job, just to check rules
		job := &jobs.Job{
			OwnerID:    repo.Owner.GetID(),
			RepoID:     repo.GetID(),
			RepoNodeID: repo.GetNodeID(),
			// We just need to check that any branch starting with the agent's prefix is allowed
			BranchName: agent.BranchPrefix() + "/not-a-real-branch",
		}
		rulesResult := h.jobService.CheckRules(ctx, gh, agent, job, repo.Owner.GetLogin(), repo.GetName(), job.BranchName)
		if len(rulesResult.Rules) > 0 {
			e := goerrors.Errorf("repository rules violation: %v", rulesResult.Rules)
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
	// Parse custom agent name and version from the request - may be in the form name@version
	name, version := customagent.ParseCustomAgentName(customAgent)

	params := jobservice.GetCustomAgentParams{
		UserID:   userID,
		GHClient: gh,
		GHRepo:   repo,
		Name:     name,
		Version:  version,
	}

	return h.jobService.GetCustomAgent(ctx, params)
}

type jobRoute func(userInfo *requestctx.UserInfo, repo *gg.Repository) http.HandlerFunc

func (h *Handler) middleware(route jobRoute) http.HandlerFunc {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		ctx, span := h.obsv.Tracer.Start(r.Context(), "jobapi.middleware")
		defer span.End()

		r = r.WithContext(ctx)
		_ = requestctx.AddRequestStartedAt(ctx, start)

		// Wrap the response writer to capture status code and error message
		rw := api.NewResponseWrapper(w)
		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)
		logger.Info("job api request started")

		// Emit a single log event at the end of the request
		defer func() {
			duration := time.Since(start)
			// Get logger with all context data that was added during request processing.
			logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)
			logKvps := []kvp.Field{
				kvp.Int64("duration_ms", duration.Milliseconds()),
				kvp.Int("http.status_code", rw.StatusCode),
			}
			if rw.ErrMsg != "" {
				logKvps = append(logKvps,
					kvp.String("exception.message", rw.ErrMsg),
				)
			}
			logger.WithFields(logKvps...).Info("job api request completed")
		}()

		repoName := chi.URLParam(r, "repo")
		repoOwner := chi.URLParam(r, "owner")

		if repoName == "" || repoOwner == "" {
			_ = h.errorResponse(rw, "API call requires repo_owner and repo_name", http.StatusBadRequest)
			return
		}

		user, ok := requestctx.User(ctx)
		if !ok {
			_ = h.errorResponse(rw, "user not authenticated", http.StatusUnauthorized)
			return
		}

		// User is authorized to call the API (note that whether the repo has the coding agent and user has quota is later)
		repo, err := h.authorizeUser(ctx, logger, repoOwner, repoName, user)
		if err != nil {
			// A "not found" marked error means that the user was explicitly blocked by a feature flag likely for abuse.
			// So, if this is the case, or we hit some sort of internal server error, report. Otherwise, just log the error.
			statusCode := joberrors.StatusCodeFromMarkedError(err)
			if statusCode == http.StatusNotFound || statusCode == http.StatusInternalServerError {
				h.obsv.LogAndReportError(ctx, err, "authorization failed for user or app", observability.WithRequest(r))
			} else {
				// Log 401/403 authorization failures for debugging (don't report to Sentry)
				logger.WithFields(
					kvp.String("exception.message", err.Error()),
					kvp.Int("http.status_code", statusCode),
					kvp.String("repo_owner", repoOwner),
					kvp.String("repo_name", repoName),
				).Info("authorization failed")
			}
			_ = h.errorResponse(rw, http.StatusText(statusCode), statusCode)
			return
		}

		route(user, repo)(rw, r)
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
func (h *Handler) authorizeUser(ctx context.Context, logger log.Logger, repoOwner, repoName string, user *requestctx.UserInfo) (*gg.Repository, error) {
	// See if the user or app has been blocked
	requestAppID := int64(user.TokenInfo.ApplicationID)
	if h.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentAPIDisallow, int64(user.ID)) ||
		h.ffClient.IsEnabledForGitHubApp(ctx, featureflags.CopilotSWEAgentAPIDisallow, requestAppID) ||
		h.ffClient.IsEnabledForOAuthApp(ctx, featureflags.CopilotSWEAgentAPIDisallow, requestAppID) {
		return nil, mark.With(mark.ErrNotFound, goerrors.New("user or app is not allowed to use the API")) // Use 404 to obfuscate the fact that the user or app is blocked
	}

	// Verify token has appropriate privs
	credentialType := authd.CredentialType(user.TokenInfo.Type)
	if !slices.Contains(allowedAPICredentialTypes, credentialType) {
		return nil, mark.With(mark.ErrUnauthorized, goerrors.New("API was passed unsupported token type"))
	}

	hasAccess, err := h.verifyTokenAccess(ctx, user, repoOwner, repoName, requiredAccessActionsDefault)
	if err != nil {
		return nil, goerrors.Errorf("API failed to verify token's access: %w", err)
	}
	if !hasAccess {
		return nil, mark.With(mark.ErrUnauthorized, goerrors.New("user does not have access to create PRs or push to the specified repository"))
	}
	logger.Info("user token has appropriate permissions to use API")

	// TODO: This check is in place due to the fact that a privileged app token could be used
	// for a user that does not directly have permissions to write to the repo. We should look
	// remove this check entirely by requiring all upstream callers to have a push and PR create rights.
	app := h.appProvider.CopilotApp()
	userTokenGH := h.cf.NewClientForUser(user.TokenInfo.Token, user.ID, app)
	permission, err := userTokenGH.GetUserPermissionsForRepository(ctx, repoOwner, repoName, user.Login)
	if err != nil {
		// Possible we will hit a rate limit, so get the response code so we use the right one for the response
		var githubErr *github.GitHubAPIError
		if errors.As(err, &githubErr) {
			if githubErr.Response != nil {
				return nil, joberrors.MarkExistingError(githubErr, githubErr.Response.Status)
			}
		}
		return nil, err
	}
	// If people can push, they can also create PRs. So we do not need to do a separate check for this bit.
	if !permission.Push {
		return nil, mark.With(mark.ErrUnauthorized, goerrors.New("user does not have write permissions to specified repository"))
	}
	logger.Info("user has push rights")
	if h.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWERepoFromParams, int64(user.ID)) {
		repo, err := userTokenGH.GetRepository(ctx, repoOwner, repoName)
		if err != nil {
			var githubErr *github.GitHubAPIError
			if errors.As(err, &githubErr) {
				if githubErr.Response != nil {
					return nil, joberrors.MarkExistingError(goerrors.Errorf("failed to get repository: %w", err), githubErr.Response.Status)
				}
			}
			return nil, goerrors.Errorf("failed to get repository: %w", err)
		}
		logger.Info("got repository for authorization")
		return repo, nil
	}
	return nil, nil
}

func (h *Handler) checkProvidedRefExists(ctx context.Context, repoID uint64, refName string) (bool, error) {
	// If they've specified a fully qualified ref, just use that. Otherwise assume it's a branch name.
	if !strings.HasPrefix(refName, "refs/") {
		refName = "refs/heads/" + refName
	}
	// Validate that the requested baseRef actually exists
	baseRefExists, err := h.spokes.CheckForExistingRefs(ctx, repoID, []string{refName})
	if err != nil {
		return false, err
	}
	return baseRefExists[0], nil
}

// ErrAgentNotEnabled is returned when the agent is not enabled for the user or repository.
var ErrAgentNotEnabled = goerrors.New("agent not enabled")

func (h *Handler) getClientWithRepo(ctx context.Context, logger log.Logger, user *requestctx.UserInfo, agentID int64, repoOwner, repoName string, repo *gg.Repository, w http.ResponseWriter) (github.ClientInterface, *gg.Repository, error) {
	if h.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWERepoFromParams, int64(user.ID)) {
		repoName = repo.GetName()
		repoOwner = repo.Owner.GetLogin()
	}

	app, err := h.appProvider.FindByID(agentID)
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to find app with agentID: %w", err)
	}

	gh, err := h.cf.NewClientFromRepoName(ctx, app, repoName, repoOwner, user.ID)
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to create client: %w", err)
	}
	// This will only be nil if the user isn't FF'd into the new flow, if they are FF'd the repo will already be passed in
	// so we won't have to do the redundant API call here
	if repo == nil {
		// TODO: Make this a twirp call to just get essential repo details - mainly IDs
		repo, err = gh.GetRepository(ctx, repoOwner, repoName)
		if err != nil {
			return nil, nil, goerrors.Errorf("failed to get repository: %w", err)
		}
		logger.Info("got repository for request")
	}

	// Now that we have the repository, verify agent is enabled for this specific repo
	enabled, _, err := h.ghTwirp.IsAgentEnabled(ctx, app.AppID(), int64(user.ID), repo.GetID())
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to check whether copilot is enabled: %w", err)
	}
	if !enabled {
		return nil, nil, ErrAgentNotEnabled
	}

	return gh, repo, nil
}
