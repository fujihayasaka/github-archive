package webhook

import (
	"context"

	"github.com/google/go-github/v25/github"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/deploy"
	"github.com/github/launch/services/pbtypes"
	"github.com/github/launch/services/pbtypes/launchtypes"
	terrors "github.com/github/launch/types/errors"
)

func (p *Processor) handleRepository(ctx context.Context, obs *observability.Observability, event *github.RepositoryEvent) error {
	ctx, span := tracing.Start(ctx, trace.WithAttributes(
		attribute.String("gh.launch.event.name", "repository"),
	))
	defer span.End()

	changes := event.GetChanges()

	req := &launchtypes.NotifyRepositoryEvent{
		RepositoryNodeId:      &pbtypes.Identity{GlobalId: event.GetRepo().GetNodeID()},
		RepositoryId:          event.GetRepo().GetID(),
		InstallationId:        event.GetInstallation().GetID(),
		Action:                event.GetAction(),
		ActorNodeId:           event.GetSender().GetNodeID(),
		ActorLogin:            event.GetSender().GetLogin(),
		DefaultBranchChanged:  changes != nil && changes.DefaultBranch != nil,
		RepositoryOwnerNodeId: &pbtypes.Identity{GlobalId: event.GetRepo().GetOwner().GetNodeID()},
		OwnerDatabaseId:       event.GetRepo().GetOwner().GetID(),
	}

	return p.deployerHandleRepository(ctx, obs, req)
}

func (p *Processor) deployerHandleRepository(ctx context.Context, obs *observability.Observability, event *launchtypes.NotifyRepositoryEvent) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	err := deploy.NotifyRepository(ctx, obs.Logger, event, p.scheduleMngr, p.rptr, p.cfg.IsEnterprise)
	if err != nil {
		return terrors.WrapAsRetryable(tracing.RecordError(span, err), "failed to notify repository")
	}
	return nil
}
