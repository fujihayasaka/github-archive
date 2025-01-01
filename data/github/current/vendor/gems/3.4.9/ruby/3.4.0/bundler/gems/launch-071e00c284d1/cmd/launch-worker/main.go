package main

import (
	"context"
	"database/sql"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/facebookgo/clock"
	diet_earthsmoke "github.com/github/diet_earthsmoke/go"
	"github.com/github/go-config/v2"
	"github.com/github/go-kvp"
	"github.com/github/go-log"
	"github.com/github/hydro-client-go/v3/pkg/hydro"
	"github.com/pkg/errors"
	"github.com/redis/go-redis/v9"
	circuit "github.com/rubyist/circuitbreaker"
	"github.com/twitchtv/twirp"

	kredzpb "github.com/github/kredz/services/protobuf/credz"
	varzpb "github.com/github/kredz/services/protobuf/varz"

	"github.com/github/launch/cli"
	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/clients/authzd"
	clients_earthsmoke "github.com/github/launch/clients/earthsmoke"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/clients/kredz"
	"github.com/github/launch/clients/launchblob"
	"github.com/github/launch/clients/launchredis"
	"github.com/github/launch/clients/launchtwirp"
	"github.com/github/launch/clients/results"
	"github.com/github/launch/clients/runservice"
	"github.com/github/launch/clients/spokesd"
	cu "github.com/github/launch/clients/utils"
	"github.com/github/launch/clients/varz"
	"github.com/github/launch/config/customerlabels"
	"github.com/github/launch/db/stores/deployer"
	dbpayloads "github.com/github/launch/db/stores/payloads"
	"github.com/github/launch/db/stores/schedules"
	"github.com/github/launch/hydro/events"
	"github.com/github/launch/keystore"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/logger/kafkalog"
	"github.com/github/launch/observability/reqobs"
	"github.com/github/launch/observability/slometrics"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/abreaker"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/azp/azkeyvault"
	"github.com/github/launch/pkg/azp/azpbearer"
	"github.com/github/launch/pkg/azp/azpbearer/jwt"
	"github.com/github/launch/pkg/azp/azpbearer/tokensrc"
	"github.com/github/launch/pkg/azp/azpclient"
	"github.com/github/launch/pkg/azp/azpclientsecret"
	"github.com/github/launch/pkg/azp/azps2s"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchchaos"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/pkg/payloads"
	"github.com/github/launch/pkg/processors/build"
	"github.com/github/launch/pkg/processors/webhook"
	"github.com/github/launch/pkg/rate"
	"github.com/github/launch/pkg/schedulemanager"
	"github.com/github/launch/services"
	"github.com/github/launch/services/auth/hkdf"
	"github.com/github/launch/services/deploy/adminevents"
	schconfig "github.com/github/launch/services/deploy/scheduled/config"
	"github.com/github/launch/services/deploy/scheduled/model"
	"github.com/github/launch/services/deploy/workflowinvoker"
	"github.com/github/launch/services/health"
	"github.com/github/launch/services/queueworker"
	"github.com/github/launch/utils"
	"github.com/github/launch/utils/ahttp"
	"github.com/github/launch/utils/appcontext"
	"github.com/github/launch/utils/apphttp"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/workflowbuild"
	azpwfb "github.com/github/launch/workflowbuild/azp"
	azpconf "github.com/github/launch/workflowbuild/azp/config"
)

func main() {
	if err := realMain(); err != nil {
		log.Error("failed to run launch-worker", kvp.Err(err))
		os.Exit(1)
	}
}

