package internal

import (
	"context"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	_ "embed"
	"encoding/pem"
	"fmt"
	nethttp "net/http"
	"os"
	"path"
	"regexp"
	"strings"
	"time"

	"github.com/IBM/sarama"
	"github.com/github/blackbird/crates/client/pkg/blackbird"
	"github.com/github/go-chatterbox"
	freno "github.com/github/go-freno-client"
	"github.com/github/go-kvp"
	"github.com/github/go-log"
	"github.com/github/go-reqmeta"
	"github.com/github/go-stats"
	"github.com/github/go-stats/ps"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	"github.com/github/go-twirp/client"
	clientauth "github.com/github/go-twirp/client/auth"
	clientid "github.com/github/go-twirp/client/requestid"
	twhooks "github.com/github/go-twirp/server/hooks"
	twirpauth "github.com/github/go-twirp/server/hooks/auth"
	twlogs "github.com/github/go-twirp/server/hooks/log"
	twstats "github.com/github/go-twirp/server/hooks/stats"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	sitesapi "github.com/github/sitesapiclient"
	"github.com/go-redis/redis/v8"
	"github.com/kelseyhightower/envconfig"
	"github.com/pkg/errors"
	"github.com/rcrowley/go-metrics"
	"github.com/twitchtv/twirp"
	"github.com/unrolled/secure"

	"github.com/github/blackbird-mw/internal/auth"
	"github.com/github/blackbird-mw/internal/auth/ong"
	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/chat"
	"github.com/github/blackbird-mw/internal/constants"
	"github.com/github/blackbird-mw/internal/copilot"
	"github.com/github/blackbird-mw/internal/db"
	dbstore "github.com/github/blackbird-mw/internal/db/mysql"
	noopstore "github.com/github/blackbird-mw/internal/db/noop"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/gitaccess/spokesd"
	"github.com/github/blackbird-mw/internal/github"
	ghclient "github.com/github/blackbird-mw/internal/github/client"
	"github.com/github/blackbird-mw/internal/http"
	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/publish/repo"
	"github.com/github/blackbird-mw/internal/quota"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/treelights"
	"github.com/github/blackbird-mw/internal/types"
	"github.com/github/blackbird-mw/schemas"
)

const (
	developmentEnv string = "development"
	productionEnv  string = "production"
	testEnv        string = "test"
	rootCACertPath string = "/etc/ssl/certs/ca-certificates.crt"
)

// globalDB is the global database handle for use in the whole application.
var globalDB db.RetryableDB

