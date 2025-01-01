// Package config provides the configuration options used by Turboscan services.
package config

import (
	"context"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"net/http"
	"os"
	"runtime/debug"
	"strings"
	"time"

	"github.com/github/go-twirp/v2/client/requestid"
	"github.com/go-sql-driver/mysql"
	"github.com/twitchtv/twirp"

	enterprise "github.com/github/turboscan/ts/monolith_twirp/enterprise/v1"
	ma_api "github.com/github/turboscan/ts/monolith_twirp/managed_analyses/v1"
	repositories "github.com/github/turboscan/ts/monolith_twirp/repositories/v1"
	sf_api "github.com/github/turboscan/ts/monolith_twirp/suggested_fixes/v1"
	"github.com/github/turboscan/ts/o11y"

	"github.com/github/go-twirp/v2/client/auth"

	"github.com/github/turboscan/ts/twirp/clients/ghgh"

	// turboscan libraries
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/hydrologger"
	"github.com/github/turboscan/ts/limits"

	// github libraries
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	goconfig "github.com/github/go-config"
	"github.com/github/go-exceptions"
	httpexporter "github.com/github/go-exceptions/exporters/http"
	"github.com/github/go-exceptions/exporters/writer"
	"github.com/github/go-exceptions/stacktracers/pkgerrors"
	throttler "github.com/github/go-freno-client"
	"github.com/github/go-stats"
	ghhydro "github.com/github/hydro-client-go/v7/pkg/hydro"

	// third party libraries

	"github.com/pkg/errors"
)

type StorageEngine int

const (
	STORAGE_S3 StorageEngine = iota
	STORAGE_AZURE
	STORAGE_MEMORY
)