//gocyclo:ignore
func realMain() error {
	cli.ParseFlags()

	metadata := cli.GetApplicationMetadata("launch-worker")
	ctx, ctxCancel := context.WithCancel(appcontext.InitializeWithoutRequestID(context.Background(), metadata))
	defer ctxCancel()

	if err := launchconfig.LoadGlobalConfig(); err != nil {
		return err
	}

	var cfg Config
	if err := config.Load(&cfg); err != nil {
		return err
	}
	err := cfg.AzureProviderConfig.Parse()
	if err != nil {
		return err
	}

	log := cfg.getLogger()
	stats := cfg.getStatter(metadata.ObservabilityFields)
	obs := observability.New(log, stats)

	// Instantiate tracer
	shutdownTracer, err := tracing.Instrument(ctx, log, cfg.TracingEnabled)
	if err != nil {
		return err
	}
	defer shutdownTracer()

	var redisClient redis.UniversalClient
	if cfg.RedisConfig.RedisURL != "" {
		redisClient, err = launchredis.New(ctx, cfg.RedisConfig, obs)
		if err != nil {
			return err
		}
	}
	redisBreaker, err := abreaker.NewRedisBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return err
	}
	cache := launchcache.NewSharedCache(redisClient, redisBreaker, cfg.CacheConfig, obs)

	twirpTelemetry := reqobs.NewTwirpMetricsHooks(stats)
	twirpOpts := reqobs.AdaptTwirpHooksToClientOptions(twirpTelemetry, time.Now)

	httpClients, err := buildHTTPClients(obs, cfg, cache.GitHubTwirp(), twirpOpts)
	if err != nil {
		return err
	}

	aqueductBreaker, err := abreaker.NewAqueductWorkerClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return err
	}

	actionsBotNodeIDs, err := cfg.GetActionsBotNodeIDs(ctx)
	if err != nil {
		return err
	}

	actionsAppIDs, err := cfg.GetActionsAppIDs()
	if err != nil {
		return err
	}

	githubTwirpBreaker, err := abreaker.NewGithubTwirpClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return errors.Wrap(err, "unable to create twirp client")
	}

	var githubTwirpClient ghtwirp.Client

	githubTwirpClient, err = ghtwirp.NewClient(
		cfg.GitHubTwirpAddr,
		cfg.GitHubTwirpHMACSecret,
		obs,
		cfg.LaunchEnv,
		cache.GitHubTwirp(),
		ahttp.NewRetryClient(githubTwirpBreaker, obs.Statter, httpClients.Default, "ghtwirp"),
		twirpOpts,
		launchconfig.IsMultiTenant(),
	)
	if err != nil {
		return errors.Wrap(err, "error creating GitHub Twirp client")
	}

	if cfg.IsEnterprise() {
		githubTwirpClient = ghtwirp.NewEnterpriseClient(githubTwirpClient)
	}

	var kredzClient kredz.Client
	kredzTwirpBreaker, err := abreaker.NewKredzTwirpClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return err
	}

	kredzTwirpHTTPClient, err := launchtwirp.NewClient(cfg.KredzHMACSecrets(), kredzTwirpBreaker, stats, httpClients.Default)
	if err != nil {
		return err
	}

	kredzTwirpClient := kredzpb.NewCredentialsServiceProtobufClient(cfg.KredzHTTPAddr, kredzTwirpHTTPClient, twirpOpts...)

	kredzClient = kredz.NewClient(kredzTwirpClient, kredz.KredzMaxRetries, kredz.KredzReqRetryDelay)

	varzTwirpBreaker, err := abreaker.NewVarzTwirpClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return err
	}

	varzTwirpHTTPClient, err := launchtwirp.NewClient(cfg.VarzHMACSecrets(), varzTwirpBreaker, stats, httpClients.Default)
	if err != nil {
		return err
	}

	varzTwirpClient := varzpb.NewVariablesServiceProtobufClient(cfg.VarzHTTPAddr, varzTwirpHTTPClient, twirpOpts...)

	varzClient := varz.NewClient(varzTwirpClient, varz.VarzMaxRetries, varz.VarzReqRetryDelay)

	gitHubBreaker, err := abreaker.NewGithubClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return errors.Wrap(err, "error building github breaker")
	}

	apiBase, err := url.Parse(cfg.APIHost)
	if err != nil {
		return err
	}
	apiBase.Path = cfg.V3APIEndpoint

	ghAppPrivateKey := utils.UnescapeConsulKVBytes([]byte(cfg.AppPrivateKey))
	tokenService, err := tokens.NewService(
		cfg.Environment(),
		obs,
		apiBase,
		cfg.AppID,
		ghAppPrivateKey,
		gitHubBreaker,
		httpclient.New(httpClients.Default, httpclient.WithRetryDelay(25*time.Millisecond)),
		cache.GitHub(),
		githubTwirpClient.IsFeatureEnabledForActor,
		githubTwirpClient.IsFeatureEnabledGlobally,
		githubTwirpClient.GetRepositoryOwnerID,
		reqobs.NewHTTPClientHooks(obs),
		launchconfig.IsMultiTenant(),
	)
	if err != nil {
		return errors.Wrap(err, "error creating tokens service")
	}

	hooks := reqobs.GitHubGraphQLHooks(obs)

	graphQLAPIProvider, err := cu.NewGraphQLURLProvider(cfg.APIHost, cfg.GraphQLEndpoint)
	if err != nil {
		return fmt.Errorf("error creating URLProvider for graphql client: %w", err)
	}

	clientFactory := github.NewFactory(
		cfg.Environment(),
		graphQLAPIProvider,
		cfg.GetGraphQLServiceToken(),
		tokenService,
		obs,
		gitHubBreaker,
		hooks,
		httpClients.Default,
		githubTwirpClient,
		launchconfig.IsMultiTenant(),
	)

	aqueductClientFactory := aqueduct.NewFactory(httpClients.Default)

	ks, err := makeKeyStore(&cfg, obs.Logger, obs.Statter)
	if err != nil {
		return errors.Wrap(err, "failed to make keystore")
	}

	dbOptions := &utils.DatabaseOptions{
		EmulatePreparedStatements: cfg.EmulatePreparedStatements,
		UseUTCForMySQL:            cfg.UseUTCForMySQL,
		ForceCharsetForMySQL:      cfg.ForceCharsetForMySQL,
		MySQLMaxOpenConns:         cfg.MySQLMaxOpenConns,
		MySQLMaxIdleConns:         cfg.MySQLMaxIdleConns,
		MySQLMaxIdleTime:          cfg.MySQLMaxIdleTime,
		MySQLMaxLifetime:          cfg.MySQLMaxLifetime,
	}

	deployerDB, err := utils.GetDatabaseConnection(cfg.DatabaseURL, stats, dbOptions)
	if err != nil {
		return errors.Wrap(err, "failed to create deployer database connection")
	}

	dbBreaker, err := abreaker.NewLaunchDBClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return errors.Wrap(err, "error building db breaker")
	}
	adb := asql.New(deployerDB, log, stats, dbBreaker, asql.LaunchCluster)

	var payloadsRepo payloads.Store
	if launchconfig.UsingPayloadsBlobStorage() {
		bc, err := launchblob.NewClient(cfg.BlobConfig, log, stats, httpClients.Default)
		if err != nil {
			return errors.Wrap(err, "error creating blob client")
		}

		payloadMetadataRepo := deployer.NewPayloadMetadataStoreSQL(adb, log, stats, clock.New())

		payloadsRepo, err = launchblob.NewPayloadStore(bc,
			cfg.AzureStorageAccountIDs(),
			cfg.AzureStorageAccountPrefix,
			cfg.AzureStorageAccountCount,
			cfg.AzureStorageContainerName,
			log,
			stats,
			payloadMetadataRepo,
		)
		if err != nil {
			return errors.Wrap(err, "error creating blob payload store")
		}
	} else {
		if cfg.PayloadsDatabaseURL == "" {
			return errors.New("payloads database URL is required in this environment")
		}

		payloadsCluster, err := utils.GetDatabaseConnection(cfg.PayloadsDatabaseURL, stats, dbOptions)
		if err != nil {
			return errors.Wrap(err, "failed to create payloads database connection")
		}

		payloadsBreaker, err := abreaker.NewPayloadsClientBreaker(ctx, obs, cfg.BreakerConfig)
		if err != nil {
			return errors.Wrap(err, "error building payloads breaker")
		}

		payloadsRepo = dbpayloads.New(asql.New(payloadsCluster, log, stats, payloadsBreaker, asql.PayloadsCluster), log, stats)
	}

	globalIDMigrator := deployer.NewGlobalIDMigrator(githubTwirpClient)
	executionsRepo := deployer.NewWorkflowBuildExecutionsRepository(adb, obs, clock.New(), globalIDMigrator)
	workflowBuildsRepo := deployer.NewWorkflowBuildsRepository(adb, log, stats, clock.New(), payloadsRepo, executionsRepo, globalIDMigrator, cfg.IsMultiTenant)

	azpResourcesRepo := makeAZPRepo(cfg, obs, deployerDB, dbBreaker, globalIDMigrator, githubTwirpClient)
	azpClients, err := setupAZPClientFactory(
		ctx,
		httpClients,
		githubTwirpClient,
		cfg.AzureProviderConfig,
		cfg.BreakerConfig,
		obs,
		ks,
		azpResourcesRepo,
		cache,
		cfg.Environment(),
		cfg.IsEnterprise(),
	)
	if err != nil {
		return err
	}
	tenantKeyGenerator := azpwfb.NewBufferedTenantKeyGenerator(
		cfg.TenantKeyGeneratorBufferSize,
		cfg.TenantKeyGeneratorWorkers,
		obs,
	)

	tenantHandler := azpwfb.NewTenantHandler(
		azpClients.S2sClient,
		ks,
		obs,
		azpClients.RepositoryClientFactory,
		azpResourcesRepo,
		tenantKeyGenerator,
		cfg.Environment(),
		githubTwirpClient,
	)

	earthsmokeDecryptor, err := makeEarthsmokeDecryptor(cfg, log, stats)
	if err != nil {
		return errors.Wrap(err, "failed to create earthsmoke decryptor")
	}

	var keyGenerator hkdf.KeyGenerator
	if cfg.ActionRunnerSecret != "" {
		keyGenerator = hkdf.NewKeyGenerator([]byte(cfg.ActionRunnerSecret))
	}

	var publisher events.EmitterOption
	if cfg.IsEnterprise() || cfg.KafkaBrokers == "disabled" {
		publisher = events.WithNullPublisher()
	} else {
		publisher, err = newEventPublisherForKafka(ctx, cfg, obs)
		if err != nil {
			return errors.Wrap(err, "error creating kafka event publisher")
		}
	}

	emitter, err := events.NewEmitter(
		publisher,
		events.WithLogger(log),
		events.WithStatter(stats))
	if err != nil {
		return err
	}
	sloReporter := slometrics.New(emitter)

	var labeler customerlabels.CustomerLabeler
	if !cfg.IsEnterprise() {
		labeler, err = customerlabels.NewCustomerLabeler(cfg.Top100Customers, cfg.TemporaryFourNinesStageRolloutEnterpriseNames)
		if err != nil {
			return errors.Wrap(err, "error building customer labels")
		}
	} else {
		labeler = customerlabels.NewNoopCustomerLabeler()
	}

	dependabotRelayID, ok := cfg.GetDependabotAppRelayID()
	if !cfg.IsEnterprise() {
		// In our production runtime, we expect there to be a Dependabot global ID, so it is required.
		// In GHES the Dependabot app may or may not be created, so it is optional and we should
		// not fail the process here.

		// In workflowinvoker.getSecretStore fetching Dependabot secrets is skipped if the value of
		// dependabotRelayId is an empty string.
		if !ok {
			return errors.New("dependabot app global id not set in config but is required by config")
		}
	}

	var queueBuildRateLimiter rate.RateLimiter
	if cfg.IsEnterprise() && cfg.QueueRunRateLimitEnabled {
		queueBuildRateLimiter = rate.NewGHESRateLimiter(cfg.QueueRunRateLimitPerMinute)
	} else if cfg.QueueRunRateLimitEnabled {
		queueBuildRateLimiter = rate.NewQueueBuildRateLimiter(ctx, obs, redisClient, redisBreaker)
	} else {
		queueBuildRateLimiter = &rate.NullRateLimiter{}
	}

	buildInvokerURLProviderFactory, err := cu.NewURLProviderFactory(cfg.ExternalAPIHost, cfg.V3APIEndpoint, cfg.GraphQLEndpoint, cfg.ExternalGitHubHost, cfg.IsMultiTenant)
	if err != nil {
		return fmt.Errorf("error creating build invoker url provider factory: %w", err)
	}

	buildInvokerFactory := workflowinvoker.NewBuildInvokerFactory(
		cfg.Environment(),
		workflowbuild.NewTokenFactory(tokenService, githubTwirpClient.IsFeatureEnabledForRepoOrOwners, cfg.Environment()),
		workflowBuildsRepo,
		cfg.SecretsAppRelayID,
		dependabotRelayID,
		kredzClient,
		varzClient,
		earthsmokeDecryptor,
		keyGenerator,
		cfg.ReceiverURL,
		cfg.ReceiverInternalURL,
		cfg.ReceiverPublicURL,
		cfg.ResultsReceiverURL,
		buildInvokerURLProviderFactory,
		sloReporter,
		labeler,
		cfg.IsEnterprise(),
		cfg.EnterpriseVersion,
		queueBuildRateLimiter,
	)

	workflowFilterer := azpwfb.NewWorkflowFilterer(obs, githubTwirpClient.IsFeatureEnabledForRepoOrOwners)

	var workflowSourceFactory workflowinvoker.WorkflowSourceFactory
	var spokesdClient spokesd.Client
	var authzdClient authzd.Client

	spokesdBreaker, err := abreaker.NewSpokesdClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return errors.Wrap(err, "error building spokesd breaker")
	}
	spokesdClient, err = makeSpokesdClient(cfg, stats, httpClients.Spokesd, spokesdBreaker, metadata.BuildVersion)
	if err != nil {
		return errors.Wrap(err, "setting up spokesd client")
	}

	authzdBreaker, err := abreaker.NewAuthzdClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return errors.Wrap(err, "error building authzd breaker")
	}
	authzdClient, err = makeAuthzdClient(cfg, obs, authzdBreaker, metadata.BuildVersion, httpClients.Default, twirpOpts)
	if err != nil {
		return errors.Wrap(err, "setting up authzd client")
	}

	workflowSourceFactory = workflowinvoker.SpokesdWorkflowSourceFactory(
		authzdClient,
		spokesdClient,
		githubTwirpClient,
		logger.AdaptToFieldLogger(ctx, log),
		obs,
	)
	log.Debug(ctx, "created spokesd workflow factory")

	workflowProvider := azpwfb.NewWorkflowProvider(spokesdClient, authzdClient, githubTwirpClient, obs, cfg.IsEnterprise(), cfg.Environment())

	workflowInvokerFactory := workflowinvoker.NewWorkflowInvokerFactory(
		buildInvokerFactory,
		workflowSourceFactory,
		clientFactory,
		tenantHandler,
		azpResourcesRepo,
		cfg.LaunchEnv == "lab",
		workflowProvider,
		workflowFilterer,
		nil, // workers is set to nil here, we don't use this
		cfg.AppMode(),
		cfg.IsEnterprise(),
		cfg.EnterpriseVersion,
		sloReporter,
	)

	errorHandlerFactory := workflowinvoker.NewErrorHandlerFactory(workflowBuildsRepo, sloReporter, cfg.IsEnterprise())

	runServiceTwirpBreaker, err := abreaker.NewRunServiceTwirpClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return errors.Wrap(err, "error building run service twirp breaker")
	}

	runServiceClient, err := runservice.NewClient(cfg.Environment(), cfg.RunServiceHMACSecrets(), runServiceTwirpBreaker, httpClients.Default, obs, cfg.RunServiceURL, twirpOpts, githubTwirpClient, cfg.IsMultiTenant)

	if err != nil {
		return errors.Wrap(err, "error creating run service client")
	}

	resultsTwirpBreaker, err := abreaker.NewResultsTwirpClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return errors.Wrap(err, "error building results twirp breaker")
	}

	var resultsClient results.Client
	if launchconfig.UsingResults() || cfg.IsMultiTenant {
		resultsConfig := results.Config{
			AqueductURL:           cfg.AqueductURL,
			AqueductAPIKey:        cfg.ResultsAqueductAPIKey,
			AqueductAPIKeyVersion: cfg.ResultsAqueductAPIKeyVersion,
			CoreURL:               cfg.ResultsCoreURL,
			CoreHMACSecret:        cfg.ResultsCoreHMACSecret,
		}

		resultsClient, err = results.NewClient(
			resultsConfig,
			aqueductClientFactory,
			aqueductBreaker,
			httpClients.Default,
			resultsTwirpBreaker,
			obs,
		)
		if err != nil {
			return fmt.Errorf("unable to initialize results client: %w", err)
		}
	}

	invoker := workflowinvoker.NewInvoker(
		workflowInvokerFactory,
		clientFactory,
		githubTwirpClient,
		workflowBuildsRepo,
		errorHandlerFactory,
		cfg.LaunchEnv == "lab",
		cfg.IsEnterprise(),
		sloReporter,
		runServiceClient,
		resultsClient,
	)

	scheduleMngr := makeScheduleManager(
		cfg,
		obs,
		metadata,
		adb,
		clientFactory,
		githubTwirpClient,
		azpResourcesRepo,
		workflowSourceFactory,
	)

	adminEventReporter := adminevents.NewAdminEventsReporter(
		obs, workflowBuildsRepo, azpClients.RepositoryClientFactory, azpResourcesRepo, githubTwirpClient)

	var webhookRateLimiter rate.RateLimiter = &rate.NullRateLimiter{}
	if cfg.WebhookRateLimitEnabled {
		webhookRateLimiter = rate.NewWebhookRateLimiter(ctx, obs, redisClient, redisBreaker, rate.WithThreshold(cfg.WebhookRateLimitThreshold))
	}

	// Webhooks, non-webhooks, health
	svcs := make([]services.Service, 0, 3)
	webhookJobProcessor := webhook.New(&webhook.Config{
		AppID:             cfg.AppID,
		ActionsBotNodeIDs: actionsBotNodeIDs,
		ActionsAppIDs:     actionsAppIDs,
		IsEnterprise:      cfg.IsEnterprise(),
		IsMultiTenant:     cfg.IsMultiTenant,
	}, invoker, workflowBuildsRepo, scheduleMngr, githubTwirpClient, adminEventReporter, sloReporter, labeler, webhookRateLimiter)

	webhookAqueductPool := "launch-worker-webhook"
	if cfg.IsLab() {
		webhookAqueductPool += "-lab"
	}
	webhooksSvc, err := queueworker.New(
		queueworker.QueueWorkerConfig{
			LaunchEnv:                cfg.LaunchEnv,
			AqueductApp:              cfg.AqueductApp,
			AqueductURL:              cfg.AqueductURL,
			AqueductAPIKey:           cfg.AqueductAPIKey,
			AqueductAPIKeyVersion:    cfg.AqueductAPIKeyVersion,
			AqueductQueues:           []string{cfg.AqueductQueueWebhooks},
			AqueductWorkerPool:       webhookAqueductPool,
			AqueductTimeoutMs:        cfg.AqueductTimeoutMs,
			NumWorkers:               cfg.AqueductNumWorkers,
			HeartbeatAttemptInterval: time.Duration(cfg.AqueductHeartbeatAttemptIntervalMs) * time.Millisecond,
			MaxTimeWithoutHeartbeat:  time.Duration(cfg.AqueductMaxTimeWithoutHeartbeatMs) * time.Millisecond,
			IsMultiTenant:            cfg.IsMultiTenant,
		}, webhookJobProcessor, obs, aqueductBreaker, aqueductClientFactory)
	if err != nil {
		return err
	}
	svcs = append(svcs, webhooksSvc)

	// Register worker service for processing `scheduled` and `dynamic` builds
	nonWebhookAqueductPool := "launch-worker-nonwebhook"
	if cfg.IsLab() {
		nonWebhookAqueductPool += "-lab"
	}
	nonWebhookBuildJobProcessor := build.New(invoker, sloReporter, labeler, cfg.IsMultiTenant)
	nonWebhookBuildsSvc, err := queueworker.New(
		queueworker.QueueWorkerConfig{
			LaunchEnv:                cfg.LaunchEnv,
			AqueductApp:              cfg.AqueductApp,
			AqueductURL:              cfg.AqueductURL,
			AqueductAPIKey:           cfg.AqueductAPIKey,
			AqueductAPIKeyVersion:    cfg.AqueductAPIKeyVersion,
			AqueductTimeoutMs:        cfg.AqueductTimeoutMs,
			AqueductQueues:           []string{cfg.AqueductQueueScheduled, cfg.AqueductQueueDynamic},
			AqueductWorkerPool:       nonWebhookAqueductPool,
			NumWorkers:               cfg.AqueductNumWorkersNonWebhook,
			HeartbeatAttemptInterval: time.Duration(cfg.AqueductHeartbeatAttemptIntervalMs) * time.Millisecond,
			MaxTimeWithoutHeartbeat:  time.Duration(cfg.AqueductMaxTimeWithoutHeartbeatMs) * time.Millisecond,
			IsMultiTenant:            cfg.IsMultiTenant,
		}, nonWebhookBuildJobProcessor, obs, aqueductBreaker, aqueductClientFactory)
	if err != nil {
		return err
	}
	svcs = append(svcs, nonWebhookBuildsSvc)

	healthSvc, err := health.New(health.Config{Version: metadata.BuildVersion, Address: cfg.InternalAddr}, obs)
	if err != nil {
		return err
	}
	svcs = append(svcs, healthSvc)

	obs.Debug(ctx, "Starting services")
	return services.RunServices(ctx, obs, svcs...)
}

