package hydrosvc

import (
	"context"
	"fmt"
	"time"

	"github.com/github/go-kvp"
	ghstats "github.com/github/go-stats"
	hydroschemas "github.com/github/hydro-client-go/v3/generated/hydro/schemas/hydro/v1"
	"github.com/github/hydro-client-go/v3/pkg/hydro"
	"github.com/gogo/protobuf/proto"
	"github.com/pkg/errors"
	"github.com/redis/go-redis/v9"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/launchredis"
	"github.com/github/launch/clients/launchtwirp"
	ghschemasV0 "github.com/github/launch/hydro/schemas/github/actions/v0"
	ghschemas "github.com/github/launch/hydro/schemas/github/v1"
	ghentities "github.com/github/launch/hydro/schemas/github/v1/entities"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/reqobs"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/abreaker"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/services/deploy/adminevents"
	"github.com/github/launch/services/hydrosvc/config"
	"github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/services/pbtypes"
	"github.com/github/launch/services/pbtypes/launchtypes"
	"github.com/github/launch/utils/ahttp"
	"github.com/github/launch/utils/apphttp"
)

const (
	AbuseClassification                  = "cp1-iad.ingest.github.v1.AbuseClassification"
	InvocationBlockedTopic               = "cp1-iad.ingest.github.actions.v0.InvocationBlocked"
	InvocationUnblockedTopic             = "github.actions.v0.InvocationUnblocked"
	OrganizationRestoreTopic             = "github.v1.OrganizationRestore"
	RepositoryDeletedTopic               = "cp1-iad.ingest.github.v1.RepositoryDeleted"
	RepositoryArchivedStatusChangedTopic = "cp1-iad.ingest.github.v1.RepositoryArchivedStatusChanged"
	RepositoryRestoredTopic              = "cp1-iad.ingest.github.v1.RepositoryRestored"
	RepositoryTransferTopic              = "cp1-iad.ingest.github.v1.RepositoryTransfer"
	UserDestroyTopic                     = "cp1-iad.ingest.github.v1.UserDestroy"
	WorkflowStateChangeTopic             = "cp1-iad.ingest.github.actions.v0.WorkflowStateChange"
)

var topics = []string{
	AbuseClassification,
	InvocationBlockedTopic,
	InvocationUnblockedTopic,
	OrganizationRestoreTopic,
	RepositoryArchivedStatusChangedTopic,
	RepositoryDeletedTopic,
	RepositoryRestoredTopic,
	RepositoryTransferTopic,
	UserDestroyTopic,
	WorkflowStateChangeTopic,
}

// Service wraps a Hydro consumer and runs it as a Go service.
type Service struct {
	hydroSource   hydro.Source
	topics        []string
	log           logger.Logger
	stats         ghstats.Client
	ghTwirpClient ghtwirp.Client
	deployer      deploy.LaunchDeploymentService
	launchEnv     string
}

// New returns a new instance of the hydro service.
func New(ctx context.Context, cfg *config.Config, obs *observability.Observability) (*Service, error) {
	topics := topics

	golog := logger.AdaptToFieldLogger(ctx, obs.Logger)
	kc, err := cfg.NewKafkaConfig(golog, obs.Statter.Client())
	if err != nil {
		return nil, errors.Wrap(err, "error creating kafka config")
	}

	hydroSource, err := hydro.NewKafkaSource(*kc, cfg.KafkaGroup, topics)
	if err != nil {
		return nil, errors.Wrap(err, "error creating kafka source")
	}

	// Set up a github twirp client.
	var redisClient redis.UniversalClient
	if cfg.RedisConfig.RedisURL != "" {
		redisClient, err = launchredis.New(ctx, cfg.RedisConfig, obs)
		if err != nil {
			return nil, err
		}
	}
	breaker, err := abreaker.NewRedisBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return nil, errors.Wrap(err, "error creating redis breaker")
	}
	cache := launchcache.NewSharedCache(redisClient, breaker, cfg.CacheConfig, obs)
	githubTwirpBreaker, err := abreaker.NewGithubTwirpClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return nil, errors.Wrap(err, "error creating ghtwirp circuit breaker")
	}

	twirpTelemetry := reqobs.NewTwirpMetricsHooks(obs.Statter)
	twirpOpts := reqobs.AdaptTwirpHooksToClientOptions(twirpTelemetry, time.Now)
	var ghTwirpClient ghtwirp.Client
	ghTwirpClient, err = ghtwirp.NewClient(
		cfg.GitHubTwirpAddr,
		cfg.GitHubTwirpHMACSecret,
		obs,
		cfg.LaunchEnv,
		cache.GitHubTwirp(),
		ahttp.NewRetryClient(
			githubTwirpBreaker,
			obs.Statter,
			//nolint:gocritic
			apphttp.NewClient(apphttp.WithObservability(obs, cfg.RoundTripperConfig)),
			"ghtwirp"),
		twirpOpts,
		launchconfig.IsMultiTenant(),
	)
	if err != nil {
		return nil, errors.Wrap(err, "error creating ghtwirp client")
	}

	if cfg.IsEnterprise() {
		ghTwirpClient = ghtwirp.NewEnterpriseClient(ghTwirpClient)
	}

	// Twirp Deployer Client
	deployerTwirpBreaker, err := abreaker.NewDeployerTwirpClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return nil, errors.Wrap(err, "error creating twirp client breaker")
	}

	defaultOpts := []apphttp.Option{apphttp.WithObservability(obs, cfg.RoundTripperConfig), apphttp.WithMaxTimeout(time.Second * 35)}
	twirpClient, err := launchtwirp.NewClient([]string{cfg.DeployerHMACSigningSecret}, deployerTwirpBreaker, obs.Statter, apphttp.NewClient(defaultOpts...))
	if err != nil {
		return nil, errors.Wrap(err, "error creating launchtwirp client")
	}

	deployerClient := deploy.NewLaunchDeploymentServiceProtobufClient(cfg.DeployerTwirpAddr, twirpClient, twirpOpts...)

	return &Service{
		log:           obs.Logger,
		stats:         obs.Statter.Client(),
		topics:        topics,
		hydroSource:   hydroSource,
		ghTwirpClient: ghTwirpClient,
		deployer:      deployerClient,
		launchEnv:     cfg.LaunchEnv,
	}, nil
}