// Config defines the configuration to run the TurboScan service
type Config struct {
	// These environment variables are set automatically by Heaven on deployment.
	Environment string `config:"development,env=APP_ENV"`

	HMACKey string `config:",env=TURBOSCAN_HMAC_KEY"`
	// This HMAC key is used by insights to connect to turboscan - see https://github.com/github/code-scanning/issues/7637
	InsightsHMACKey string `config:",env=INSIGHTS_TURBOSCAN_HMAC_KEY"`
	// This HMAC key is used by dependabot-api to connect to turboscan - see https://github.com/github/security-iam/issues/9836
	DependabotHMACKey  string `config:",env=DEPENDABOT_TURBOSCAN_HMAC_KEY"`
	GitHubTwirpHMACKey string `config:"turboscanhmac,env=API_INTERNAL_TWIRP_HMAC_KEYS_FOR_TURBOSCAN"`
	GitHubTwirpAddr    string `config:"http://api.github.localhost/internal,env=GITHUB_TWIRP_ADDR"`
	// This uses the same environment variable as `GitHubTwirpAddr` but defaults to empty so running tests does not require a copy of github/github.
	FeatureFlagServiceTwirpAddr string `config:",env=GITHUB_TWIRP_ADDR"`

	// Interal api address, ends in /internal
	GitHubInternalApiAddr string `config:"http://api.github.localhost/internal,env=GITHUB_INTERNAL_API_ADDR"`
	// Base addr for the API, where the subdomain is internal-api.
	GitHubApiBaseAddr   string          `config:"http://internal-api.service.ghe.localhost,env=GITHUB_API_BASE_ADR"`
	GitHubAppPrivateKey *rsa.PrivateKey `config:",env=GITHUB_APP_PRIVATE_KEY"`
	GitHubAppID         int64           `config:"1,env=GITHUB_APP_ID"`
	GitHubAppToken      string          `config:"1,env=GITHUB_APP_TOKEN"`

	// Limits
	MaxSarifSize          goconfig.Byte `config:"400MiB,env=TURBOSCAN_MAX_SARIF_SIZE"`
	DisableSarifHardLimit bool          `config:"false,env=TURBOSCAN_DISABLE_SARIF_HARD_LIMIT"`
	ArchiverConcurrency   int           `config:"1,env=TURBOSCAN_ARCHIVER_CONCURRENCY"`

	// Logging
	LogLevel string `config:",env=TURBOSCAN_LOG_LEVEL"`

	// Exceptions
	FailbotDeployedTo  string `config:",env=FAILBOT_CONTEXT_DEPLOYED_TO"`
	FailbotRelease     string `config:",env=FAILBOT_CONTEXT_RELEASE"`
	FailbotKubeSite    string `config:",env=KUBE_SITE"`
	FailbotKubeCluster string `config:",env=KUBE_CLUSTER_NAME"`

	// DB.
	// The .skeema file and environment will be loaded first
	MySQLSkeemaPath string `config:",env=MYSQL_SKEEMA_PATH"`

	// If any of these contain non-zero values they will override the .skeema
	// configuration
	MySQLDBName   string `config:",env=MYSQL_DB_NAME"`
	MySQLUsername string `config:",env=MYSQL_USERNAME"`
	MySQLAddr     string `config:",env=MYSQL_ADDR"`
	MySQLPassword string `config:",env=MYSQL_PASSWORD"`
	MySQLTLS      string `config:"false,env=MYSQL_TLS"`

	// Chatops
	ChatopsBaseURL      string `config:"http://localhost:8888/_chatops,env=CHATOPS_BASE_URL"`
	ChatopsBotPublicKey string `config:",env=CHATOPS_BOT_PUBLIC_KEY"`

	// Metrics
	StatsAddr   string        `config:",env=STATS_ADDR"`
	StatsPeriod time.Duration `config:"10s,env=STATS_PERIOD"`

	// AWS
	AWSRegion      string `config:"us-east-1,env=S3_AWS_REGION"`
	AWSID          string `config:"minio,env=S3_AWS_KEY_ID"`
	AWSSecret      string `config:"miniostorage,env=S3_AWS_SECRET_KEY_ID"`
	S3Bucket       string `config:",env=S3_BUCKET"`
	S3Endpoint     string `config:"http://localhost:9000,env=S3_ENDPOINT"`
	S3NodeProtocol string `config:"http,env=S3_NODE_PROTOCOL"`
	S3NodePort     int    `config:"10004,env=S3_NODE_PORT"`

	// Azure
	AzureAccountName string `config:",env=AZURE_STORAGE_ACCOUNT"`
	AzureAccountKey  string `config:",env=AZURE_STORAGE_ACCOUNT_KEY"`
	AzureContainer   string `config:",env=AZURE_STORAGE_CONTAINER"`
	// AzureEndpoint is used to connect to a local Azurite instance.
	AzureEndpoint string `config:",env=AZURE_ENDPOINT"`

	// Hydro
	KafkaBrokers string `config:"localhost:9092,env=KAFKA_BROKERS"`
	KafkaGroup   string `config:"turboscan-consumer,env=KAFKA_GROUP"`
	KafkaCACert  string `config:",env=KAFKA_CA_CERT"`
	KafkaVersion string `config:"1.1.1,env=KAFKA_VERSION"`

	// Freno
	FrenoAddr string `config:",env=FRENO_ADDR"`

	TurboscanPort int `config:"8888,env=TURBOSCAN_PORT"`

	// Elasticsearch (primary cluster)
	ESAddr     string `config:"http://localhost:9402,env=ES_ADDR"`
	ESUsername string `config:"elastic,env=ES_USERNAME"`
	ESPassword string `config:"changeme,env=ES_PASSWORD"`
	ESReplicas int    `config:"0,env=ES_REPLICAS"`
	ESShards   int    `config:"1,env=DEFAULT_ES_SHARD_COUNT"`

	// Elasticsearch (secondary cluster, this is used to migrate cross-cluster, like ES5 to ES8, or for fail-over)
	ESSecondaryAddr     string `config:",env=ES_SECONDARY_ADDR"`
	ESSecondaryUsername string `config:",env=ES_SECONDARY_USERNAME"`
	ESSecondaryPassword string `config:",env=ES_SECONDARY_PASSWORD"`

	// Aqueduct
	AqueductApp    string `config:"turboscan-dev,env=AQUEDUCT_APP"`
	AqueductQueues string `config:",env=AQUEDUCT_QUEUES"`
	AqueductAddr   string `config:"http://localhost:18081,env=AQUEDUCT_ADDR"`
	AqueductAPIKey string `config:",env=AQUEDUCT_API_KEY"`

	AqueductProcessorRate time.Duration `config:"1s,env=AQUEDUCT_PROCESSOR_RATE"`

	// Actions
	LaunchDeployerHMAC string `config:"deployzzzz,env=LAUNCH_DEPLOYER_HMAC_SECRET"`
	LaunchDeployerAddr string `config:"http://localhost:5001,env=LAUNCH_DEPLOYER_ADDR"`

	// GHES
	GHESMigrationEventsFile string `config:",env=GHES_MIGRATION_EVENTS_FILE"`
	GHESMigrationListFile   string `config:",env=GHES_MIGRATION_LIST_FILE"`

	// CAPI
	CapiDevKey       string `config:",env=COPILOT_ADVANCED_SECURITY_HMAC_KEY_DEV"`
	CapiDevEnv       bool   `config:"false,env=CAPI_DEV_ENV"`
	CapiProdKey      string `config:",env=COPILOT_ADVANCED_SECURITY_HMAC_KEY"`
	CapiUserID       uint64 `config:"1,env=CAPI_USER_ID"`
	CapiModelName    string `config:",env=CAPI_MODEL_NAME"`
	CapiThrottlerUrl string `config:",env=CAPI_THROTTLER_URL"`

	// Spokes
	SpokesAddr      string `config:"http://localhost:28081,env=SPOKES_ADDR"`
	SpokesCaChain   string `config:",env=SPOKESD_CA_CHAIN"`
	SpokesCert      string `config:",env=SPOKESD_CLIENT_CERT"`
	SpokesClientKey string `config:",env=SPOKESD_CLIENT_CERT_KEY"`

	// Advanced Security Bot
	BotGRID  ts.ActorGRID `config:",env=GHAS_BOT_GRID"`
	BotLogin string       `config:",env=GHAS_BOT_LOGIN"`

	// GHES Config option to disable buildless scans for select languages
	// Remove option for language once it is put out of Beta.
	JavaBuildlessDisabled   bool `config:"false,env=ENTERPRISE_DISABLE_BUILDLESS_JAVA"`
	CSharpBuildlessDisabled bool `config:"false,env=ENTERPRISE_DISABLE_BUILDLESS_CSHARP"`
}

