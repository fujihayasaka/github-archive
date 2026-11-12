// Package telemetry provides functionality for publishing telemetry events
// related to jobs and commands in the sweagentd system.
package telemetry

import (
	"context"
	"strconv"
	"sync"
	"time"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/command"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/telemetry/standardevents"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	standardpb "github.com/github/hydro-schemas-go/hydro/schemas/analytics_pipelines/v0"
	copilotEntitiesv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/copilot/v0/entities"
	copilotEntitiesv2 "github.com/github/hydro-schemas-go/hydro/schemas/github/copilot/v2/entities"
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

	jobLifecycleGen standardevents.JobLifecycleStandardEventGenerator
	modelCallGen    standardevents.ModelCallStandardEventGenerator
	pullRequestGen  standardevents.PullRequestStandardEventGenerator
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
// See Copilot telemetry settings and https://github.com/github/copilot-metrics/wiki/IDE-Telemetry#where-is-restricted-telemetry-set for details.
func (tp *TelemetryPublisher) ShouldPublishRestrictedTelemetry(ctx context.Context, actorID int64) bool {
	// Check if user has the feature flag enabled (includes GitHub staff and Microsoft members via custom gates)
	if tp.ffClient.IsEnabledForUser(ctx, featureflags.CodingAgentForceRestrictedTelemetry, actorID) {
		return true
	}

	// Get cached user details
	userDetails := tp.getCopilotUserDetails(ctx, actorID)
	if userDetails == nil {
		// Conservative default: don't allow if we can't determine telemetry configuration
		return false
	}

	// Use the telemetry_configuration from the Copilot monolith.
	telemetryCfg := userDetails.TelemetryConfiguration
	tp.obsv.LoggerWithTelemetry(ctx).Debug("checking telemetry_configuration for restricted telemetry",
		kvp.String("telemetry_configuration", telemetryCfg.String()))
	// Only emit restricted telemetry when explicitly enabled; treat INVALID and DISABLED as false.
	return telemetryCfg == copilotUsersTwirp.Telemetry_TELEMETRY_ENABLED
}

// PublishJobCompletedTelemetry publishes a job completed telemetry event with an optional terminal reason.
func (tp *TelemetryPublisher) PublishJobCompletedTelemetry(ctx context.Context, job *jobs.Job) {
	jobCompletedEvent := ToJobCompleted(job)
	tp.enrichJobWithCopilotMetadata(ctx, jobCompletedEvent.Job, job.ActorID)

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

	tp.publishJobCompletedStandardEvent(ctx, job)
}

// PublishCommandCreatedTelemetry publishes a command created telemetry event.
func (tp *TelemetryPublisher) PublishCommandCreatedTelemetry(ctx context.Context, cmd *command.Command) {
	commandCreatedEvent := ToCommandCreated(cmd)
	tp.enrichCommandWithCopilotMetadata(ctx, commandCreatedEvent.Command, cmd.ActorID)

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
	tp.enrichCommandWithCopilotMetadata(ctx, commandUpdatedEvent.Command, cmd.ActorID)

	err := tp.obsv.HydroPbl.Publish(commandUpdatedEvent)
	if err != nil {
		tp.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to publish command_updated event")
	}
}

// PublishJobStartedTelemetry publishes a job started telemetry event.
func (tp *TelemetryPublisher) PublishJobStartedTelemetry(ctx context.Context, job *jobs.Job) {
	jobStartedEvent := ToJobStarted(job)
	tp.enrichJobWithCopilotMetadata(ctx, jobStartedEvent.Job, job.ActorID)

	err := tp.obsv.HydroPbl.Publish(jobStartedEvent)
	if err != nil {
		tp.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to publish job_started event")
	}

	tp.publishJobStartedStandardEvent(ctx, job)
}

// PublishModelCallStandardEvent generates and publishes a standard event for a model call.
func (tp *TelemetryPublisher) PublishModelCallStandardEvent(ctx context.Context, job *jobs.Job, params standardevents.ModelCallParams) {
	if !tp.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CodingAgentLearningMachinePipelineEvents, job) {
		return
	}

	event := tp.modelCallGen.GenerateModelCallStandardEvent(ctx, job, params)
	tp.enrichStandardEventWithCopilotMetadata(ctx, event, job.ActorID)
	err := tp.obsv.HydroPbl.Publish(event)
	if err != nil {
		tp.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to publish model_call standard event")
	}
}

