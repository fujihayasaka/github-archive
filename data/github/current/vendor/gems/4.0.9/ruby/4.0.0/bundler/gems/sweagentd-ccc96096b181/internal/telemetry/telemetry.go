// Package telemetry provides functionality for publishing telemetry events
// related to jobs and commands in the sweagentd system.
package telemetry

import (
	"context"
	"strconv"
	"sync"
	"time"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/command"
	"github.com/github/sweagentd/internal/observability"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	copilotEntitiesv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/copilot/v0/entities"
	sweagentv0 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v0"
	sweagentEntitiesv0 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v0/entities"
)

// TelemetryPublisher manages the publication of telemetry events for jobs and commands.
//
//nolint:revive // TelemetryPublisher name is intentionally kept for API compatibility across multiple packages
type TelemetryPublisher struct {
	obsv             observability.Exporters
	twirp            githubtwirp.ClientInterface
	ffClient         featureflags.Client
	userDetailsCache map[int64]*copilotUsersTwirp.CopilotUserDetails
	cacheMu          sync.RWMutex
}

// NewTelemetryPublisher creates a new TelemetryPublisher instance.
func NewTelemetryPublisher(obsv observability.Exporters, twirp githubtwirp.ClientInterface, ffClient featureflags.Client) *TelemetryPublisher {
	return &TelemetryPublisher{
		obsv:             obsv,
		twirp:            twirp,
		ffClient:         ffClient,
		userDetailsCache: make(map[int64]*copilotUsersTwirp.CopilotUserDetails),
	}
}

// ShouldPublishRestrictedTelemetry determines if restricted telemetry should be published for a user.
func (tp *TelemetryPublisher) ShouldPublishRestrictedTelemetry(ctx context.Context, actorID int64) bool {
	// Check if user has the feature flag enabled (includes GitHub staff and Microsoft members via custom gates)
	if tp.ffClient.IsEnabledForUser(ctx, "coding_agent_force_restricted_telemetry", actorID) {
		return true
	}

	// Get cached user details
	userDetails := tp.getCopilotUserDetails(ctx, actorID)
	if userDetails == nil {
		// Conservative default: don't allow if we can't determine plan
		return false
	}

	return isRestrictedTelemetryAllowed(userDetails.CopilotPlan)
}

// PublishJobCompletedTelemetry publishes a job completed telemetry event with an optional terminal reason.
func (tp *TelemetryPublisher) PublishJobCompletedTelemetry(ctx context.Context, job *jobs.Job) {
	jobCompletedEvent := ToJobCompleted(job)

	if tp.shouldEmitCopilotAccessTypeStats(ctx, job.ActorID) {
		if accessType := tp.getCopilotAccessType(ctx, job.ActorID); accessType != nil {
			jobCompletedEvent.Job.CopilotAccessType = copilotEntitiesv0.CopilotAccessType(*accessType)
		}
	}
	err := tp.obsv.HydroPbl.Publish(jobCompletedEvent)
	if err != nil {
		tp.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to publish job_completed event")
	}
	if tp.ShouldPublishRestrictedTelemetry(ctx, job.ActorID) {
		restrictedJobCompletedEvent := ToRestrictedJobCompleted(job)
		err = tp.obsv.HydroPbl.Publish(restrictedJobCompletedEvent)
		if err != nil {
			tp.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to publish restricted job_completed event")
		}
	}
}

// PublishCommandCreatedTelemetry publishes a command created telemetry event.
func (tp *TelemetryPublisher) PublishCommandCreatedTelemetry(ctx context.Context, cmd *command.Command) {
	commandCreatedEvent := ToCommandCreated(cmd)

	if tp.shouldEmitCopilotAccessTypeStats(ctx, cmd.ActorID) {
		if accessType := tp.getCopilotAccessType(ctx, cmd.ActorID); accessType != nil {
			commandCreatedEvent.Command.CopilotAccessType = copilotEntitiesv0.CopilotAccessType(*accessType)
		}
	}
	err := tp.obsv.HydroPbl.Publish(commandCreatedEvent)
	if err != nil {
		tp.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to publish command_created event")
	}
	if tp.ShouldPublishRestrictedTelemetry(ctx, cmd.ActorID) {
		restrictedCommandCreatedEvent := ToRestrictedCommandCreated(cmd)
		err = tp.obsv.HydroPbl.Publish(restrictedCommandCreatedEvent)
		if err != nil {
			tp.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to publish restricted command_created event")
		}
	}
}