// Config values.
//
// NOTE: Fields will NOT be set unless config has been loaded from the
// environment.
type Config struct {
	Environment                      string        `envconfig:"env" default:"development"`
	Stamp                            routing.Stamp `envconfig:"KUBE_CLUSTER_STAMP" default:"dotcom"`               // The stamp (e.g. dotcom, staff-wus2-01, etc), set by Heaven/Moda
	DeployedEnv                      string        `envconfig:"HEAVEN_DEPLOYED_ENV" default:"production"`          // set by Heaven/Moda. Can be `production`, `production/canary`, or `production/<deploy_group>`
	DeployedSHA                      string        `envconfig:"HEAVEN_DEPLOYED_SHA" default:"unknown"`             // set by Heaven/Moda
	DeployedRef                      string        `envconfig:"HEAVEN_DEPLOYED_REF" default:"unknown"`             // set by Heaven/Moda
	SharedKafkaBrokers               []string      `envconfig:"SHARED_KAFKA_BROKERS" default:"localhost:29094"`    // Shared Kafka: published to by github/github
	BlackbirdKafkaBrokers            []string      `envconfig:"BLACKBIRD_KAFKA_BROKERS" default:"localhost:29094"` // Blackbird Kafka: published to by blackbird and blackbird-mw ONLY
	OutputCorpus                     string        `envconfig:"output_corpus" default:"blue"`
	StatsAddr                        string        `envconfig:"stats_addr"`
	Pod                              string        `envconfig:"pod"`
	KubeNamespace                    string        `envconfig:"BLACKBIRD_MW_KUBE_NAMESPACE"` // Value is injected via kubernetes deployment config.
	LogLevel                         string        `envconfig:"log_level"`
	StatsPeriod                      time.Duration `envconfig:"stats_period"`
	HTTPPort                         int           `envconfig:"http_port" default:"8080"`
	BlackbirdIndexHMACKey            redacted      `envconfig:"blackbird_index_hmac_key" default:"octocat"` // Vault-injected (production only)
	SpokesdURL                       string        `envconfig:"spokesd_url" default:"https://localhost:12443"`
	SpokesdKey                       redacted      `envconfig:"spokesd_key"`                                               // Vault-injected Spokesd key (production only)
	SpokesdCert                      redacted      `envconfig:"spokesd_cert"`                                              // Vault-injected Spokesd certificate (production only)
	SpokesdCertChain                 redacted      `envconfig:"spokesd_cert_chain"`                                        // Vault-injected Spokesd certificate chain. Not secret, redacted due to length (production only)
	SpokesdHMACKey                   redacted      `envconfig:"spokesd_hmac_key"`                                          // Vault-injected in production environment, otherwise must be set in the environment variable e.g. for docker compose environment
	MySQLSkeemaEnv                   string        `envconfig:"MYSQL_SKEEMA_ENV" default:"production-rw"`                  // Name of an env in .skeema
	MySQLSkeemaPasswordEnvVar        string        `envconfig:"MYSQL_SKEEMA_PASSWORD_ENV_VAR" default:"MYSQL_PASSWORD"`    // Name of env var where mysql password is set
	MySQLSkeemaAnalyticsEnv          string        `envconfig:"MYSQL_SKEEMA_ANALYTICS_ENV" default:"production-analytics"` // Name of an env in .skeema
	QueryServiceHMACKeys             []redacted    `envconfig:"query_service_hmac_keys" default:"octocat"`                 // Vault-injected (production only)
	IngestionWorkers                 int           `envconfig:"num_ingestion_workers" default:"2"`
	AccessibleResourcesRedisAddr     string        `envconfig:"ACCESSIBLE_RESOURCES_REDIS_ADDR" default:"localhost:6380"`
	AccessibleResourcesRedisUsername string        `envconfig:"ACCESSIBLE_RESOURCES_REDIS_USERNAME" default:""` // Blank in dev and test
	AccessibleResourcesRedisPassword redacted      `envconfig:"ACCESSIBLE_RESOURCES_REDIS_PASSWORD" default:""` // Blank in dev and test (Vault-injected (production only))
	RedisUseTLS                      bool          `envconfig:"REDIS_USE_TLS" default:"false"`
	PaginationRedisAddr              string        `envconfig:"PAGINATION_REDIS_ADDR" default:"localhost:6380"`
	PaginationRedisUsername          string        `envconfig:"PAGINATION_REDIS_USERNAME" default:""` // Blank in dev and test
	PaginationRedisPassword          redacted      `envconfig:"PAGINATION_REDIS_PASSWORD" default:""` // Blank in dev and test (Vault-injected (production only))
	GitHubAPIToken                   redacted      `envconfig:"GITHUB_API_TOKEN"`                     // Vault-injected (production only)
	GitHubInternalAPIURL             string        `envconfig:"GITHUB_INTERNAL_API_URL" default:"http://api.github.localhost/"`
	GitHubInternalAPIHMACKey         redacted      `envconfig:"GITHUB_INTERNAL_API_HMAC_KEY" default:"octocat"` // Vault-injected (production only)
	ChatopsBaseURL                   string        `envconfig:"CHATOPS_AUTH_BASE_URL"`                          // Chatops base URL
	ChatopsPublicKey                 redactedBytes `envconfig:"CHATOPS_AUTH_PUBLIC_KEY"`                        // Hubot PEM Public Key - vault-injected
	ChatopsLDAPPassword              redacted      `envconfig:"LDAP_BINDPW"`                                    // Chatops LDAP Password - vault-injected, https://github.com/github/security-iam/issues/4218
	ChatterboxToken                  redacted      `envconfig:"CHATTERBOX_TOKEN"`                               // Chatterbox token - vault injected
	ChatterboxURL                    string        `envconfig:"CHATTERBOX_URL"`
	TreelightsURL                    string        `envconfig:"TREELIGHTS_URL" default:"https://treelights-production.service.iad.github.net"`
	FrenoHost                        string        `envconfig:"FRENO_HOST"`
	OktaHMACKey                      redacted      `envconfig:"BLACKBIRD_ONG_HMAC"`
	CopilotAPIURL                    string        `envconfig:"COPILOT_API_URL" default:"https://acopilot-api-local/embeddings"`
	CopilotAPIHMACKey                string        `envconfig:"copilot_api_hmac_key" default:"octocat"` // Vault-injected (production only)
	SitesAPIPassword                 redacted      `envconfig:"SITES_API_PASSWORD"`
}

func Load() (Config, error) {
	var conf Config
	if err := envconfig.Process("blackbird_mw", &conf); err != nil {
		return conf, err
	}

	// Disable Sarama's useless and memory-wasting metrics.
	// This must be set before starting a Sarama consumer.
	// See: https://github.com/IBM/sarama/blob/0ab2bb77aeca321f41a0953a8c6f52472607a59e/config.go#L497-L502
	metrics.UseNilMetrics = true

	// Set the number of partitions for the backfill topics
	routing.BackfillTopicNumPartitions = uint32(conf.TopicConfig().Backfill.Partitions)

	return conf, nil
}

func (c Config) GetEnv() string {
	return c.Environment
}

func (c Config) GetDeployedEnv() string {
	return c.DeployedEnv
}

func (c Config) GetDeployedSHA() string {
	return c.DeployedSHA
}

func (c Config) GetDeployedRef() string {
	return c.DeployedRef
}

func (c Config) Corpus() routing.Corpus {
	corpus, err := routing.CorpusFromString(c.OutputCorpus)
	if err != nil {
		panic(errors.Wrap(err, "could not parse corpus"))
	}
	return corpus
}

func (c Config) BackfillConsumer(epochID types.EpochID) (*hydro.KafkaSource, error) {
	corpus := c.Corpus()
	// Start at the oldest offset in the per-epoch backfill topic. We always
	// start at the beginning because there's a new topic for each epoch.
	src, err := hydro.NewKafkaSource(
		c.kafkaConfig(c.BlackbirdKafkaBrokers, sarama.OffsetOldest),
		corpus.ConsumerGroup(epochID),
		[]string{corpus.EpochBackfillTopic(epochID)},
	)
	if err != nil {
		return nil, fmt.Errorf("could not create Kafka source: %w", err)
	}

	return src, nil
}

