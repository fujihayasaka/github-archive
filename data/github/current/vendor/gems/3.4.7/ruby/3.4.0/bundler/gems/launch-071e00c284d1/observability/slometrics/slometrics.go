// Helper functions to produce metrics for SLOs that cross packages.
package slometrics

import (
	"context"

	"github.com/pkg/errors"

	"github.com/github/go-kvp"

	"github.com/github/launch/pkg/mu/muhttp/mw"

	hydroV0 "github.com/github/launch/hydro/schemas/github/actions/v0"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/types"
)

// HydroEmitter is an interface to emitting Hydro events
type HydroEmitter interface {
	EmitQueueRun(evt *hydroV0.QueueRun)
}

// Reporter is a wrapper around the emitter for SLO Metrics
type Reporter struct {
	hydroEmitter HydroEmitter
}

func New(hydroEmitter HydroEmitter) *Reporter {
	return &Reporter{
		hydroEmitter: hydroEmitter,
	}
}

func (r *Reporter) emitQueueRun(ctx context.Context, obs *observability.Observability, msg *hydroV0.QueueRun, status hydroV0.QueueRun_Status) {
	if msg != nil {
		msg.Status = status
		r.hydroEmitter.EmitQueueRun(msg)
	} else {
		obs.Debug(ctx, "skipping queue run event emission because message is nil")
	}
}

// ActorID is a type alias for the Actor GlobalID so we don't mess up the order
// of our inputs.
type ActorID types.GlobalID

// OwnerID is a type alias for the Owner GloablID so we don't mess up the order
// of our inputs.
type OwnerID types.GlobalID

// RepositoryID is a type alias for the Repository GlobalID so we don't mess up
// the order of our inputs.
type RepositoryID types.GlobalID

type QueueRunMessageOption func(*hydroV0.QueueRun)

func NewQueueRunMessage(
	ctx context.Context,
	obs *observability.Observability,
	triggeringActorID ActorID,
	ownerGlobalID OwnerID,
	repositoryGlobalID RepositoryID,
	eventName string,
	eventAction string,
	opts ...QueueRunMessageOption,
) *hydroV0.QueueRun {
	var actorID int64
	var err error
	if triggeringActorID != "" {
		_, actorID, err = types.NewGlobalID(ctx, string(triggeringActorID)).Decode()
		if err != nil {
			// Log the error while decoding an actor because this can be blank
			// sometimes.
			obs.Error(ctx, "error decoding actor", kvp.Err(err))
		}
	} else {
		obs.Debug(ctx, "missing actor global ID")
	}

	var repositoryID int64
	if repositoryGlobalID != "" {
		_, repositoryID, err = types.NewGlobalID(ctx, string(repositoryGlobalID)).Decode()
		if err != nil {
			// If there's an error decoding the repository, report the error because
			// this is the primary identifier for a workflow run.
			obs.Report(ctx, errors.Wrap(err, "failed to decode repository global ID"))
		}
	} else {
		obs.Debug(ctx, "missing repository global ID")
	}

	var ownerType string
	var ownerID int64
	if ownerGlobalID != "" {
		ownerType, ownerID, err = types.NewGlobalID(ctx, string(ownerGlobalID)).Decode()
		if err != nil {
			// if there's an error decoding the repository owner, report it, but don't
			// skip the reporting because owner can be derived from the repository.
			obs.Error(ctx, "error decoding repository owner ID", kvp.Err(err))
		}
	}

	msg := &hydroV0.QueueRun{
		InvokingUserId:       uint64(actorID),
		RepositoryDatabaseId: uint64(repositoryID),
		OwnerDatabaseId:      uint64(ownerID),
		OwnerType:            ownerType,
		EventName:            eventName,
		EventAction:          eventAction,
		Stats:                &hydroV0.QueueRun_Stats{},
	}

	for _, opt := range opts {
		opt(msg)
	}

	return msg
}

func WithRerunInfo(in *types.RerunInfo) QueueRunMessageOption {
	return func(msg *hydroV0.QueueRun) {
		if in != nil {
			msg.RerunInfo = &hydroV0.QueueRun_RerunInfo{
				PlanId: in.PlanID,
				JobId:  in.JobIDs,
			}
		}
	}
}