func newEventPublisherForKafka(ctx context.Context, cfg Config, obs *observability.Observability) (events.EmitterOption, error) {
	obs.Debug(ctx, "Setting up event publisher for kafka")

	kc, err := newKafkaConfig(ctx, cfg, obs)
	if err != nil {
		return nil, errors.Wrap(err, "setting up kafka config")
	}

	kafkaSink, err := hydro.NewKafkaSink(*kc)
	if err != nil {
		return nil, errors.Wrap(err, "creating kafka sink")
	}

	site := hydro.CP1IAD

	emo, err := events.WithKafkaPublisher(kafkaSink, site, obs.Logger, obs.Statter)
	if err != nil {
		return nil, errors.Wrap(err, "creating kafka publisher")
	}

	return emo, nil
}

func newKafkaConfig(ctx context.Context, cfg Config, obs *observability.Observability) (*hydro.KafkaConfig, error) {
	if cfg.KafkaBrokers == "disabled" {
		return nil, errors.New("kafka broker is disabled")
	}

	brokers := strings.Split(cfg.KafkaBrokers, ",")
	var logb []kvp.Field
	for _, b := range brokers {
		logb = append(logb, kvp.String("peer.service", b))
	}
	obs.Debug(ctx, "connecting to brokers", logb...)

	golog := logger.AdaptToFieldLogger(ctx, obs.Logger)
	klog := kafkalog.AdaptFieldLoggerToKafkaLogger(golog)
	hydro.SetKafkaLogger(klog)

	kafkaOptions := []hydro.KafkaConfigOption{
		hydro.WithKafkaStats(obs.Statter.Client()),
		hydro.WithKafkaLogger(klog),
	}

	if cfg.IsDevelopment() {
		// Use a kafka-lite compatible version for the local environment
		kafkaOptions = append(kafkaOptions, hydro.WithKafkaVersion("1.1.1"))
	} else {
		kafkaOptions = append(kafkaOptions, hydro.WithClientID(fmt.Sprintf("launch-deployer-%s", cfg.LaunchEnv)))
		kafkaOptions = append(kafkaOptions, hydro.WithRootCA(cfg.KafkaRootCAPath))
	}

	return hydro.NewKafkaConfig(brokers, kafkaOptions...)
}