func (c Config) IncrementalConsumer(epochID types.EpochID) *hydro.KafkaSource {
	corpus := c.Corpus()
	// Start at the newest offset in the incremental topic. This will allow
	// changing the consumer group name to jump past all existing messages.
	//
	// TODO: Re-evaluate this setting when we switch to per-epoch consumer
	// groups. The new consumer group will have its offsets set, but what about
	// the cold start case? Should we jump to the beginning?
	src, err := hydro.NewKafkaSource(
		c.kafkaConfig(c.SharedKafkaBrokers, sarama.OffsetNewest),
		corpus.ConsumerGroup(epochID),
		corpus.IncrementalTopics(),
	)
	if err != nil {
		panic(errors.Wrap(err, "could not create Kafka source"))
	}
	return src
}

func (c Config) AssignmentsReader() kafka.AssignmentsReader {
	return kafka.NewAssignmentsReader(func() (sarama.Client, error) {
		sc := c.saramaConfig()
		return sarama.NewClient(c.BlackbirdKafkaBrokers, sc)
	})
}

func (c Config) RepoPublisher() *repo.Publisher {
	partitions := uint32(1)
	if c.isProduction() {
		partitions = 32
	}

	producer, err := sarama.NewSyncProducer(c.SharedKafkaBrokers, c.saramaConfig())
	if err != nil {
		panic(errors.Wrap(err, "failed to create sync producer"))
	}

	return repo.NewPublisher(producer, partitions)
}

func (c Config) SnapshotProducer() sarama.SyncProducer {
	p, err := sarama.NewSyncProducer(c.BlackbirdKafkaBrokers, c.saramaConfig())
	if err != nil {
		panic(errors.Wrap(err, "failed to create sync producer"))
	}
	return p
}

func (c Config) BlackbirdKafkaAdminProvider() func() sarama.ClusterAdmin {
	return func() sarama.ClusterAdmin {
		sc := c.saramaConfig()
		sc.Metadata.Full = true // cluster admin needs to fetch metadata

		client, err := sarama.NewClusterAdmin(c.BlackbirdKafkaBrokers, sc)
		if err != nil {
			panic(errors.Wrap(err, "failed to create sarama cluster admin"))
		}
		return client
	}
}

func (c Config) BlackbirdKafkaAdminClient() *kafka.AdminClient {
	sc := c.saramaConfig()
	sc.Metadata.Full = true // cluster admin needs to fetch metadata

	client, err := sarama.NewClient(c.BlackbirdKafkaBrokers, sc)
	if err != nil {
		panic(errors.Wrap(err, "failed to create sarama client"))
	}

	makeAdminClient := func() sarama.ClusterAdmin {
		adminClient, err := sarama.NewClusterAdmin(c.BlackbirdKafkaBrokers, sc)
		if err != nil {
			panic(errors.Wrap(err, "failed to create sarama cluster admin"))
		}

		return adminClient
	}

	return kafka.NewAdminClient(makeAdminClient, client)
}

func (c Config) SharedKafkaAdminClient() *kafka.AdminClient {
	sc := c.saramaConfig()
	sc.Metadata.Full = true // cluster admin needs to fetch metadata

	client, err := sarama.NewClient(c.SharedKafkaBrokers, sc)
	if err != nil {
		panic(errors.Wrap(err, "failed to create sarama client"))
	}

	makeAdminClient := func() sarama.ClusterAdmin {
		adminClient, err := sarama.NewClusterAdmin(c.SharedKafkaBrokers, sc)
		if err != nil {
			panic(errors.Wrap(err, "failed to create sarama cluster admin"))
		}
		return adminClient
	}

	return kafka.NewAdminClient(makeAdminClient, client)
}

func (c Config) SharedKafkaClient() sarama.Client {
	return c.sharedKafkaClient(false)
}

func (c Config) SharedAutoCommittingKafkaClient() sarama.Client {
	return c.sharedKafkaClient(true)
}

func (c Config) sharedKafkaClient(autoCommit bool) sarama.Client {
	client, err := sarama.NewClient(c.SharedKafkaBrokers, c.saramaConfig())
	client.Config().Consumer.Offsets.AutoCommit.Enable = autoCommit
	if err != nil {
		panic(errors.Wrap(err, "failed to create sarama client"))
	}
	return client
}

func (c Config) saramaConfig() *sarama.Config {
	sc := sarama.NewConfig()

	// sarama.Config.Net configuration
	if c.isProduction() {
		rootCA, err := os.ReadFile(rootCACertPath)
		if err != nil {
			panic(fmt.Errorf("failed to read root CA cert for sarama config: %w", err))
		}

		certPool := x509.NewCertPool()
		if ok := certPool.AppendCertsFromPEM(rootCA); !ok {
			panic(fmt.Errorf("failed to add root CA to cert pool for saram config: %w", err))
		}

		sc.Net.TLS.Enable = true
		sc.Net.TLS.Config = &tls.Config{RootCAs: certPool}
	}
	sc.Metadata.Full = false // only request necessary metadata

	// general sarama config
	sc.ClientID = c.KafkaClientID()
	sc.Version = sarama.V2_6_1_0

	// sarama.Producer config
	sc.Producer.MaxMessageBytes = hydro.MaxMessageBytes
	sc.Producer.RequiredAcks = sarama.WaitForAll // NOTE: Lost messages cause index inconsistencies
	sc.Producer.Compression = sarama.CompressionLZ4
	sc.Producer.Partitioner = sarama.NewManualPartitioner // NOTE: This is NOT a default Hydro config.
	sc.Producer.Return.Successes = true                   // Required for synchronous producer
	sc.Producer.Return.Errors = true                      // Required for synchronous producer
	// sarama.Config.Producer.Retry configs With a retry backoff of 100ms and
	// assuming 5ms metadata requests, we expect the producer to block for up
	// to ~3150ms (30 * (100ms + 5ms)) by default.
	sc.Producer.Retry.Max = 30

	// Temporary for debugging
	l := logging.GetLogger()
	l = l.With(kvp.String("subsystem", "sarama"))
	sarama.Logger = log.Standardize(l, log.DebugLevel)

	return sc
}