func NewTestService(ghTwirpClient ghtwirp.Client, deployerClient deploy.LaunchDeploymentService) *Service {
	return &Service{
		ghTwirpClient: ghTwirpClient,
		deployer:      deployerClient,
		log:           logger.NullLogger(),
		stats:         &ghstats.NullClient{},
	}
}

func (s *Service) handleRepositoryDeletedMessage(ctx context.Context, msg *ghschemas.RepositoryDeleted) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	repo := msg.GetDeletedRepository()
	repoGIDString := repo.GetGlobalRelayId()
	repoGlobalID, err := s.ghTwirpClient.GetNextGlobalID(ctx, repoGIDString)
	if err != nil {
		s.log.Report(ctx, errors.Wrap(err, "error getting next global ID for repository deleted"), kvp.String("gh.repo.global_id", repoGIDString))
		return
	}
	s.logGlobalIDReplacement(ctx, adminevents.RepositoryDeleted, repoGIDString, repoGlobalID.String())
	repoGIDString = repoGlobalID.String()

	// Try to cancel any in-progress workflow runs
	s.log.Debug(ctx, "cancelling any in-progress workflows for deleted repository", kvp.String("gh.repo.global_id", repoGIDString))
	workflowCancelReq := &deploy.WorkflowCancelAllRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: repoGIDString,
		},
		Name:      repo.GetName(),
		EventType: adminevents.RepositoryDeleted,
	}

	_, err = s.deployer.WorkflowCancelAll(ctx, workflowCancelReq)

	if err != nil {
		s.log.Report(ctx, err, kvp.String("gh.repo.global_id", repoGIDString))
	} else {
		s.log.Debug(ctx, "successfully cancelled workflows", kvp.String("gh.repo.global_id", repoGIDString))
	}
}

func (s *Service) handleRepositoryRestoredMessage(ctx context.Context, msg *ghschemas.RepositoryRestored) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	restoredRepo := msg.GetRestoredRepository()
	repoGIDString := restoredRepo.GetGlobalRelayId()
	repoGlobalID, err := s.ghTwirpClient.GetNextGlobalID(ctx, repoGIDString)
	if err != nil {
		s.log.Report(ctx, errors.Wrap(err, "error getting next global ID for repository restored"), kvp.String("gh.repo.global_id", repoGIDString))
		return
	}
	s.logGlobalIDReplacement(ctx, adminevents.BillingOwnerRestored, repoGIDString, repoGlobalID.String())
	repoGIDString = repoGlobalID.String()

	// Check if the repository is spammy or actions usage is not allowed.
	billingDetail, err := s.ghTwirpClient.GetBillingDetails(ctx, repoGlobalID)
	if err != nil {
		s.log.Report(ctx, errors.Wrap(err, "error getting billing details for repository restored"), kvp.String("gh.repo.global_id", repoGIDString))
		return
	}

	if billingDetail.IsOwnerSpammy {
		s.log.Debug(ctx, "skipping repository restore event for spammy repository owner",
			kvp.String("gh.repo.global_id", repoGIDString),
			kvp.Bool("gh.launch.owner.spammy", billingDetail.IsOwnerSpammy))
		return
	}

	// Get the repository owners.
	repoOwner, err := s.ghTwirpClient.GetRepositoryOwners(ctx, int64(restoredRepo.Id))
	if err != nil {
		s.log.Report(ctx, errors.Wrap(err, "error getting repository owners"),
			kvp.String("gh.repo.global_id", repoGIDString),
			kvp.Int64("gh.repo.id", int64(restoredRepo.Id)))
		return
	}

	billingOwner := repoOwner.Owner
	if repoOwner.Business != nil {
		billingOwner = *repoOwner.Business
	}

	// Let Action service know that the repository has been restored.
	s.log.Debug(ctx, "Enable billing owner to process workflows for restored repository",
		kvp.String("gh.repo.global_id", repoGIDString),
		kvp.String("gh.billing.owner.global_id", billingOwner.GlobalID.String()),
		kvp.String("gh.billing.owner.type", billingOwner.Type))

	req := &deploy.ReportAdminEventForBillingOwnerRequest{
		OwnerId:       billingOwner.ID,
		OwnerName:     billingOwner.Name,
		OwnerGlobalId: billingOwner.GlobalID.String(),
		AdminEvent:    adminevents.BillingOwnerRestored,
	}

	_, err = s.deployer.ReportAdminEventForBillingOwner(ctx, req)

	if err != nil {
		s.log.Report(ctx, errors.Wrap(err, "error reporting repository restored on the billing owner level"),
			kvp.String("gh.repo.global_id", repoGIDString),
			kvp.String("gh.billing.owner.global_id", billingOwner.GlobalID.String()))
		return
	}

	s.log.Debug(ctx, "successfully report repository restored to billing owner", kvp.String("gh.repo.global_id", repoGIDString))
}