// PublishPullRequestStateChangedStandardEvent generates and publishes a standard event for a PR state change.
func (tp *TelemetryPublisher) PublishPullRequestStateChangedStandardEvent(ctx context.Context, job *jobs.Job, prState string, occurredAt time.Time) {
	if !tp.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CodingAgentLearningMachinePipelineEvents, job) {
		return
	}

	event := tp.pullRequestGen.GeneratePullRequestStateChangedStandardEvent(ctx, job, prState, occurredAt)
	tp.enrichStandardEventWithCopilotMetadata(ctx, event, job.ActorID)
	err := tp.obsv.HydroPbl.Publish(event)
	if err != nil {
		tp.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to publish pull_request_state_changed standard event")
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

// getCopilotAccessType fetches the CopilotAccessType for a given actor ID.
// Returns nil if the actor ID is 0 or if fetching fails.
// Results are cached to avoid repeated API calls for the same actor.
func (tp *TelemetryPublisher) getCopilotPlan(ctx context.Context, actorID int64) *copilotUsersTwirp.CopilotPlan {
	userDetails := tp.getCopilotUserDetails(ctx, actorID)
	if userDetails == nil {
		return nil
	}

	copilotPlan := userDetails.CopilotPlan
	return &copilotPlan
}

// shouldEmitCopilotAccessTypeStats returns true if CopilotAccessType should be emitted
func (tp *TelemetryPublisher) shouldEmitCopilotAccessTypeStats(ctx context.Context, actorID int64) bool {
	return tp.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentEmitCopilotAccessTypeStats, actorID)
}

// shouldEmitCopilotPlanStats returns true if CopilotPlan should be emitted
func (tp *TelemetryPublisher) shouldEmitCopilotPlanStats(ctx context.Context, actorID int64) bool {
	return tp.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentEmitCopilotPlanStats, actorID)
}

// enrichJobWithCopilotMetadata enriches a Job entity with CopilotAccessType and CopilotPlan
// based on the provided actor ID and feature flag settings.
func (tp *TelemetryPublisher) enrichJobWithCopilotMetadata(ctx context.Context, job *sweagentEntitiesv0.Job, actorID int64) {
	if tp.shouldEmitCopilotAccessTypeStats(ctx, actorID) {
		if accessType := tp.getCopilotAccessType(ctx, actorID); accessType != nil {
			job.CopilotAccessType = copilotEntitiesv0.CopilotAccessType(*accessType)
		}
	}
	if tp.shouldEmitCopilotPlanStats(ctx, actorID) {
		if plan := tp.getCopilotPlan(ctx, actorID); plan != nil {
			job.CopilotPlan = toHydroCopilotPlan(*plan)
		}
	}
}

// enrichCommandWithCopilotMetadata enriches a Command entity with CopilotAccessType and CopilotPlan
// based on the provided actor ID and feature flag settings.
func (tp *TelemetryPublisher) enrichCommandWithCopilotMetadata(ctx context.Context, cmd *sweagentEntitiesv0.Command, actorID int64) {
	if tp.shouldEmitCopilotAccessTypeStats(ctx, actorID) {
		if accessType := tp.getCopilotAccessType(ctx, actorID); accessType != nil {
			cmd.CopilotAccessType = copilotEntitiesv0.CopilotAccessType(*accessType)
		}
	}
	if tp.shouldEmitCopilotPlanStats(ctx, actorID) {
		if plan := tp.getCopilotPlan(ctx, actorID); plan != nil {
			cmd.CopilotPlan = toHydroCopilotPlan(*plan)
		}
	}
}

