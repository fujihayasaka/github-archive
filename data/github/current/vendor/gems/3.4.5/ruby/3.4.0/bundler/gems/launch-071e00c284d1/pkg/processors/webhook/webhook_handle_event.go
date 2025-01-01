package webhook

import (
	"context"
	"time"

	"github.com/github/go-kvp"
	"github.com/google/go-github/v25/github"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"

	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/flow/flowevents/eventactions"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/slometrics"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/globalidmigration"
	"github.com/github/launch/services/deploy/deliveryguid"
	"github.com/github/launch/services/deploy/workflowinvoker"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/ghtenant"
)

func (p *Processor) handleEvent(ctx context.Context, obs *observability.Observability, job Job, event flowevents.GitHubEvent, jsonEvent *webhookJSON, sanitizedPayload []byte, isFinalAttempt bool, githubTenant ghtenant.GitHubTenant) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	// Other events must be on explicitly allowed:
	if !flowevents.IsAllowedWebhookEvent(job.Event) {
		obs.Debug(ctx, "skipping disallowed event")
		obs.Counter(ctx, "queue.webhook.skipped", statter.Tags{"reason": "not_allowed", "event": job.Event}, 1)
		return nil
	}

	webhookData, err := p.extractData(ctx, obs, jsonEvent, job.Event)
	if err != nil {
		// We don't have `webhookData` so we don't have access to our global IDs
		msg := slometrics.NewQueueRunMessage(ctx, obs, "", "", "", job.Event, "")
		p.sloReporter.ReportQueueRunError(ctx, obs, msg, "extractData")

		return errors.Wrap(err, "error extracting data from payload")
	}
	if webhookData == nil {
		return nil
	}
	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.repo.global_id", webhookData.RepositoryGlobalID.String()),
		kvp.Int64("gh.repo.id", webhookData.RepositoryDatabaseID),
		kvp.String("gh.launch.event.type", webhookData.EventAction),
	)

	msg := slometrics.NewQueueRunMessage(
		ctx,
		obs,
		slometrics.ActorID(webhookData.ActorGlobalID),
		slometrics.OwnerID(webhookData.RepositoryOwnerGlobalID),
		slometrics.RepositoryID(webhookData.RepositoryGlobalID),
		job.Event,
		webhookData.EventAction,
		slometrics.WithRerunInfo(job.RerunInfo()))

	span.SetAttributes(
		attribute.String("gh.launch.event.type", webhookData.EventAction),
	)

	if isCheckSuiteRequest(event) {
		return nil
	}

	// Extract the commit and ref from the payload.
	commit, ref, ok, err := flowevents.ExtractCommitAndRef(job.Event, event)
	if err != nil {
		obs.Report(ctx, errors.Wrap(err, "failed to extract commit and ref"))
		p.sloReporter.ReportQueueRunError(ctx, obs, msg, "ExtractCommitAndRef")
		return tracing.RecordError(span, errors.Wrap(err, "could not extract target commit or ref"))
	}

	ctx = ctxstash.WithFields(ctx, kvp.Any("gh.launch.event.commit_sha", commit), kvp.Any("gh.launch.event.ref", ref))
	obs.Debug(ctx, "extracted commit and ref")
	if _, err = obs.LogDurationWithoutThreshold(ctx, observability.AqJobRecvAtCheckpoint, "ref_extracted", nil); err != nil {
		// Report the error but continue
		obs.Report(ctx, errors.Wrap(err, "failed to log duration"), kvp.String("gh.launch.operation.name", "ref_extracted"))
	}

	if !ok {
		obs.Log(ctx, "Skipping event with no commit or ref")
		obs.Counter(ctx, "queue.webhook.skipped", statter.Tags{"reason": "invalid_extraction", "event": job.Event}, 1)
		return nil
	}

	if isPushBranchDeleteRequest(event, commit, ref) {
		obs.Log(ctx, "Skipping branch delete push event")
		obs.Counter(ctx, "queue.webhook.skipped", statter.Tags{"reason": "push_branch_delete", "event": job.Event}, 1)
		return nil
	}

	if isDraftReleaseEvent(event) {
		obs.Log(ctx, "Skipping draft release event")
		obs.Counter(ctx, "queue.webhook.skipped", statter.Tags{"reason": "draft_release", "event": job.Event}, 1)
		return nil
	}

	// Telemetry investigation for https://github.com/github/c2c-actions-support/issues/1196
	if wr, isCompleted := isCompletedWorkflowRunEvent(event); isCompleted {
		if wr.GetWorkflowRun().GetConclusion() == "" {
			obs.Log(ctx, "missing conclusion for workflow_run.completed event")
			obs.Counter(ctx, "queue.webhook.missing_conclusion", statter.Tags{}, 1)
		}
	}

	// If the event is a check suite event created by the launch app and it's re-requested, we want
	// to re-run this event and restart it.
	cs, isRerun := isRerequestedCheckSuite(event, p.cfg.AppID)
	ctx = ctxstash.WithFields(ctx, kvp.Bool("gh.launch.event.is_rerun", isRerun), kvp.Bool("gh.launch.event.is_partial_rerun", job.RerunInfo() != nil))

	eventOriginTime, err := deliveryguid.ExtractTime(job.WebhookDeliveryID)
	if err != nil {
		return tracing.RecordError(span, errors.Wrap(err, "could not extract time from webhook_delivery_id"))
	}
	ctx = ctxstash.WithFields(ctx, kvp.Time("gh.launch.event.origin_time", eventOriginTime))

	pushedAt := flowevents.ExtractEventTime(job.Event, event)
	if !pushedAt.IsZero() {
		ctx = ctxstash.WithFields(ctx, kvp.Time("gh.launch.pushed_at", pushedAt))
	}

	jobSentAt, ok, err := obs.GetCheckpointTime(observability.AqJobSentAtCheckpoint)
	if err != nil {
		return tracing.RecordError(span, errors.Wrap(err, "could not retrieve aqueduct job's sent_at time"))
	}
	if ok {
		obs.Timing(ctx, "delays.delivery_system_triggered_at.job_sent_at", statter.Tags{}, jobSentAt.Sub(eventOriginTime))
		obs.Timing(ctx, "delays.delivery_system_enqueued_at.job_sent_at", statter.Tags{}, jobSentAt.Sub(job.EnqueuedAtTime()))
	}

	eventAction := flowevents.ExtractEventAction(event)

	var invocation workflowinvoker.Invocation

	if isRerun {
		inv, err := p.invocationForRerun(ctx, cs, webhookData, eventAction, pushedAt, eventOriginTime, obs, job.WebhookDeliveryID, job.RerunInfo(), job.EnableDebugLogging(), githubTenant)
		if err != nil {
			obs.Report(ctx, errors.Wrap(err, "failed in rerun invocation"))
			if isFinalAttempt {
				p.sloReporter.ReportQueueRunError(ctx, obs, msg, "invocationForRerun")
			}
			return terrors.WrapAsRetryable(tracing.RecordError(span, err), "failed to build rerun invocation")
		}
		invocation = *inv
	} else {
		commitMessage := flowevents.ExtractCommitMessage(event)
		invocation = newInvocation(webhookData, commit, commitMessage, ref, job.Event, eventAction, pushedAt, eventOriginTime, sanitizedPayload, event, job.WebhookDeliveryID, githubTenant)
	}

	obs.Debug(ctx, "built invocation")
	err = p.workflowInvoker.Start(ctx, obs, invocation, isFinalAttempt, p.labeler)
	if err != nil {
		// Start already called CountQueueRunError if appropriate.
		return tracing.RecordError(span, err)
	}

	return nil
}

