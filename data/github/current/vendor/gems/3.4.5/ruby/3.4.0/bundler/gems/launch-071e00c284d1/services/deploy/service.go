package deploy

import (
	"context"
	"database/sql"

	"github.com/pkg/errors"

	"github.com/github/go-kvp"

	"github.com/github/launch/auth"
	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/clients/authzd"
	"github.com/github/launch/clients/billingplatform"
	"github.com/github/launch/clients/ghinternal"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/clients/kredz"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/hydro/events"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/resolver"
	"github.com/github/launch/pkg/schedulemanager"
	"github.com/github/launch/services/deploy/adminevents"
	"github.com/github/launch/services/deploy/workflowcanceler"
	"github.com/github/launch/services/deploy/workflowinvoker"
	pbtypes "github.com/github/launch/services/pbtypes"
	"github.com/github/launch/types"
	"github.com/github/launch/workerpool"
	"github.com/github/launch/workflowbuild"
	azpbuild "github.com/github/launch/workflowbuild/azp"
	azpconf "github.com/github/launch/workflowbuild/azp/config"
)

type service struct {
	cfg               config
	IsEnterprise      bool
	IsMultiTenant     bool
	EnterpriseVersion string
	AuthzClient       authzd.Client
	TwirpCache        launchcache.GitHubTwirpCache
	gidMigrator       deployer.GlobalIDMigrator
}

// New builds a mu GRPC service.
func New(
	Hostname string,
	DB *sql.DB,
	Credz kredz.Client,
	WorkflowBuilds deployer.WorkflowBuildsRepository,
	AZPResources deployer.AzpResourcesRepository,
	AzpResourcesLoader deployer.AzpResourcesLoader,
	Log logger.Logger,
	Observability *observability.Observability,
	Stats statter.Statter,
	Events *events.Emitter,
	ClientFactory github.Factory,
	GithubTwirpClient ghtwirp.Client,
	GithubBillingTwirpClient ghtwirp.Client,
	AqueductClient aqueduct.Client,
	AqueductQueue string,
	AqueductApp string,
	InternalClientFactory ghinternal.Factory,
	Workers workerpool.Workers,
	WorkflowCanceler workflowcanceler.Canceler,
	WorkflowSourceFactory workflowinvoker.WorkflowSourceFactory,
	AdminEventsReporter adminevents.Reporter,
	AppID int64,
	ScheduleManager schedulemanager.Manager,
	AppEnv launchconfig.AppEnv,
	Verifier auth.Verifier,
	AzpClient azp.S2SClient,
	KeyVaultClient azp.KeyVaultClient,
	AzureProviderConfig azpconf.AzureProviderConfig,
	TenantHandler azpbuild.TenantHandler,
	TokenFactory workflowbuild.TokenFactory,
	TokenService tokens.Service,
	JobsRepo deployer.JobsRepository,
	ResolverTokenFactory resolver.TokenFactory,
	isEnterprise bool,
	enterpriseVersion string,
	AuthzClient authzd.Client,
	TwirpCache launchcache.GitHubTwirpCache,
	gidMigrator deployer.GlobalIDMigrator,
	isMultiTenant bool,
	BillingPlatformTwirpClient billingplatform.Client,
) *service {
	return &service{
		IsEnterprise:      isEnterprise,
		IsMultiTenant:     isMultiTenant,
		EnterpriseVersion: enterpriseVersion,
		AuthzClient:       AuthzClient,
		TwirpCache:        TwirpCache,
		gidMigrator:       gidMigrator,
		cfg: config{
			Hostname:                   Hostname,
			DB:                         DB,
			Credz:                      Credz,
			WorkflowBuilds:             WorkflowBuilds,
			AZPResources:               AZPResources,
			AZPResourcesLoader:         AzpResourcesLoader,
			Log:                        Log,
			Obs:                        Observability,
			Stats:                      Stats,
			Events:                     Events,
			Hydro:                      Events,
			ClientFactory:              ClientFactory,
			GithubTwirpClient:          GithubTwirpClient,
			GithubTwirpBillingClient:   GithubBillingTwirpClient,
			AqueductClient:             AqueductClient,
			AqueductQueue:              AqueductQueue,
			AqueductApp:                AqueductApp,
			InternalClientFactory:      InternalClientFactory,
			Workers:                    Workers,
			WorkflowCanceler:           WorkflowCanceler,
			WorkflowSourceFactory:      WorkflowSourceFactory,
			AdminEventsReporter:        AdminEventsReporter,
			AppID:                      AppID,
			ScheduleManager:            ScheduleManager,
			AppEnv:                     AppEnv,
			Verifier:                   Verifier,
			AzpClient:                  AzpClient,
			KeyVaultClient:             KeyVaultClient,
			AzureProviderConfig:        AzureProviderConfig,
			TenantHandler:              TenantHandler,
			TokenFactory:               TokenFactory,
			TokenService:               TokenService,
			JobsRepo:                   JobsRepo,
			ResolverTokenFactory:       ResolverTokenFactory,
			BillingPlatformTwirpClient: BillingPlatformTwirpClient,
		},
	}
}

func (s *service) GetGlobalIDFromIdentity(ctx context.Context, id *pbtypes.Identity, method string) (types.GlobalID, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	rawGID := id.GetGlobalId()
	refinedGID, err := s.gidMigrator.GetNextGlobalID(ctx, rawGID)
	if err != nil {
		s.cfg.Obs.Counter(ctx, "global_ids.get_global_id_from_identity", statter.Tags{"status": "failure", "operation": method}, 1)
		s.cfg.Obs.Report(ctx, errors.Wrap(err, "error getting next global ID from identity"), kvp.String("gh.launch.global_id", rawGID))
		return types.NilGlobalID, tracing.RecordError(span, err)
	}
	s.cfg.Obs.Counter(ctx, "global_ids.get_global_id_from_identity", statter.Tags{"status": "success", "operation": method}, 1)
	s.LogGlobalIDReplacement(ctx, method, rawGID, refinedGID)
	return refinedGID, nil
}

func (s *service) LogGlobalIDReplacement(ctx context.Context, method, legacyGID string, nextGID types.GlobalID) {
	if legacyGID != nextGID.String() {
		s.cfg.Obs.Counter(ctx, "global_ids.replace_deployer_legacy_id", statter.Tags{"method": method}, 1)
		s.cfg.Obs.Logger.Debug(ctx, "Replacing legacy global id with next value in launch deployer",
			kvp.String("code.function", method),
			kvp.String("gh.launch.legacy_global_id", legacyGID),
			kvp.String("gh.launch.next_global_id", nextGID.String()))
	}
}