func makeKeyStore(cfg *Config, log logger.Logger, stats statter.Statter) (keystore.Store, error) {
	if cfg.IsEnterprise() {
		return keystore.NewNullStore(keystore.NewEncoder()), nil
	}

	if cfg.KeystoreAZPOrganizationKey == "" {
		return nil, errors.New("keystore:azp:organization key not found for keystore")
	}
	return keystore.NewStore(cfg.KeystoreAZPOrganizationKey, log, stats), nil
}

func makeAZPRepo(cfg Config, obs *observability.Observability, db *sql.DB, breaker *circuit.Breaker, gidMigrator deployer.GlobalIDMigrator, ghTwirpClient ghtwirp.Client) deployer.AzpResourcesRepository {
	adb := asql.New(db, obs.Logger, obs.Statter, breaker, asql.LaunchCluster)

	return deployer.NewAZPResourcesRepo(
		adb,
		cfg.Environment(),
		obs,
		cfg.AzureProviderConfig.ResourcesLockPollFreq,
		cfg.AzureProviderConfig.ResourcesLockTimeout,
		gidMigrator,
		ghTwirpClient,
	)
}

func makeEarthsmokeDecryptor(cfg Config, log logger.Logger, stats statter.Statter) (clients_earthsmoke.Decryptor, error) {
	if cfg.IsEnterprise() {
		return clients_earthsmoke.NewEnterpriseDecryptor(), nil
	}

	secretsKeyMap, err := createSecretKeysMap(cfg)
	if err != nil {
		return nil, errors.Wrap(err, "unable to get one or more diet earthsmoke high level keys")
	}

	return clients_earthsmoke.NewDecryptor(log, stats, secretsKeyMap), nil
}

