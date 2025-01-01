package webhook

import (
	"context"

	"github.com/github/go-kvp"
	"github.com/google/go-github/v25/github"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
)

func (p *Processor) handlePush(ctx context.Context, obs *observability.Observability, event *github.PushEvent) {
	ctx, span := tracing.Start(ctx, trace.WithAttributes(
		attribute.String("gh.launch.event.name", "push"),
	))
	defer span.End()

	ownerDatabaseID := event.GetRepo().GetOwner().GetID()

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.repo.global_id", event.GetRepo().GetNodeID()),
		kvp.Int64("gh.repo.id", event.GetRepo().GetID()),
		kvp.String("gh.launch.before_sha", event.GetBefore()),
		kvp.String("gh.launch.after_sha", event.GetAfter()),
		kvp.Int64("gh.launch.owner.id", ownerDatabaseID),
	)

	obs.Debug(ctx, "syncing schedules for repository push")
	p.scheduleMngr.SyncOnPush(
		ctx,
		types.NewGlobalID(ctx, event.GetRepo().GetNodeID()),
		types.GitRef(event.GetRef()),
		types.NewGlobalID(ctx, event.GetSender().GetNodeID()),
		ownerDatabaseID,
	)

	mw.TagStatsWith(ctx, reqmeta.Tags{"result": "success"})
}