func (s *Service) handleInvocationBlockedMessage(ctx context.Context, msg *ghschemasV0.InvocationBlocked) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	reason := "action invocation blocked"
	account := msg.GetAccount()
	if account == nil {
		err := errors.New("invocation blocked message has a nil account")
		s.log.Report(ctx, err)
		return
	}

	actorGIDString := account.GetGlobalRelayId()
	actorGlobalID, err := s.ghTwirpClient.GetNextGlobalID(ctx, actorGIDString)
	if err != nil {
		s.log.Report(ctx, errors.Wrap(err, "error getting owner next global ID for invocation blocked"), kvp.String("gh.launch.owner.global_id", actorGIDString))
		return
	}
	s.logGlobalIDReplacement(ctx, adminevents.OwnerInvocationBlocked, actorGIDString, actorGlobalID.String())
	actorGIDString = actorGlobalID.String()

	req := &deploy.ReportAdminEventForOwnerReposRequest{
		OwnerName:     account.Login,
		OwnerId:       int64(account.Id),
		OwnerGlobalId: actorGIDString,
		AdminEvent:    adminevents.OwnerInvocationBlocked,
		Data:          reason,
	}

	_, err = s.deployer.ReportAdminEventForOwnerRepos(ctx, req)

	if err != nil {
		s.log.Report(ctx, errors.Wrap(err, "error reporting blocked owner"), kvp.String("gh.launch.owner.global_id", actorGIDString))
		return
	}
	s.log.Log(ctx, "successfully reported blocked owner", kvp.String("gh.launch.owner.global_id", actorGIDString))

	s.log.Debug(ctx, "report invocation blocked on the billing owner level", kvp.String("gh.launch.owner.global_id", actorGIDString))

	request := &deploy.ReportAdminEventForBillingOwnerRequest{
		OwnerName:     account.Login,
		OwnerId:       int64(account.Id),
		OwnerGlobalId: actorGIDString,
		AdminEvent:    adminevents.OwnerInvocationBlocked,
	}

	_, err = s.deployer.ReportAdminEventForBillingOwner(ctx, request)

	if err != nil {
		s.log.Report(ctx, errors.New("error reporting invocation blocked on the billing owner level"), kvp.String("gh.launch.owner.global_id", actorGIDString), kvp.Err(err))
	} else {
		s.log.Log(ctx, "successfully reported invocation blocked on the billing owner level", kvp.String("gh.launch.owner.global_id", actorGIDString))
	}

	workflowCancelReq := &deploy.WorkflowCancelAllForNonOwnerReposRequest{
		ActorName: account.Login,
		ActorId:   int64(account.Id),
		ActorGlobalId: &pbtypes.Identity{
			GlobalId: actorGIDString,
		},
		Data: reason,
	}

	result, err := s.deployer.WorkflowCancelAllForNonOwnerRepos(ctx, workflowCancelReq)

	if err != nil {
		s.log.Report(ctx, errors.New("error cancelling workflows for repos not owned by blocked actor"), kvp.String("gh.actor.global_id", actorGIDString), kvp.Err(err))
		return
	}

	s.log.Log(ctx, "successfully cancelled workflows for repos not owned by blocked actor", kvp.String("gh.actor.global_id", actorGIDString), kvp.Int64("gh.launch.workflow.cancelled_count", result.GetWorkflowCount()))
}

