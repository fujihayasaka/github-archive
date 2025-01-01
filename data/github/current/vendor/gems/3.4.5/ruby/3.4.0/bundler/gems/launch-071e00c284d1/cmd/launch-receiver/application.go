package main

import (
	"context"
	"encoding/base64"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/Shopify/sarama"
	"github.com/facebookgo/clock"
	diet_earthsmoke "github.com/github/diet_earthsmoke/go"
	"github.com/github/go-config/v2"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/hydro-client-go/v3/pkg/hydro"
	"github.com/pkg/errors"
	"github.com/redis/go-redis/v9"
	"github.com/twitchtv/twirp"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

	"github.com/github/launch/pkg/mu"
	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"
	"github.com/github/launch/pkg/payloads"

	kredzpb "github.com/github/kredz/services/protobuf/credz"
	varzpb "github.com/github/kredz/services/protobuf/varz"

	"github.com/github/launch/auth/hmac"
	"github.com/github/launch/clients/billingplatform"
	clients_earthsmoke "github.com/github/launch/clients/earthsmoke"
	"github.com/github/launch/clients/freno"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/kredz"
	"github.com/github/launch/clients/launchblob"
	"github.com/github/launch/clients/launchredis"
	"github.com/github/launch/clients/launchtwirp"
	"github.com/github/launch/clients/varz"
	"github.com/github/launch/constants"
	"github.com/github/launch/db/stores/deployer"
	dbpayloads "github.com/github/launch/db/stores/payloads"
	"github.com/github/launch/hydro/events"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/logger/kafkalog"
	"github.com/github/launch/observability/measurehttp"
	"github.com/github/launch/observability/reqobs"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/abreaker"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/azp/azkeyvault"
	"github.com/github/launch/pkg/azp/azpbearer"
	"github.com/github/launch/pkg/azp/azpbearer/jwt"
	"github.com/github/launch/pkg/azp/azpbearer/tokensrc"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchchaos"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/pkg/launchserver"
	"github.com/github/launch/services/auth/hkdf"
	tokenauth "github.com/github/launch/services/auth/token"
	deployerEnv "github.com/github/launch/services/deploy/environment"
	deployerStatus "github.com/github/launch/services/deploy/status"
	"github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/services/pb/deploy/token"
	"github.com/github/launch/services/receiver/abuse"
	"github.com/github/launch/services/receiver/accountdetails"
	"github.com/github/launch/services/receiver/auditlog"
	"github.com/github/launch/services/receiver/billing"
	actions_cache "github.com/github/launch/services/receiver/cache"
	environment "github.com/github/launch/services/receiver/environment"
	"github.com/github/launch/services/receiver/globalid"
	idmapping "github.com/github/launch/services/receiver/id_mapping"
	"github.com/github/launch/services/receiver/networksettings"
	"github.com/github/launch/services/receiver/prejobtoken"
	"github.com/github/launch/services/receiver/refreshjobtoken"
	resolveactions "github.com/github/launch/services/receiver/resolve_actions"
	"github.com/github/launch/services/receiver/revokejobtoken"
	runnerresolveactions "github.com/github/launch/services/receiver/runner_resolve_actions"
	"github.com/github/launch/services/receiver/status"
	"github.com/github/launch/utils"
	"github.com/github/launch/utils/ahttp"
	"github.com/github/launch/utils/apphttp"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/workflowbuild"
)

const (
	actionsAppRealmWideHmacKey = "actionsAppRealmWideHmacKey"
)

var _ Application

type Application struct {
	cfg     Config
	closers []func() error
}

func newApplication() *Application {
	return &Application{}
}

func (a *Application) ServiceName() string {
	return "launch-receiver"
}

// OnConfig runs before the mu service is started up.
func (a *Application) OnConfig(_ *mu.Config) error {
	if err := launchconfig.LoadGlobalConfig(); err != nil {
		return err
	}

	if err := config.Load(&a.cfg); err != nil {
		return err
	}

	return a.cfg.Validate()
}

