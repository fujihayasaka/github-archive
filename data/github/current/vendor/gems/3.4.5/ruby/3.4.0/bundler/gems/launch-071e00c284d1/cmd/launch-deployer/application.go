package main

import (
	"context"
	"crypto/tls"
	"database/sql"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/facebookgo/clock"
	"github.com/github/go-config/v2"
	"github.com/github/go-kvp"
	twirphooks "github.com/github/go-twirp/server/hooks"
	twirpauth "github.com/github/go-twirp/server/hooks/auth"
	twirpstats "github.com/github/go-twirp/server/hooks/stats"
	"github.com/github/hydro-client-go/v3/pkg/hydro"
	"github.com/github/otel-instrumentation-go/oteltwirp"
	"github.com/google/uuid"
	"github.com/pkg/errors"
	"github.com/redis/go-redis/v9"
	circuit "github.com/rubyist/circuitbreaker"
	"github.com/twitchtv/twirp"

	"github.com/github/launch/pkg/mu"
	"github.com/github/launch/pkg/payloads"

	kredzpb "github.com/github/kredz/services/protobuf/credz"

	"github.com/github/launch/auth/hmac"
	"github.com/github/launch/cli"
	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/clients/authzd"
	"github.com/github/launch/clients/billingplatform"
	"github.com/github/launch/clients/ghinternal"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/clients/kredz"
	"github.com/github/launch/clients/launchblob"
	"github.com/github/launch/clients/launchredis"
	"github.com/github/launch/clients/launchtwirp"
	"github.com/github/launch/clients/spokesd"
	cu "github.com/github/launch/clients/utils"
	"github.com/github/launch/db/stores/deployer"
	dbpayloads "github.com/github/launch/db/stores/payloads"
	"github.com/github/launch/db/stores/schedules"
	"github.com/github/launch/hydro/events"
	"github.com/github/launch/keystore"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/logger/kafkalog"
	"github.com/github/launch/observability/reqobs"
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
	"github.com/github/launch/pkg/buildhealer"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchchaos"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/pkg/resolver"
	"github.com/github/launch/pkg/schedulemanager"
	deploysvc "github.com/github/launch/services/deploy"
	"github.com/github/launch/services/deploy/adminevents"
	"github.com/github/launch/services/deploy/artifactcache"
	"github.com/github/launch/services/deploy/artifactsexchange"
	"github.com/github/launch/services/deploy/checks"
	"github.com/github/launch/services/deploy/environment"
	"github.com/github/launch/services/deploy/largerrunners"
	"github.com/github/launch/services/deploy/runnergroups"
	"github.com/github/launch/services/deploy/runnerscalesets"
	"github.com/github/launch/services/deploy/scheduled"
	schconfig "github.com/github/launch/services/deploy/scheduled/config"
	"github.com/github/launch/services/deploy/scheduled/model"
	"github.com/github/launch/services/deploy/selfhostedrunners"
	"github.com/github/launch/services/deploy/status"
	tokensvc "github.com/github/launch/services/deploy/token"
	"github.com/github/launch/services/deploy/workflowcanceler"
	"github.com/github/launch/services/deploy/workflowinvoker"
	"github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/services/pb/deploy/token"
	"github.com/github/launch/utils"
	"github.com/github/launch/utils/ahttp"
	"github.com/github/launch/utils/apphttp"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/utils/metadata"
	"github.com/github/launch/workerpool"
	"github.com/github/launch/workflowbuild"
	azpwfb "github.com/github/launch/workflowbuild/azp"
	azpconf "github.com/github/launch/workflowbuild/azp/config"
)

type application struct {
	cfg                Config
	db                 *sql.DB
	dbRo               *sql.DB
	PayloadsCluster    *sql.DB
	hydroEmitter       *events.Emitter
	workers            workerpool.Workers
	workflowBuildsRepo deployer.WorkflowBuildsRepository
	obs                *observability.Observability
	azpClients         *azp.Clients
	closers            []func() error
}

func newApplication() *application {
	return &application{}
}

func (a *application) ServiceName() string {
	return "launch-deployer"
}

// OnConfig runs before the mu service is started up.
func (a *application) OnConfig(_ *mu.Config) error {
	var err error
	if err = metadata.Init(); err != nil {
		return err
	}

	if err := launchconfig.LoadGlobalConfig(); err != nil {
		return err
	}

	if err = config.Load(&a.cfg); err != nil {
		return err
	}

	err = a.cfg.AzureProviderConfig.Parse()
	if err != nil {
		return err
	}

	return nil
}

// Kafka is used in launch lab and development
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

	if cfg.IsEnterprise() {
		kafkaOptions = append(kafkaOptions, hydro.WithKafkaVersion(cfg.KafkaVersion))
	} else if cfg.IsDevelopment() {
		// Use a kafka-lite compatible version for the local environment
		kafkaOptions = append(kafkaOptions, hydro.WithKafkaVersion("1.1.1"))
	} else {
		kafkaOptions = append(kafkaOptions, hydro.WithClientID(fmt.Sprintf("launch-deployer-%s", cfg.LaunchEnv)))
		kafkaOptions = append(kafkaOptions, hydro.WithRootCA(cfg.KafkaRootCAPath))
	}

	return hydro.NewKafkaConfig(brokers, kafkaOptions...)
}