func WithWorkflowExecutionID(in types.WorkflowExecutionID) QueueRunMessageOption {
	return func(msg *hydroV0.QueueRun) {
		msg.WorkflowExecutionId = in.String()
	}
}

func WithCallableWorkflowStats(localRefsCount, remoteRefsCount int) QueueRunMessageOption {
	return func(msg *hydroV0.QueueRun) {
		if msg.Stats == nil {
			msg.Stats = &hydroV0.QueueRun_Stats{}
		}
		if localRefsCount > 0 || remoteRefsCount > 0 {
			msg.Stats.UsedCallableWorkflows = true
			msg.Stats.LocalWorkflowCalls = int64(localRefsCount)
			msg.Stats.RemoteWorkflowCalls = int64(remoteRefsCount)
		}
	}
}

func (r *Reporter) emitQueueRunSuccess(ctx context.Context, o *observability.Observability, msg *hydroV0.QueueRun) {
	r.emitQueueRun(ctx, o, msg, hydroV0.QueueRun_SUCCESS)
}

func (r *Reporter) emitQueueRunDropped(ctx context.Context, o *observability.Observability, msg *hydroV0.QueueRun) {
	r.emitQueueRun(ctx, o, msg, hydroV0.QueueRun_DROPPED)
}

func (r *Reporter) emitQueueRunFailure(ctx context.Context, o *observability.Observability, msg *hydroV0.QueueRun) {
	r.emitQueueRun(ctx, o, msg, hydroV0.QueueRun_FAILURE)
}

// ReportQueueRunError reports a workflow run failing to be queued due to a non-user
// error
func (r *Reporter) ReportQueueRunError(ctx context.Context, o *observability.Observability, msg *hydroV0.QueueRun, errType string) {
	if msg != nil {
		msg.ErrorMessage = errType
	}

	r.emitQueueRunFailure(ctx, o, msg)
	CountQueueRunError(ctx, o, errType)
}

// ReportQueueRunSuccess reports a workflow run that's successfully queued.
func (r *Reporter) ReportQueueRunSuccess(ctx context.Context, o *observability.Observability, msg *hydroV0.QueueRun) {
	r.emitQueueRunSuccess(ctx, o, msg)
	CountQueueRunSuccess(ctx, o)
}

// ReportQueueRunDropped reports a workflow run that's been dropped.
func (r *Reporter) ReportQueueRunDropped(ctx context.Context, o *observability.Observability, msg *hydroV0.QueueRun) {
	r.emitQueueRunDropped(ctx, o, msg)
	CountQueueRunDropped(ctx, o)
}

// Count a workflow run being dropped before it could be queued.
// SLO: actions/availability/queue-run-failures
func CountQueueRunDropped(ctx context.Context, o *observability.Observability) {
	countQueueRunResult(ctx, o, statter.Tags{"status": "dropped"})
}

// Count a workflow run being queued successfully.
// SLO: actions/availability/queue-run-failures
func CountQueueRunSuccess(ctx context.Context, o *observability.Observability) {
	countQueueRunResult(ctx, o, statter.Tags{"status": "success"})
}

// Count a workflow run failing to be queued due to a non-user error.
// This can also be called for errors prior to workflow parsing, that likely prevented workflow(s) from being queued.
// SLO: actions/availability/queue-run-failures
func CountQueueRunError(ctx context.Context, o *observability.Observability, errType string) {
	countQueueRunResult(ctx, o, statter.Tags{"status": "error", "error_type": errType})
}

func countQueueRunResult(ctx context.Context, o *observability.Observability, tags statter.Tags) {
	// Used for the actions/availability/queue-run-failures SLO and associated alerts.
	key := "availability.queue_run"

	// Tag the backend as inconclusive if it's not set.
	// This normally means we encountered an error before we could determine the backend.
	if rmd := mw.GetRequestMetadata(ctx); rmd != nil {
		rmdTags := rmd.StatTags()
		if _, ok := rmdTags["backend"]; !ok {
			rmdTags["backend"] = types.WorkflowBackendInconclusive.String()
		}
	}

	o.Counter(ctx, key, tags, 1)
	observability.LogStatTags(ctx, o.Logger, key, tags)
}
