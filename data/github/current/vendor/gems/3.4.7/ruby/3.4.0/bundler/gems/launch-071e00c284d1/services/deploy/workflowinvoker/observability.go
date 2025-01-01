package workflowinvoker

import (
	"context"

	"github.com/github/go-kvp"

	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/logkeys"
	"github.com/github/launch/types"
)

const invokedStatKey = "workflow.invoker.invoked"

type Observability struct {
	observability.Observability
	completedWorkflowMatch bool
}

func NewNullObservability() *Observability {
	return NewTestObservability(observability.NewNullObservability())
}

func NewTestObservability(obs *observability.Observability) *Observability {
	return &Observability{
		*obs,
		false,
	}
}

func NewObservability(ctx context.Context, obs *observability.Observability, inv Invocation) (context.Context, *Observability) {
	if obs == nil {
		return ctx, nil
	}
	addInitialStatTags(ctx, inv)
	ctx = withInitialLogFields(ctx, inv)
	return ctx, &Observability{*obs, false}
}

func addInitialStatTags(ctx context.Context, inv Invocation) {
	mw.TagStatsWith(ctx, reqmeta.Tags{
		"status":      "unknown",
		"event":       inv.Event.Name,
		"repo_bucket": observability.BucketGlobalID(inv.Target.RepositoryID),
	})
	if inv.ExistingCheckSuite != nil {
		mw.TagStatsWith(ctx, reqmeta.Tags{"rerun": "true"})
	}
	if inv.RerunInfo != nil {
		mw.TagStatsWith(ctx, reqmeta.Tags{"partial_rerun": "true"})
	}
}

func withInitialLogFields(ctx context.Context, inv Invocation) context.Context {
	return ctxstash.WithFields(ctx,
		kvp.Any("gh.launch.event.name", inv.Event.Name),
		kvp.Any("gh.launch.event.type", inv.Event.Action),
		kvp.Any("gh.launch.event.commit_sha", inv.Event.Commit),
		kvp.Any("gh.launch.event.ref", inv.Event.Ref),
		kvp.String("gh.launch.executing_actor.global_id", inv.ExecutingActor.ID.String()),
		kvp.String("gh.launch.triggering_actor.global_id", inv.TriggeringActor.ID.String()),
		kvp.String("gh.repo.global_id", inv.Target.RepositoryID.String()),
		kvp.Int64("gh.repo.id", inv.Target.RepositoryDatabaseID),
	)
}

func addGitHubDataStatsTags(ctx context.Context, data *types.WorkflowInvocationData) {
	mw.TagStatsWith(ctx, reqmeta.Tags{
		"plan_owner_bucket": observability.BucketGlobalID(data.PlanOwner.GlobalID),
	})
}

func withGitHubDataLogFields(ctx context.Context, data *types.WorkflowInvocationData) context.Context {
	return ctxstash.WithFields(ctx,
		kvp.Any("gh.launch.plan_owner.global_id", data.PlanOwner.GlobalID),
		kvp.Any("gh.launch.resolved_commit.sha", data.References.EventCommit.CommitSHA),
		kvp.Any("gh.launch.resolved_ref", data.References.EventCommit.GitRef),
	)
}

func (o *Observability) WorkflowMatchCompleted() {
	o.completedWorkflowMatch = true
}

func (o *Observability) logCompletion(ctx context.Context) {
	observability.LogStatTags(ctx, o.Logger, invokedStatKey, nil, kvp.Bool("gh.launch.completed_workflow_match", o.completedWorkflowMatch))
}

func addEventOriginTimeCheckpoint(inv Invocation, obs *Observability) {
	if !inv.Event.OriginTime.IsZero() {
		obs.AddCheckpoint(observability.EventOriginTime, inv.Event.OriginTime)
	}
}

func logInvokerStartStage(ctx context.Context, obs *Observability) {
	observability.LogStage(ctx, obs.Logger, logkeys.InvokerStartStage)
}