// OnStartUp runs when the application is ready to start.
//
//gocyclo:ignore
func (a *application) OnStartUp(svc *mu.Service) error {
	ctx, ctxCancel := context.WithCancel(context.Background())
	a.closers = append(a.closers, func() error {
		ctxCancel()
		return nil
	})

	log := svc.Config.NewLogger(a.cfg.CommonConfig.LoggerConfig)

	stats := svc.Config.NewStatter()
	stats.Start()

	a.obs = observability.New(log, stats)

	shutdown, err := tracing.Instrument(ctx, log, a.cfg.TracingEnabled)
	if err != nil {
		return err
	}
	a.closers = append(a.closers, func() error {
		shutdown()
		return nil
	})

	var redisClient redis.UniversalClient
	if a.cfg.RedisConfig.RedisURL != "" {
		redisClient, err = launchredis.New(ctx, a.cfg.RedisConfig, a.obs)
		if err != nil {
			return err
		}
	}
	redisBreaker, err := abreaker.NewRedisBreaker(ctx, a.obs, a.cfg.BreakerConfig)
	if err != nil {
		return errors.Wrap(err, "could not build breaker for redis")
	}
	cache := launchcache.NewSharedCache(redisClient, redisBreaker, a.cfg.CacheConfig, a.obs)

	twirpTelemetry := reqobs.NewTwirpMetricsHooks(stats)
	twirpOpts := reqobs.AdaptTwirpHooksToClientOptions(twirpTelemetry, time.Now)

	httpClients, err := buildHTTPClients(a.obs, a.cfg, cache.GitHubTwirp(), twirpOpts)
	if err != nil {
		return err
	}

	// HOSTNAME is the pod name, allowing us to resume locks across restarts
	hostname, err := os.Hostname()
	if err != nil {
		// Create a needle, then generate a random replacement
		log.Report(ctx, err)
		hostname = uuid.New().String()
	}

	dbOptions := &utils.DatabaseOptions{
		EmulatePreparedStatements: a.cfg.EmulatePreparedStatements,
		UseUTCForMySQL:            a.cfg.UseUTCForMySQL,
		ForceCharsetForMySQL:      a.cfg.ForceCharsetForMySQL,
		MySQLMaxOpenConns:         a.cfg.MySQLMaxOpenConns,
		MySQLMaxIdleConns:         a.cfg.MySQLMaxIdleConns,
		MySQLMaxIdleTime:          a.cfg.MySQLMaxIdleTime,
		MySQLMaxLifetime:          a.cfg.MySQLMaxLifetime,
	}

	dbConnection, err := utils.GetDatabaseConnection(a.cfg.DatabaseURL, stats, dbOptions)
	if err != nil {
		return errors.Wrap(err, "error connecting to db")
	}
	a.db = dbConnection

	dbConnectionReadOnly, err := utils.GetDatabaseConnection(a.cfg.ReadOnlyDatabaseURL, stats, dbOptions)
	if err != nil {
		return errors.Wrap(err, "error connecting to readonly db")
	}
	a.dbRo = dbConnectionReadOnly

	breaker, err := abreaker.NewGithubClientBreaker(ctx, a.obs, a.cfg.BreakerConfig)
	if err != nil {
		return errors.Wrap(err, "could not build breaker for github client")
	}

	apiBase, err := url.Parse(a.cfg.APIHost)
	if err != nil {
		return errors.Wrap(err, "invalid API endpoint")
	}

	apiBase.Path = a.cfg.V3APIEndpoint

	a.workers = workerpool.NewSimple(
		log,
		stats,
	)

	githubTwirpBreaker, err := abreaker.NewGithubTwirpClientBreaker(ctx, a.obs, a.cfg.BreakerConfig)
	if err != nil {
		return errors.Wrap(err, "could not build breaker for twirp client")
	}

	var githubTwirpClient, githubBillingTwirpClient ghtwirp.Client

	githubTwirpClient, err = ghtwirp.NewClient(
		a.cfg.GitHubTwirpAddr,
		a.cfg.GitHubTwirpHMACSecret,
		a.obs,
		a.cfg.LaunchEnv,
		cache.GitHubTwirp(),
		ahttp.NewRetryClient(githubTwirpBreaker, a.obs.Statter, httpClients.Default, "ghtwirp"),
		twirpOpts,
		launchconfig.IsMultiTenant(),
	)
	if err != nil {
		return errors.Wrap(err, "error creating GitHub Twirp client")
	}

	// Use a separate client for the billing details Twirp endpoints
	githubBillingTwirpBreaker, err := abreaker.NewGithubTwirpBillingClientBreaker(ctx, a.obs, a.cfg.BreakerConfig)
	if err != nil {
		return errors.Wrap(err, "could not build breaker for twirp billing client")
	}

	githubBillingHTTPClient := ahttp.NewRetryClient(
		githubBillingTwirpBreaker,
		a.obs.Statter,
		httpClients.GitHubBilling,
		"ghbillingtwirp",
	)
	githubBillingHTTPClient.Attempts = 2

	githubBillingTwirpClient, err = ghtwirp.NewClient(
		a.cfg.GitHubTwirpAddr,
		a.cfg.GitHubTwirpHMACSecret,
		a.obs,
		a.cfg.LaunchEnv,
		cache.GitHubTwirp(),
		githubBillingHTTPClient,
		twirpOpts,
		launchconfig.IsMultiTenant(),
	)
	if err != nil {
		return errors.Wrap(err, "error creating GitHub Billing Twirp client")
	}

	if a.cfg.IsEnterprise() {
		githubTwirpClient = ghtwirp.NewEnterpriseClient(githubTwirpClient)
		githubBillingTwirpClient = ghtwirp.NewEnterpriseClient(githubBillingTwirpClient)
	}

	var billingClient billingplatform.Client

	if a.cfg.IsEnterprise() {
		log.Debug(ctx, "Billing platform client not created for enterprise - using no-op client")
		billingClient = billingplatform.NewNopClient(a.obs.Logger)
	} else {
		var billingPlatformClient billingplatform.Client

		billingPlatformTwirpBreaker, err := abreaker.NewBillingPlatformTwirpClientBreaker(ctx, a.obs, a.cfg.BreakerConfig)
		if err != nil {
			return errors.Wrap(err, "could not build breaker for twirp billing platform client")
		}

		billingPlatformRetryClient := ahttp.NewRetryClient(billingPlatformTwirpBreaker, a.obs.Statter, httpClients.Default, "billingplatformtwirp")

		if a.cfg.BillingPlatformURL != "" && a.cfg.BillingPlatformHMACSecret != "" {
			billingPlatformClient, err = billingplatform.NewHMACClientFromHTTPClient(billingPlatformRetryClient, a.cfg.BillingPlatformURL, a.cfg.BillingPlatformHMACSecret, a.obs.Statter, githubTwirpClient)
			if err != nil {
				return errors.Wrap(err, "error creating billing platform client")
			}
			log.Debug(ctx, "successfully created billing platform client")
		} else {
			return errors.New("billing platform URL or HMAC secret not set")
		}

		billingClient = billingPlatformClient
	}

	var kredzClient kredz.Client
	kredzTwirpBreaker, err := abreaker.NewKredzTwirpClientBreaker(ctx, a.obs, a.cfg.BreakerConfig)
	if err != nil {
		return err
	}

	kredzTwirpHTTPClient, err := launchtwirp.NewClient(a.cfg.KredzHMACSecrets(), kredzTwirpBreaker, stats, httpClients.Default)
	if err != nil {
		return err
	}

	kredzTwirpClient := kredzpb.NewCredentialsServiceProtobufClient(a.cfg.KredzHTTPAddr, kredzTwirpHTTPClient, twirpOpts...)

	kredzClient = kredz.NewClient(kredzTwirpClient, kredz.KredzMaxRetries, kredz.KredzReqRetryDelay)

	ghAppPrivateKey := utils.UnescapeConsulKVBytes([]byte(a.cfg.AppPrivateKey))

	tokenService, err := tokens.NewService(
		a.cfg.Environment(),
		a.obs,
		apiBase,
		a.cfg.AppID,
		ghAppPrivateKey,
		breaker,
		httpclient.New(httpClients.Default, httpclient.WithRetryDelay(25*time.Millisecond)),
		cache.GitHub(),
		githubTwirpClient.IsFeatureEnabledForActor,
		githubTwirpClient.IsFeatureEnabledGlobally,
		githubTwirpClient.GetRepositoryOwnerID,
		reqobs.NewHTTPClientHooks(a.obs),
		a.cfg.IsMultiTenant,
	)
	if err != nil {
		return errors.Wrap(err, "error creating token service")
	}

	hooks := reqobs.GitHubGraphQLHooks(a.obs)

	graphQLAPIProvider, err := cu.NewGraphQLURLProvider(a.cfg.APIHost, a.cfg.GraphQLEndpoint)
	if err != nil {
		return fmt.Errorf("error creating URLProvider for graphql client: %w", err)
	}

	clientFactory := github.NewFactory(
		a.cfg.Environment(),
		graphQLAPIProvider,
		a.cfg.GetGraphQLServiceToken(),
		tokenService,
		a.obs,
		breaker,
		hooks,
		httpClients.Default,
		githubTwirpClient,
		a.cfg.IsMultiTenant,
	)

	dbBreaker, err := abreaker.NewLaunchDBClientBreaker(ctx, a.obs, a.cfg.BreakerConfig)
	if err != nil {
		return errors.Wrap(err, "could not build breaker for launch db client")
	}
	adb := asql.New(a.db, log, stats, dbBreaker, asql.LaunchCluster)

	globalIDMigrator := deployer.NewGlobalIDMigrator(githubTwirpClient)
	executionsRepo := deployer.NewWorkflowBuildExecutionsRepository(adb, a.obs, clock.New(), globalIDMigrator)

	var payloadsRepo payloads.Store
	if launchconfig.UsingPayloadsBlobStorage() {
		bc, err := launchblob.NewClient(a.cfg.BlobConfig, log, stats, httpClients.Default)
		if err != nil {
			return errors.Wrap(err, "error creating blob client")
		}

		payloadMetadataRepo := deployer.NewPayloadMetadataStoreSQL(adb, log, stats, clock.New())

		payloadsRepo, err = launchblob.NewPayloadStore(bc,
			a.cfg.AzureStorageAccountIDs(),
			a.cfg.AzureStorageAccountPrefix,
			a.cfg.AzureStorageAccountCount,
			a.cfg.AzureStorageContainerName,
			log,
			stats,
			payloadMetadataRepo,
		)
		if err != nil {
			return errors.Wrap(err, "error creating blob payload store")
		}
	} else {
		if a.cfg.PayloadsDatabaseURL == "" {
			return errors.New("payloads database URL is required in this environment")
		}

		payloadsClusterConnection, err := utils.GetDatabaseConnection(a.cfg.PayloadsDatabaseURL, stats, dbOptions)
		if err != nil {
			return errors.Wrap(err, "error connecting to payloads db")
		}
		a.PayloadsCluster = payloadsClusterConnection

		payloadsBreaker, err := abreaker.NewPayloadsClientBreaker(ctx, a.obs, a.cfg.BreakerConfig)
		if err != nil {
			return errors.Wrap(err, "could not build breaker for payloads db client")
		}

		payloadsRepo = dbpayloads.New(asql.New(payloadsClusterConnection, log, stats, payloadsBreaker, asql.PayloadsCluster), log, stats)
	}

	a.workflowBuildsRepo = deployer.NewWorkflowBuildsRepository(adb, log, stats, clock.New(), payloadsRepo, executionsRepo, globalIDMigrator, a.cfg.IsMultiTenant)

	var publisher events.EmitterOption

	if a.cfg.KafkaBrokers == "disabled" {
		publisher = events.WithNullPublisher()
	} else {
		publisher, err = newEventPublisherForKafka(ctx, a.cfg, a.obs)
		if err != nil {
			return errors.Wrap(err, "error creating kafka event publisher")
		}
	}

	a.hydroEmitter, err = events.NewEmitter(
		publisher,
		events.WithLogger(log),
		events.WithStatter(stats))
	if err != nil {
		return err
	}

	ks, err := a.makeKeyStore()
	if err != nil {
		return errors.Wrap(err, "failed to make keystore")
	}

	azpResourcesRepo := a.makeAZPRepo(dbBreaker, globalIDMigrator, githubTwirpClient)
	azpClients, err := a.setupAZPClientFactory(
		ctx,
		*httpClients,
		githubTwirpClient,
		a.cfg.AzureProviderConfig,
		a.cfg.BreakerConfig,
		a.obs,
		ks,
		azpResourcesRepo,
		cache,
		a.cfg.Environment(),
		a.cfg.IsEnterprise(),
	)
	if err != nil {
		return err
	}

	a.azpClients = azpClients

	tenantKeyGenerator := azpwfb.NewBufferedTenantKeyGenerator(
		a.cfg.TenantKeyGeneratorBufferSize,
		a.cfg.TenantKeyGeneratorWorkers,
		a.obs,
	)
	tenantHandler := azpwfb.NewTenantHandler(
		a.azpClients.S2sClient,
		ks,
		a.obs,
		azpClients.RepositoryClientFactory,
		azpResourcesRepo,
		tenantKeyGenerator,
		a.cfg.Environment(),
		githubTwirpClient,
	)

	appMetadata := cli.GetApplicationMetadata(a.ServiceName())

	aqueductFactory := aqueduct.NewFactory(http.DefaultClient)
	clientOptions := &aqueduct.ClientOptions{
		App:           a.cfg.AqueductApp,
		URL:           a.cfg.AqueductURL,
		APIKey:        a.cfg.AqueductAPIKey,
		APIKeyVersion: a.cfg.AqueductAPIKeyVersion,
		WorkerID:      42,
	}
	resultsClientOptions := &aqueduct.ClientOptions{
		App:           a.cfg.AqueductApp,
		URL:           a.cfg.AqueductURL,
		APIKey:        a.cfg.ResultsAqueductAPIKey,
		APIKeyVersion: a.cfg.ResultsAqueductAPIKeyVersion,
		WorkerID:      42,
	}
	aqueductBreaker, err := abreaker.NewAqueductDeployerClientBreaker(ctx, a.obs, a.cfg.BreakerConfig)
	if err != nil {
		return errors.Wrap(err, "could not build breaker for payloads aqueduct client")
	}
	aqueductClient, err := aqueductFactory.NewClient(stats, aqueductBreaker, clientOptions)
	if err != nil {
		return errors.Wrap(err, "error creating Aqueduct client")
	}
	resultsAqueductClient, err := aqueductFactory.NewClient(stats, aqueductBreaker, resultsClientOptions)
	if err != nil {
		return errors.Wrap(err, "error creating Aqueduct client")
	}

	scheduleCfg := schconfig.ScheduledConfig{
		LoopSleepDuration:         a.cfg.ScheduledLoopSleep,
		ReassignWorkAfterDuration: a.cfg.ScheduledReassignWorkAfter,
		ScatterOffsetDuration:     a.cfg.ScheduledScatterOffset,
		TasksPerTick:              a.cfg.ScheduledTaskPerTick,
		TierCacheExpiration:       a.cfg.ScheduledTierCacheExpiration,
		Environment:               appMetadata.Environment,
		AqueductQueueScheduled:    a.cfg.AqueductQueueScheduled,
		AqueductApp:               a.cfg.AqueductApp,
	}
	scheduleStore := schedules.New(
		adb,
		log,
		model.NewScheduleParser(),
		scheduleCfg,
		clock.New(),
		stats,
		globalIDMigrator,
		githubTwirpClient.IsFeatureEnabledForActor,
	)

	var authzdClient authzd.Client
	var workflowSourceFactory workflowinvoker.WorkflowSourceFactory

	authzdBreaker, err := abreaker.NewAuthzdClientBreaker(ctx, a.obs, a.cfg.BreakerConfig)
	if err != nil {
		return errors.Wrap(err, "could not build breaker for authz client")
	}
	var aerr error
	authzdClient, aerr = makeAuthzdClient(a, authzdBreaker, appMetadata.BuildVersion, http.DefaultClient, twirpOpts)
	if aerr != nil {
		return errors.Wrap(aerr, "setting up authzd client")
	}

	spokesdBreaker, err := abreaker.NewSpokesdClientBreaker(ctx, a.obs, a.cfg.BreakerConfig)
	if err != nil {
		return errors.Wrap(err, "could not build breaker for spokesd client")
	}
	spokesdClient, serr := makeSpokesdClient(a, log, stats, spokesdBreaker, appMetadata.BuildVersion)
	if serr != nil {
		return errors.Wrap(serr, "setting up spokesd client")
	}

	workflowSourceFactory = workflowinvoker.SpokesdWorkflowSourceFactory(
		authzdClient,
		spokesdClient,
		githubTwirpClient,
		logger.AdaptToFieldLogger(ctx, log),
		a.obs,
	)
	log.Debug(ctx, "created spokesd workflow factory")

	scheduleManager := schedulemanager.New(
		&schedulemanager.Config{
			Environment:  appMetadata.Environment,
			IsEnterprise: a.cfg.IsEnterprise(),
		},
		a.obs,
		scheduleStore,
		clientFactory,
		githubTwirpClient,
		azpResourcesRepo,
		workflowSourceFactory,
	)
	scheduledSubService := scheduled.New(
		scheduleCfg,
		scheduleStore,
		log,
		clientFactory,
		githubTwirpClient,
		aqueductClient,
		stats,
		hostname,
		appMetadata,
		a.cfg.IsEnterprise(),
		a.cfg.IsMultiTenant,
		cache.LaunchDependency(),
	)

	healer := buildhealer.New(a.obs, clientFactory, githubTwirpClient, a.workflowBuildsRepo)
	canceler := workflowcanceler.NewWorkflowCanceler(
		a.obs, &healer, a.workflowBuildsRepo, azpClients.RepositoryClientFactory, a.hydroEmitter, githubTwirpClient)

	reporter := adminevents.NewAdminEventsReporter(
		a.obs, a.workflowBuildsRepo, azpClients.RepositoryClientFactory, azpResourcesRepo, githubTwirpClient)

	internal := ghinternal.NewFactory(
		apiBase,
		a.obs,
		breaker,
		[]byte(a.cfg.HMACKeyInternalAPI),
		httpClients.Default,
		reqobs.NewHTTPClientHooks(a.obs),
	)

	dbROBreaker, err := abreaker.NewLaunchRODBClientBreaker(ctx, a.obs, a.cfg.BreakerConfig)
	if err != nil {
		return errors.Wrap(err, "could not build breaker for launch ro db client")
	}
	adbReadOnly := asql.New(a.dbRo, log, stats, dbROBreaker, asql.LaunchROCluster)
	workflowBuildsRepoReadOnly := deployer.NewWorkflowBuildsRepositoryReadOnly(adbReadOnly, log, stats, clock.New(), globalIDMigrator, a.cfg.IsMultiTenant)
	apiTokenService := tokensvc.New(
		log,
		stats,
		workflowBuildsRepoReadOnly,
		workflowbuild.NewTokenFactory(tokenService, githubTwirpClient.IsFeatureEnabledForRepoOrOwners, launchconfig.AppEnv(a.cfg.LaunchEnv)),
		a.cfg.IsMultiTenant,
	)

	defaultTwirpHooks := twirp.ChainHooks(
		twirphooks.DefaultHooks(),
		twirpstats.DefaultHooks(stats.Client()),
		twirpauth.VerifyRequestHMACHooks(a.cfg.DeployerHMACVerifySecrets()...),
		observability.EnableTwirpRequestMetadata(),
		oteltwirp.NewServerHooks(),
	)

	twirpTokensHandler := token.NewLaunchTokenServiceServer(apiTokenService, defaultTwirpHooks)
	registerTwirpService(ctx, a.obs, svc, twirpTokensHandler, "tokens")

	jobsRepository := deployer.NewJobsRepository(adb, a.obs, globalIDMigrator)
	resolverTokenFactory, err := resolver.NewTokenFactory(a.cfg.LaunchEnv, a.cfg.ResolverConfig, httpClients.Default, a.obs)
	if err != nil {
		log.Error(ctx, "failed to create resolver token factory", kvp.Err(err))
	} else if resolverTokenFactory != nil {
		log.Log(ctx, "successfully created resolver token factory")
	} else {
		log.Log(ctx, "resolver application is not configured")
	}

	azpResourcesLoader := a.makeAZPResourcesLoader(globalIDMigrator)
	deployerSvc := deploysvc.New(
		hostname,
		a.db,
		kredzClient,
		a.workflowBuildsRepo,
		azpResourcesRepo,
		azpResourcesLoader,
		log,
		a.obs,
		stats,
		a.hydroEmitter,
		clientFactory,
		githubTwirpClient,
		githubBillingTwirpClient,
		aqueductClient,
		a.cfg.AqueductQueueDynamic,
		a.cfg.AqueductApp,
		internal,
		a.workers,
		canceler,
		workflowSourceFactory,
		reporter,
		a.cfg.AppID,
		scheduleManager,
		launchconfig.AppEnv(a.cfg.LaunchEnv),
		hmac.NewVerifier(hmac.NewSigner()),
		a.azpClients.S2sClient,
		a.azpClients.KeyVaultClient,
		a.cfg.AzureProviderConfig,
		tenantHandler,
		workflowbuild.NewTokenFactory(tokenService, githubTwirpClient.IsFeatureEnabledForRepoOrOwners, launchconfig.AppEnv(a.cfg.LaunchEnv)),
		tokenService,
		jobsRepository,
		resolverTokenFactory,
		a.cfg.IsEnterprise(),
		a.cfg.EnterpriseVersion,
		authzdClient,
		cache.GitHubTwirp(),
		globalIDMigrator,
		a.cfg.IsMultiTenant,
		billingClient,
	)

	twirpDeployHandler := deploy.NewLaunchDeploymentServiceServer(deployerSvc, defaultTwirpHooks)
	registerTwirpService(ctx, a.obs, svc, twirpDeployHandler, "deploy")

	scheduledSubService.RegisterWorkers(a.workers)
	shr := selfhostedrunners.New(
		log,
		stats,
		clientFactory,
		azpClients.RepositoryClientFactory,
		azpResourcesRepo,
		jobsRepository,
		a.cfg.Environment(),
		a.cfg.IsMultiTenant,
		githubTwirpClient.IsFeatureEnabledForActor,
	)
	twirpSHRHandler := selfhostedrunners.NewSelfHostedRunnersServer(shr, defaultTwirpHooks)
	registerTwirpService(ctx, a.obs, svc, twirpSHRHandler, "selfhostedrunners")

	runnerGroups := runnergroups.New(
		log,
		stats,
		clientFactory,
		azpClients.RepositoryClientFactory,
		azpResourcesRepo,
	)
	twirpRunnerGroupsHandler := runnergroups.NewRunnerGroupsServer(runnerGroups, defaultTwirpHooks)
	registerTwirpService(ctx, a.obs, svc, twirpRunnerGroupsHandler, "runnergroups")

	largerRunners := largerrunners.New(
		log,
		stats,
		azpClients.RepositoryClientFactory,
		azpResourcesRepo,
		jobsRepository,
	)
	twirpLargerRunnersHandler := largerrunners.NewLargerRunnersServer(largerRunners, defaultTwirpHooks)
	registerTwirpService(ctx, a.obs, svc, twirpLargerRunnersHandler, "largerrunners")

	statusService := status.New(
		log,
		stats,
		azpResourcesRepo,
		a.workflowBuildsRepo,
		jobsRepository,
		clientFactory,
		githubTwirpClient,
		azpClients.RepositoryClientFactory,
		a.cfg.IsLab(),
		a.hydroEmitter,
		resultsAqueductClient,
		a.cfg.LaunchEnv,
		a.cfg.IsMultiTenant,
	)
	twirpStatusHandler := status.NewLaunchStatusServiceServer(statusService, defaultTwirpHooks)
	registerTwirpService(ctx, a.obs, svc, twirpStatusHandler, "status")

	artifactsExchangeService := artifactsexchange.New(
		log,
		stats,
		azpClients.RepositoryClientFactory,
		azpResourcesRepo,
		a.workflowBuildsRepo,
	)
	twirpArtifactsExchangeHandler := artifactsexchange.NewActionsArtifactExchangeServer(artifactsExchangeService, defaultTwirpHooks)

	registerTwirpService(ctx, a.obs, svc, twirpArtifactsExchangeHandler, "artifactsexchange")
	log.Debug(ctx, "successfully registered artifacts exchange service")

	environmentSvc := environment.New(
		log,
		stats,
		azpClients.RepositoryClientFactory,
		azpResourcesRepo,
		clientFactory,
		a.workflowBuildsRepo,
		githubTwirpClient,
		a.cfg.IsMultiTenant,
	)
	twirpEnvironmentHandler := environment.NewEnvironmentServer(environmentSvc, defaultTwirpHooks)
	registerTwirpService(ctx, a.obs, svc, twirpEnvironmentHandler, "environment")

	artifactCacheSvc := artifactcache.New(
		log,
		stats,
		azpClients.RepositoryClientFactory,
		azpResourcesRepo,
	)
	twirpCacheHandler := artifactcache.NewArtifactCacheServer(artifactCacheSvc, defaultTwirpHooks)
	registerTwirpService(ctx, a.obs, svc, twirpCacheHandler, "artifactcache")

	checksSvc := checks.New(
		log,
		stats,
		azpClients.RepositoryClientFactory,
		azpResourcesRepo,
	)
	twirpChecksHandler := checks.NewChecksServer(checksSvc, defaultTwirpHooks)
	registerTwirpService(ctx, a.obs, svc, twirpChecksHandler, "checks")

	runnerScaleSetsSvc := runnerscalesets.New(
		log,
		stats,
		azpClients.RepositoryClientFactory,
		azpResourcesRepo,
	)
	twirpRunnerScaleSetsHandler := runnerscalesets.NewRunnerScaleSetsServer(runnerScaleSetsSvc, defaultTwirpHooks)
	registerTwirpService(ctx, a.obs, svc, twirpRunnerScaleSetsHandler, "runnerscalesets")

	log.Debug(ctx, "launch-deployer registered",
		kvp.String("gh.launch.app.mode", a.cfg.AppMode().String()),
		kvp.String("gh.launch.build_version", svc.Config.BuildVersion),
		kvp.String("gh.launch.api_host", a.cfg.APIHost),
		kvp.String("gh.launch.v3_api_endpoint", a.cfg.V3APIEndpoint),
		kvp.String("gh.launch.graphql_endpoint", a.cfg.GraphQLEndpoint),
		kvp.Int64("gh.launch.github_app.id", a.cfg.AppID),
		kvp.String("gh.launch.site", metadata.GetSite()),
	)

	return nil
}

