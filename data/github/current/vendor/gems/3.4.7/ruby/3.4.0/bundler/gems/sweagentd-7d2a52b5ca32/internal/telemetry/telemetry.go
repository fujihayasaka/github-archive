package telemetry

import (
	"context"
	"strconv"
	"time"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/command"
	"github.com/github/sweagentd/internal/observability"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	sweagentv0 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v0"
	sweagentEntitiesv0 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v0/entities"
)

type TelemetryPublisher struct {
	obsv     observability.Exporters
	twirp    copilotUsersTwirp.CopilotUserDetailAPI
	ffClient featureflags.Client
	cache    map[int64]bool
}

func NewTelemetryPublisher(obsv observability.Exporters, twirp copilotUsersTwirp.CopilotUserDetailAPI, ffClient featureflags.Client) *TelemetryPublisher {
	return &TelemetryPublisher{
		obsv:     obsv,
		twirp:    twirp,
		ffClient: ffClient,
		cache:    make(map[int64]bool),
	}
}

func (tp *TelemetryPublisher) ShouldPublishRestrictedTelemetry(ctx context.Context, actorID int64) bool {
	// Check cache first
	if allowed, ok := tp.cache[actorID]; ok {
		return allowed
	}

	// Check if user has the feature flag enabled (includes GitHub staff and Microsoft members via custom gates)
	if tp.ffClient.IsEnabledForUser(ctx, "coding_agent_force_restricted_telemetry", actorID) {
		tp.cache[actorID] = true
		return true
	}

	// Fetch Copilot user details to determine plan
	cu, err := tp.twirp.GetCopilotUser(ctx, &copilotUsersTwirp.GetCopilotUserRequest{
		Id: uint64(actorID),
	})

	if err != nil {
		tp.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to fetch copilot user details for telemetry")
		// Conservative default: don't allow if we can't determine plan, but don't cache this result
		return false
	}

	restrictedTelemetryAllowed := isRestrictedTelemetryAllowed(cu.UserDetails.CopilotPlan)
	tp.cache[actorID] = restrictedTelemetryAllowed

	return restrictedTelemetryAllowed
}

func (tp *TelemetryPublisher) PublishJobCompletedTelemetry(ctx context.Context, job *jobs.Job) {
	jobCompletedEvent := ToJobCompleted(job)
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

func (tp *TelemetryPublisher) PublishCommandCreatedTelemetry(ctx context.Context, cmd *command.Command) {
	commandCreatedEvent := ToCommandCreated(cmd)
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

func (tp *TelemetryPublisher) PublishCommandUpdatedTelemetry(ctx context.Context, cmd *command.Command) {
	tags := tp.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"type":   string(cmd.Type),
		"status": string(cmd.Status),
	})
	tp.obsv.Statter.Increment("jobs.commands.update", tags)
	tp.obsv.Statter.DistributionMs("jobs.commands.latency", tags, time.Since(time.Unix(cmd.Timestamp(), 0)))

	commandUpdatedEvent := ToCommandUpdated(cmd)
	err := tp.obsv.HydroPbl.Publish(commandUpdatedEvent)
	if err != nil {
		tp.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to publish command_updated event")
	}
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
	default:
		// Conservative default: don't allow if we can't determine plan
		return false
	}
}

func PublishJobStartTelemetry(ctx context.Context, obsv observability.Exporters, ffClient featureflags.Client, job *jobs.Job) {
	jobStartedEvent := ToJobStarted(job)
	err := obsv.HydroPbl.Publish(jobStartedEvent)
	if err != nil {
		obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to publish job_started event")
	}
}

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
		CustomAgent: &sweagentEntitiesv0.Job_CustomAgent{
			CustomAgentName: job.CustomAgent.Name,
			Version:         job.CustomAgent.Version,
			RepoOwnerId:     job.CustomAgent.RepoOwnerID,
			RepoId:          job.CustomAgent.RepoID,
		},
	}
}

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
	return event
}

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
		// TODO(dy-hu): Add TerminalState_TIMED_OUT to github/hydro-schemas
		return sweagentEntitiesv0.TerminalState_UNKNOWN_STATE
	default:
		return sweagentEntitiesv0.TerminalState_UNKNOWN_STATE
	}
}

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
	case jobs.EventTypePullRequestComment:
		return sweagentEntitiesv0.JobTrigger_PULL_REQUEST_COMMENT_CREATED
	case jobs.EventTypePullRequestCommentNonCopilotPullRequest:
		return sweagentEntitiesv0.JobTrigger_PULL_REQUEST_COMMENT_CREATED
	case jobs.EventTypePullRequestReview:
		return sweagentEntitiesv0.JobTrigger_PULL_REQUEST_REVIEW_SUBMIT
	case jobs.EventTypePullRequestReviewNonCopilotPullRequest:
		return sweagentEntitiesv0.JobTrigger_PULL_REQUEST_REVIEW_SUBMIT
	case jobs.EventTypeCodeScanningAlertsAssignment:
		return sweagentEntitiesv0.JobTrigger_CODE_SCANNING_ALERTS_ASSIGNED
	case jobs.EventTypeApiCallReceived:
		return sweagentEntitiesv0.JobTrigger_API_CALL_RECEIVED
	default:
		// The Jobs API allows for custom event types, so if we encounter an
		// unknown event type we can assume it was an API call.
		return sweagentEntitiesv0.JobTrigger_API_CALL_RECEIVED
	}
}

func resolveTriggerID(job *jobs.Job) int64 {
	switch job.EventType {
	case jobs.EventTypeIssueAssignment, jobs.EventTypePullRequestComment, jobs.EventTypePullRequestReview:
		return triggerIDFromEventIdentifiers(job.EventIdentifiers)
	case jobs.EventTypeCodeScanningAlertsAssignment:
		// Alerts is currently using the PR id as the trigger ID
		return job.PullRequestID
	default:
		return triggerIDFromEventIdentifiers(job.EventIdentifiers)
	}
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