func (s *Service) handleInvocationUnblockedMessage(ctx context.Context, msg *ghschemasV0.InvocationUnblocked) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	account := msg.GetAccount()
	if account == nil {
		err := errors.New("invocation unblocked message has a nil account")
		s.log.Report(ctx, err)
		return
	}

	actorGIDString := account.GetGlobalRelayId()
	actorGlobalID, err := s.ghTwirpClient.GetNextGlobalID(ctx, actorGIDString)
	if err != nil {
		s.log.Report(ctx, errors.Wrap(err, "error getting owner next global ID for invocation unblocked"), kvp.String("gh.launch.owner.global_id", actorGIDString))
		return
	}
	s.logGlobalIDReplacement(ctx, adminevents.OwnerInvocationUnblocked, actorGIDString, actorGlobalID.String())
	actorGIDString = actorGlobalID.String()

	s.log.Debug(ctx, "report invocation unblocked on the billing owner level", kvp.String("gh.launch.owner.global_id", actorGIDString))

	req := &deploy.ReportAdminEventForBillingOwnerRequest{
		OwnerName:     account.Login,
		OwnerId:       int64(account.Id),
		OwnerGlobalId: actorGIDString,
		AdminEvent:    adminevents.OwnerInvocationUnblocked,
	}

	_, err = s.deployer.ReportAdminEventForBillingOwner(ctx, req)

	if err != nil {
		s.log.Report(ctx, errors.New("error reporting invocation unblocked on the billing owner level"), kvp.String("gh.launch.owner.global_id", actorGIDString), kvp.Err(err))
	} else {
		s.log.Log(ctx, "successfully reported invocation unblocked on the billing owner level", kvp.String("gh.launch.owner.global_id", actorGIDString))
	}
}

func (s *Service) handleWorkflowStateChangeMessage(ctx context.Context, msg *ghschemasV0.WorkflowStateChange) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	workflowID := int(msg.GetWorkflowId())
	repository := msg.GetRepository()
	workflowPath := msg.GetWorkflowFilePath()
	workflowState := msg.GetWorkflowState()
	actor := msg.GetActor()

	kvpWorkflowID := kvp.Int("gh.launch.workflow.id", workflowID)

	actorGIDString := actor.GetGlobalRelayId()
	actorGlobalID, err := s.ghTwirpClient.GetNextGlobalID(ctx, actorGIDString)
	if err != nil {
		s.log.Report(ctx, errors.Wrap(err, "error getting actor next global ID for workflow state changed"), kvp.String("gh.launch.owner.global_id", actorGIDString))
		return
	}
	s.logGlobalIDReplacement(ctx, "WorkflowStateChange", actorGIDString, actorGlobalID.String())
	actorGIDString = actorGlobalID.String()

	repoGIDString := repository.GetGlobalRelayId()
	repoGlobalID, err := s.ghTwirpClient.GetNextGlobalID(ctx, repoGIDString)
	if err != nil {
		s.log.Report(ctx, errors.Wrap(err, "error getting repo next global ID for workflow state changed"), kvp.String("gh.repo.global_id", repoGIDString))
		return
	}
	s.logGlobalIDReplacement(ctx, "WorkflowStateChange", repoGIDString, repoGlobalID.String())
	repoGIDString = repoGlobalID.String()

	if workflowState == ghschemasV0.WorkflowStateChange_ACTIVE {
		// synchronize scheduled workflows, this re-creates any scheduled workflows that were previously deleted
		synchronizeRequest := &launchtypes.SynchronizeScheduledWorkflowsRequest{
			Ref: msg.GetBranchRef(),
			RepositoryNodeId: &pbtypes.Identity{
				GlobalId: repoGIDString,
			},
			InstallationId: int64(msg.GetInstallationId()),
			ActorNodeId: &pbtypes.Identity{
				GlobalId: actorGIDString,
			},
			OwnerDatabaseId: int64(repository.GetOwnerId().Value),
		}

		s.log.Debug(ctx, "attempting to synchronize scheduled workflow", kvpWorkflowID)
		_, err = s.deployer.SynchronizeScheduledWorkflows(ctx, synchronizeRequest)

		if err != nil {
			s.log.Report(ctx, err, kvpWorkflowID)
		} else {
			s.log.Debug(ctx, "successfully synchronized scheduled workflow", kvpWorkflowID)
		}
	} else {
		// disable a scheduled workflow by deleting all entries for it
		disableRequest := &launchtypes.DisableScheduledWorkflowRequest{
			Environment: msg.GetEnvironment(),
			RepositoryNodeId: &pbtypes.Identity{
				GlobalId: repoGIDString,
			},
			WorkflowFilePath: workflowPath,
		}

		s.log.Debug(ctx, "attempting to delete scheduled workflow", kvpWorkflowID)
		_, err = s.deployer.DisableScheduledWorkflow(ctx, disableRequest)

		if err != nil {
			s.log.Report(ctx, err, kvpWorkflowID)
		} else {
			s.log.Debug(ctx, "successfully disabled workflow", kvpWorkflowID)
		}
	}
}

