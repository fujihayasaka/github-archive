package main

import (
	"context"
	"errors"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/clients/launchblob"
	"github.com/github/launch/clients/launchredis"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/abreaker"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/roundtrippers"
	"github.com/github/launch/workflowbuild/azp/config"
)

type Config struct {
	launchconfig.CommonConfig

	Name              string `config:"launch"`
	EnterpriseVersion string `config:"latest,env=ENTERPRISE_INSTALLED_VERSION"`
	ReportingAddr     string `config:",env=FAILBOT_HAYSTACK_URL"`
	InternalAddr      string `config:",env=INTERNAL_ADDR,required"`
	AppID             int64  `config:",env=GITHUB_APP_ID,required"`

	launchcache.CacheConfig
	launchredis.RedisConfig
	launchblob.BlobConfig

	AqueductApp                  string `config:"actions,env=AQUEDUCT_APP"`
	AqueductURL                  string `config:",env=AQUEDUCT_URL,required"`
	AqueductAPIKey               string `config:",env=AQUEDUCT_API_KEY"`
	AqueductAPIKeyVersion        int    `config:"0,env=AQUEDUCT_API_KEY_VERSION"`
	ResultsAqueductAPIKey        string `config:",env=RESULTS_AQUEDUCT_API_KEY"`
	ResultsAqueductAPIKeyVersion int    `config:"0,env=RESULTS_AQUEDUCT_API_KEY_VERSION"`
	AqueductTimeoutMs            int32  `config:"4000,env=AQUEDUCT_TIMEOUT_MS"`

	// AqueductQueueWebhooks is the name of the queue to use for webhooks
	AqueductQueueWebhooks string `config:"webhooks,env=AQUEDUCT_QUEUE_WEBHOOKS"`

	// AqueductQueueScheduled is the name of the queue to use for scheduled builds
	AqueductQueueScheduled string `config:"scheduled_builds,env=AQUEDUCT_QUEUE_SCHEDULED_BUILDS"`

	// AqueductQueueDynamic is the name of the queue to use for dynamic builds
	AqueductQueueDynamic string `config:"dynamic_builds,env=AQUEDUCT_QUEUE_DYNAMIC_BUILDS"`

	// AqueductNumWorkers is the number of worker goroutines each worker instance starts up.
	AqueductNumWorkers int `config:"2,env=AQUEDUCT_NUM_WORKERS"`

	// AqueductNumWorkersNonWebhook is the number of workers to work on non-webhook builds
	// e.g. scheduled and dynamic builds
	AqueductNumWorkersNonWebhook int `config:"2,env=AQUEDUCT_NUM_WORKERS_NON_WEBHOOK"`

	AqueductHeartbeatAttemptIntervalMs int32 `config:"5000,env=AQUEDUCT_HEARTBEAT_ATTEMPT_INTERVAL_MS"`
	AqueductMaxTimeWithoutHeartbeatMs  int32 `config:"30000,env=AQUEDUCT_MAX_TIME_WITHOUT_HEARTBEAT_MS"`

	RawActionsBotNodeIDs string `config:",env=GITHUB_ACTIONS_BOT_NODE_IDS,required"`
	RawActionsAppIDs     string `config:",env=GITHUB_ACTIONS_APP_IDS,required"`

	// Database connections
	DatabaseURL         string `config:",env=DATABASE_URL,required"`
	PayloadsDatabaseURL string `config:",env=PAYLOADS_DATABASE_URL"`

	// API URLs
	APIHost            string `config:"http://api.github.localhost,env=API_HOST,required"`
	V3APIEndpoint      string `config:",env=V3_API_PATH"`
	GraphQLEndpoint    string `config:"/graphql,env=GRAPHQL_API_PATH"`
	ExternalAPIHost    string `config:"http://api.github.localhost,env=EXTERNAL_API_HOST,required"`
	ExternalGitHubHost string `config:"http://github.localhost,env=EXTERNAL_GITHUB_HOST,required"`

	KredzHTTPAddr   string `config:",env=KREDZ_HTTP_ADDR,required"`
	KredzHMACSecret string `config:",env=KREDZ_HMAC_SECRET,required"`

	VarzHTTPAddr   string `config:",env=VARZ_HTTP_ADDR"`
	VarzHMACSecret string `config:",env=VARZ_HMAC_SECRET"`

	SecretsAppRelayID string `config:",env=GITHUB_SECRETS_APP_RELAY_ID,required"`
	// DependabotAppRelayID may be empty. Therefore it should only be accessed through GetDependabotAppRelayID
	DependabotAppRelayID string `config:",env=DEPENDABOT_APP_RELAY_ID"`
	AppPrivateKey        string `config:",env=GITHUB_APP_PRIVATE_KEY,required"`

	// Hydro configuration.
	KafkaRootCAPath string `config:",env=KAFKA_ROOT_CA_PATH"`
	KafkaBrokers    string `config:"disabled,env=KAFKA_BROKERS"`

	// GraphQLServiceToken will be passed as "GitHub-Internal-GraphQL-Token".
	// See also https://github.com/github/github/blob/f596db27beef26d9f7b84aa942a77cccdb05f8a3/app/api/graph_ql.rb#L93-L101
	GraphQLServiceToken string `config:",env=GITHUB_GRAPHQL_SERVICE_TOKEN"`

	// The secret to use for HMAC verification to GitHub's Twirp API
	GitHubTwirpHMACSecret string `config:",env=GITHUB_TWIRP_HMAC_SECRET,required"`
	GitHubTwirpAddr       string `config:",env=GITHUB_TWIRP_ADDR,required"`

	// From DEPLOYER_ACTION_RUNNER_SECRET in vault
	ActionRunnerSecret string `config:",env=ACTION_RUNNER_SECRET,required"`

	// The secret to use to sign requests to deployer for HMAC verification.
	// This should match one of the secrets in Deployer's DEPLOYER_HMAC_VERIFY_SECRETS
	DeployerHMACSigningSecret string `config:",env=DEPLOYER_HMAC_SECRET,required"`

	ReceiverURL         string `config:",env=RECEIVER_URL"`
	ReceiverPublicURL   string `config:",env=RECEIVER_PUBLIC_URL"`
	ReceiverInternalURL string `config:",env=RECEIVER_INTERNAL_URL"`
	// ResultsReceiverURL is the results service URL sent to actions service (or run service) to be passed to the runner.
	// This is used for websocket and API communication between results and the runner.
	// In multitenant scenarios, this will have a slug formatter within the URL.
	ResultsReceiverURL string `config:",env=RESULTS_RECEIVER_URL"`

	// Diet earthsmoke crypto keys
	DietEarthsmokeCustomTasksKey string `config:",env=EARTHSMOKE_CUSTOM_TASKS_KEY"`
	DependabotSecretsKey         string `config:",env=EARTHSMOKE_DEPENDABOT_SECRETS_KEY"`

	// MySQL configuration
	EmulatePreparedStatements     bool          `config:"false,env=EMULATE_PREPARED_STATEMENTS"`
	UseUTCForMySQL                bool          `config:"false,env=USE_UTC_FOR_MYSQL"`
	ForceCharsetForMySQL          bool          `config:"false,env=FORCE_CHARSET_FOR_MYSQL"`
	MySQLBreakerConsecutiveErrors int           `config:"500,env=MYSQL_CIRCUIT_BREAKER_CONSECUTIVE_ERRORS"`
	MySQLMaxOpenConns             int           `config:"1024,env=MYSQL_MAX_OPEN_CONNS"`
	MySQLMaxIdleConns             int           `config:"1024,env=MYSQL_MAX_IDLE_CONNS"`
	MySQLMaxIdleTime              time.Duration `config:"25s,env=MYSQL_MAX_IDLE_TIME"`
	MySQLMaxLifetime              time.Duration `config:"5m,env=MYSQL_MAX_LIFETIME"`

	// HMACKeyInternalAPI is used to make service-to-service calls to the api/internal handles in dotcom
	// To change this: add new key to comma separated list of keys in Dotcom's vault, deploy, then change here. After
	// it's deployed and no deployments are using the old key, you can remove the old key from dotcom's vault.
	HMACKeyInternalAPI string `config:",env=API_INTERNAL_HMAC_KEY"`

	// TenantKeyGenerator
	TenantKeyGeneratorBufferSize int `config:"10,env=TENANT_KEY_GENERATOR_BUFFER_SIZE"`
	TenantKeyGeneratorWorkers    int `config:"1,env=TENANT_KEY_GENERATOR_WORKERS"`

	// AzureProviderConfig
	config.AzureProviderConfig

	// Config for scheduled service - see ScheduledConfig
	ScheduledLoopSleep         time.Duration `config:"1m,env=SCHEDULE_LOOP_SLEEP_DURATION"`
	ScheduledReassignWorkAfter time.Duration `config:"3m,env=SCHEDULE_REASSIGN_AFTER_DURATION"`
	ScheduledScatterOffset     time.Duration `config:"30s,env=SCHEDULE_SCATTER_OFFSET_DURATION"`
	ScheduledTaskPerTick       int           `config:"10,env=SCHEDULE_TASKS_PER_TICK"`

	// Spokesd
	SpokesdURL       string `config:",env=SPOKESD_URL"`
	SpokesdCert      string `config:",env=SPOKESD_CERT_PEM"`
	SpokesdKey       string `config:",env=SPOKESD_KEY_PEM"`
	SpokesdChain     string `config:",env=SPOKESD_CHAIN_PEM"`
	SpokesdConfigTLS bool   `config:"false,env=SPOKESD_CONFIG_TLS"`

	// Authzd
	AuthzdURL string `config:",env=AUTHZD_URL"`

	// Keystore diet earthsmoke key
	KeystoreAZPOrganizationKey string `config:",env=EARTHSMOKE_KEYSTORE_AZP_ORGANIZATION"`

	BreakerConfig abreaker.Config

	// Queue run rate limiting
	QueueRunRateLimitEnabled   bool `config:"false,env=QUEUE_RUN_RATE_LIMIT_ENABLED"`
	QueueRunRateLimitPerMinute int  `config:"1000,env=QUEUE_RUN_RATE_LIMIT_PER_MINUTE"`

	// Per repository rate limiter for reading off webhook aqueduct queue.
	WebhookRateLimitEnabled   bool   `config:"false,env=WEBHOOK_RATE_LIMIT_ENABLED"`
	WebhookRateLimitThreshold uint64 `config:"1250,env=WEBHOOK_RATE_LIMIT_PER_BUCKET"`

	// Chaos Mode, beware this could unleash gremlins
	ChaosMode     bool   `config:"false"`
	ChaosScenario string `config:""`

	roundtrippers.RoundTripperConfig

	// Top100 customers list string separated by ','.
	Top100Customers string `config:",env=TOP_100_CUSTOMERS"`

	// Temporary four nines stage rollout enterprise names string separated by ','.
	// Being part of this list implies customer label will just be enterprise name it'self, instead of "top100" for example, for such enterprises.
	// TODO(https://github.com/github/actions-runtime/issues/4892): enterpriseName can be removed after we are done with specific enterprise rollout
	TemporaryFourNinesStageRolloutEnterpriseNames string `config:",env=TEMPORARY_FOUR_NINES_STAGE_ROLLOUT_ENTERPRISE_NAMES"`

	// Run Service (part of 4 nines)
	RunServiceURL        string `config:",env=RUN_SERVICE_URL"`
	RunServiceHMACSecret string `config:",env=RUN_SERVICE_HMAC_SECRET,required"`

	// Results
	ResultsCoreURL        string `config:",env=RESULTS_CORE_ADDR"`
	ResultsCoreHMACSecret string `config:",env=RESULTS_CORE_HMAC_SECRET"`
}