// Load parses configuration from the environment and places it in a newly
// allocated Config struct.
func Load() (*Config, error) {
	cfg := &Config{}
	if err := goconfig.Load(cfg); err != nil {
		return nil, err
	}

	if cfg.Environment == "development" {
		if cfg.S3Bucket == "" {
			cfg.S3Bucket = "turboscan-dev"
		}
		if cfg.AzureEndpoint == "" {
			cfg.AzureEndpoint = "http://localhost:10000"
		}
		if cfg.AzureContainer == "" {
			cfg.AzureContainer = "sarif-upload"
		}
		// these are the default Azurite credentials
		// see: https://docs.microsoft.com/en-us/azure/storage/common/storage-use-azurite?tabs=visual-studio#well-known-storage-account-and-key
		if cfg.AzureAccountName == "" {
			cfg.AzureAccountName = "devstoreaccount1"
		}
		if cfg.AzureAccountKey == "" {
			cfg.AzureAccountKey = "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=="
		}
	}

	return cfg, nil
}

// GetStorageEngine returns the type of backing storage that should be used.
func (cfg *Config) GetStorageEngine() StorageEngine {
	// Use minio in development. We still set the AzureAccountName so that tests and CI can use Azurite.
	if cfg.AzureAccountName != "" && cfg.Environment != "development" {
		return STORAGE_AZURE
	}
	return STORAGE_S3
}

// IsProdEnv returns true if we are in a production environment
func (cfg *Config) IsProdEnv() bool {
	return cfg.Environment == "production" || cfg.Environment == "proxima"
}

// IsDotComEnv returns true if we are in the dotcom environment
func (cfg *Config) IsDotComEnv() bool {
	return cfg.Environment == "production"
}

// IsEnterpriseEnv returns true if we are in a GitHub Enterprise Server environment.
func (cfg *Config) IsEnterpriseEnv() bool {
	return cfg.Environment == "enterprise"
}

// IsDevelopmentEnv returns true if we are in the development environment
func (cfg *Config) IsDevelopmentEnv() bool {
	return cfg.Environment == "development"
}

// IsProximaEnv returns true if we are in the proxima environment
func (cfg *Config) IsProximaEnv() bool {
	return cfg.Environment == "proxima"
}

