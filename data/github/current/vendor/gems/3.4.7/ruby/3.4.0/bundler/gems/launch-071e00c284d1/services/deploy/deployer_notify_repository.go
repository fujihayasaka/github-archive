package deploy

import (
	"context"

	"github.com/github/go-kvp"
	"github.com/golang/protobuf/ptypes/empty"
	"github.com/hashicorp/go-multierror"
	"github.com/pkg/errors"

	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/schedulemanager"
	"github.com/github/launch/services/deploy/adminevents"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/services/pbtypes/launchtypes"
	"github.com/github/launch/types"
)

const (
	ActionDeleted  = "deleted"
	ActionArchived = "archived"
)

func (s *service) NotifyRepository(ctx context.Context, event *launchtypes.NotifyRepositoryEvent) (*empty.Empty, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	repoGid, err := s.GetGlobalIDFromIdentity(ctx, event.GetRepositoryNodeId(), "NotifyRepository")
	if err != nil {
		return nil, tracing.RecordError(span, svcerr.NewInternalError("failed to notify repository, %v", err))
	}
	event.RepositoryNodeId = types.IdentityFromGlobalID(repoGid)
	repoOwnerGid, err := s.GetGlobalIDFromIdentity(ctx, event.GetRepositoryOwnerNodeId(), "NotifyRepository")
	if err != nil {
		return nil, tracing.RecordError(span, svcerr.NewInternalError("failed to notify repository, %v", err))
	}
	event.RepositoryOwnerNodeId = types.IdentityFromGlobalID(repoOwnerGid)
	err = NotifyRepository(ctx, s.cfg.Log, event, s.cfg.ScheduleManager, s.cfg.AdminEventsReporter, s.IsEnterprise)
	if err != nil {
		return nil, tracing.RecordError(span, svcerr.NewInternalError("failed to notify repository, %v", err))
	}
	return &empty.Empty{}, nil
}

// NotifyRepository is a standalone function so that it can be used by launch-worker as well as launch-deployer
func NotifyRepository(ctx context.Context, log logger.Logger, event *launchtypes.NotifyRepositoryEvent, sch schedulemanager.Manager, rptr adminevents.Reporter, isEnterprise bool) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	errGroup := &multierror.Group{}

	errGroup.Go(func() error {
		// Handle repository event for scheduled workflows
		_, err := sch.NotifyRepository(ctx, event)
		return errors.Wrap(err, "failed to handle repository event for scheduled workflows")
	})

	errGroup.Go(func() error {
		return notifyForArchivedAndDeleted(ctx, log, event, rptr, isEnterprise)
	})

	if errs := errGroup.Wait(); errs.ErrorOrNil() != nil {
		log.Report(ctx, errs)
		return tracing.RecordError(span, errs)
	}

	return nil
}

func notifyForArchivedAndDeleted(ctx context.Context, log logger.Logger, event *launchtypes.NotifyRepositoryEvent, rptr adminevents.Reporter, isEnterprise bool) error {
	// Sending admin event for archived and deleted repositories
	// will cancel all workflows in the repository in Actions Service side
	repoGID := types.IdentityToGlobalID(ctx, event.GetRepositoryNodeId())
	repoOwnerGID := types.IdentityToGlobalID(ctx, event.GetRepositoryOwnerNodeId())
	if event.GetAction() == ActionDeleted || event.GetAction() == ActionArchived {

		var eventType string
		if event.GetAction() == ActionArchived {
			eventType = adminevents.RepositoryArchived
		} else if event.GetAction() == ActionDeleted {
			eventType = adminevents.RepositoryDeleted
		}

		ctx = ctxstash.WithFields(ctx,
			kvp.String("gh.repo.global_id", repoGID.String()),
			kvp.String("gh.actor.global_id", event.GetActorNodeId()),
			kvp.String("gh.launch.event.type", eventType),
			kvp.String("gh.repo.owner.global_id", repoOwnerGID.String()),
		)

		if !isEnterprise {
			log.Debug(ctx, "skipping cancel all workflows in the repository, since hydro event handles this")
			return nil
		}

		log.Debug(ctx, "reporting repo admin event to cancel all workflows in the repository")

		data := map[string]string{
			"repo_global_id":       repoGID.String(),
			"repo_owner_global_id": repoOwnerGID.String(),
		}

		err := rptr.ReportRepoAdminEvent(ctx, repoGID, eventType, data)
		if err != nil {
			log.Report(ctx, errors.Wrap(err, "error in cancelling all workflows"))
			return errors.Wrap(err, "attempting to cancel all workflows for repository")
		}

		log.Log(ctx, "successfully reported admin event to cancel all workflows for repository")
		return nil
	}

	return nil
}