func (c Config) kafkaConfig(brokers []string, initialOffset int64) hydro.KafkaConfig {
	// Kafka stats are super noisy on the console, so cut them out in development
	sc := statting.GetStatsClient()
	if c.isDevelopment() {
		sc = stats.NullStatter
	}

	opts := []hydro.KafkaConfigOption{
		hydro.WithClientID(c.KafkaClientID()),
		hydro.WithKafkaStats(sc),
		hydro.WithKafkaVersion("2.2.0"), // This is the version of Kafka used in production
		hydro.WithSaramaConfig(func(scfg *sarama.Config) {
			// override the default hydro-client-go behavior to start at the
			// provided initialOffset when there are no offsets for the consumer
			// group.
			scfg.Consumer.Offsets.Initial = initialOffset
			// Try out a sticky rebalance strategy to minimize consumer group
			// rebalances when pods restart.
			scfg.Consumer.Group.Rebalance.Strategy = sarama.NewBalanceStrategySticky()
		}),
	}
	if c.isProduction() {
		opts = append(opts, hydro.WithRootCA(rootCACertPath))
	}

	// Enable hydro and sarama logging if we're running in test mode
	if c.isTest() || c.isDevelopment() {
		l := logging.GetLogger()
		opts = append(opts, hydro.WithKafkaLogger(log.Standardize(l.With(kvp.String("subsystem", "hydro")), log.DebugLevel)))
		sarama.Logger = log.Standardize(l.With(kvp.String("subsystem", "sarama")), log.DebugLevel)
	}

	kafkaCfg, err := hydro.NewKafkaConfig(brokers, opts...)
	if err != nil {
		panic(errors.WithMessage(err, "failed to create Kafka config"))
	}
	return *kafkaCfg
}

func (c Config) KafkaClientID() string {
	clientID, err := os.Hostname()
	if err != nil {
		panic(fmt.Sprintf("could not get host name: %+v", err))
	}

	return clientID
}

func (c Config) App() string {
	exec, err := os.Executable()
	if err != nil {
		panic("Could not get executable, this shouldn't happen")
	}
	return path.Base(exec)
}

func (c Config) TopicConfig() routing.TopicConfig {
	const (
		backfillRetentionBytes    int           = 53_687_091_200      // 50 GiB per partition (same as Hydro default)
		backfillRetentionDuration time.Duration = 14 * 24 * time.Hour // Hydro default
	)

	if c.isProduction() {
		return routing.TopicConfig{
			Document: routing.DocumentTopicConfig{
				ReplicationFactor:          2,                  // NOTE: We use a lower replication factor for document topics to save space
				NewRetentionBytes:          549_755_813_888,    // 512 GiB * 2RF * 32 partitions = 32 TiB per epoch; 4 corpora = 128 TiB total
				NewRetentionDuration:       7 * 24 * time.Hour, // Hopefully enough time to fix ingest problems
				TruncatedRetentionBytes:    10_737_418_240,     // 10 GiB * 2RF * 32 partitions = 640 GiB per truncated topic; 2 truncated * 3 corpora = 3.75 TiB
				TruncatedRetentionDuration: 48 * time.Hour,
			},
			Snapshot: routing.SnapshotTopicConfig{
				ReplicationFactor: 3, // Default for Kafka
			},
			Backfill: routing.BackfillTopicConfig{
				Partitions:        32,
				ReplicationFactor: 3, // Default for Kafka
				RetentionBytes:    backfillRetentionBytes,
				RetentionDuration: backfillRetentionDuration,
			},
			Onboard: routing.OnboardTopicConfig{
				Partitions: 32, // Must match hydro-schemas
			},
			Incremental: routing.IncrementalTopicConfig{
				Partitions: 16, // Must match hydro-schemas
			},
		}
	}

	return routing.TopicConfig{
		Document: routing.DocumentTopicConfig{
			ReplicationFactor:          1,
			NewRetentionBytes:          10_737_418_240, // 10 GiB * 1RF * 2 partitions => 20 GiB
			NewRetentionDuration:       24 * time.Hour,
			TruncatedRetentionBytes:    1_073_741_824, // 1 GiB * 1RF * 2 partitions => 2 GiB
			TruncatedRetentionDuration: 12 * time.Hour,
		},
		Snapshot: routing.SnapshotTopicConfig{
			ReplicationFactor: 1,
		},
		Backfill: routing.BackfillTopicConfig{
			Partitions:        1,
			ReplicationFactor: 1,
			RetentionBytes:    backfillRetentionBytes,
			RetentionDuration: backfillRetentionDuration,
		},
		Onboard: routing.OnboardTopicConfig{
			Partitions: 1,
		},
		Incremental: routing.IncrementalTopicConfig{
			Partitions: 1,
		},
	}
}