func (a *application) makeAZPRepo(breaker *circuit.Breaker, gidMigrator deployer.GlobalIDMigrator, ghTwirpClient ghtwirp.Client) deployer.AzpResourcesRepository {

	adb := asql.New(a.db, a.obs.Logger, a.obs.Statter, breaker, asql.LaunchCluster)

	return deployer.NewAZPResourcesRepo(
		adb,
		a.cfg.Environment(),
		a.obs,
		a.cfg.AzureProviderConfig.ResourcesLockPollFreq,
		a.cfg.AzureProviderConfig.ResourcesLockTimeout,
		gidMigrator,
		ghTwirpClient,
	)
}

func (a *application) makeAZPResourcesLoader(gidMigrator deployer.GlobalIDMigrator) deployer.AzpResourcesLoader {
	dbBreaker := circuit.NewConsecutiveBreaker(int64(a.cfg.MySQLBreakerConsecutiveErrors))
	adb := asql.New(a.db, a.obs.Logger, a.obs.Statter, dbBreaker, asql.LaunchCluster)

	return deployer.NewAZPResourcesLoader(
		a.obs,
		adb,
		gidMigrator,
	)
}

func (a *application) makeKeyStore() (keystore.Store, error) {
	if a.cfg.IsEnterprise() {
		return keystore.NewNullStore(keystore.NewEncoder()), nil
	}

	if a.cfg.KeystoreAZPOrganizationKey == "" {
		return nil, errors.New("keystore:azp:organization key not found for keystore")
	}
	return keystore.NewStore(a.cfg.KeystoreAZPOrganizationKey, a.obs.Logger, a.obs.Statter), nil
}