func createSecretKeysMap(cfg Config) (map[workflowbuild.SecretSource]*diet_earthsmoke.HighLevelKey, error) {
	secretSourceToKeyMap := make(map[workflowbuild.SecretSource]string)
	secretSourceToKeyMap[workflowbuild.ActionsSecretSource] = cfg.DietEarthsmokeCustomTasksKey
	secretSourceToKeyMap[workflowbuild.DependabotSecretSource] = cfg.DependabotSecretsKey

	secretSourceToHLKMap := make(map[workflowbuild.SecretSource]*diet_earthsmoke.HighLevelKey)
	for source, key := range secretSourceToKeyMap {
		hlk, err := diet_earthsmoke.UnmarshalHighLevelKey(key)
		if err != nil {
			return nil, err
		}
		secretSourceToHLKMap[source] = hlk
	}

	return secretSourceToHLKMap, nil
}

func makeScheduleManager(
	cfg Config,
	obs *observability.Observability,
	metadata appcontext.ApplicationMetadata,
	db *asql.SQL,
	fct github.Factory,
	twp ghtwirp.Client,
	azpResourcesRepo deployer.AzpResourcesRepository,
	wfSrcFactory workflowinvoker.WorkflowSourceFactory,
) schedulemanager.Manager {
	scheduleCfg := schconfig.ScheduledConfig{
		LoopSleepDuration:         cfg.ScheduledLoopSleep,
		ReassignWorkAfterDuration: cfg.ScheduledReassignWorkAfter,
		ScatterOffsetDuration:     cfg.ScheduledScatterOffset,
		TasksPerTick:              cfg.ScheduledTaskPerTick,
		Environment:               metadata.Environment,
	}
	scheduleStore := schedules.New(
		db,
		obs.Logger,
		model.NewScheduleParser(),
		scheduleCfg,
		clock.New(),
		obs.Statter,
		deployer.NewGlobalIDMigrator(twp),
		twp.IsFeatureEnabledForActor,
	)

	return schedulemanager.New(
		&schedulemanager.Config{
			Environment:  metadata.Environment,
			IsEnterprise: cfg.IsEnterprise(),
		},
		obs,
		scheduleStore,
		fct,
		twp,
		azpResourcesRepo,
		wfSrcFactory,
	)
}

