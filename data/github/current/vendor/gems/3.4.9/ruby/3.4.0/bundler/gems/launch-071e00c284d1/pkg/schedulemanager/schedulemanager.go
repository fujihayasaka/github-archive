package schedulemanager

import (
	"context"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/go-kvp"
	"github.com/golang/protobuf/ptypes/empty"
	errs "github.com/pkg/errors"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/db/stores/schedules"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/tiers"
	"github.com/github/launch/services/deploy/scheduled/model"
	"github.com/github/launch/services/deploy/workflowinvoker"
	"github.com/github/launch/services/errors"
	"github.com/github/launch/services/pbtypes/launchtypes"
	"github.com/github/launch/types"
	"github.com/github/launch/utils"
	"github.com/github/launch/workflowparser"
)

const (
	scheduledRepoKey = "scheduled.repo"
)

type service struct {
	cfg                *Config
	obs                *observability.Observability
	store              schedules.Store
	clientFactory      github.Factory
	githubTwirpClient  ghtwirp.Client
	azpResourcesRepo   deployer.AzpResourcesRepository
	workflowSrcFactory workflowinvoker.WorkflowSourceFactory
}

type Config struct {
	Environment       launchconfig.AppEnv
	IsEnterprise      bool
	EnterpriseVersion string
}

func New(cfg *Config, obs *observability.Observability, store schedules.Store, factory github.Factory, githubTwirpClient ghtwirp.Client, azpResourcesRepo deployer.AzpResourcesRepository, workflowSrcFactory workflowinvoker.WorkflowSourceFactory) Manager {
	return &service{
		cfg:                cfg,
		obs:                obs,
		store:              store,
		clientFactory:      factory,
		githubTwirpClient:  githubTwirpClient,
		azpResourcesRepo:   azpResourcesRepo,
		workflowSrcFactory: workflowSrcFactory,
	}
}

type Manager interface {
	SyncOnPush(ctx context.Context,
		repoGID types.GlobalID,
		ref types.GitRef,
		actorGID types.GlobalID,
		ownerID int64,
	)
	NotifyRepository(ctx context.Context, event *launchtypes.NotifyRepositoryEvent) (*empty.Empty, error)
	DeleteSchedules(ctx context.Context, request *launchtypes.DeleteSchedulesRequest) (*launchtypes.DeleteSchedulesResponse, error)
	DisableScheduledWorkflow(ctx context.Context, request *launchtypes.DisableScheduledWorkflowRequest) (*empty.Empty, error)
	SynchronizeScheduledWorkflows(ctx context.Context, request *launchtypes.SynchronizeScheduledWorkflowsRequest) (*empty.Empty, error)
	ListSchedules(ctx context.Context, request *launchtypes.ListSchedulesRequest) (*launchtypes.ListSchedulesResponse, error)
}

// SyncOnPush synchronises schedules after a push event. Pass the fullRef (e.g `refs/heads...`) rather
// than ref name
func (s *service) SyncOnPush(ctx context.Context,
	repoGID types.GlobalID,
	ref types.GitRef,
	actorGID types.GlobalID,
	ownerID int64,
) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.launch.operation.name", "SyncOnPush"),
		kvp.String("gh.repo.global_id", repoGID.String()),
		kvp.String("gh.actor.global_id", actorGID.String()),
		kvp.String("gh.launch.event.ref", ref.String()),
		kvp.Int64("gh.launch.owner.id", ownerID),
	)
	s.obs.Counter(ctx, "scheduled.SyncOnPush", nil, 1)

	err := s.RunScheduleSync(ctx, repoGID, ref, actorGID, ownerID)
	if err != nil {
		s.obs.Report(ctx, mysqldb.RollupDBError(errs.Wrap(err, "failed to sync schedule data for repo")))
		return
	}

	s.obs.Log(ctx, "schedule sync complete")
}

func (s *service) RunScheduleSync(ctx context.Context, repoGID types.GlobalID, ref types.GitRef, actorGID types.GlobalID, ownerID int64) error {
	s.obs.Debug(ctx, "syncing schedule now")

	// Check if the user is spammy and if they are, don't sync the workflows.
	b := backoff.WithMaxRetries(backoff.NewConstantBackOff(500*time.Millisecond), 3)

	var isSpammy bool

	if !s.cfg.IsEnterprise {
		err := backoff.Retry(func() error {
			res, err := s.githubTwirpClient.IsUserSpammy(ctx, actorGID)
			if err != nil {
				return err
			}
			isSpammy = res
			return nil
		}, b)
		if err != nil {
			// Don't bail out but do throw a needle
			s.obs.Report(ctx, errs.Wrap(err, "error checking if user is spammy"))
		}
	}

	if isSpammy {
		s.obs.Log(ctx, "found known spammy/suspended user, skipping schedule sync")
		return nil
	}

	client, err := s.clientFactory.NewClientForRepositoryOwnerDatabaseID(ctx, repoGID, ownerID)
	if err != nil {
		return errs.Wrap(err, "failed to create github client for repository owner")
	}

	scheduleData, err := client.GetRepositoryScheduleData(
		ctx,
		repoGID,
		ref,
		actorGID,
		s.cfg.Environment,
	)
	if err != nil {
		return errs.Wrap(err, "failed to load schedule data for repo")
	}
	if scheduleData.DefaultBranchFullRef != ref.String() && ref != types.DefaultBranch {
		return nil
	}
	s.obs.Counter(ctx, "scheduled.changed", nil, 1)
	err = s.runSync(
		ctx,
		repoGID,
		scheduleData.ActorGID,
		scheduleData.ActorLogin,
		&scheduleData.RepositoryScheduleState,
		ownerID,
	)
	return err
}