const (
	blackbirdServerPort  uint16 = 4443
	blackbirdCachePort   uint16 = 4443
	blackbirdIndexerPort uint16 = 4444
)

func (c Config) SearchClusters() *routing.SearchClusters {
	clients := map[routing.Corpus]blackbird.Client{}
	for _, corpus := range routing.Corpora {
		clients[corpus] = blackbird.NewSearchClient(
			func(hostname string) blackbird.SearchAPI {
				return c.searchAPI(hostname)
			},
			c.blackbirdClientConfig(),
			corpus.ClusterName(),
			c.blackbirdClientScheme(),
			blackbirdServerPort,
			c.BlackbirdIndexHMACKey.value,
		)
	}

	return routing.NewSearchClusters(clients)
}

func (c Config) CacheClusters() *routing.CacheClusters {
	clients := map[string]blackbird.Client{}
	for _, cacheCluster := range routing.CacheClusterNames {
		clients[cacheCluster] = c.cacheClient(cacheCluster)
	}

	return routing.NewCacheClusters(clients)
}

func (c Config) blackbirdClientConfig() string {
	var prefix string
	if c.isTest() {
		prefix = "/config/blackbird/test"
	} else if c.Stamp == routing.Dotcom {
		prefix = "/etc/blackbird/production"
	} else {
		prefix = "/etc/blackbird/proxima"
	}
	path := fmt.Sprintf("%s/blackbird-client.toml", prefix)
	config, err := os.ReadFile(path)
	if err != nil {
		panic(fmt.Sprintf("Unable read to dsa client config from file %s: %v", path, err))
	}
	return string(config)
}

func (c Config) cacheClient(cacheCluster string) blackbird.Client {
	return blackbird.NewCacheClient(
		func(hostname string) blackbird.CacheAPI {
			return c.cacheAPI(hostname)
		},
		c.blackbirdClientConfig(),
		cacheCluster,
		c.blackbirdClientScheme(),
		blackbirdCachePort,
		c.BlackbirdIndexHMACKey.value,
	)
}

func (c Config) indexerClient(corpus routing.Corpus) blackbird.Client {
	return blackbird.NewIndexerClient(
		func(hostname string) blackbird.IndexAPI {
			return c.indexAPI(hostname)
		},
		c.blackbirdClientConfig(),
		corpus.ClusterName(),
		c.blackbirdClientScheme(),
		blackbirdIndexerPort,
		c.BlackbirdIndexHMACKey.value,
	)
}

func (c Config) IndexerCluster() *routing.IndexerCluster {
	return routing.NewIndexerCluster(c.indexerClient(c.Corpus()))
}

func (c Config) IndexerClusters() *routing.IndexerClusters {
	clusters := map[routing.Corpus]blackbird.Client{}

	for _, corpus := range c.Stamp.EnabledCorpora() {
		clusters[corpus] = c.indexerClient(corpus)
	}

	return routing.NewIndexerClusters(clusters)
}

// InitializeTelemetry creates logger and statter (and starts the statter).
func (c Config) InitializeTelemetry(ctx context.Context) {
	defaultKVPs := c.defaultKVPs()

	// Initialize and start the stats client so it's ready to use.
	statter := c.initializeStatter()

	statter.Run()
	statting.SetStatsClient(statter)

	// Report process stats in production.
	if c.isProduction() {
		reporter := ps.Reporter{Stats: statter}
		go reporter.Run(ctx) //nolint:errcheck
	}

	logger := c.initializeLogger(defaultKVPs...)
	logging.SetLogger(ctx, logger)
}

// Close shuts down anything that was started up by initializing the config.
func (c Config) Close() {
	statting.GetStatsClient().Stop()
	if globalDB != nil {
		globalDB.Close()
		globalDB = nil // NOTE: This allows tests to have their own config instances
	}
}

// GetHTTPPort returns the HTTP port for the web server.
func (c Config) GetHTTPPort() int {
	return c.HTTPPort
}

// AuthClient wraps calls to internal github authZ APIs.
func (c Config) AuthClient(store db.Store) *auth.Client {
	client := auth.NewBlackbirdInternalAPIClient(c.httpClient(), c.GitHubInternalAPIURL, c.GitHubInternalAPIHMACKey.value)
	cache := cache.NewRedis(c.getAccessibleResourcesRedisClient())

	return auth.NewClient(cache, client, store)
}

func (c Config) PagerCache() cache.Store {
	return cache.NewRedis(c.getPaginationRedisClient())
}

func (c Config) QuotaRateEstimator(ctx context.Context) quota.RateEstimator {
	est, err := quota.NewRedisRateEstimator(ctx, c.getAccessibleResourcesRedisClient())
	if err != nil {
		panic(errors.Wrap(err, "failed to create redis quota rate estimator"))
	}
	return est
}

// GitHubClient returns an http client for the blackbird specific internal GitHub API.
func (c Config) GitHubClient() github.InternalAPIClient {
	if c.isDevelopment() {
		return nil
	}

	return ghclient.NewInternalAPIClient(c.httpClient(), c.GitHubInternalAPIURL, c.GitHubInternalAPIHMACKey.value, c.GitHubAPIToken.value)
}