// PublishCommandUpdatedTelemetry publishes a command updated telemetry event.
func (tp *TelemetryPublisher) PublishCommandUpdatedTelemetry(ctx context.Context, cmd *command.Command) {
	tags := tp.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"type":   string(cmd.Type),
		"status": string(cmd.Status),
	})
	tp.obsv.Statter.Increment("jobs.commands.update", tags)
	tp.obsv.Statter.DistributionMs("jobs.commands.latency", tags, time.Since(time.Unix(cmd.Timestamp(), 0)))

	commandUpdatedEvent := ToCommandUpdated(cmd)

	if tp.shouldEmitCopilotAccessTypeStats(ctx, cmd.ActorID) {
		if accessType := tp.getCopilotAccessType(ctx, cmd.ActorID); accessType != nil {
			commandUpdatedEvent.Command.CopilotAccessType = copilotEntitiesv0.CopilotAccessType(*accessType)
		}
	}
	err := tp.obsv.HydroPbl.Publish(commandUpdatedEvent)
	if err != nil {
		tp.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to publish command_updated event")
	}
}

// PublishJobStartedTelemetry publishes a job started telemetry event.
func (tp *TelemetryPublisher) PublishJobStartedTelemetry(ctx context.Context, job *jobs.Job) {
	jobStartedEvent := ToJobStarted(job)

	if tp.shouldEmitCopilotAccessTypeStats(ctx, job.ActorID) {
		if accessType := tp.getCopilotAccessType(ctx, job.ActorID); accessType != nil {
			jobStartedEvent.Job.CopilotAccessType = copilotEntitiesv0.CopilotAccessType(*accessType)
		}
	}
	err := tp.obsv.HydroPbl.Publish(jobStartedEvent)
	if err != nil {
		tp.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to publish job_started event")
	}
}

// getCopilotUserDetails fetches and caches the full CopilotUserDetails for a given actor ID.
// Returns nil if the actor ID is 0 or if fetching fails.
func (tp *TelemetryPublisher) getCopilotUserDetails(ctx context.Context, actorID int64) *copilotUsersTwirp.CopilotUserDetails {
	if actorID == 0 {
		return nil
	}

	// Check cache first
	tp.cacheMu.RLock()
	userDetails, ok := tp.userDetailsCache[actorID]
	tp.cacheMu.RUnlock()
	if ok {
		return userDetails
	}

	// Fetch from API
	userDetails, err := tp.twirp.GetCopilotUserDetails(ctx, actorID)
	if err != nil {
		tp.obsv.LoggerWithTelemetry(ctx).WithError(err).Debug("failed to fetch copilot user details")
		return nil
	}

	// Cache the result
	tp.cacheMu.Lock()
	tp.userDetailsCache[actorID] = userDetails
	tp.cacheMu.Unlock()

	return userDetails
}

// getCopilotAccessType fetches the CopilotAccessType for a given actor ID.
// Returns nil if the actor ID is 0 or if fetching fails.
// Results are cached to avoid repeated API calls for the same actor.
func (tp *TelemetryPublisher) getCopilotAccessType(ctx context.Context, actorID int64) *copilotUsersTwirp.AccessType {
	userDetails := tp.getCopilotUserDetails(ctx, actorID)
	if userDetails == nil {
		return nil
	}

	accessType := userDetails.CopilotAccessType
	return &accessType
}

// shouldEmitCopilotAccessTypeStats returns true if CopilotAccessType should be emitted
func (tp *TelemetryPublisher) shouldEmitCopilotAccessTypeStats(ctx context.Context, actorID int64) bool {
	return tp.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentEmitCopilotAccessTypeStats, actorID)
}

// isRestrictedTelemetryAllowed returns true if restricted telemetry should be published
// for the given Copilot plan. Business and Enterprise plans are blocked.
func isRestrictedTelemetryAllowed(plan copilotUsersTwirp.CopilotPlan) bool {
	switch plan {
	case copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
		copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_PRO:
		return true
	case copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
		copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE:
		return false
	}
	// Conservative default: don't allow if we can't determine plan
	return false
}

// ToJobError converts a jobs.JobError to a hydro JobError entity.
// Returns nil if the input error is nil.
func ToJobError(jobError *jobs.JobError) *sweagentEntitiesv0.JobError {
	if jobError == nil {
		return nil
	}

	return &sweagentEntitiesv0.JobError{
		Code:    jobError.Summary(),
		Message: jobError.Message,
	}
}