func (s *service) NotifyRepository(ctx context.Context, event *launchtypes.NotifyRepositoryEvent) (*empty.Empty, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	repoGID := types.IdentityToGlobalID(ctx, event.GetRepositoryNodeId())

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.repo.global_id", repoGID.String()),
		kvp.String("gh.launch.event.name", event.GetAction()),
		kvp.String("gh.actor.global_id", event.GetActorNodeId()),
	)

	var err error

	s.obs.Debug(ctx, "executing sync for NotifyRepository", kvp.String("gh.launch.event.type", event.Action))

	switch event.Action {
	case "unarchived":
		s.obs.Counter(ctx, scheduledRepoKey, statter.Tags{"event": "unarchived"}, 1)
		err = s.syncToCurrent(ctx, repoGID, event)
	case "edited":
		if event.GetDefaultBranchChanged() {
			s.obs.Counter(ctx, scheduledRepoKey, statter.Tags{"event": "defaultBranchChange"}, 1)
			err = s.syncToCurrent(ctx, repoGID, event)
		}
	case "deleted":
		s.obs.Counter(ctx, scheduledRepoKey, statter.Tags{"event": "deleted"}, 1)
		err = s.removeSchedules(ctx, repoGID)
	case "archived":
		s.obs.Counter(ctx, scheduledRepoKey, statter.Tags{"event": "archived"}, 1)
		err = s.removeSchedules(ctx, repoGID)
	case "transferred":
		// When a repo is transferred, the installation the app and the owner of the repo is changed so we need to update
		// the schedules.
		s.obs.Counter(ctx, scheduledRepoKey, statter.Tags{"event": "transferred"}, 1)
		err = s.syncToCurrent(ctx, repoGID, event)
	}

	if err != nil {
		s.obs.Report(ctx, errs.Wrap(err, "failed in notify repository"), kvp.String("gh.launch.event.type", event.Action))
		return nil, errors.NewInternalError(err.Error())
	}

	return &empty.Empty{}, nil
}

func (s *service) runSync(ctx context.Context,
	repoGID types.GlobalID,
	actorGID types.GlobalID,
	actorLogin string,
	state *github.RepositoryScheduleState,
	ownerID int64,
) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	// workflow_identifier stores the cron
	flowIdentifierToSchedule := map[types.WorkflowSelector]string{}
	invalidWorkflowfiles := make([]string, 0)

	// WorkflowSource is used to fetch the called workflow files
	// since we parse only cron expressions in caller workflows, passing wfSrc as NullWorkflowSource
	var wfSrc workflowparser.WorkflowSource = workflowparser.NullWorkflowSource{}

	runtimeHelper := utils.NewRuntimeHelper(s.cfg.IsEnterprise, s.cfg.EnterpriseVersion)
	_, actorID, err := actorGID.Decode()
	if err != nil {
		s.obs.Error(ctx, "Failed to decode actor global ID", kvp.Err(err))
	}

	for _, pl := range state.PipelineFiles {
		parsed, err := workflowparser.Parse(
			ctx,
			pl,
			state.WorkflowFeatureFlags,
			wfSrc,
			runtimeHelper,
			actorID,
			s.obs,
		)
		if err != nil {
			invalidWorkflowfiles = append(invalidWorkflowfiles, pl.Path)
			continue
		}
		for _, expression := range parsed.GetCronExpressions() {
			flowIdentifierToSchedule[types.WorkflowSelector{
				WorkflowPath: pl.Path,
				Identifier:   expression,
			}] = expression
		}
	}

	var tier types.RepositoryTier
	if s.cfg.IsEnterprise {
		tier = types.RepositoryTier1
	} else {
		var err error
		tier, err = tiers.FetchRepositoryTier(ctx, s.obs.Logger, s.githubTwirpClient, repoGID)
		if err != nil {
			// There was some issue getting the tier from dotcom. Not fatal, we just default to tier 3
			s.obs.Report(ctx, errs.Wrap(err, "Failed in fetching repository tier"))
		}
	}

	update := model.ScheduleSync{
		RepoNodeID:                repoGID,
		FlowIdentifiersToSchedule: flowIdentifierToSchedule,
		ActorID:                   actorGID,
		ActorLogin:                actorLogin,
		CommitSHA:                 state.CurrentHeadSHA,
		InvalidFiles:              invalidWorkflowfiles,
		Tier:                      tier,
		OwnerID:                   ownerID,
	}

	err = s.store.PersistUpdate(ctx, update)
	if err != nil {
		return errs.Wrap(err, "failed to sync schedule data")
	}

	s.obs.Counter(ctx, "scheduled.synced", nil, 1)

	return nil
}

func (s *service) removeSchedules(ctx context.Context, repoGID types.GlobalID) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	err := s.store.RemoveSchedules(ctx, repoGID)
	if err != nil {
		return errs.Wrap(err, "failed to remove schedules")
	}

	return nil
}

func (s *service) syncToCurrent(ctx context.Context, repoGID types.GlobalID, event *launchtypes.NotifyRepositoryEvent) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ownerDatabaseID := event.GetOwnerDatabaseId()

	client, err := s.clientFactory.NewClientForRepositoryOwnerDatabaseID(ctx, repoGID, ownerDatabaseID)
	if err != nil {
		return errs.Wrap(err, "failed to create github client for repository owner")
	}

	state, err := client.GetCurrentScheduleState(ctx, repoGID, s.cfg.Environment)
	if err != nil {
		return errs.Wrap(err, "failed to retrieve schedule state")
	}

	err = s.runSync(
		ctx,
		repoGID,
		types.NewGlobalID(ctx, event.GetActorNodeId()),
		event.GetActorLogin(),
		state,
		ownerDatabaseID,
	)
	if err != nil {
		return errs.Wrap(err, "failed to sync schedule state")
	}

	return nil
}