// toHydroCopilotPlan maps a copilot-twirp CopilotPlan enum to the hydro-schemas CopilotPlan enum.
// These two enums have different integer values for the same plans, so a direct cast is incorrect.
func toHydroCopilotPlan(plan copilotUsersTwirp.CopilotPlan) copilotEntitiesv2.CopilotPlan {
	switch plan {
	case copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL:
		return copilotEntitiesv2.CopilotPlan_INDIVIDUAL
	case copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_PRO:
		return copilotEntitiesv2.CopilotPlan_INDIVIDUAL_PRO_PLUS
	case copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS:
		return copilotEntitiesv2.CopilotPlan_BUSINESS
	case copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE:
		return copilotEntitiesv2.CopilotPlan_ENTERPRISE
	case copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INVALID:
		return copilotEntitiesv2.CopilotPlan_INVALID
	default:
		return copilotEntitiesv2.CopilotPlan_UNKNOWN
	}
}

// publishJobStartedStandardEvent generates and publishes a standard event for job started.
func (tp *TelemetryPublisher) publishJobStartedStandardEvent(ctx context.Context, job *jobs.Job) {
	if !tp.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CodingAgentLearningMachinePipelineEvents, job) {
		return
	}

	event := tp.jobLifecycleGen.GenerateJobStartedStandardEvent(ctx, job)
	tp.enrichStandardEventWithCopilotMetadata(ctx, event, job.ActorID)
	err := tp.obsv.HydroPbl.Publish(event)
	if err != nil {
		tp.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to publish job_started standard event")
	}
}

// publishJobCompletedStandardEvent generates and publishes a standard event for job completed.
func (tp *TelemetryPublisher) publishJobCompletedStandardEvent(ctx context.Context, job *jobs.Job) {
	if !tp.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CodingAgentLearningMachinePipelineEvents, job) {
		return
	}

	event := tp.jobLifecycleGen.GenerateJobCompletedStandardEvent(ctx, job)
	tp.enrichStandardEventWithCopilotMetadata(ctx, event, job.ActorID)
	err := tp.obsv.HydroPbl.Publish(event)
	if err != nil {
		tp.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to publish job_completed standard event")
	}
}

func (tp *TelemetryPublisher) enrichStandardEventWithCopilotMetadata(ctx context.Context, event *standardpb.StandardEvent, actorID int64) {
	if accessType := tp.getCopilotAccessType(ctx, actorID); accessType != nil {
		event.Metadata["copilot_access_type"] = accessType.String()
	}
	if plan := tp.getCopilotPlan(ctx, actorID); plan != nil {
		event.Metadata["copilot_plan"] = plan.String()
	}
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
	hydroJob := &sweagentEntitiesv0.Job{
		CreatedAt:                timestamppb.New(time.Unix(job.CreatedAt, 0)),
		JobId:                    job.ID,
		RepositoryId:             job.RepoID,
		OwnerId:                  job.OwnerID,
		ActorId:                  job.ActorID,
		PullRequestId:            job.PullRequestID,
		SessionId:                job.SessionID,
		ActorAnalyticsTrackingId: job.ActorAnalyticsTrackingID,
		AssignmentId:             job.AssignmentID,
		RefName:                  job.RefName(),
		AgentId:                  strconv.FormatInt(job.AgentID, 10),
		ComputeId:                job.ComputeID,
		ComputeType:              job.ComputeType(),
		CustomAgent: &sweagentEntitiesv0.Job_CustomAgent{
			CustomAgentName: job.CustomAgent.Name,
			Version:         job.CustomAgent.Version,
			RepoOwnerId:     job.CustomAgent.RepoOwnerID,
			RepoId:          job.CustomAgent.RepoID,
			Metadata:        job.CustomAgent.Metadata,
		},
		Error:      ToJobError(job.Error),
		Model:      job.Model,
		IsAutoMode: job.IsAutoMode,
	}
	if workflowRunID, ok := job.WorkflowRunID(); ok {
		hydroJob.WorkflowRunId = strconv.FormatInt(workflowRunID, 10)
	}
	return hydroJob
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
	case jobs.AgentActionTask:
		return sweagentEntitiesv0.ActionType_TASK
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