func (s *Service) handleRepositoryTransferMessage(ctx context.Context, msg *ghschemas.RepositoryTransfer) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	repo := msg.GetRepository()
	repoGIDString := repo.GetGlobalRelayId()
	repoGlobalID, err := s.ghTwirpClient.GetNextGlobalID(ctx, repoGIDString)
	if err != nil {
		s.log.Report(ctx, errors.Wrap(err, "error getting repo next global ID for repository transfer"), kvp.String("gh.repo.global_id", repoGIDString))
		return
	}
	s.logGlobalIDReplacement(ctx, adminevents.RepositoryTransferred, repoGIDString, repoGlobalID.String())
	repoGIDString = repoGlobalID.String()

	// Only react to immediate or responded to transfers
	if msg.Criteria != ghschemas.RepositoryTransfer_IMMEDIATE && (msg.Criteria != ghschemas.RepositoryTransfer_REQUEST || msg.State != ghschemas.RepositoryTransfer_RESPONDED) {
		s.log.Debug(ctx, "ignoring repository transfer message, not an immediate transfer or not yet responded", kvp.String("gh.repo.global_id", repoGIDString))
		return
	}

	// Try to cancel any in-progress workflow runs
	s.log.Debug(ctx, "cancelling any in-progress workflows for transferred repository", kvp.String("gh.repo.global_id", repoGIDString))
	workflowCancelReq := &deploy.WorkflowCancelAllRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: repoGIDString,
		},
		Name:      repo.GetName(),
		EventType: adminevents.RepositoryTransferred,
	}

	_, err = s.deployer.WorkflowCancelAll(ctx, workflowCancelReq)

	if err != nil {
		s.log.Report(ctx, err, kvp.String("gh.repo.global_id", repoGIDString))
	} else {
		s.log.Debug(ctx, "successfully cancelled workflows", kvp.String("gh.repo.global_id", repoGIDString))
	}
}

func (s *Service) handleRepositoryArchivedStatusChangedMessage(ctx context.Context, msg *ghschemas.RepositoryArchivedStatusChanged) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	if msg.IsArchived {
		repoGIDString := msg.GetRepositoryGlobalId()
		if repoGIDString == "" {
			s.log.Report(ctx, errors.New("missing repository global id"), kvp.String("gh.repo.global_id", repoGIDString))
			return
		}

		repoGlobalID, err := s.ghTwirpClient.GetNextGlobalID(ctx, repoGIDString)
		if err != nil {
			s.log.Report(ctx, errors.New("error getting repo next global ID for archive status change"), kvp.String("gh.repo.global_id", repoGIDString))
			return
		}
		s.logGlobalIDReplacement(ctx, adminevents.RepositoryArchived, repoGIDString, repoGlobalID.String())
		repoGIDString = repoGlobalID.String()

		// Try to cancel any in-progress workflow runs
		s.log.Debug(ctx, "cancelling any in-progress workflows for archived repository", kvp.String("gh.repo.global_id", repoGIDString))
		workflowCancelReq := &deploy.WorkflowCancelAllRequest{
			RepositoryId: &pbtypes.Identity{
				GlobalId: repoGIDString,
			},
			EventType: adminevents.RepositoryArchived,
		}

		_, err = s.deployer.WorkflowCancelAll(ctx, workflowCancelReq)

		if err != nil {
			s.log.Report(ctx, err, kvp.String("gh.repo.global_id", repoGIDString))
		} else {
			s.log.Debug(ctx, "successfully cancelled workflows", kvp.String("gh.repo.global_id", repoGIDString))
		}
	}
}

func (s *Service) handleAbuseClassificationMessage(ctx context.Context, msg *ghschemas.AbuseClassification) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	account := msg.GetAccount()
	if account == nil {
		err := errors.New("abuse classification message has a nil account")
		s.log.Report(ctx, err)
		return
	}

	actorGIDString := account.GetGlobalRelayId()
	actorGlobalID, err := s.ghTwirpClient.GetNextGlobalID(ctx, actorGIDString)
	if err != nil {
		s.log.Report(ctx, errors.Wrap(err, "error getting owner next global ID for abuse classification"), kvp.String("gh.launch.owner.global_id", actorGIDString))
		return
	}
	s.logGlobalIDReplacement(ctx, "AbuseClassification", actorGIDString, actorGlobalID.String())
	actorGIDString = actorGlobalID.String()

	if !account.GetSpammy() {
		s.handleUnmarkedSpammyReporting(ctx, account, msg.GetPreviousClassification())
		return
	}

	spammyReason := msg.GetCurrentSpammyReason().Value
	s.handleMarkedSpammyReporting(ctx, account, spammyReason)

	workflowCancelReq := &deploy.WorkflowCancelAllForNonOwnerReposRequest{
		ActorName: account.Login,
		ActorId:   int64(account.Id),
		ActorGlobalId: &pbtypes.Identity{
			GlobalId: actorGIDString,
		},
		Data: spammyReason,
	}

	result, err := s.deployer.WorkflowCancelAllForNonOwnerRepos(ctx, workflowCancelReq)

	if err != nil {
		s.log.Report(ctx, errors.New("error cancelling workflows for repos not owned by spammy actor"), kvp.String("gh.actor.global_id", actorGIDString), kvp.Err(err))
	} else {
		s.log.Log(ctx, "successfully cancelled workflows for repos not owned by spammy actor", kvp.String("gh.actor.global_id", actorGIDString), kvp.Int64("gh.launch.workflow.cancelled_count", result.GetWorkflowCount()))
	}
}