func (c Config) CopilotClient() copilot.Client {
	if c.isDevelopment() {
		return nil
	}

	return copilot.NewClient(c.CopilotAPIURL, c.CopilotAPIHMACKey, c.httpClient())
}

func (c Config) getAccessibleResourcesRedisClient() *redis.Client {
	var tlsConfig *tls.Config
	if c.RedisUseTLS {
		tlsConfig = &tls.Config{MinVersion: tls.VersionTLS12}
	}
	return redis.NewClient(&redis.Options{
		Addr:      c.AccessibleResourcesRedisAddr,
		Username:  c.AccessibleResourcesRedisUsername,
		Password:  c.AccessibleResourcesRedisPassword.value,
		TLSConfig: tlsConfig,
	})
}

func (c Config) getPaginationRedisClient() *redis.Client {
	var tlsConfig *tls.Config
	if c.RedisUseTLS {
		tlsConfig = &tls.Config{MinVersion: tls.VersionTLS12}
	}
	return redis.NewClient(&redis.Options{
		Addr:      c.PaginationRedisAddr,
		Username:  c.PaginationRedisUsername,
		Password:  c.PaginationRedisPassword.value,
		TLSConfig: tlsConfig,
	})
}

func (c Config) GitClient() gitaccess.Client {
	if len(c.SpokesdURL) == 0 {
		panic("cannot create spokesd.Client. Set BLACKBIRD_MW_SPOKESD_URL")
	}

	opts := &spokesd.ClientOpts{
		FetchConcurrency: constants.GetBlobsFetchConcurrency,
		BatchSize:        constants.GetBlobsBatchSize,
		Retries:          constants.SpokesHTTPRetries,
	}
	return spokesd.New(c.SpokesdURL, c.spokesdHTTPClient(), opts)
}

func (c Config) blackbirdClientScheme() string {
	if c.isDevelopment() || c.isTest() {
		return "http"
	}
	return "https"
}

func (c Config) searchAPI(hostname string) blackbird.SearchAPI {
	url := fmt.Sprintf("%s://%s:%d", c.blackbirdClientScheme(), hostname, blackbirdServerPort)
	return blackbird.NewSearchAPIClient(url, c.twirpClient())
}

func (c Config) cacheAPI(hostname string) blackbird.CacheAPI {
	url := fmt.Sprintf("%s://%s:%d", c.blackbirdClientScheme(), hostname, blackbirdCachePort)
	return blackbird.NewCacheAPIClient(url, c.twirpClient())
}

func (c Config) indexAPI(hostname string) blackbird.IndexAPI {
	url := fmt.Sprintf("%s://%s:%d", c.blackbirdClientScheme(), hostname, blackbirdIndexerPort)
	return blackbird.NewIndexAPIClient(url, c.twirpClient())
}

func (c Config) twirpClient() client.Client {
	// We don't care aobut hmac authentication in development mode so the
	// twirp client is just an http client.
	if c.isDevelopment() {
		return c.httpClient()
	}

	var twirpClient client.Client
	twirpClient, err := clientauth.NewRequestHMACSigner(c.BlackbirdIndexHMACKey.value, c.httpClient())
	if err != nil {
		panic(fmt.Sprintf("failed to create hmac signer %v", err))
	}

	twirpClient = clientid.NewForwarder(twirpClient)
	return twirpClient
}

func (c Config) Store() db.Store {
	if c.isProduction() || c.isDevelopment() || c.isTest() {
		return dbstore.New(c.globalDatabase(), c.DatabaseThrottler())
	}

	return noopstore.New()
}

func (c Config) DefaultUserAgent() string {
	return fmt.Sprintf("%s/%s", c.App(), c.GetDeployedSHA())
}

func (c Config) isProduction() bool {
	return c.GetEnv() == productionEnv
}

func (c Config) isDevelopment() bool {
	return c.GetEnv() == developmentEnv
}

func (c Config) isTest() bool {
	return c.GetEnv() == testEnv
}

// Initialize github/go/log/v2 Logger
func (c Config) initializeLogger(defaultKvps ...kvp.Field) log.FieldLogger {
	var formatter log.Formatter
	opts := log.LogfmtOpts{Duration: log.DurationWithFixedScale(time.Millisecond)}

	if c.isDevelopment() {
		formatter = &log.Terminal{Sink: log.Stdout, Opts: opts}
	} else {
		formatter = &log.Logfmt{Sink: log.Stdout, Opts: opts}
	}

	return log.New(log.LevelFromString(c.LogLevel), formatter).With(defaultKvps...)
}

// Initialize github/go/stats/v2 Client
func (c Config) initializeStatter() stats.Client {
	var client stats.Client = stats.NullStatter

	switch {
	case len(c.StatsAddr) > 0:
		// TODO: update with sampling param when we need it
		client = stats.NewClient(stats.UDPSink(c.StatsAddr), c.StatsPeriod, c.App())
	case c.isTest():
		// NB: Uncomment if you want to see stats on stdout in tests
		// client = stats.NewClient(os.Stdout, c.StatsPeriod, c.App())
	case c.isDevelopment():
		// NB: Uncomment if you want to see stats on stdout in development
		// client = stats.NewClient(os.Stdout, c.StatsPeriod, c.App())
	default:
		panic("unexpected case while initializing statter")
	}

	tags := stats.Tags{
		"blackbird_mw_env": c.formatEnvTag(),
		"deployed_env":     c.GetDeployedEnv(),
	}

	if c.Pod != "" {
		tags["blackbird_mw_pod"] = c.Pod
	}
	if c.KubeNamespace != "" {
		tags["kube_namespace"] = c.KubeNamespace
	}

	return client.WithTags(tags)
}