// OnStartUp runs when the application is ready to start.
//
//gocyclo:ignore
func (a *Application) OnStartUp(svc *mu.Service) error {
	ctx, ctxCancel := context.WithCancel(context.Background())
	a.closers = append(a.closers, func() error {
		ctxCancel()
		return nil
	})

	err := a.cfg.AzureProviderConfig.Parse()
	if err != nil {
		return err
	}

	log := svc.Config.NewLogger(a.cfg.CommonConfig.LoggerConfig)

	stats := svc.Config.NewStatter()
	stats.Start()

	obs := observability.New(log, stats)

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
		redisClient, err = launchredis.New(ctx, a.cfg.RedisConfig, obs)
		if err != nil {
			return err
		}
		a.closers = append(a.closers, redisClient.Close)
	}
	redisBreaker, err := abreaker.NewRedisReceiverBreaker(ctx, obs, a.cfg.BreakerConfig)
	if err != nil {
		return err
	}
	cache := launchcache.NewSharedCache(redisClient, redisBreaker, a.cfg.CacheConfig, obs)

	twirpTelemetry := reqobs.NewTwirpMetricsHooks(stats)
	twirpOpts := reqobs.AdaptTwirpHooksToClientOptions(twirpTelemetry, time.Now)

	httpClients, err := buildHTTPClients(obs, a.cfg, cache.GitHubTwirp(), twirpOpts)
	if err != nil {
		return err
	}

	log.Debug(ctx, "launch-receiver registered",
		kvp.String("gh.launch.app.mode", a.cfg.AppMode().String()),
		kvp.String("gh.launch.mu.build_version", svc.Config.BuildVersion),
	)

	dbOptions := &utils.DatabaseOptions{
		EmulatePreparedStatements: a.cfg.EmulatePreparedStatements,
		UseUTCForMySQL:            a.cfg.UseUTCForMySQL,
		ForceCharsetForMySQL:      a.cfg.ForceCharsetForMySQL,
		MySQLMaxOpenConns:         a.cfg.MySQLMaxOpenConns,
		MySQLMaxIdleConns:         a.cfg.MySQLMaxIdleConns,
		MySQLMaxIdleTime:          a.cfg.MySQLMaxIdleTime,
		MySQLMaxLifetime:          a.cfg.MySQLMaxLifetime,
	}

	dbConn, err := utils.GetDatabaseConnection(a.cfg.DatabaseURL, stats, dbOptions)
	if err != nil {
		return errors.Wrap(err, "error connecting to mysql")
	}

	deployerTwirpBreaker, err := abreaker.NewDeployerTwirpClientBreaker(ctx, obs, a.cfg.BreakerConfig)
	if err != nil {
		return err
	}

	twirpClient, err := launchtwirp.NewClient([]string{a.cfg.DeployerHMACSigningSecret}, deployerTwirpBreaker, stats, httpClients.Default)
	if err != nil {
		return err
	}

	deployerTwirpClient := deploy.NewLaunchDeploymentServiceProtobufClient(a.cfg.DeployerTWIRPAddr, twirpClient, twirpOpts...)

	githubTwirpBreaker, err := abreaker.NewGithubTwirpClientBreaker(ctx, obs, a.cfg.BreakerConfig)
	if err != nil {
		return err
	}

	var ghTwirpClient ghtwirp.Client
	ghTwirpClient, err = ghtwirp.NewClient(
		a.cfg.GitHubTwirpAddr,
		a.cfg.GitHubTwirpHMACSecret,
		obs,
		a.cfg.LaunchEnv,
		cache.GitHubTwirp(),
		ahttp.NewRetryClient(githubTwirpBreaker, obs.Statter, httpClients.Default, "ghtwirp"),
		twirpOpts,
		launchconfig.IsMultiTenant(),
	)
	if err != nil {
		return errors.Wrap(err, "error creating GitHub Twirp client")
	}

	if a.cfg.IsEnterprise() {
		ghTwirpClient = ghtwirp.NewEnterpriseClient(ghTwirpClient)
	}

	var keyGenerators []hkdf.KeyGenerator
	for _, key := range strings.Split(a.cfg.ActionRunnerSecret, ",") {
		keyGenerators = append(keyGenerators, hkdf.NewKeyGenerator([]byte(key)))
	}

	statusTwirpClient := deployerStatus.NewLaunchStatusServiceProtobufClient(a.cfg.DeployerTWIRPAddr, twirpClient, twirpOpts...)

	// For the status verifier, we assume that the duration here is set to the
	// default value of 1 hour. Therefore, we have an 8 hour validity period (builds
	// timeout after 6 hours, but we add a 2 hour buffer just in case the
	// postbacks are delayed for any reason).
	statusVerifier := hkdf.NewVerifier(keyGenerators, constants.ActionRunnerStatusSecretDuration)

	statusRc := &status.Servicer{
		Stats:         stats,
		Log:           log,
		Deployer:      statusTwirpClient,
		Verifier:      statusVerifier,
		IsLab:         a.cfg.IsLab(),
		IsDevelopment: a.cfg.IsDevelopment(),
		ReceiverURL:   a.cfg.ReceiverURL,
		GHTwirpClient: ghTwirpClient,
	}

	svc.RouteService(statusRc, defaultMiddleware(obs, svc.Config)...)

	resolveActionsRc := &resolveactions.Servicer{
		Obs:         observability.New(log, stats),
		Verifier:    statusVerifier,
		Deployer:    deployerTwirpClient,
		IsLab:       a.cfg.IsLab(),
		ReceiverURL: a.cfg.ReceiverURL,
	}

	svc.RouteService(resolveActionsRc, defaultMiddleware(obs, svc.Config)...)

	tokenAuthClient, err := getTokenAuthClient(ctx, a.cfg, log)
	if err != nil {
		return err
	}

	runnerResolveActionsRc := &runnerresolveactions.Servicer{
		Obs:           observability.New(log, stats),
		AuthClient:    tokenAuthClient,
		Deployer:      deployerTwirpClient,
		IsLab:         a.cfg.IsLab(),
		GHTwirpClient: ghTwirpClient,
	}
	middlewares := defaultMiddleware(obs, svc.Config)

	middlewares = append(middlewares, tokenAuthClient.AuthenticationMiddleware(log))
	svc.RouteService(runnerResolveActionsRc, middlewares...)

	tokenTwirpClient := token.NewLaunchTokenServiceProtobufClient(a.cfg.DeployerTWIRPAddr, twirpClient, twirpOpts...)

	// The token verifier uses the same settings as the status verifier.
	tokenVerifier := hkdf.NewVerifier(keyGenerators, constants.ActionRunnerStatusSecretDuration)

	abuseStatusRc := abuse.NewServicer(
		log,
		stats,
		deployerTwirpClient)

	svc.RouteService(abuseStatusRc, defaultMiddleware(obs, svc.Config)...)

	publisher, err := newEventPublisherForKafka(ctx, a.cfg, log, stats)
	if err != nil {
		e := errors.Wrap(err, "creating event publisher for kafka")
		log.Error(ctx, e.Error())
		return e
	}

	hydroEmitter, err := events.NewEmitter(
		publisher,
		events.WithLogger(log),
		events.WithStatter(stats))
	if err != nil {
		return err
	}

	dbBreaker, err := abreaker.NewLaunchDBClientBreaker(ctx, obs, a.cfg.BreakerConfig)
	if err != nil {
		return err
	}

	aconn := asql.New(dbConn, obs.Logger, obs.Statter, dbBreaker, asql.LaunchCluster)
	globalIDMigrator := deployer.NewGlobalIDMigrator(ghTwirpClient)

	deployerDB := deployer.NewAZPResourcesLoader(
		obs,
		aconn,
		globalIDMigrator,
	)

	var payloadsRepo payloads.Store
	if launchconfig.UsingPayloadsBlobStorage() {
		bc, err := launchblob.NewClient(a.cfg.BlobConfig, log, stats, httpClients.Default)
		if err != nil {
			return errors.Wrap(err, "error creating blob client")
		}

		payloadMetadataRepo := deployer.NewPayloadMetadataStoreSQL(aconn, log, stats, clock.New())

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

		payloadsBreaker, err := abreaker.NewPayloadsClientBreaker(ctx, obs, a.cfg.BreakerConfig)
		if err != nil {
			return errors.Wrap(err, "could not build breaker for payloads db client")
		}

		payloadsRepo = dbpayloads.New(asql.New(payloadsClusterConnection, log, stats, payloadsBreaker, asql.PayloadsCluster), log, stats)
	}

	executionsRepo := deployer.NewWorkflowBuildExecutionsRepository(aconn, obs, clock.New(), globalIDMigrator)

	workflowBuildsRepo := deployer.NewWorkflowBuildsRepository(aconn, log, stats, clock.New(), payloadsRepo, executionsRepo, globalIDMigrator, a.cfg.IsMultiTenant)

	keyVaultClient, err := a.buildKeyVaultClient(ctx, obs, httpClients.KeyVault, cache)
	if err != nil {
		return err
	}

	auditLogCfg := &auditlog.Config{
		IsDevelopment:               a.cfg.IsDevelopment(),
		IsEnterprise:                a.cfg.IsEnterprise(),
		IsMultiTenant:               a.cfg.IsMultiTenant,
		ActionsAuthHmacKeyPrimary:   a.cfg.ActionsAuthHMACKeyPrimary,
		ActionsAuthHmacKeySecondary: a.cfg.ActionsAuthHMACKeySecondary,
	}

	auditlogSvc := auditlog.NewService(
		auditLogCfg,
		obs,
		hydroEmitter,
		deployerDB,
		a.cfg.AzureProviderConfig.AuthVaultName,
		keyVaultClient,
		hmac.NewVerifier(hmac.NewSigner()),
		ghTwirpClient)
	svc.RouteService(auditlogSvc, defaultMiddleware(obs, svc.Config)...)
	hmacHTTPVerifier, err := getHmacHTTPVerifier(actionsAppRealmWideHmacKey, a.cfg, keyVaultClient, obs)
	if err != nil {
		return err
	}

	var billingClient billingplatform.Client

	if a.cfg.IsEnterprise() {
		log.Debug(ctx, "Billing platform client not created for enterprise - using no-op client")
		billingClient = billingplatform.NewNopClient(obs.Logger)
	} else {
		var billingPlatformClient billingplatform.Client

		billingPlatformTwirpBreaker, err := abreaker.NewBillingPlatformTwirpClientBreaker(ctx, obs, a.cfg.BreakerConfig)
		if err != nil {
			return errors.Wrap(err, "could not build breaker for twirp billing platform client")
		}

		billingPlatformRetryClient := ahttp.NewRetryClient(billingPlatformTwirpBreaker, obs.Statter, httpClients.Default, "billingplatformtwirp")

		if a.cfg.BillingPlatformURL != "" && a.cfg.BillingPlatformHMACSecret != "" {
			billingPlatformClient, err = billingplatform.NewHMACClientFromHTTPClient(billingPlatformRetryClient, a.cfg.BillingPlatformURL, a.cfg.BillingPlatformHMACSecret, obs.Statter, ghTwirpClient)
			if err != nil {
				return errors.Wrap(err, "error creating billing platform client")
			}
			log.Debug(ctx, "successfully created billing platform client")
		} else {
			return errors.New("billing platform URL or HMAC secret not set")
		}

		billingClient = billingPlatformClient
	}

	billingSvc := billing.NewService(
		obs,
		deployerDB,
		hmacHTTPVerifier,
		ghTwirpClient,
		billingClient,
	)
	svc.RouteService(billingSvc, defaultMiddleware(obs, svc.Config)...)

	accountDetailsSvc := accountdetails.NewService(
		obs,
		deployerDB,
		hmacHTTPVerifier,
		ghTwirpClient,
	)
	svc.RouteService(accountDetailsSvc, defaultMiddleware(obs, svc.Config)...)

	cacheSvc := actions_cache.NewService(
		obs,
		hydroEmitter,
		hmacHTTPVerifier,
		deployerDB,
	)

	svc.RouteService(cacheSvc, defaultMiddleware(obs, svc.Config)...)

	globalIDSvc := globalid.NewService(
		obs,
		ghTwirpClient,
		hmacHTTPVerifier)

	svc.RouteService(globalIDSvc, defaultMiddleware(obs, svc.Config)...)

	// register the network configuration service proxy API on hosted only
	if !a.cfg.IsEnterprise() {
		decodedNetworkServiceHmacSecret, err := base64.StdEncoding.DecodeString(strings.Split(a.cfg.NetworkConfigServiceKeys, ";")[0])
		if err != nil {
			return err
		}

		networkServiceBreaker, err := abreaker.NewNetworkServiceClientBreaker(ctx, obs, a.cfg.BreakerConfig)
		if err != nil {
			return err
		}

		networkSettingsSvc := networksettings.NewService(
			obs,
			deployerDB,
			hmacHTTPVerifier,
			a.cfg.NetworkConfigServiceURL,
			string(decodedNetworkServiceHmacSecret),
			ahttp.NewRetryClient(networkServiceBreaker, obs.Statter, httpClients.Default, "networkservice"),
			ghTwirpClient,
		)

		svc.RouteService(networkSettingsSvc, defaultMiddleware(obs, svc.Config)...)
	}

	if !a.cfg.IsEnterprise() {
		idMappingSvc := idmapping.NewService(
			obs,
			deployerDB,
			hmacHTTPVerifier,
		)

		svc.RouteService(idMappingSvc, defaultMiddleware(obs, svc.Config)...)
	}

	kredzClient, err := getKredzClient(ctx, a.cfg, httpClients.Default, twirpOpts, obs, stats)
	if err != nil {
		return err
	}

	varzClient, err := getVarzClient(ctx, a.cfg, httpClients.Default, twirpOpts, obs, stats)
	if err != nil {
		return err
	}

	earthsmokeDecryptor, err := a.makeEarthsmokeDecryptor(a.cfg, log, stats)
	if err != nil {
		return errors.Wrap(err, "failed to create earthsmoke decryptor")
	}

	breaker, err := abreaker.NewFrenoClientBreaker(ctx, obs, a.cfg.BreakerConfig)
	if err != nil {
		return err
	}
	var frenoclient freno.Client
	if a.cfg.FrenoURL != "" {
		frenoclient, err = freno.NewClient(a.cfg.FrenoURL, a.cfg.FrenoOverrideCluster, reqobs.FrenoHooks(obs), httpClients.Default, breaker)
		if err != nil {
			return err
		}
	} else {
		// GHES and some Proxima stamps do not have Freno, so use a nop client, which
		// always reports databases as being writeable with 0s
		// replication lag.
		frenoclient = freno.NopClient{}
	}

	preJobTokenRc := prejobtoken.NewServicer(
		observability.New(log, stats),
		log,
		stats,
		tokenVerifier,
		workflowBuildsRepo,
		ghTwirpClient,
		tokenTwirpClient,
		deployerTwirpClient,
		a.cfg.ReceiverURL,
		a.cfg.IsLab(),
		kredzClient,
		varzClient,
		earthsmokeDecryptor,
		a.cfg.SecretsAppRelayID,
		frenoclient,
		a.cfg.IsEnterprise(),
	)

	preJobTokenMiddleware := []func(http.Handler) http.Handler{}
	preJobTokenMiddleware = append(preJobTokenMiddleware, defaultMiddleware(obs, svc.Config)...)
	// hook up the otel middleware for the pre-job token endpoint since run-service will call it which has otel data.
	preJobTokenMiddleware = append(preJobTokenMiddleware, otelhttp.NewMiddleware("PreJobToken"))
	svc.RouteService(preJobTokenRc, preJobTokenMiddleware...)

	// we can merge the internalPreJobTokenRc with the preJobTokenRc once we stop having actions-dotnet in Actions
	internalPreJobTokenRc := prejobtoken.NewServicer(
		observability.New(log, stats),
		log,
		stats,
		tokenVerifier,
		workflowBuildsRepo,
		ghTwirpClient,
		tokenTwirpClient,
		deployerTwirpClient,
		a.cfg.ReceiverInternalURL,
		a.cfg.IsLab(),
		kredzClient,
		varzClient,
		earthsmokeDecryptor,
		a.cfg.SecretsAppRelayID,
		frenoclient,
		a.cfg.IsEnterprise(),
	)
	// Match the middleware used for public routes
	internalPreJobTokenMiddleware := []func(http.Handler) http.Handler{
		mw.GitHubRequestID,
		mw.RequestMetadata(reqmeta.NewRequestMetadata()),
		mw.MeasureHTTP(log, stats),
	}
	internalPreJobTokenMiddleware = append(internalPreJobTokenMiddleware, preJobTokenMiddleware...)
	svc.RouteInternal(internalPreJobTokenRc, internalPreJobTokenMiddleware...) // internal route for run-service

	refreshJobTokenRc := &refreshjobtoken.Servicer{
		Log:          log,
		Stats:        stats,
		Verifier:     tokenVerifier,
		TokenService: tokenTwirpClient,
		ReceiverURL:  a.cfg.ReceiverURL,
	}

	svc.RouteService(refreshJobTokenRc, defaultMiddleware(obs, svc.Config)...)

	revokeJobTokenRc := &revokejobtoken.Servicer{
		Log:          log,
		Stats:        stats,
		Verifier:     tokenVerifier,
		TokenService: tokenTwirpClient,
		ReceiverURL:  a.cfg.ReceiverURL,
	}

	svc.RouteService(revokeJobTokenRc, defaultMiddleware(obs, svc.Config)...)

	// Twirp environment client
	deployerEnvironmentClient := deployerEnv.NewEnvironmentProtobufClient(a.cfg.DeployerTWIRPAddr, twirpClient, twirpOpts...)

	environmentRc := &environment.Servicer{
		Log:           log,
		Stats:         stats,
		Verifier:      tokenVerifier,
		Deployer:      deployerEnvironmentClient,
		IsLab:         a.cfg.IsLab(),
		IsEnterprise:  a.cfg.IsEnterprise(),
		ReceiverURL:   a.cfg.ReceiverURL,
		GHTwirpClient: ghTwirpClient,
	}

	svc.RouteService(environmentRc, defaultMiddleware(obs, svc.Config)...)
	return nil
}