// BeforeShutdown is called before the application stops processing requests.
func (a *application) BeforeShutdown(ctx context.Context, _ *mu.Service) error { // nolint: unparam
	if a.workers != nil {
		a.obs.Logger.Debug(ctx, "stopping workers", kvp.Int64("gh.launch.active_worker_count", a.workers.Active()))
		a.workers.Stop()
		a.obs.Logger.Debug(ctx, "all workers stopped", kvp.Int64("gh.launch.active_worker_count", a.workers.Active()))
	}

	return nil
}

// OnShutdown runs when the application is ready to shut down.
// This is called after all request processing has finished.
func (a *application) OnShutdown(ctx context.Context, _ *mu.Service) error {
	if a.hydroEmitter != nil {
		a.hydroEmitter.Close()
	}

	if a.db != nil {
		err := a.db.Close()
		if err != nil {
			return errors.Wrap(err, "error closing main database connection")
		}
	}

	if a.dbRo != nil {
		err := a.dbRo.Close()
		if err != nil {
			return errors.Wrap(err, "error closing readonly database connection")
		}
	}
	if a.PayloadsCluster != nil {
		err := a.PayloadsCluster.Close()
		if err != nil {
			return errors.Wrap(err, "error closing payloads database connection")
		}
	}

	for _, closer := range a.closers {
		if err := closer(); err != nil {
			return errors.Wrap(err, "error invoking closer")
		}
	}

	a.obs.Logger.Debug(ctx, "closed resources")

	return nil
}