func (cfg *Config) Limits() map[ts.RepositoryEID]limits.Table {
	out := map[ts.RepositoryEID]limits.Table{
		0: limits.LimitsDefault(),
	}
	if cfg.IsDotComEnv() {
		// Overrides for dotCom
		out[252783419] = limits.LimitsHuge() // Anthophila/OWASP-Benchmark
	}
	if cfg.IsEnterpriseEnv() {
		// Do not store metric results on GHES
		t := out[limits.AllRepos]
		t.MetricsPerRunLimit = 0
		out[limits.AllRepos] = t
	}
	return out
}

// NewLogger returns a new logger based on the environment
func (cfg *Config) NewLogger() (log.Logger, error) {
	telem, err := telemetry.NewFromEnv()
	if err != nil {
		return nil, errors.Wrap(err, "Failed configuring telemetry")
	}

	level := log.DebugLevel

	if cfg.LogLevel != "" {
		switch strings.ToLower(cfg.LogLevel) {
		case "debug":
			level = log.DebugLevel
		case "info":
			level = log.InfoLevel
		case "error":
			level = log.ErrorLevel
		default:
			return nil, errors.Errorf("unknown log level \"%s\"", cfg.LogLevel)
		}
	}

	return telem.Logger.WithLevel(level), nil
}

// ExceptionReporter configures a new exceptions reporter based on the config.
// It prints reports to stdout in development environment, but sends them to
// Failbotg (which is proxied to Sentry) in production.
func (cfg *Config) ExceptionReporter(logger log.Logger, name string) (o11y.ExceptionReporter, error) {
	var err error
	var exceptionExporter exceptions.Exporter = writer.NewExporter(os.Stdout)
	if cfg.IsProdEnv() {
		exceptionExporter, err = httpexporter.NewExporter()
		if err != nil {
			return nil, err
		}
	}

	errorLogger := func(reportErr, exception error, payload map[string]string) {
		fields := []kvp.Field{}

		// make sure we only log the error if it's non-nil
		if exception != nil {
			fields = append(fields, kvp.String("gh.turboscan.exception_error", exception.Error()))
		}

		for k, v := range payload {
			if !strings.Contains(k, ".") {
				k = "gh.turboscan." + k
			}
			fields = append(fields, kvp.String(k, v))
		}

		logger.WithError(reportErr).Error("failed to report exception", fields...)
	}

	reporter, err := exceptions.NewReporter(
		exceptions.WithExporter(exceptionExporter),
		exceptions.WithStacktraceFunc(pkgerrors.NewStackTracer()),
		exceptions.WithRollupInfoFunc(RollupInfoFunc),
		exceptions.WithApplication("turboscan"),
		exceptions.WithCatalogService("github/code_scanning"),
		exceptions.WithValues(map[string]string{
			"deployed_to":                   cfg.FailbotDeployedTo,
			"release":                       cfg.FailbotRelease,
			"#kube_site":                    cfg.FailbotKubeSite,
			"#kube_cluster":                 cfg.FailbotKubeCluster,
			"#gh.exception.catalog_service": "github/code_scanning", // We send both the semantic and non-semantic key for this tag because Failbot uses the non-semantic key for metric reporting.
			"#gh.turboscan.app":             name,
		}),
		exceptions.WithErrorLogger(errorLogger),
	)
	if err != nil {
		return nil, err
	}

	return o11y.NewAnnotatingExceptionReporter(reporter), nil
}

func RollupInfoFunc(err error) (string, bool) {
	var mysqlErr *mysql.MySQLError
	if err != nil && errors.As(err, &mysqlErr) {
		// group server shutdown messages
		if mysqlErr.Number == 1053 {
			return mysqlErr.Error(), true
		}
	}
	var stacktracer interface{ StackTrace() errors.StackTrace }
	if !errors.As(err, &stacktracer) {
		// timeout errors contain an execution time and query id that stop them being rolled up
		// group them all together in the case where we don't have a stacktrace
		message := err.Error()
		if strings.HasPrefix(message, "Error 1317 (70100):") {
			message = "query execution was interrupted"
		}
		if strings.HasPrefix(message, "twirp error unknown: failed to write response") {
			message = "twirp error unknown: failed to write response"
		}
		return message, true
	}
	if errors.Is(err, context.Canceled) {
		return "context canceled", true
	}
	var result strings.Builder
	for _, frame := range stacktracer.StackTrace() {
		fmt.Fprintf(&result, "%+s:%n\n", frame, frame)
	}
	return result.String(), true
}

