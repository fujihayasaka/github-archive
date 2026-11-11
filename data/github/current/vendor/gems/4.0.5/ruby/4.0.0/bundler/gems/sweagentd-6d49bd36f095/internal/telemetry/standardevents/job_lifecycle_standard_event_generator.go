package standardevents

import (
	"context"
	"strconv"
	"time"

	standardpb "github.com/github/hydro-schemas-go/hydro/schemas/analytics_pipelines/v0"
	"github.com/github/sweagentd/internal/experiments/exp"
	"github.com/github/sweagentd/internal/jobs"
)

// JobLifecycleStandardEventGenerator generates StandardEvent messages for job
// lifecycle events (started, completed). Each method takes a Job and returns
// a StandardEvent ready for Hydro publishing.
type JobLifecycleStandardEventGenerator struct{}

// GenerateJobStartedStandardEvent creates a StandardEvent for a job_started event.
func (g *JobLifecycleStandardEventGenerator) GenerateJobStartedStandardEvent(ctx context.Context, job *jobs.Job) *standardpb.StandardEvent {
	sdkContext := assignmentContextFromContext(ctx, job)
	jobContext := assignmentContextFromJob(job)

	event := newBaseEvent(
		EventTypeJobStarted,
		time.Unix(job.CreatedAt, 0),
		job.ActorAnalyticsTrackingID,
		EntityTypeCopilotTrackingID,
		sdkContext,
	)

	setSessionID(event, job.ID)
	setSecondaryEntity(event, formatPullRequestID(job.PullRequestID), EntityTypePullRequestID, jobContext)
	setJobMetadata(event, job)

	return event
}

// GenerateJobCompletedStandardEvent creates a StandardEvent for a job_completed event.
func (g *JobLifecycleStandardEventGenerator) GenerateJobCompletedStandardEvent(ctx context.Context, job *jobs.Job) *standardpb.StandardEvent {
	sdkContext := assignmentContextFromContext(ctx, job)
	jobContext := assignmentContextFromJob(job)

	event := newBaseEvent(
		EventTypeJobCompleted,
		time.Unix(job.CompletedAt, 0),
		job.ActorAnalyticsTrackingID,
		EntityTypeCopilotTrackingID,
		sdkContext,
	)

	setSessionID(event, job.ID)
	setSecondaryEntity(event, formatPullRequestID(job.PullRequestID), EntityTypePullRequestID, jobContext)
	setJobMetadata(event, job)

	durationSec := job.CompletedAt - job.CreatedAt
	event.Measurements["duration_sec"] = float64(durationSec)

	event.Metadata["terminal_state"] = string(job.Status)
	if job.Error != nil {
		event.Metadata["terminal_reason"] = job.Error.Summary()
	}

	return event
}

// assignmentContextFromContext returns the SDK experiment assignment context,
// preferring the value cached on the job (set at build time) and falling back
// to the context-based lookup.
func assignmentContextFromContext(ctx context.Context, job *jobs.Job) string {
	if job.SDKAssignmentContext != "" {
		return job.SDKAssignmentContext
	}
	return exp.AssignmentFromContext(ctx).GetAssignmentContext()
}

// assignmentContextFromJob extracts the experiment assignment context from job, if available.
// TODO: Migrate to SDK (assignmentContextFromContext) once all experiments use exp-go-sdk.
// This reads from the legacy Twirp-based experiment flow.
func assignmentContextFromJob(job *jobs.Job) string {
	if job.Experiments != nil {
		return job.Experiments.AssignmentContext
	}
	return ""
}

// formatPullRequestID converts a pull request ID to a string, returning empty string for zero values.
func formatPullRequestID(prID int64) string {
	if prID == 0 {
		return ""
	}
	return strconv.FormatInt(prID, 10)
}

// setJobMetadata populates common metadata and conditions from a Job onto a StandardEvent.
func setJobMetadata(event *standardpb.StandardEvent, job *jobs.Job) {
	event.Conditions["is_auto_mode"] = job.IsAutoMode
	event.Conditions["is_automation"] = job.IsTriggered
	event.Conditions["is_custom_agent"] = job.CustomAgent.Name != ""
	event.Conditions["custom_setup_steps_used"] = job.CustomSetupStepsUsed

	event.Metadata["model"] = job.Model
	event.Metadata["event_type"] = string(job.EventType)
	event.Metadata["action"] = string(job.Action)
	event.Metadata["repository_id"] = strconv.FormatInt(job.RepoID, 10)
	event.Metadata["owner_id"] = strconv.FormatInt(job.OwnerID, 10)
	event.Metadata["actor_id"] = strconv.FormatInt(job.ActorID, 10)
	event.Metadata["assignment_id"] = job.AssignmentID
	event.Metadata["session_id"] = job.SessionID
	event.Metadata["compute_id"] = job.ComputeID
	event.Metadata["compute_type"] = job.ComputeType()
	if workflowRunID, ok := job.WorkflowRunID(); ok {
		event.Metadata["workflow_run_id"] = strconv.FormatInt(workflowRunID, 10)
	}
	event.Metadata["agent_id"] = strconv.FormatInt(job.AgentID, 10)
	if refName := job.RefName(); refName != "" {
		event.Metadata["ref_name"] = refName
	}
	if job.IssueNumber != 0 {
		event.Metadata["issue_number"] = strconv.Itoa(job.IssueNumber)
	}
	if job.CustomAgent.Name != "" {
		event.Metadata["custom_agent_name"] = job.CustomAgent.Name
	}
}