// BeforeShutdown is called before the application stops processing requests.
func (a *Application) BeforeShutdown(_ context.Context, _ *mu.Service) error { // nolint: unparam
	return nil
}

// OnShutdown runs when the application is ready to shut down.
// This is called after all request processing has finished.
func (a *Application) OnShutdown(_ context.Context, _ *mu.Service) error { // nolint: unparam
	for _, closer := range a.closers {
		if err := closer(); err != nil {
			return errors.Wrap(err, "error invoking closer")
		}
	}
	return nil
}

func (a *Application) OnHealthCheck(_ *mu.Service) (string, map[string]any) {
	return "OK", map[string]any{}
}

// Kafka-lite is used in launch in production and GHES 3.3 or later
func newEventPublisherForKafka(ctx context.Context, cfg Config, log logger.Logger, statter statter.Statter) (events.EmitterOption, error) {
	log.Debug(ctx, "Setting up event publisher for kafka")

	kc, err := newKafkaConfig(ctx, cfg, log, statter.Client())
	if err != nil {
		return nil, errors.Wrap(err, "setting up kafka config")
	}

	kafkaSink, err := hydro.NewKafkaSink(*kc)
	if err != nil {
		return nil, errors.Wrap(err, "creating kafka sink")
	}

	var site hydro.Site
	if cfg.IsEnterprise() {
		site = hydro.Localhost
	} else {
		site = hydro.CP1IAD
	}

	emo, err := events.WithKafkaPublisher(kafkaSink, site, log, statter)
	if err != nil {
		return nil, errors.Wrap(err, "creating kafka publisher")
	}

	return emo, nil
}