func (s *Service) handleMarkedSpammyReporting(ctx context.Context, account *ghentities.User, spammyReason string) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	actorGIDString := account.GetGlobalRelayId()
	actorGlobalID, err := s.ghTwirpClient.GetNextGlobalID(ctx, actorGIDString)
	if err != nil {
		s.log.Report(ctx, errors.New("error getting repo next global ID for owner marked spammy"), kvp.String("gh.launch.owner.global_id", actorGIDString))
		return
	}
	s.logGlobalIDReplacement(ctx, adminevents.OwnerMarkedAsSpammy, actorGIDString, actorGlobalID.String())
	actorGIDString = actorGlobalID.String()

	// report on repo level for each repo associated with this account

	req := &deploy.ReportAdminEventForOwnerReposRequest{
		OwnerName:     account.Login,
		OwnerId:       int64(account.Id),
		OwnerGlobalId: actorGIDString,
		AdminEvent:    adminevents.OwnerMarkedAsSpammy,
		Data:          spammyReason,
	}

	_, err = s.deployer.ReportAdminEventForOwnerRepos(ctx, req)

	if err != nil {
		s.log.Report(ctx, errors.Wrap(err, "error reporting owner as spammy"), kvp.String("gh.actor.global_id", actorGIDString))
	} else {
		s.log.Log(ctx, "successfully reported owner as spammy.", kvp.String("gh.actor.global_id", actorGIDString))
	}

	// report on owner level
	s.log.Debug(ctx, "report owner marked spammy on the billing owner level", kvp.String("gh.launch.owner.global_id", actorGIDString))

	request := &deploy.ReportAdminEventForBillingOwnerRequest{
		OwnerName:     account.Login,
		OwnerId:       int64(account.Id),
		OwnerGlobalId: actorGIDString,
		AdminEvent:    adminevents.OwnerMarkedAsSpammy,
		Data:          spammyReason,
	}

	_, err = s.deployer.ReportAdminEventForBillingOwner(ctx, request)

	if err != nil {
		s.log.Report(ctx, errors.Wrap(err, "error reporting owner marked spammy on the billing owner level"), kvp.String("gh.launch.owner.global_id", actorGIDString))
	} else {
		s.log.Log(ctx, "successfully reported owner marked spammy on the billing owner level", kvp.String("gh.launch.owner.global_id", actorGIDString))
	}
}

func (s *Service) handleUnmarkedSpammyReporting(ctx context.Context, account *ghentities.User, previousClassification ghentities.AbuseClassificationState) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	actorGIDString := account.GetGlobalRelayId()
	actorGlobalID, err := s.ghTwirpClient.GetNextGlobalID(ctx, actorGIDString)
	if err != nil {
		s.log.Report(ctx, errors.New("error getting repo next global ID for owner unmarked spammy"), kvp.String("gh.launch.owner.global_id", actorGIDString))
		return
	}
	s.logGlobalIDReplacement(ctx, adminevents.OwnerUnmarkedAsSpammy, actorGIDString, actorGlobalID.String())
	actorGIDString = actorGlobalID.String()

	s.log.Debug(ctx, "user is not marked as spammy", kvp.String("gh.actor.global_id", actorGIDString))

	wasPreviouslySpammy := previousClassification == ghentities.AbuseClassificationState_SPAMMY
	if wasPreviouslySpammy {
		s.log.Debug(ctx, "report owner unmarked as spammy on the billing owner level", kvp.String("gh.launch.owner.global_id", actorGIDString))

		req := &deploy.ReportAdminEventForBillingOwnerRequest{
			OwnerName:     account.Login,
			OwnerId:       int64(account.Id),
			OwnerGlobalId: actorGIDString,
			AdminEvent:    adminevents.OwnerUnmarkedAsSpammy,
		}

		_, err = s.deployer.ReportAdminEventForBillingOwner(ctx, req)

		if err != nil {
			s.log.Report(ctx, errors.Wrap(err, "error owner unmarked as spammy on the billing owner level"), kvp.String("gh.launch.owner.global_id", actorGIDString))
		} else {
			s.log.Log(ctx, "successfully reported owner unmarked as spammy on the billing owner level", kvp.String("gh.launch.owner.global_id", actorGIDString))
		}
	}
}

func (s *Service) handleUserDestroyMessage(ctx context.Context, msg *ghschemas.UserDestroy) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	user := msg.GetUser()
	userGIDString := user.GetGlobalRelayId()
	userGlobalID, err := s.ghTwirpClient.GetNextGlobalID(ctx, userGIDString)
	if err != nil {
		s.log.Report(ctx, errors.New("error getting repo next global ID for user destroy"), kvp.String("gh.launch.owner.global_id", userGIDString))
		return
	}
	s.logGlobalIDReplacement(ctx, adminevents.BillingOwnerDeleted, userGIDString, userGlobalID.String())
	userGIDString = userGlobalID.String()

	// Try to cancel any in-progress workflow runs
	s.log.Debug(ctx, "cancelling any in-progress workflows for deleted billing owner", kvp.String("gh.launch.owner.global_id", userGIDString))

	req := &deploy.ReportAdminEventForBillingOwnerRequest{
		OwnerName:     user.Login,
		OwnerId:       int64(user.Id),
		OwnerGlobalId: userGIDString,
		AdminEvent:    adminevents.BillingOwnerDeleted,
	}

	_, err = s.deployer.ReportAdminEventForBillingOwner(ctx, req)

	if err != nil {
		s.log.Report(ctx, errors.Wrap(err, "error reporting billing owner is deleted"), kvp.String("gh.launch.owner.global_id", userGIDString))
	} else {
		s.log.Log(ctx, "successfully reported billing owner is deleted.", kvp.String("gh.launch.owner.global_id", userGIDString))
	}

	workflowCancelReq := &deploy.WorkflowCancelAllForNonOwnerReposRequest{
		ActorName: user.Login,
		ActorId:   int64(user.Id),
		ActorGlobalId: &pbtypes.Identity{
			GlobalId: userGIDString,
		},
		Data: adminevents.BillingOwnerDeleted,
	}

	result, err := s.deployer.WorkflowCancelAllForNonOwnerRepos(ctx, workflowCancelReq)

	if err != nil {
		s.log.Report(ctx, errors.New("error cancelling workflows for repos not owned by destroyed actor"), kvp.String("gh.actor.global_id", userGIDString), kvp.Err(err))
	} else {
		s.log.Log(ctx, "successfully cancelled workflows for repos not owned by destroyed actor", kvp.String("gh.actor.global_id", userGIDString), kvp.Int64("gh.launch.workflow.cancelled_count", result.GetWorkflowCount()))
	}
}