// DefaultKVPs for loggers and error reporters
func (c Config) defaultKVPs() []kvp.Field {
	return []kvp.Field{
		kvp.String("environment", c.GetEnv()),
		kvp.String("release", c.GetDeployedSHA()),
		kvp.String("deployed_env", c.GetDeployedEnv()),
		kvp.String("deployed_ref", c.GetDeployedRef()),
		kvp.String("app", c.App()),
		kvp.String("pod", c.Pod),
	}
}

var envTagPattern = regexp.MustCompile(`[^a-z]+`)

// FormatEnvTag returns the conf.Environment string for use in a stats.Tags map.
func (c Config) formatEnvTag() string {
	tag := "unknown"

	if len(c.Environment) > 0 {
		tag = envTagPattern.ReplaceAllString(strings.ToLower(c.Environment), "_")
	}

	return tag
}

// Return a properly configured HTTP client
func (c Config) httpClient() *nethttp.Client {
	return http.Default(c.DefaultUserAgent())
}

// spokesdHTTPClient returns an HTTP client which can be used to communicate
// with Spokesd.
func (c Config) spokesdHTTPClient() *nethttp.Client {
	if c.isDevelopment() || c.isTest() {
		return c.httpClient()
	}

	if len(c.SpokesdKey.value) == 0 {
		// mTLS is implemented by istio on proxima so no need for a cert.
		httpClient := http.Default(c.DefaultUserAgent())
		httpClient.Transport = http.SpokesRoundTripper(httpClient.Transport)
		return httpClient
	}

	if len(c.SpokesdKey.value) == 0 {
		panic("missing required spokesd environment variable BLACKBIRD_MW_SPOKESD_KEY")
	}

	if len(c.SpokesdCert.value) == 0 {
		panic("missing required spokesd environment variable BLACKBIRD_MW_SPOKESD_CERT")
	}

	if len(c.SpokesdCertChain.value) == 0 {
		panic("missing required spokesd environment variable BLACKBIRD_MW_SPOKESD_CERT_CHAIN")
	}

	httpClient := http.NewClient(
		c.DefaultUserAgent(),
		http.ConfigureTLSByPEM(
			[]byte(c.SpokesdKey.value),
			[]byte(c.SpokesdCert.value),
			[]byte(c.SpokesdCertChain.value),
		),
	)

	httpClient.Transport = http.SpokesRoundTripper(httpClient.Transport)

	return httpClient
}

// globalDatabase opens a database handle, configures it, and checks that the
// connection is valid, then returns the handle on success.
func (c Config) globalDatabase() db.RetryableDB {
	if globalDB != nil {
		return globalDB
	}

	password := os.Getenv(c.MySQLSkeemaPasswordEnvVar)
	globalDB = db.NewRetryableMySQL(schemas.DB(c.skeemaEnv(), password))

	return globalDB
}

func (c Config) skeemaEnv() string {
	if c.isProduction() {
		return c.MySQLSkeemaEnv
	}

	return c.GetEnv()
}

func (c Config) QueryServiceHooks() *twirp.ServerHooks {
	// We initialize logger and stats client when calling InitializeTelemetry
	// logger here is cast into the parent interface since the hooks interface is
	// not directly compatible with FieldLogger which is kind of unfortunate since
	// both libraries are owned by GH and require casting.
	// TODO: follow up task to either change https://github.com/github/go-twirp/blob/main/server/hooks/log/logrequest.go
	// or find out the reason for incompatibility.
	logger := logging.GetLogger().(*log.Logger)
	hooks := twirp.ChainHooks(
		enableRequestMetadataHook(), // Add RequestMetadata as early as possible so the statting hook can use its stats tags
		twhooks.DefaultHooks(),      // captures both timing and errors
		twlogs.DefaultHooks(logger), // logs both timings and errors
		twstats.DefaultHooks(statting.GetStatsClient()),
	)

	// Set a blank hmac key to disable hmac (used in proxima)
	if !c.isDevelopment() && len(c.QueryServiceHMACKeys) > 0 {
		keys := []string{}
		for _, key := range c.QueryServiceHMACKeys {
			keys = append(keys, key.value)
		}
		hooks = twirp.ChainHooks(hooks, twirpauth.VerifyRequestHMACHooks(keys...))
	}
	return hooks
}

func (c Config) AdminServiceHooks() *twirp.ServerHooks {
	// TODO: Optionally add hmac hooks here for admin services running in each stamp...
	return twirp.ChainHooks(
		enableRequestMetadataHook(),              // Add RequestMetadata as early as possible so the statting hook can use its stats tags
		twhooks.DefaultHooks(),                   // captures both timing and errors
		twlogs.DefaultHooks(logging.GetLogger()), // logs both timings and errors
		twstats.DefaultHooks(statting.GetStatsClient()),
	)
}