func newInvocation(
	w *webhookData,
	commit types.CommitSha,
	commitMessage types.CommitMessage,
	ref types.GitRef,
	eventName string,
	eventAction string,
	pushedAt, eventOriginTime time.Time,
	sanitizedPayload []byte,
	event flowevents.GitHubEvent,
	deliveryID string,
	githubTenant ghtenant.GitHubTenant,
) workflowinvoker.Invocation {
	return workflowinvoker.NewInvocation(
		workflowinvoker.NewEvent(
			&deliveryID,
			ref,
			commit,
			commitMessage,
			eventName,
			eventAction,
			sanitizedPayload,
			pushedAt,
			eventOriginTime,
			event,
		),
		workflowinvoker.NewActor(
			w.ActorGlobalID,
			w.ActorLogin,
		),
		workflowinvoker.NewActor(
			w.ActorGlobalID,
			w.ActorLogin,
		),
		workflowinvoker.NewTarget(
			w.RepositoryGlobalID,
			w.RepositoryDatabaseID,
			workflowinvoker.NewWorkflowSelector(eventName, event),
			w.RepositoryOwnerGlobalID,
			w.RepositoryOwnerDatabaseID,
			githubTenant,
		),
	)
}

func (p *Processor) invocationForRerun(ctx context.Context,
	cs *github.CheckSuiteEvent,
	w *webhookData,
	eventAction string,
	pushedAt, eventOriginTime time.Time,
	obs *observability.Observability,
	webhookDeliveryID string,
	rerunInfo *types.RerunInfo,
	enableDebugLogging bool,
	githubTenant ghtenant.GitHubTenant,
) (*workflowinvoker.Invocation, error) {

	checkSuiteID := types.NewGlobalID(ctx, cs.GetCheckSuite().GetNodeID())
	obs.Log(ctx, "re-run request received", kvp.String("gh.check_suite.global_id", checkSuiteID.String()))

	checkSuiteState, ok, err := p.wbRepo.GetStateByCheckSuiteID(ctx, checkSuiteID)
	if err != nil {
		mw.TagStatsWith(ctx, reqmeta.Tags{
			"status":       "unhandled_error",
			"error_type":   "GetStateByCheckSuiteID",
			"error_reason": "internal",
		})
		return nil, err
	}
	if !ok {
		mw.TagStatsWith(ctx, reqmeta.Tags{
			"status":       "unhandled_error",
			"error_type":   "GetStateByCheckSuiteID.missing",
			"error_reason": "internal",
		})
		err := errors.New("could not find workflow for re-run")
		obs.Error(ctx, "missing check suite state", kvp.String("gh.check_suite.global_id", checkSuiteID.String()))
		return nil, err
	}

	if checkSuiteState.EventPayload == nil {
		return nil, errors.New("missing event payload for workflow run")
	}

	// Update any legacy global IDs in the job payload to the Next Global ID format
	eventPayload, err := globalidmigration.ConvertPayloadIDs(ctx, obs, p.ghtwirp,
		"webhook.processor.invocationforrerun", checkSuiteState.EventPayload)
	if err != nil {
		obs.Report(ctx, errors.Wrap(err, "error encountered while trying to convert job payload global IDs"))
	}

	// Parse the GitHub event out of the stored payload instead of the incoming aqueduct job.
	ghe, err := workflowinvoker.EventFromPersistedPayload(checkSuiteState.Event, eventPayload)
	if err != nil {
		return nil, err
	}

	commit, ref, err := extractCommitAndRefForRerun(checkSuiteState, ghe)
	if err != nil {
		return nil, err
	}

	commitMessage := flowevents.ExtractCommitMessage(ghe)

	triggeringActor := workflowinvoker.NewActor(
		w.ActorGlobalID,
		w.ActorLogin,
	)
	var executingActor workflowinvoker.InvokingActor
	if checkSuiteState.ExecutedAsActorID.IsEquivalent(w.ActorGlobalID) {
		executingActor = triggeringActor
		obs.Log(ctx, "rerun triggering actor matches original executing actor",
			kvp.String("gh.launch.executing_actor.global_id", string(executingActor.ID)),
			kvp.String("gh.launch.executing_actor.login", executingActor.Login),
		)
	} else {
		executingActorID := checkSuiteState.ExecutedAsActorID
		login, ok, err := p.getLoginFromID(ctx, executingActorID)
		if err != nil {
			obs.Report(ctx, err, kvp.String("gh.launch.executing_actor.global_id", executingActorID.String()))
			return nil, errors.Wrap(err, "resolving executing actor's login from ID")
		}
		if !ok {
			obs.Error(ctx, "executing actor ID for a rerun appears to not exist anymore",
				kvp.String("gh.launch.executing_actor.global_id", executingActorID.String()),
			)
			return nil, errors.New("this check suite's original executing actor doesn't appear to exist - unable to proceed")
		}
		executingActor = workflowinvoker.NewActor(
			executingActorID,
			login,
		)
		obs.Log(ctx, "rerunning using prior executing actor",
			kvp.String("gh.launch.executing_actor.global_id", string(executingActor.ID)),
			kvp.String("gh.launch.executing_actor.login", executingActor.Login),
			kvp.String("gh.launch.triggering_actor.id", string(triggeringActor.ID)),
			kvp.String("gh.launch.triggering_actor.login", triggeringActor.Login),
		)
	}

	inv := workflowinvoker.NewInvocation(
		workflowinvoker.NewEvent(
			checkSuiteState.WebhookDeliveryID,
			ref,
			commit,
			commitMessage,
			checkSuiteState.Event,
			eventAction,
			checkSuiteState.EventPayload,
			pushedAt,
			eventOriginTime,
			ghe,
		),
		executingActor,
		triggeringActor,
		workflowinvoker.NewTarget(
			w.RepositoryGlobalID,
			w.RepositoryDatabaseID,
			workflowinvoker.WorkflowSelector{
				EventName: checkSuiteState.Event,
				// For a re-run, we only want to run one specific workflow
				Path: &checkSuiteState.WorkflowFilePath,
			},
			w.RepositoryOwnerGlobalID,
			w.RepositoryOwnerDatabaseID,
			githubTenant,
		),
		workflowinvoker.WithCheckSuiteState(checkSuiteState),
		workflowinvoker.WithRerunWebhookDeliveryID(webhookDeliveryID),
		workflowinvoker.WithRerunInfo(rerunInfo),
		workflowinvoker.WithEnableDebugLogging(enableDebugLogging),
	)
	return &inv, nil
}