func (s *Service) handleOrganizationRestoreMessage(ctx context.Context, msg *ghschemas.OrganizationRestore) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	restoredOrg := msg.GetOrganization()
	orgGIDString := restoredOrg.GetGlobalRelayId()
	orgGID, err := s.ghTwirpClient.GetNextGlobalID(ctx, orgGIDString)
	if err != nil {
		s.log.Report(ctx, errors.New("error getting repo next global ID for org restore"), kvp.String("gh.launch.global_id", orgGIDString))
		return
	}

	if restoredOrg.Spammy || restoredOrg.Suspended {
		s.log.Debug(ctx, "skipping org restore event for spammy or suspended org", kvp.String("gh.launch.global_id", orgGID.String()))
		return
	}

	orgOwner, err := s.ghTwirpClient.GetOrganizationOwner(ctx, int64(restoredOrg.Id))
	if err != nil {
		s.log.Report(ctx, errors.Wrap(err, "error getting org owner for org restored"), kvp.String("gh.launch.global_id", orgGID.String()))
		return
	}

	billingOwner := orgOwner.Organization
	if orgOwner.Business != nil {
		billingOwner = *orgOwner.Business
	}

	req := &deploy.ReportAdminEventForBillingOwnerRequest{
		OwnerId:       billingOwner.ID,
		OwnerName:     billingOwner.Name,
		OwnerGlobalId: billingOwner.GlobalID.String(),
		AdminEvent:    adminevents.BillingOwnerRestored,
	}

	_, err = s.deployer.ReportAdminEventForBillingOwner(ctx, req)

	if err != nil {
		s.log.Report(ctx, errors.Wrap(err, "error reporting org restored on the billing owner level"),
			kvp.String("gh.launch.global_id", orgGID.String()),
			kvp.String("gh.billing.owner.global_id", billingOwner.GlobalID.String()))
		return
	}

	s.log.Debug(ctx, "successfully report org restored to billing owner", kvp.String("gh.launch.global_id", orgGID.String()))
}