func newKafkaConfig(ctx context.Context, cfg Config, log logger.Logger, stats stats.Client) (*hydro.KafkaConfig, error) {
	if cfg.KafkaBrokers == "disabled" {
		return nil, errors.New("kafka broker is disabled")
	}

	brokers := strings.Split(cfg.KafkaBrokers, ",")
	var logb []kvp.Field
	for _, b := range brokers {
		logb = append(logb, kvp.String("peer.service", b))
	}
	log.Debug(ctx, "connecting to brokers", logb...)

	golog := logger.AdaptToFieldLogger(ctx, log)
	klog := kafkalog.AdaptFieldLoggerToKafkaLogger(golog)
	hydro.SetKafkaLogger(klog)

	kafkaOptions := []hydro.KafkaConfigOption{
		hydro.WithKafkaStats(stats),
		hydro.WithKafkaLogger(klog),
		hydro.WithSaramaConfig(func(scfg *sarama.Config) {
			scfg.Consumer.Offsets.Initial = sarama.OffsetNewest
		}),
	}

	if cfg.IsEnterprise() {
		kafkaOptions = append(kafkaOptions, hydro.WithKafkaVersion(cfg.KafkaVersion))
	} else if cfg.IsDevelopment() {
		// Use a kafka-lite compatible version for the local environment
		kafkaOptions = append(kafkaOptions, hydro.WithKafkaVersion("1.1.1"))
	} else {
		kafkaOptions = append(kafkaOptions, hydro.WithClientID(fmt.Sprintf("launch-reciever-%s", cfg.LaunchEnv)))
		kafkaOptions = append(kafkaOptions, hydro.WithRootCA(cfg.KafkaRootCAPath))
	}

	return hydro.NewKafkaConfig(brokers, kafkaOptions...)
}

