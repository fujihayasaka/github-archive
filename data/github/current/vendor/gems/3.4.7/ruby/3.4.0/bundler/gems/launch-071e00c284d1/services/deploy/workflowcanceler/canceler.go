package workflowcanceler

import (
	"context"
	"time"

	"github.com/github/go-kvp"
	errs "github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/deployer"
	hydroV0 "github.com/github/launch/hydro/schemas/github/actions/v0"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/buildhealer"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/graphqlid"
)

const (
	statusSuccess = "success"
	statusFailure = "failure"

	// see WorkflowCancelRequest hydro
	cancelFailed     = "cancel_failed"
	notRequested     = "error_before_requested"
	runInfoFailed    = "run_info_failed"
	healingFailed    = "healing_failed"
	healingCompleted = "healing_completed"
	healingSkipped   = "healing_skipped"
)

type healer interface {
	CompleteBuild(ctx context.Context, w buildhealer.WorkflowInfo, status, conclusion string, reason buildhealer.HealReason) (fixType string, healed bool, err error)
}

type Canceler interface {
	Cancel(ctx context.Context, wf *deployer.WorkflowBuildState, opts *azp.CancelOptions) error

	// CancelAllWorkflowsForActorIDExludeRepoIDs attempts to cancel all pending workflows for given actor and excluding the given repos
	CancelAllWorkflowsForActorIDExludeRepoIDs(ctx context.Context, actorID types.GlobalID, excludeRepoIDs []types.GlobalID) (int64, error)
}

type canceler struct {
	obs     *observability.Observability
	healer  healer
	wbr     deployer.WorkflowBuildsRepository
	azp     azp.RepositoryClientFactory
	hyd     cancelHydro
	ghTwirp ghtwirp.Client
}

type cancelHydro interface {
	EmitWorkflowCancelRequest(evt *hydroV0.WorkflowCancelRequest)
}

func NewWorkflowCanceler(obs *observability.Observability, healer healer, wbr deployer.WorkflowBuildsRepository, rps azp.RepositoryClientFactory, hyd cancelHydro, ghTwirp ghtwirp.Client) Canceler {
	// you can not nix tre ltr ids
	return &canceler{
		healer:  healer,
		obs:     obs,
		wbr:     wbr,
		azp:     rps,
		hyd:     hyd,
		ghTwirp: ghTwirp,
	}
}

func (c *canceler) Cancel(ctx context.Context, wf *deployer.WorkflowBuildState, opts *azp.CancelOptions) error {
	fields := []kvp.Field{
		kvp.String("gh.repo.global_id", wf.RepositoryID.String()),
		kvp.Int64("gh.launch.workflow_build.id", wf.DatabaseID),
		kvp.String("gh.launch.external_build.id", wf.ExternalBuildID),
	}

	if opts != nil && opts.ActorName != nil {
		fields = append(fields, kvp.String("gh.actor.name", *opts.ActorName), kvp.Bool("gh.launch.cancel_event.forced", opts.Force))
	}

	c.obs.Log(ctx, "cancelling check suite", fields...)

	recordCancelResult := func(status string, cancelFailureReason string) {
		c.obs.Counter(ctx, "workflow.cancel", statter.Tags{
			"status": status,
		}, 1)

		ts := timestamppb.New(time.Now())

		id, err := graphqlid.DecodeInt64ID(wf.RepositoryID.String())
		if err != nil {
			c.obs.Report(ctx, errs.Wrap(err, "failed to decode repo ID for cancel hydro"))
			// preferable to send the message anyhow
			id = 0
		}

		// TODO once https://github.com/github/pe-actions-service/issues/255 lands, we'll want to
		// send the conclusion we self heal to
		c.hyd.EmitWorkflowCancelRequest(&hydroV0.WorkflowCancelRequest{
			RequestedAt:                ts,
			ExternalProviderReference:  wf.ExternalBuildID,
			WorkflowBuildId:            uint64(wf.DatabaseID),
			WorkflowRepositoryGlobalId: wf.RepositoryID.String(),
			WorkflowRepositoryId:       uint64(id),
			CheckSuiteGlobalId:         wf.CheckSuiteID.String(),
			CancelFailureReason:        cancelFailureReason,
		})
	}

	// we validate this afterwards because we may receive requests to cancel builds between
	// time check suite is created and build is queued (or when the build queue goes on to fail)
	if wf.ExternalBuildID == "" {
		recordCancelResult(statusFailure, notRequested)
		return errs.New("unable to cancel this workflow, external build identifier is empty")
	}

	client, err := c.azp.ClientFromRepoGID(ctx, wf.RepositoryID)
	if err != nil {
		recordCancelResult(statusFailure, notRequested)
		return errs.Wrap(err, "could not get repo client")
	}

	if err = client.Cancel(ctx, wf.ExternalBuildID, opts); err != nil {
		recordCancelResult(statusFailure, cancelFailed)
		return errs.Wrap(err, "unable to cancel AZP build")
	}

	recordCancelResult(statusSuccess, healingSkipped)
	return nil
}