func makeSpokesdClient(cfg Config, stats statter.Statter, httpClient *http.Client, breaker *circuit.Breaker, buildVersion string) (spokesd.Client, error) {
	if cfg.SpokesdURL == "" {
		return nil, errors.New("SpokesdURL is required")
	}

	twirpTelemetry := reqobs.NewTwirpMetricsHooks(stats)

	client, err := spokesd.NewClient(spokesd.Config{
		SpokesdURL:   cfg.SpokesdURL,
		BuildVersion: buildVersion,
		ServiceName:  "launch-worker",
	}, httpClient, stats, breaker, reqobs.AdaptTwirpHooksToClientOptions(twirpTelemetry, time.Now))

	if err != nil {
		return nil, errors.Wrap(err, "making spokesd client")
	}

	return client, nil
}

func makeAuthzdClient(cfg Config, obs *observability.Observability, breaker *circuit.Breaker, buildVersion string, httpClient *http.Client, twirpOpts []twirp.ClientOption) (authzd.Client, error) {
	if cfg.AuthzdURL == "" {
		return nil, errors.New("AuthzdURL is required")
	}

	client, err := authzd.NewClient(authzd.Config{
		AuthzdURL:    cfg.AuthzdURL,
		BuildVersion: buildVersion,
		ServiceName:  "launch-worker",
	}, obs, breaker, httpClient, twirpOpts)
	if err != nil {
		return nil, errors.Wrap(err, "making authzd client")
	}

	return client, nil
}