func defaultMiddleware(obs *observability.Observability, cfg *mu.Config) []func(http.Handler) http.Handler {
	return []func(http.Handler) http.Handler{
		launchserver.RecoverPanics(obs),
		logHTTPThreshold,
		launchserver.SetupCtxStashMiddleware(&launchserver.CtxStashConfig{
			Name:         cfg.Name,
			BuildVersion: cfg.BuildVersion,
			Host:         mu.AppHost(),
			StatsTags:    stats.Tags(cfg.StatsTags),
		}),
		launchserver.SetupGitHubTenantMiddleware(launchconfig.IsMultiTenant(), obs),
	}
}

func logHTTPThreshold(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		ctx := measurehttp.WithThresholdLogging(r.Context())

		h.ServeHTTP(w, r.WithContext(ctx))

		threshold := measurehttp.GetThreshold(ctx)

		if threshold > 0 {
			duration := time.Since(start)
			withinThreshold := strconv.FormatBool(duration < threshold)
			mw.TagStatsWith(ctx, reqmeta.Tags{"within_threshold": withinThreshold})
		}
	})
}

func (a *Application) makeEarthsmokeDecryptor(cfg Config, log logger.Logger, stats statter.Statter) (clients_earthsmoke.Decryptor, error) {
	if a.cfg.IsEnterprise() {
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

func getHMACKeyConfig(hmacConfigType string, cfg Config, keyVaultClient azp.KeyVaultClient) (hmac.KeyFetcher, error) {
	if hmacConfigType == actionsAppRealmWideHmacKey {
		if cfg.IsEnterprise() || (cfg.IsDevelopment() && cfg.ActionsAppRealmWideHmacKeyPrimary != "") {
			return hmac.NewConfigKeyFetcher(cfg.ActionsAppRealmWideHmacKeyPrimary, cfg.ActionsAppRealmWideHmacKeySecondary)
		}
		return hmac.NewVaultKeyFetcher(cfg.ActionsAppRealmWideHmacKeyNamePrimary, cfg.ActionsAppRealmWideHmacKeyNameSecondary, cfg.RealmWideVaultName, keyVaultClient), nil
	}
	return nil, nil
}

func getHmacHTTPVerifier(hmacConfigType string, cfg Config, keyVaultClient azp.KeyVaultClient, obs *observability.Observability) (*hmac.HTTPVerifier, error) {
	KeyFetcher, err := getHMACKeyConfig(hmacConfigType, cfg, keyVaultClient)
	if err != nil {
		return nil, err
	}
	if KeyFetcher == nil {
		return nil, errors.New("Invalid HmacKey Configuration")
	}
	var httpsScheme string
	if cfg.IsEnterprise() || cfg.IsDevelopment() {
		httpsScheme = "http"
	} else {
		httpsScheme = "https"
	}
	hmacHTTPVerifier := hmac.NewHTTPVerifier(KeyFetcher, obs, hmac.NewVerifier(hmac.NewSigner()), httpsScheme)
	return hmacHTTPVerifier, nil
}

func getKredzClient(ctx context.Context, cfg Config, defaultHTTPClient *http.Client, twirpOpts []twirp.ClientOption, obs *observability.Observability, stats statter.Statter) (kredz.Client, error) {
	var kredzClient kredz.Client

	kredzTwirpBreaker, err := abreaker.NewKredzTwirpClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return nil, err
	}

	kredzTwirpHTTPClient, err := launchtwirp.NewClient(cfg.KredzHMACSecrets(), kredzTwirpBreaker, stats, defaultHTTPClient)
	if err != nil {
		return nil, err
	}

	kredzTwirpClient := kredzpb.NewCredentialsServiceProtobufClient(cfg.KredzHTTPAddr, kredzTwirpHTTPClient, twirpOpts...)

	kredzClient = kredz.NewClient(kredzTwirpClient, kredz.KredzMaxRetries, kredz.KredzReqRetryDelay)

	return kredzClient, nil
}

func getVarzClient(ctx context.Context, cfg Config, defaultHTTPClient *http.Client, twirpOpts []twirp.ClientOption, obs *observability.Observability, stats statter.Statter) (varz.Client, error) {
	var varzClient varz.Client

	varzTwirpBreaker, err := abreaker.NewVarzTwirpClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return nil, err
	}

	varzTwirpHTTPClient, err := launchtwirp.NewClient(cfg.VarzHMACSecrets(), varzTwirpBreaker, stats, defaultHTTPClient)
	if err != nil {
		return nil, err
	}

	varzTwirpClient := varzpb.NewVariablesServiceProtobufClient(cfg.VarzHTTPAddr, varzTwirpHTTPClient, twirpOpts...)

	varzClient = varz.NewClient(varzTwirpClient, varz.VarzMaxRetries, varz.VarzReqRetryDelay)

	return varzClient, nil
}