// GetActionsBotNodeIDs splits RawActionsBotNodeIDs and verifies that there's at least one value.
func (cfg *Config) GetActionsBotNodeIDs(ctx context.Context) ([]types.GlobalID, error) {
	var res []types.GlobalID
	for _, s := range strings.Split(cfg.RawActionsBotNodeIDs, ",") {
		if len(s) > 0 {
			res = append(res, types.NewGlobalID(ctx, s))
		}
	}
	if len(res) < 1 {
		return nil, errors.New("GITHUB_ACTIONS_BOT_NODE_IDS must contain at least one GlobalID")
	}
	return res, nil
}

// GetActionsAppIDs parses the ints contained in RawActionsAppIDs and verifies that there's at least one value.
func (cfg *Config) GetActionsAppIDs() ([]int64, error) {
	var res []int64
	values := strings.Split(strings.TrimSpace(cfg.RawActionsAppIDs), "\n")
	for _, s := range values {
		value := strings.TrimSpace(s)
		if len(value) > 0 {
			n, err := strconv.ParseInt(value, 10, 64)
			if err != nil {
				return nil, err
			}
			res = append(res, n)
		}
	}
	if len(res) < 1 {
		return nil, errors.New("GITHUB_ACTIONS_APP_IDS must contain at least one int64 app ID")
	}
	return res, nil
}