type httpClients struct {
	Default, AZP, Spokesd *http.Client
}

func buildHTTPClients(obs *observability.Observability, cfg Config, ffcache launchcache.GitHubTwirpCache, twirpOpts []twirp.ClientOption) (*httpClients, error) {
	defaultOpts := []apphttp.Option{apphttp.WithObservability(obs, cfg.RoundTripperConfig)}
	azpOpts := []apphttp.Option{apphttp.WithObservability(obs, cfg.RoundTripperConfig), apphttp.WithIgnoreRedirects(), apphttp.WithAzureFrontDoorMaxTimeout()}

	spokesdOpts := make([]apphttp.Option, 0, 3)
	spokesdOpts = append(spokesdOpts, apphttp.WithMaxTimeout(spokesd.MaxTimeout))

	// Don't enable observability in GHES or local development mode.
	if !(cfg.IsDevelopment() || cfg.IsEnterprise()) {
		spokesdOpts = append(spokesdOpts, apphttp.WithObservability(obs, cfg.RoundTripperConfig))
	}

	if cfg.SpokesdConfigTLS {
		tlsCfg, err := spokesd.LoadTLSConfig(cfg.SpokesdCert, cfg.SpokesdKey, cfg.SpokesdChain)
		if err != nil {
			return nil, errors.Wrap(err, "loading TLS key pair")
		}
		spokesdOpts = append(spokesdOpts, apphttp.WithTLSClientConfig(tlsCfg))
	}

	if cfg.ChaosMode && cfg.ChaosScenario != "" {
		ffConfig := launchchaos.GitHubFeatureFlagTwirpConfig{
			Addr:       cfg.GitHubTwirpAddr,
			HMACSecret: cfg.GitHubTwirpHMACSecret,
			Env:        cfg.LaunchEnv,
			Cache:      ffcache,
			Opts:       twirpOpts,
		}
		chaosMiddleware, err := launchchaos.SetupChaosMode(obs, ffConfig, cfg.ChaosScenario)
		if err != nil {
			return nil, errors.Wrap(err, "setting up chaos mode")
		}
		chaosOption := apphttp.WithMiddleware(chaosMiddleware)
		defaultOpts = append(defaultOpts, chaosOption)
	}

	hc := &httpClients{
		Default: apphttp.NewClient(defaultOpts...),
		AZP:     apphttp.NewClient(azpOpts...),
		Spokesd: apphttp.NewClient(spokesdOpts...),
	}
	return hc, nil

}