func getTokenAuthClient(ctx context.Context, cfg Config, log logger.Logger) (*tokenauth.Client, error) {
	authClient, err := tokenauth.New(ctx, &cfg.TokenAuth, log)
	if err != nil {
		return nil, err
	}
	return authClient, nil
}

type httpClients struct {
	Default, KeyVault *http.Client
}

func buildHTTPClients(obs *observability.Observability, cfg Config, ffcache launchcache.GitHubTwirpCache, twirpOpts []twirp.ClientOption) (*httpClients, error) {
	defaultOpts := []apphttp.Option{apphttp.WithObservability(obs, cfg.RoundTripperConfig), apphttp.WithMaxTimeout(time.Second * 35)}
	keyVaultOpts := []apphttp.Option{apphttp.WithObservability(obs, cfg.RoundTripperConfig), apphttp.WithIgnoreRedirects(), apphttp.WithMaxTimeout(time.Second * 100)}

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
		keyVaultOpts = append(keyVaultOpts, chaosOption)
	}

	hc := &httpClients{
		Default:  apphttp.NewClient(defaultOpts...),
		KeyVault: apphttp.NewClient(keyVaultOpts...),
	}
	return hc, nil
}

func (a *Application) buildKeyVaultClient(ctx context.Context, obs *observability.Observability, httpBackend *http.Client, cache launchcache.Cache) (azp.KeyVaultClient, error) {
	breaker, err := abreaker.NewAzpKeyVaultBreaker(ctx, obs, a.cfg.BreakerConfig)
	if err != nil {
		return nil, err
	}
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
	), nil
}