func (s *Service) handleHydroMessage(ctx context.Context, msg hydro.Message) error {
	defer func() {
		if r := recover(); r != nil {
			err := errFromPanic(r)
			s.log.Report(ctx, err)
		}
	}()

	ctx, span := tracing.Start(ctx)
	defer span.End()

	var envelope hydroschemas.Envelope
	if err := proto.Unmarshal(msg.Value, &envelope); err != nil {
		s.log.Error(ctx, "error unmarshaling envelope", kvp.Err(err), kvp.String("gh.hydro.msg.topic", msg.Topic))
		return tracing.RecordError(span, errors.Wrap(err, "unmarshalling hydro envelope"))
	}

	s.log.Debug(ctx, "Handling Hydro message", kvp.String("messaging.hydro.envelope_id", envelope.Id), kvp.String("gh.hydro.msg.topic", msg.Topic), kvp.Int64("messaging.hydro.message_offset", msg.Offset), kvp.Int64("gh.hydro.msg.partition", int64(msg.Partition)))

	switch topic := msg.Topic; topic {
	case AbuseClassification:
		var msg ghschemas.AbuseClassification
		if err := proto.Unmarshal(envelope.Message, &msg); err != nil {
			s.log.Error(ctx, "error unmarshaling abuse classification message", kvp.Err(err))
			return tracing.RecordError(span, errors.Wrap(err, "error unmarshalling abuse classification message"))
		}

		s.handleAbuseClassificationMessage(ctx, &msg)
		return nil

	case InvocationBlockedTopic:
		var msg ghschemasV0.InvocationBlocked
		if err := proto.Unmarshal(envelope.Message, &msg); err != nil {
			s.log.Error(ctx, "error unmarshaling invocation blocked message", kvp.Err(err))
			return tracing.RecordError(span, errors.Wrap(err, "error unmarshalling invocation blocked message"))
		}

		s.handleInvocationBlockedMessage(ctx, &msg)
		return nil

	case InvocationUnblockedTopic:
		var msg ghschemasV0.InvocationUnblocked
		if err := proto.Unmarshal(envelope.Message, &msg); err != nil {
			s.log.Error(ctx, "error unmarshaling invocation blocked message", kvp.Err(err))
			return tracing.RecordError(span, errors.Wrap(err, "error unmarshalling invocation blocked message"))
		}

		s.handleInvocationUnblockedMessage(ctx, &msg)
		return nil

	case OrganizationRestoreTopic:
		var msg ghschemas.OrganizationRestore
		if err := proto.Unmarshal(envelope.Message, &msg); err != nil {
			s.log.Error(ctx, "error unmarshaling organization restore message", kvp.Err(err))
			return tracing.RecordError(span, errors.Wrap(err, "error unmarshaling organization restore message"))
		}

		s.handleOrganizationRestoreMessage(ctx, &msg)
		return nil

	case RepositoryDeletedTopic:
		var msg ghschemas.RepositoryDeleted
		if err := proto.Unmarshal(envelope.Message, &msg); err != nil {
			s.log.Error(ctx, "error unmarshaling repository deleted message", kvp.Err(err))
			return tracing.RecordError(span, errors.Wrap(err, "error unmarshalling repository deleted message"))
		}

		s.handleRepositoryDeletedMessage(ctx, &msg)
		return nil

	case RepositoryRestoredTopic:
		var msg ghschemas.RepositoryRestored
		if err := proto.Unmarshal(envelope.Message, &msg); err != nil {
			s.log.Error(ctx, "error unmarshaling repository restored message", kvp.Err(err))
			return tracing.RecordError(span, errors.Wrap(err, "error unmarshalling repository restored message"))
		}

		s.handleRepositoryRestoredMessage(ctx, &msg)
		return nil

	case RepositoryArchivedStatusChangedTopic:
		var msg ghschemas.RepositoryArchivedStatusChanged
		if err := proto.Unmarshal(envelope.Message, &msg); err != nil {
			s.log.Error(ctx, "error unmarshaling repository archived status changed message", kvp.Err(err))
			return tracing.RecordError(span, errors.Wrap(err, "error unmarshaling repository archived status changed message"))
		}

		s.handleRepositoryArchivedStatusChangedMessage(ctx, &msg)
		return nil

	case RepositoryTransferTopic:
		var msg ghschemas.RepositoryTransfer
		if err := proto.Unmarshal(envelope.Message, &msg); err != nil {
			s.log.Error(ctx, "error unmarshaling repository transfer message", kvp.Err(err))
			return tracing.RecordError(span, errors.Wrap(err, "error unmarshaling repository transfer message"))
		}

		s.handleRepositoryTransferMessage(ctx, &msg)
		return nil

	case UserDestroyTopic:
		var msg ghschemas.UserDestroy
		if err := proto.Unmarshal(envelope.Message, &msg); err != nil {
			s.log.Error(ctx, "error unmarshaling user destroy message", kvp.Err(err))
			return errors.Wrap(err, "error unmarshaling user destroy message")
		}

		s.handleUserDestroyMessage(ctx, &msg)
		return nil

	case WorkflowStateChangeTopic:
		var msg ghschemasV0.WorkflowStateChange
		if err := proto.Unmarshal(envelope.Message, &msg); err != nil {
			s.log.Error(ctx, "error unmarshaling workflow state change message", kvp.Err(err))
			return errors.Wrap(err, "error unmarshaling workflow state change message")
		}

		s.handleWorkflowStateChangeMessage(ctx, &msg)
		return nil

	default:
		err := fmt.Errorf("encountered message from unexpected topic: %s", msg.Topic)
		return tracing.RecordError(span, err)
	}
}

func errFromPanic(p any) error {
	if err, ok := p.(error); ok {
		return err
	}
	return errors.Errorf("hydro consumer panic handling message: %v", p)
}

func (s *Service) logGlobalIDReplacement(ctx context.Context, event, legacyGID, nextGID string) {
	if legacyGID != nextGID {
		s.stats.Counter("global_ids.replace_hydro_legacy_id", ghstats.Tags{"hydro_event": event}, 1)
		s.log.Debug(ctx, "Replacing legacy global id with next value for hydro event",
			kvp.String("messaging.hydro.topic.suffix", event),
			kvp.String("gh.launch.legacy_global_id", legacyGID),
			kvp.String("gh.launch.next_global_id", nextGID))
	}
}

// Run starts consuming messages from Hydro.
func (s *Service) Run(ctx context.Context) error {
	s.log.Debug(ctx, "starting kafka consumer server...")

	err := s.hydroSource.Consume(ctx, s.handleHydroMessage)
	if err != nil {
		s.log.Error(ctx, "error consuming hydro message", kvp.Err(err))
		return err
	}

	// this is blocking until the context is cancelled
	<-ctx.Done()

	return s.Stop(ctx)
}

// Stop stops the consumer and also stops collecting metrics.
func (s *Service) Stop(_ context.Context) error {
	if err := s.hydroSource.Close(); err != nil {
		return errors.Wrap(err, "Error while closing hydroSource")
	}

	return nil
}
