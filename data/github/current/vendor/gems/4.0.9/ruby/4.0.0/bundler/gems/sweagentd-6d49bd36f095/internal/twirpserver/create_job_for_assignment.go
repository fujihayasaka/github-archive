package twirpserver

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	limits "github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/problemstatement"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/twitchtv/twirp"
)

// validateCreateJobForAssignmentRequest validates the required fields for CreateJobForAssignment.
func validateCreateJobForAssignmentRequest(req *jobs_pb.CreateJobForAssignmentRequest) error {
	if req.ActorId == 0 {
		return twirp.RequiredArgumentError("actor_id")
	}
	if req.OwnerId == 0 {
		return twirp.RequiredArgumentError("owner_id")
	}
	if req.RepoId == 0 {
		return twirp.RequiredArgumentError("repo_id")
	}
	// problem_statement is required for normal job creation, but a resume
	// triggered by `resume_session_id` reuses the previous job's problem
	// statement (inherited in jobservice) so the caller is not required to
	// re-supply it.
	if strings.TrimSpace(req.ProblemStatement) == "" && strings.TrimSpace(req.ResumeSessionId) == "" {
		return twirp.RequiredArgumentError("problem_statement")
	}
	if len(req.ProblemStatement) > problemstatement.MaxProblemStatementLength {
		return twirp.InvalidArgumentError("problem_statement", fmt.Sprintf("problem_statement exceeds maximum length of %d characters", problemstatement.MaxProblemStatementLength))
	}
	if strings.TrimSpace(req.AssignmentId) == "" {
		return twirp.RequiredArgumentError("assignment_id")
	}
	return nil
}

// CreateJobForAssignment handles the creation of a new job for a given assignment.
func (s *Server) CreateJobForAssignment(ctx context.Context, req *jobs_pb.CreateJobForAssignmentRequest) (*jobs_pb.CreateJobForAssignmentResponse, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "twirpserver.CreateJobForAssignment")
	defer span.End()

	// Validate the request fields
	err := validateCreateJobForAssignmentRequest(req)
	if err != nil {
		return nil, err
	}

	// Surface quota errors at task creation time.
	// Apps/integrations with the check exemption flag enabled are exempt.
	if !s.appProvider.IsAgentCheckExempt(ctx, s.ffClient, int64(req.AgentId), int64(req.RepoId)) {
		err = CheckQuota(ctx, s.ghTwirp, s.ffClient, s.obsv, int64(req.OwnerId), int64(req.RepoId), int64(req.ActorId), "job")
		if err != nil {
			return nil, err
		}
	}

	params := createJobForAssignmentParamsFromRequest(req, nil)

	// If HeadRef is provided, look up an existing PR for that branch and link
	// the assignment to it. This allows the builder to skip PR creation and
	// work on the existing PR's branch — mirroring the CreateJob behavior.
	if params.Features.PullRequest != nil && params.Features.PullRequest.HeadRef != "" {
		gh, err := s.ghf.NewClientFromRepo(ctx, s.appProvider.CopilotApp(), int64(req.RepoId), int64(req.OwnerId))
		if err != nil {
			return nil, goerrors.Errorf("failed to create gh client: %w", err)
		}
		repo, err := gh.GetRepositoryByID(ctx, int64(req.RepoId))
		if err != nil {
			return nil, goerrors.Errorf("failed to get repo by ID: %w", err)
		}
		params.Repo = repo

		baseRef := repo.GetDefaultBranch()
		if params.Features.PullRequest.BaseRef != "" {
			baseRef = params.Features.PullRequest.BaseRef
		}
		skipDefaultBranchCheck := s.shouldSkipDefaultBranchHeadRefCheck(ctx, int64(req.ActorId), int64(req.RepoId), int64(req.AgentId))

		existingPR, err := s.lookupExistingPRForHeadRef(ctx, gh, repo, &params.Features, req.AssignmentId, baseRef, skipDefaultBranchCheck)
		if err != nil {
			return nil, err
		}
		if existingPR != nil {
			params.PullRequestID = existingPR.GetID()
			params.PullRequestNumber = existingPR.GetNumber()
		}
	}

	result, err := s.jobService.CreateJobForAssignment(ctx, params)
	if err != nil {
		return nil, mapJobServiceError(err)
	}

	return &jobs_pb.CreateJobForAssignmentResponse{
		JobId:     result.Job.ID,
		SessionId: result.SessionID,
	}, nil
}