// ToJob converts a Job to a hydro Job entity.
func ToJob(job *jobs.Job) *sweagentEntitiesv0.Job {
	return &sweagentEntitiesv0.Job{
		CreatedAt:                timestamppb.New(time.Unix(job.CreatedAt, 0)),
		JobId:                    job.ID,
		RepositoryId:             job.RepoID,
		OwnerId:                  job.OwnerID,
		ActorId:                  job.ActorID,
		PullRequestId:            job.PullRequestID,
		WorkflowRunId:            job.ComputeID,
		SessionId:                job.SessionID,
		ActorAnalyticsTrackingId: job.ActorAnalyticsTrackingID,
		AssignmentId:             job.AssignmentID,
		RefName:                  job.RefName(),
		AgentId:                  strconv.FormatInt(job.AgentID, 10),
		CustomAgent: &sweagentEntitiesv0.Job_CustomAgent{
			CustomAgentName: job.CustomAgent.Name,
			Version:         job.CustomAgent.Version,
			RepoOwnerId:     job.CustomAgent.RepoOwnerID,
			RepoId:          job.CustomAgent.RepoID,
			Metadata:        job.CustomAgent.Metadata,
		},
		Error: ToJobError(job.Error),
		Model: job.Model,
	}
}

// ToJobCompleted creates a JobCompleted event with an optional terminal reason.
func ToJobCompleted(job *jobs.Job) *sweagentv0.JobCompleted {
	event := &sweagentv0.JobCompleted{
		Job:           ToJob(job),
		CompletedAt:   timestamppb.New(time.Unix(job.CompletedAt, 0)),
		TerminalState: toTerminalStateProtobuf(job.Status),
		DurationSec:   job.CompletedAt - job.CreatedAt,
	}
	if job.Experiments != nil && job.Experiments.AssignmentContext != "" {
		event.ExpAssignmentContext = job.Experiments.AssignmentContext
	}

	// If the job has an error, use the summary (e.g. "capi:429") as the terminal reason
	if job.Error != nil {
		reason := job.Error.Summary()
		event.TerminalReason = &reason
	}

	return event
}

// ToRestrictedJobCompleted creates a RestrictedJobCompleted event for a completed job.
func ToRestrictedJobCompleted(job *jobs.Job) *sweagentv0.RestrictedJobCompleted {
	event := sweagentv0.RestrictedJobCompleted{
		Job:           ToJob(job),
		CompletedAt:   timestamppb.New(time.Unix(job.CompletedAt, 0)),
		TerminalState: toTerminalStateProtobuf(job.Status),
		DurationSec:   job.CompletedAt - job.CreatedAt,
	}
	if job.Experiments != nil && job.Experiments.AssignmentContext != "" {
		event.ExpAssignmentContext = job.Experiments.AssignmentContext
	}
	if job.Error != nil && job.Error.Message != "" {
		event.Result = job.Error.Message
	}
	return &event
}

func toTerminalStateProtobuf(terminalState jobs.JobStatus) sweagentEntitiesv0.TerminalState {
	switch terminalState {
	case jobs.JobStatusCompleted:
		return sweagentEntitiesv0.TerminalState_COMPLETED
	case jobs.JobStatusFailed:
		return sweagentEntitiesv0.TerminalState_FAILED
	case jobs.JobStatusCancelled:
		return sweagentEntitiesv0.TerminalState_CANCELLED
	case jobs.JobStatusTimedOut:
		return sweagentEntitiesv0.TerminalState_TIMED_OUT
	default:
		return sweagentEntitiesv0.TerminalState_UNKNOWN_STATE
	}
}

// ToJobStarted creates a JobStarted event for a job that has started.
func ToJobStarted(job *jobs.Job) *sweagentv0.JobStarted {
	hydroJob := ToJob(job)
	event := &sweagentv0.JobStarted{
		Job: hydroJob,
		Trigger: &sweagentEntitiesv0.JobTrigger{
			Type:         toTriggerTypeProtobuf(job.EventType),
			IdentifierId: resolveTriggerID(job),
			EventType:    wrapperspb.String(string(job.EventType)),
		},
		Action: toActionTypeProtobuf(job.Action),
	}
	if job.Experiments != nil && job.Experiments.AssignmentContext != "" {
		event.ExpAssignmentContext = job.Experiments.AssignmentContext
	}
	return event
}