func (p *Processor) getLoginFromID(ctx context.Context, id types.GlobalID) (login string, found bool, err error) {
	infos, err := p.ghtwirp.GetActorsInfo(ctx, []types.GlobalID{id})
	if err != nil {
		return "", false, err
	}

	for _, ai := range infos.Actors {
		if id.IsEquivalent(types.NewGlobalID(ctx, ai.GlobalId.GlobalId)) {
			return ai.IdString, true, nil
		}
	}
	return "", false, nil
}

func extractCommitAndRefForRerun(checkSuiteState *types.CheckSuiteState, ghe flowevents.GitHubEvent) (types.CommitSha, types.GitRef, error) {
	if !checkSuiteState.EventSHA.IsZeroValue() && !checkSuiteState.EventRef.IsZeroValue() {
		return checkSuiteState.EventSHA, checkSuiteState.EventRef, nil
	}

	// For builds without EventRef persisted we can parse it out of their
	// webhook payloads. For scheduled builds there is no webhook payload so
	// use the default branch.
	if flowevents.IsAllowedWebhookEvent(checkSuiteState.Event) {
		commitSHA, commitRef, ok, err := flowevents.ExtractCommitAndRef(checkSuiteState.Event, ghe)
		if err != nil {
			return types.NullCommitSha, types.GitRefZeroValue, errors.Wrap(err, "error extracting commit/ref from persisted rerun payload")
		}

		if !ok {
			return types.NullCommitSha, types.GitRefZeroValue, errors.New("could not extract commit and ref from persisted rerun payload")
		}

		return commitSHA, commitRef, nil
	} else if checkSuiteState.Event == flowevents.ScheduleEventName {
		return checkSuiteState.EventSHA, types.DefaultBranch, nil
	}

	return types.NullCommitSha, types.GitRefZeroValue, errors.Errorf("unable to handle event: %s", checkSuiteState.Event)
}