func (a *application) OnHealthCheck(_ *mu.Service) (string, map[string]any) {
	return "OK", map[string]any{}
}

func makeSpokesdClient(a *application, log logger.Logger, stats statter.Statter, breaker *circuit.Breaker, buildVersion string) (spokesd.Client, error) {
	cfg := a.cfg

	if cfg.SpokesdURL == "" {
		return nil, errors.New("SpokesdURL is required")
	}

	var httpClient *http.Client
	if cfg.IsDevelopment() || cfg.IsEnterprise() {
		// GHES and Development env uses local spokesd
		// so do not require authentication
		httpClient = apphttp.NewClient(
			apphttp.WithMaxTimeout(spokesd.MaxTimeout),
		)
	} else {
		var tlsCfg *tls.Config
		var err error

		opts := []apphttp.Option{
			apphttp.WithObservability(observability.New(log, stats), cfg.RoundTripperConfig),
			apphttp.WithMaxTimeout(spokesd.MaxTimeout),
		}

		if cfg.SpokesdConfigTLS {
			tlsCfg, err = spokesd.LoadTLSConfig(cfg.SpokesdCert, cfg.SpokesdKey, cfg.SpokesdChain)
			if err != nil {
				return nil, errors.Wrap(err, "loading TLS key pair")
			}
			opts = append(opts, apphttp.WithTLSClientConfig(tlsCfg))
		}

		httpClient = apphttp.NewClient(opts...)
	}

	twirpTelemetry := reqobs.NewTwirpMetricsHooks(stats)
	twirpOpts := reqobs.AdaptTwirpHooksToClientOptions(twirpTelemetry, time.Now)

	client, err := spokesd.NewClient(spokesd.Config{
		SpokesdURL:   cfg.SpokesdURL,
		BuildVersion: buildVersion,
		ServiceName:  "launch-deployer",
	}, httpClient, stats, breaker, twirpOpts)

	if err != nil {
		return nil, errors.Wrap(err, "making spokesd client")
	}

	return client, nil
}