func toActionTypeProtobuf(action jobs.AgentAction) sweagentEntitiesv0.ActionType {
	switch action {
	case jobs.AgentActionFix:
		return sweagentEntitiesv0.ActionType_FIX
	case jobs.AgentActionFixPRComment:
		return sweagentEntitiesv0.ActionType_FIX_PR_COMMENT
	default:
		return sweagentEntitiesv0.ActionType_UNKNOWN_ACTION
	}
}

func toTriggerTypeProtobuf(eventType jobs.EventType) sweagentEntitiesv0.JobTrigger_TriggerType {
	if eventType == "" {
		return sweagentEntitiesv0.JobTrigger_UNKNOWN_TRIGGER
	}

	switch eventType {
	case jobs.EventTypeIssueAssignment:
		return sweagentEntitiesv0.JobTrigger_ISSUE_ASSIGNED
	case jobs.EventTypePullRequestComment,
		jobs.EventTypePullRequestCommentNonCopilotPullRequest:
		return sweagentEntitiesv0.JobTrigger_PULL_REQUEST_COMMENT_CREATED
	case jobs.EventTypePullRequestReview,
		jobs.EventTypePullRequestReviewNonCopilotPullRequest:
		return sweagentEntitiesv0.JobTrigger_PULL_REQUEST_REVIEW_SUBMIT
	case jobs.EventTypeCodeScanningAlertsAssignment:
		return sweagentEntitiesv0.JobTrigger_CODE_SCANNING_ALERTS_ASSIGNED
	case jobs.EventTypeAPICallReceived:
		return sweagentEntitiesv0.JobTrigger_API_CALL_RECEIVED
	}
	// The Jobs API allows for custom event types, so if we encounter an
	// unknown event type we can assume it was an API call.
	return sweagentEntitiesv0.JobTrigger_API_CALL_RECEIVED
}

func resolveTriggerID(job *jobs.Job) int64 {
	switch job.EventType {
	case jobs.EventTypeIssueAssignment, jobs.EventTypePullRequestComment, jobs.EventTypePullRequestReview:
		return triggerIDFromEventIdentifiers(job.EventIdentifiers)
	case jobs.EventTypeCodeScanningAlertsAssignment:
		// Alerts is currently using the PR id as the trigger ID
		return job.PullRequestID
	}
	return triggerIDFromEventIdentifiers(job.EventIdentifiers)
}

func triggerIDFromEventIdentifiers(eventIdentifiers []string) int64 {
	if len(eventIdentifiers) == 0 || eventIdentifiers[0] == "" {
		return 0
	}

	triggerID, err := strconv.ParseInt(eventIdentifiers[0], 10, 64)
	if err != nil {
		return 0
	}

	return triggerID
}

// ToCommand converts a command to a Command entity for hydro events
func ToCommand(cmd *command.Command) *sweagentEntitiesv0.Command {
	return &sweagentEntitiesv0.Command{
		Id:           cmd.ID,
		JobId:        cmd.JobID,
		AssignmentId: cmd.AssignmentID,
		RepositoryId: cmd.RepoID,
		OwnerId:      cmd.OwnerID,
		SessionId:    cmd.SessionID,
		ExternalId:   &cmd.ExternalID,
		ActorId:      cmd.ActorID,
		Type:         string(cmd.Type),
		Status:       string(cmd.Status),
		CreatedAt:    timestamppb.New(time.Unix(cmd.CreatedAt, 0)),
	}
}

// ToCommandCreated converts job and command data to a CommandCreated hydro event
func ToCommandCreated(cmd *command.Command) *sweagentv0.CommandCreated {
	return &sweagentv0.CommandCreated{
		Command: ToCommand(cmd),
	}
}

// ToRestrictedCommandCreated converts job and command data to a RestrictedCommandCreated hydro event
func ToRestrictedCommandCreated(cmd *command.Command) *sweagentv0.RestrictedCommandCreated {
	return &sweagentv0.RestrictedCommandCreated{
		Command: ToCommand(cmd),
		Content: cmd.Content,
	}
}

// ToCommandUpdated converts command data to a CommandUpdated hydro event
func ToCommandUpdated(cmd *command.Command) *sweagentv0.CommandUpdated {
	return &sweagentv0.CommandUpdated{
		Command:   ToCommand(cmd),
		UpdatedAt: timestamppb.New(time.Now()),
	}
}