func isPushBranchDeleteRequest(event flowevents.GitHubEvent, commit types.CommitSha, ref types.GitRef) bool {
	if _, ok := event.(*github.PushEvent); ok {
		return commit == types.CommitShaZeroValue && ref == types.DefaultBranch
	}
	return false
}

func isDraftReleaseEvent(event flowevents.GitHubEvent) bool {
	if evt, ok := event.(*github.ReleaseEvent); ok {
		return evt.GetRelease().GetDraft()
	}
	return false
}

func isCheckSuiteRequest(event flowevents.GitHubEvent) bool {
	if cs, ok := event.(*github.CheckSuiteEvent); ok {
		return cs.GetAction() == "requested"
	}
	return false
}

func isRerequestedCheckSuite(event flowevents.GitHubEvent, appID int64) (cs *github.CheckSuiteEvent, isRerun bool) {
	if cs, ok := event.(*github.CheckSuiteEvent); ok {
		return cs, cs.GetAction() == eventactions.Rerequested && *cs.GetCheckSuite().GetApp().ID == appID
	}

	return cs, false
}

func isCompletedWorkflowRunEvent(event flowevents.GitHubEvent) (*github.WorkflowRunEvent, bool) {
	if wr, ok := event.(*github.WorkflowRunEvent); ok {
		return wr, wr.GetAction() == eventactions.Completed
	}

	return nil, false
}
