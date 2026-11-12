package jobservice

import (
	"context"
	"strconv"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/experiments/exp"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/requestctx"
)

// GetExperimentAssignment retrieves an experiment assignment for the given job.
// Returns an Assignment that can be queried for feature variable values using
// typed getters (GetBool, GetInt, GetString, GetFloat64).
//
// If the SDK client is not configured, returns a noop assignment that always
// returns the caller-supplied default values.
func (s *Service) GetExperimentAssignment(ctx context.Context, job *jobs.Job, userDetails *copilotUsersTwirp.CopilotUserDetails) exp.Assignment {
	if s.expSDKClient == nil {
		return exp.NewNoopClient().GetAssignment(ctx, nil, nil, nil)
	}

	// Build user params for assignment
	userParams := buildJobParams(job)

	if userDetails != nil {
		orgIDs := make([]uint64, len(userDetails.CopilotOrganizations))
		for i, org := range userDetails.CopilotOrganizations {
			orgIDs[i] = org.Id
		}
		// ExP expects boolean-valued params to be encoded as 1/0
		userParams[string(exp.StaffKey)] = "0"
		if exp.IsActorStaff(orgIDs) {
			userParams[string(exp.StaffKey)] = "1"
		}

		plan, err := githubtwirp.CopilotPlanFromUser(userDetails)
		if err != nil {
			s.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("failed to derive Copilot plan for ExP assignment, omitting plan param")
		} else {
			userParams[string(exp.CopilotPlanKey)] = string(plan)
		}
	}

	// GetAssignment auto-applies scopes configured at client creation.
	return s.expSDKClient.GetAssignment(ctx, userParams, nil, nil)
}

// SetSDKAssignmentForJob evaluates the exp-go-sdk assignment for the given job,
// stores the serializable assignment context on both the assignment and job for
// Cosmos persistence, and stores the full AssignmentResult in the request
// context (via requestctx) for typed access (GetBool, GetString, etc.) within
// the current request.
func (s *Service) SetSDKAssignmentForJob(ctx context.Context, jobAssignment *jobs.Assignment, job *jobs.Job, userDetails *copilotUsersTwirp.CopilotUserDetails) {
	assignment := s.GetExperimentAssignment(ctx, job, userDetails)
	assignmentContext := assignment.GetAssignmentContext()
	jobAssignment.SDKAssignmentContext = assignmentContext
	job.SDKAssignmentContext = assignmentContext
	err := requestctx.SetExpSDKAssignment(ctx, assignment)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to store ExP SDK assignment in request context")
	}
}

// WithJobAssignment evaluates the job's experiment assignment and stores the
// full AssignmentResult in the request context (via requestctx). Use
// exp.AssignmentFromContext to retrieve it later in the request lifecycle.
//
// Prefer SetSDKAssignmentForJob during job creation (it also persists data to
// Cosmos). Use WithJobAssignment in later request lifecycles (e.g. job
// execution) where the job already exists and only context-based access is
// needed.
func (s *Service) WithJobAssignment(ctx context.Context, job *jobs.Job, userDetails *copilotUsersTwirp.CopilotUserDetails) {
	assignment := s.GetExperimentAssignment(ctx, job, userDetails)
	err := requestctx.SetExpSDKAssignment(ctx, assignment)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to store ExP SDK assignment in request context")
	}
}

// buildJobParams builds SDK assignment params from job metadata.
// Missing fields are intentionally skipped — the SDK returns default variants
// for experiments that require those fields as randomization units.
func buildJobParams(job *jobs.Job) map[string]string {
	params := make(map[string]string)

	params[string(exp.ExtensionNameKey)] = exp.ExtensionNameCodingAgent

	if job.RepoID > 0 {
		params[string(exp.RepositoryIDKey)] = strconv.FormatInt(job.RepoID, 10)
	}

	if job.ActorAnalyticsTrackingID != "" {
		params[string(exp.CopilotTrackingIDKey)] = job.ActorAnalyticsTrackingID
	}

	// Note: this assignment unit/audience filter does not exist yet in the new workspace
	if job.OwnerID > 0 {
		params[string(exp.OrganizationIDKey)] = strconv.FormatInt(job.OwnerID, 10)
	}

	return params
}