func makeAuthzdClient(a *application, breaker *circuit.Breaker, buildVersion string, httpClient *http.Client, twirpOpts []twirp.ClientOption) (authzd.Client, error) {
	cfg := a.cfg

	if cfg.AuthzdURL == "" {
		return nil, errors.New("AuthzdURL is required")
	}

	client, err := authzd.NewClient(authzd.Config{
		AuthzdURL:    cfg.AuthzdURL,
		BuildVersion: buildVersion,
		ServiceName:  "launch-deployer",
	}, a.obs, breaker, httpClient, twirpOpts)
	if err != nil {
		return nil, errors.Wrap(err, "making authzd client")
	}

	return client, nil
}

type httpClients struct {
	AZP, Default, GitHubBilling *http.Client
}

func buildHTTPClients(obs *observability.Observability, cfg Config, ffcache launchcache.GitHubTwirpCache, twirpOpts []twirp.ClientOption) (*httpClients, error) {
	defaultOpts := []apphttp.Option{apphttp.WithObservability(obs, cfg.RoundTripperConfig)}
	azpOpts := []apphttp.Option{apphttp.WithObservability(obs, cfg.RoundTripperConfig), apphttp.WithIgnoreRedirects(), apphttp.WithAzureFrontDoorMaxTimeout()}
	githubBillingOpts := []apphttp.Option{apphttp.WithMaxTimeout(time.Second * 10), apphttp.WithObservability(obs, cfg.RoundTripperConfig)}

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
		githubBillingOpts = append(githubBillingOpts, chaosOption)
	}

	hc := &httpClients{
		Default:       apphttp.NewClient(defaultOpts...),
		AZP:           apphttp.NewClient(azpOpts...),
		GitHubBilling: apphttp.NewClient(githubBillingOpts...),
	}
	return hc, nil
}

func (a *application) setupAZPClientFactory(
	ctx context.Context,
	hcls httpClients,
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

	kvc := a.buildKeyVaultClient(breakers.KeyVaultBreaker, obs, hcls.Default, cache)

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

func (a *application) buildKeyVaultClient(breaker *circuit.Breaker, obs *observability.Observability, httpBackend *http.Client, cache launchcache.Cache) azp.KeyVaultClient {
	btc := azpbearer.New(
		httpclient.New(httpBackend),
		azpbearer.WithBreaker(breaker),
		azpbearer.WithCache(cache.AzureProvider()),
		azpbearer.WithHooks(reqobs.NewHTTPClientHooks(obs)),
	)
	ts := tokensrc.ForKeyVault(a.cfg.AzureProviderConfig, btc, jwt.CertificateRotationEmitter(obs, jwt.ForKeyVault))
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