// GetDependabotAppRelayID returns the app ID for Dependabot and true if an app ID for Dependabot was provided and found, if not, it will return an empty string and false.
func (cfg *Config) GetDependabotAppRelayID() (string, bool) {
	if cfg.DependabotAppRelayID == "" {
		return "", false
	}
	return cfg.DependabotAppRelayID, true
}

func (cfg *Config) getLogger() logger.Logger {
	return logger.New(&logger.Config{
		App:          "launch",
		Debug:        cfg.LogDebug,
		Hostname:     getHostname(),
		ReportURL:    cfg.ReportingAddr,
		FieldTags:    logger.DefaultFieldTags,
		LoggerConfig: cfg.LoggerConfig,
	})
}

func getHostname() string {
	if appHost, err := os.Hostname(); err == nil {
		return appHost
	}
	return "unknown"
}

func (cfg *Config) getStatter(statsTags statter.Tags) statter.Statter {
	if cfg.IsEnterprise() {
		// https://github.com/github/c2c-actions-experience/issues/2982#issuecomment-661206260
		return statter.NullStatter()
	}

	prefix := cfg.StatsPrefix
	if len(prefix) == 0 {
		prefix = cfg.Name
	}

	statter := statter.New(&statter.Config{
		Prefix: prefix,
		Addr:   cfg.StatsAddr,
		Period: cfg.StatsPeriod,
		Tags:   statsTags,
	})
	statter.Start()

	return statter
}

func (cfg *Config) GetGraphQLServiceToken() tokens.ServiceToken {
	return tokens.ServiceToken(cfg.GraphQLServiceToken)
}

func (cfg Config) KredzHMACSecrets() []string {
	return strings.Split(cfg.KredzHMACSecret, ",")
}

func (cfg Config) VarzHMACSecrets() []string {
	return strings.Split(cfg.VarzHMACSecret, ",")
}

func (cfg Config) RunServiceHMACSecrets() []string {
	return strings.Split(cfg.RunServiceHMACSecret, ",")
}