func enableRequestMetadataHook() *twirp.ServerHooks {
	return &twirp.ServerHooks{
		RequestReceived: func(ctx context.Context) (context.Context, error) {
			ctx = logging.With(ctx, twlogs.DefaultFields(ctx)...)
			meta := reqmeta.NewRequestMetadata()
			return reqmeta.WithRequestMetadata(ctx, meta), nil
		},
	}
}

func (c Config) DatabaseThrottler() freno.Throttler {
	throttler := freno.DefaultThrottler
	if c.FrenoHost != "" {
		const mysqlCluster = "blackbird-production"
		throttler = freno.NewFrenoThrottler(c.FrenoHost, c.App(), mysqlCluster)
	}

	return throttler
}

func (c Config) DatabaseMaintenance() *dbstore.Maint {
	var analyticsDB db.RetryableDB
	if c.isProduction() {
		password := os.Getenv(c.MySQLSkeemaPasswordEnvVar)
		analyticsDB = schemas.DB(c.MySQLSkeemaAnalyticsEnv, password)
	} else {
		analyticsDB = c.globalDatabase()
	}

	return dbstore.NewMaintenance(c.globalDatabase(), analyticsDB, c.DatabaseThrottler())
}

func (c Config) NumIngestionWorkers() int {
	return c.IngestionWorkers
}

func (c Config) IsChatopsEnabled() bool {
	return len(c.ChatopsPublicKey.value) > 0
}

func (c Config) GetChatopsBaseURL() string {
	return c.ChatopsBaseURL
}

func (c Config) GetChatopsPublicKey() *rsa.PublicKey {
	if len(c.ChatopsPublicKey.value) == 0 {
		panic("BLACKBIRD_MW_CHATOPS_AUTH_PUBLIC_KEY is required")
	}

	block, _ := pem.Decode(c.ChatopsPublicKey.value)
	if block == nil {
		panic("pem decoding failed")
	}

	key, err := x509.ParsePKCS1PublicKey(block.Bytes)
	if err != nil {
		panic(errors.Wrap(err, "failed to parse key"))
	}
	return key
}

func (c Config) GetChatopsLDAPPassword() string {
	return c.ChatopsLDAPPassword.value
}

func (c Config) ChatClient() chat.Client {
	if c.ChatterboxURL == "" {
		return &chat.NoopClient{}
	}

	client, err := chatterbox.New(c.ChatterboxToken.value, c.ChatterboxURL)
	if err != nil {
		panic(errors.Wrap(err, "failed to create chatterbox client"))
	}
	return client
}

func (c Config) GetTreelightsClient() treelights.Client {
	if c.isDevelopment() || c.isTest() {
		return treelights.NewNoopClient()
	}

	return treelights.NewClient(c.TreelightsURL, c.httpClient())
}

func (c Config) AdminUIEnabled() bool {
	return c.OktaHMACKey.value != ""
}

func (c Config) OktaAuthHandler() func(next nethttp.Handler) nethttp.Handler {
	if c.isProduction() {
		if c.OktaHMACKey.value == "" {
			panic("no Okta Network Gateway HMAC key. Set BLACKBIRD_ONG_HMAC.")
		}

		return ong.Auth(c.OktaHMACKey.value)
	}

	return func(next nethttp.Handler) nethttp.Handler {
		return next
	}
}

func (c Config) OktaUsernameHandler() func(next nethttp.Handler) nethttp.Handler {
	return ong.UsernameOnly()
}

func (c Config) SecurityHandler() func(next nethttp.Handler) nethttp.Handler {
	// GitHub standard security headers are to be set like so:
	// Content-Security-Policy: <See below>
	// X-Content-Type-Options: nosniff
	// X-Frame-Options: DENY // X-Xss-Protection: 1; mode=block
	// Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
	middleware := secure.New(secure.Options{
		IsDevelopment:           !c.isProduction(),
		AllowedHosts:            []string{"blackbird-admin-production.service.iad.github.net"},
		AllowedHostsAreRegex:    false,
		HostsProxyHeaders:       []string{"X-Forwarded-Host"},
		SSLRedirect:             true,
		SSLHost:                 "", // Using default value, which will use the same host to redirect to
		SSLProxyHeaders:         map[string]string{"X-Forwarded-Proto": "https"},
		STSSeconds:              63072000,
		STSIncludeSubdomains:    true,
		STSPreload:              true,
		FrameDeny:               true,
		ContentTypeNosniff:      true,
		BrowserXssFilter:        true,
		CrossOriginOpenerPolicy: "same-origin",
		ContentSecurityPolicy: `
default-src 'none';
connect-src 'self';
script-src 'self';
style-src 'self' 'unsafe-inline';
img-src 'self' data: https://github.com https://github.githubassets.com https://avatars.githubusercontent.com;
font-src 'self';
media-src 'self';
manifest-src 'self';
		`,
	})

	return func(next nethttp.Handler) nethttp.Handler {
		return middleware.Handler(next)
	}
}

func (c Config) SitesAPIClient() *sitesapi.Client {
	if c.SitesAPIPassword.value == "" {
		if c.isProduction() {
			panic("SITES_API_PASSWORD environment variable unset")
		}
		return nil
	}

	client, err := sitesapi.NewClient(c.httpClient(), &sitesapi.Config{Password: c.SitesAPIPassword.value})
	if err != nil {
		panic(fmt.Sprintf("Could not create SitesAPI client: %s", err))
	}

	return client
}

func (c Config) GetStamp() routing.Stamp {
	return c.Stamp
}