// createJobForAssignmentParamsFromRequest converts a proto request into jobservice params.
func createJobForAssignmentParamsFromRequest(req *jobs_pb.CreateJobForAssignmentRequest, repo *gg.Repository) *jobservice.CreateJobForAssignmentParams {
	features := reqFeaturesToJobFeatures(req.Features)

	return &jobservice.CreateJobForAssignmentParams{
		ActorID:               int64(req.ActorId),
		OwnerID:               int64(req.OwnerId),
		RepoID:                int64(req.RepoId),
		AssignmentID:          req.AssignmentId,
		AgentID:               int64(req.AgentId),
		Model:                 req.Model,
		ProblemStatement:      req.ProblemStatement,
		Features:              features,
		HasFeatures:           req.Features != nil,
		EventType:             req.EventType,
		EventURL:              req.EventUrl,
		EventIdentifiers:      req.EventIdentifiers,
		EventContent:          req.EventContent,
		CustomAgentName:       req.CustomAgent,
		CustomAgentAttributes: customAgentAttributesFromProto(req.CustomAgentAttributes),
		Repo:                  repo,
		ResumeSessionID:       strings.TrimSpace(req.ResumeSessionId),
		BranchRuleViolationHook: func(ctx context.Context, gh github.ClientInterface, actorLogin string, assignment *jobs.Assignment, result *jobservice.CheckRulesResult) error {
			rulesStr := strings.Join(result.Rules, "; ")
			errMsg := fmt.Sprintf("job cannot be created due to repository rules violation: %s", rulesStr)
			return twirp.FailedPrecondition.Error(errMsg)
		},
	}
}

// mapJobServiceError converts jobservice-level errors to twirp errors where appropriate.
func mapJobServiceError(err error) error {
	if errors.Is(err, jobservice.ErrAgentNotEnabled) {
		return twirp.Aborted.Error("user or repo does not have CCA enabled")
	}
	if errors.Is(err, jobservice.ErrBotActorNotAllowed) {
		return twirp.InvalidArgumentError("actor_id", "bot actors are not allowed to create jobs")
	}
	if errors.Is(err, jobservice.ErrAgentNotFound) {
		return twirp.NotFoundError("specified custom agent not found")
	}
	if errors.Is(err, jobservice.ErrAssignmentNotFound) {
		return twirp.NotFoundError("assignment not found")
	}
	if errors.Is(err, jobservice.ErrNoModelAvailable) {
		return twirp.FailedPrecondition.Error("no models available")
	}
	if errors.Is(err, jobservice.ErrModelNotFound) {
		return twirp.InvalidArgument.Error("model not found or not enabled for user")
	}
	if errors.Is(err, jobservice.ErrModelVendorMismatch) {
		return twirp.InvalidArgument.Error("model is not compatible with this agent's vendor")
	}
	if errors.Is(err, jobservice.ErrBaseRefNotFound) {
		return twirp.FailedPrecondition.Error("base ref not found")
	}
	if errors.Is(err, jobservice.ErrResumeNoProblemStatement) {
		return twirp.FailedPrecondition.Error("resume job has no problem statement to inherit")
	}
	if errors.Is(err, jobservice.ErrJobAlreadyInProgress) {
		return twirp.Aborted.Error(jobservice.ErrJobAlreadyInProgress.Error())
	}
	if limits.IsQueuedJobsExceededError(err) {
		return twirp.ResourceExhausted.Error("actor has exceeded the maximum number of queued jobs")
	}
	var capiErr *joberrors.CAPIError
	if errors.As(err, &capiErr) && capiErr.StatusCode() == http.StatusTooManyRequests {
		return twirp.ResourceExhausted.Error("rate limited by upstream service, please retry later")
	}
	var twirpErr twirp.Error
	if errors.As(err, &twirpErr) {
		return twirpErr
	}
	return err
}