// NewKafkaConfig returns a Kafka configuration to be used with
// github.com/github/hydro-client-go
func (cfg *Config) NewKafkaConfig(logger log.Logger, statsClient stats.Client) (*ghhydro.KafkaConfig, error) {
	brokers := strings.Split(cfg.KafkaBrokers, ",")
	var logb []kvp.Field
	for _, b := range brokers {
		logb = append(logb, kvp.String("gh.turboscan.kafka_broker", b))
	}
	logger.Info("Connecting to brokers", logb...)

	if statsClient == nil {
		statsClient = stats.NullStatter
	}

	klog := hydrologger.New(logger)
	ghhydro.SetKafkaLogger(klog)

	kafkaOpts := []ghhydro.KafkaConfigOption{ghhydro.WithKafkaStats(statsClient), ghhydro.WithKafkaLogger(klog)}

	if cfg.KafkaCACert != "" {
		// Try to use SSL
		rootCA, err := os.ReadFile(cfg.KafkaCACert)
		if err != nil {
			return nil, err
		}

		certPool := x509.NewCertPool()
		if ok := certPool.AppendCertsFromPEM(rootCA); !ok {
			return nil, err
		}

		kafkaOpts = append(kafkaOpts,
			ghhydro.WithTLS(&tls.Config{RootCAs: certPool, MinVersion: tls.VersionTLS12}))
	}

	if cfg.KafkaVersion != "" {
		kafkaOpts = append(kafkaOpts, ghhydro.WithKafkaVersion(cfg.KafkaVersion))
	}

	return ghhydro.NewKafkaConfig(brokers, kafkaOpts...)
}

// NewFrenoThrottler returns a new Freno throttler that is used to throttle
// writes in cases of replication lags.
func (cfg *Config) NewFrenoThrottler() throttler.Throttler {
	if cfg.FrenoAddr == "" {
		// default throttler is a pass-through throttler that always allows
		// writing.
		return throttler.DefaultThrottler
	}

	return throttler.NewFrenoThrottler(cfg.FrenoAddr, "turboscan", "turboscan")
}

// NewStatsClient returns a new go-stats client
func (cfg *Config) NewStatsClient(serviceName string) stats.Client {
	var statsClient stats.Client = stats.NullStatter
	if cfg.StatsAddr != "" {
		statsClient = stats.NewClient(stats.UDPSink(cfg.StatsAddr), cfg.StatsPeriod, "turboscan")
	}
	// Only Datadog supports tags. On Enterprise we have to remove all tags if we want our stats to be recorded.
	if cfg.IsEnterpriseEnv() {
		statsClient = stats.NewCollectdClient(statsClient)
	}

	statsClient = statsClient.WithTags(
		stats.Tags{
			"env":           cfg.Environment,
			"turboscan_app": serviceName,
		},
	)

	return statsClient
}

// ValidHMACs returns an array of HMAC keys that should be accepted by the server.
func (cfg *Config) ValidHMACs() []string {
	hmacs := []string{}
	if cfg.HMACKey != "" {
		hmacs = append(hmacs, strings.Split(cfg.HMACKey, " ")...)
	}
	if cfg.InsightsHMACKey != "" {
		hmacs = append(hmacs, strings.Split(cfg.InsightsHMACKey, " ")...)
	}
	if cfg.DependabotHMACKey != "" {
		hmacs = append(hmacs, strings.Split(cfg.DependabotHMACKey, " ")...)
	}
	// Note this can be empty when there are no valid keys, this will
	// should reject all requests.
	return hmacs
}

// ActionsDefaultNonGitHubHostedRunnerLabel returns the label to be used in workflows for non-GH runners
func (cfg *Config) ActionsDefaultNonGitHubHostedRunnerLabel() string {
	if cfg.IsEnterpriseEnv() {
		return "code-scanning"
	} else if cfg.IsDevelopmentEnv() {
		return "self-hosted"
	}
	return ""
}

func (cfg *Config) UserAgent() *twirp.ClientHooks {
	version := "unknown"
	if info, ok := debug.ReadBuildInfo(); ok {
		for _, setting := range info.Settings {
			if setting.Key == "vcs.revision" {
				version = setting.Value
				break
			}
		}
	}
	userAgent := fmt.Sprintf("turboscan/%s", version)
	return &twirp.ClientHooks{
		RequestPrepared: func(ctx context.Context, r *http.Request) (context.Context, error) {
			r.Header.Set("User-Agent", userAgent)
			return ctx, nil
		},
	}
}