func setupAZPClientFactory(
	ctx context.Context,
	hcls *httpClients,
	githubTwirpClient ghtwirp.Client,
	azcfg azpconf.AzureProviderConfig,
	brcfg abreaker.Config,
	obs *observability.Observability,
	ks keystore.Store,
	azprepo deployer.AzpResourcesRepository,
	cache launchcache.Cache,
	env launchconfig.AppEnv,
	isEnterprise bool,
) (*azp.Clients, error) {
	breakers, err := azp.MakeBreakers(ctx, obs, brcfg)
	if err != nil {
		return nil, err
	}

	hooks := reqobs.NewHTTPClientHooks(obs)
	btc := azpbearer.New(
		httpclient.New(hcls.Default),
		azpbearer.WithBreaker(breakers.TokenBreaker),
		azpbearer.WithCache(cache.AzureProvider()),
		azpbearer.WithHooks(hooks),
	)

	tsf := tokensrc.NewRepoClientTokenSourceFactory(azcfg, ks, btc, env.String())

	kvc := buildKeyVaultClient(azcfg, breakers.KeyVaultBreaker, obs, hcls.Default, cache)

	var s2sts launchhttp.TokenSource
	if isEnterprise || azcfg.ForceTokenOverAAD {
		s2sts = tokensrc.S2SForTokenService(azcfg, btc)
	} else {
		s2sts, err = azpclientsecret.TokenSource(azcfg, hcls.Default, cache.AzureProvider(), obs)
		if err != nil {
			return nil, errors.Wrap(err, "error building spn client secret token source")
		}
	}

	s2sClient, err := buildS2SClient(s2sts, azcfg, breakers.S2SBreaker, obs, hcls.AZP, githubTwirpClient)
	if err != nil {
		return nil, errors.Wrap(err, "error building s2s client azp factory")

	}

	azpClients := &azp.Clients{
		KeyVaultClient: kvc,
		S2sClient:      s2sClient,
		RepositoryClientFactory: azpclient.NewFactory(
			httpclient.New(hcls.Default),
			githubTwirpClient,
			breakers.RepoBreaker,
			obs,
			azcfg,
			azprepo,
			tsf,
			hooks,
		),
	}
	return azpClients, nil
}

func buildKeyVaultClient(azcfg azpconf.AzureProviderConfig, breaker *circuit.Breaker, obs *observability.Observability, httpBackend *http.Client, cache launchcache.Cache) azp.KeyVaultClient {
	btc := azpbearer.New(
		httpclient.New(httpBackend),
		azpbearer.WithBreaker(breaker),
		azpbearer.WithCache(cache.AzureProvider()),
		azpbearer.WithHooks(reqobs.NewHTTPClientHooks(obs)),
	)
	ts := tokensrc.ForKeyVault(azcfg, btc, jwt.CertificateRotationEmitter(obs, jwt.ForKeyVault))
	return azkeyvault.NewClient(
		httpclient.New(httpBackend),
		azkeyvault.WithBreaker(breaker),
		azkeyvault.WithCache(cache.S2SProvider()),
		azkeyvault.WithTokenSource(ts),
		azkeyvault.WithHooks(reqobs.NewHTTPClientHooks(obs)),
	)
}

func buildS2SClient(ts launchhttp.TokenSource, azcfg azpconf.AzureProviderConfig, breaker *circuit.Breaker, obs *observability.Observability, httpBackend *http.Client, githubTwirpClient ghtwirp.Client) (azp.S2SClient, error) {
	opts := []azps2s.Option{
		azps2s.WithBreaker(breaker),
		azps2s.WithTokenSource(ts),
		azps2s.WithHooks(reqobs.NewHTTPClientHooks(obs)),
	}

	return azps2s.New(
		httpclient.New(httpBackend),
		githubTwirpClient,
		azcfg,
		opts...,
	)
}