func (cfg *Config) NewManagedAnalysesAPI(logger log.Logger, st stats.Client) (ghgh.ManagedAnalysesAPI, error) {
	twirpApiUrl := cfg.GitHubTwirpAddr
	hmacSecret := cfg.GitHubTwirpHMACKey

	hmac, err := auth.NewRequestHMACSigner(hmacSecret, &http.Client{})
	if err != nil {
		return nil, err
	}

	requestID := requestid.NewForwarder(hmac)

	return ghgh.NewManagedAnalysesAPI(ma_api.NewManagedAnalysesAPIProtobufClient(twirpApiUrl, requestID, twirp.WithClientHooks(cfg.UserAgent())), logger, st), nil
}

func (cfg *Config) NewSuggestedFixesAPI(logger log.Logger, st stats.Client) (ghgh.SuggestedFixesAPI, error) {
	twirpApiUrl := cfg.GitHubTwirpAddr
	hmacSecret := cfg.GitHubTwirpHMACKey

	hmac, err := auth.NewRequestHMACSigner(hmacSecret, &http.Client{})
	if err != nil {
		return nil, err
	}

	requestID := requestid.NewForwarder(hmac)

	return ghgh.NewSuggestedFixesAPI(sf_api.NewSuggestedFixesAPIProtobufClient(twirpApiUrl, requestID, twirp.WithClientHooks(cfg.UserAgent())), logger, st), nil
}

func (cfg *Config) NewRepositoryAPI(logger log.Logger, st stats.Client) (ghgh.RepositoryAPI, error) {
	twirpApiUrl := cfg.GitHubTwirpAddr
	hmacSecret := cfg.GitHubTwirpHMACKey

	hmac, err := auth.NewRequestHMACSigner(hmacSecret, &http.Client{})
	if err != nil {
		return nil, err
	}

	requestID := requestid.NewForwarder(hmac)

	return ghgh.NewRepositoryAPI(repositories.NewRepositoriesAPIProtobufClient(twirpApiUrl, requestID, twirp.WithClientHooks(cfg.UserAgent())), logger, st), nil
}

func (cfg *Config) NewEnterpriseStorageAPI() (enterprise.StorageAPI, error) {
	twirpApiUrl := cfg.GitHubTwirpAddr
	hmacSecret := cfg.GitHubTwirpHMACKey

	hmac, err := auth.NewRequestHMACSigner(hmacSecret, &http.Client{})
	if err != nil {
		return nil, errors.Wrap(err, "could not create hmac signer")
	}

	requestID := requestid.NewForwarder(hmac)

	return enterprise.NewStorageAPIProtobufClient(twirpApiUrl, requestID, twirp.WithClientHooks(cfg.UserAgent())), nil
}

// IndexSettings returns the ElasticSearch index settings to be used based
// on the type of environment Turboscan is running in.
// The environment variables and defaults should be consistent with the ElastciSearch configuration for github/github.
func (cfg *Config) IndexSettings() interface{} {
	autoExpandReplicas := "false"
	if cfg.IsEnterpriseEnv() {
		autoExpandReplicas = "0-1"
	}

	return map[string]interface{}{
		"index.queries.cache.enabled": true,
		"index.number_of_shards":      cfg.ESShards,
		"index.number_of_replicas":    cfg.ESReplicas,
		"index.auto_expand_replicas":  autoExpandReplicas,
		"analysis": map[string]interface{}{
			"normalizer": map[string]interface{}{
				"case_insensitive_keyword": map[string]interface{}{
					"type":        "custom",
					"char_filter": []string{},
					"filter":      []string{"lowercase"},
				},
			},
		},
	}
}

func (cfg *Config) BotActor() *ts.ActorGRIDLogin {
	if cfg.BotGRID == "" || cfg.BotLogin == "" {
		return nil
	}

	return &ts.ActorGRIDLogin{
		Login: cfg.BotLogin,
		GRID:  cfg.BotGRID,
	}
}

func (cfg *Config) DormanRepoDays() *int {
	if cfg.IsEnterpriseEnv() {
		return nil
	}
	days := 180
	return &days
}
