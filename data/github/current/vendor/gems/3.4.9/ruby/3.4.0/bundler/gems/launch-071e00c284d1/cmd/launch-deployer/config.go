package main

import (
	"strings"
	"time"

	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/clients/launchblob"
	"github.com/github/launch/clients/launchredis"
	"github.com/github/launch/pkg/abreaker"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/resolver"
	"github.com/github/launch/utils/roundtrippers"
	"github.com/github/launch/workflowbuild/azp/config"
)

// Config is the complete configuration definition for the launch-deployer
// application.
//
// It is read from the environment variables present in the container on which
// this application is run, and initialized using the 'config' package
// (see: github.com/github/go-config/v2)
type Config struct {
	launchconfig.CommonConfig

	EnterpriseVersion string `config:"latest,env=ENTERPRISE_INSTALLED_VERSION"`

	DatabaseURL            string `config:",env=DATABASE_URL,required"`
	ReadOnlyDatabaseURL    string `config:",env=READ_ONLY_DATABASE_URL,required"`
	PayloadsDatabaseURL    string `config:",env=PAYLOADS_DATABASE_URL"`
	APIHost                string `config:"http://api.github.localhost,env=API_HOST,required"`
	V3APIEndpoint          string `config:",env=V3_API_PATH"`
	GraphQLEndpoint        string `config:"/graphql,env=GRAPHQL_API_PATH"`
	KredzHTTPAddr          string `config:",env=KREDZ_HTTP_ADDR,required"`
	KredzHMACSecret        string `config:",env=KREDZ_HMAC_SECRET,required"`
	AppID                  int64  `config:",env=GITHUB_APP_ID,required"`
	SecretsAppRelayID      string `config:",env=GITHUB_SECRETS_APP_RELAY_ID,required"`
	AppPrivateKey          string `config:",env=GITHUB_APP_PRIVATE_KEY,required"`
	WorkflowTimeoutMinutes int    `config:"58,env=WORKFLOW_TIMEOUT_MINUTES"`

	launchcache.CacheConfig
	launchredis.RedisConfig
	launchblob.BlobConfig

	// Hydro configuration
	KafkaRootCAPath string `config:",env=KAFKA_ROOT_CA_PATH"`
	KafkaBrokers    string `config:"disabled,env=KAFKA_BROKERS"`
	KafkaVersion    string `config:",env=KAFKA_VERSION"`

	// GraphQLServiceToken will be passed as "GitHub-Internal-GraphQL-Token".
	// See also https://github.com/github/github/blob/f596db27beef26d9f7b84aa942a77cccdb05f8a3/app/api/graph_ql.rb#L93-L101
	GraphQLServiceToken string `config:",env=GITHUB_GRAPHQL_SERVICE_TOKEN"`

	// The secret to use for HMAC verification to GitHub's Twirp API
	GitHubTwirpHMACSecret string `config:",env=GITHUB_TWIRP_HMAC_SECRET,required"`
	GitHubTwirpAddr       string `config:",env=GITHUB_TWIRP_ADDR,required"`

	// The secrets to use for HMAC verification.
	// This needs to allow multiple secrets and be separate from DEPLOYER_HMAC_SECRET
	// to support safe credential rotations.
	DeployerHMACVerifySecret string `config:",env=DEPLOYER_HMAC_VERIFY_SECRETS,required"`

	// From DEPLOYER_ACTION_RUNNER_SECRET in vault
	ActionRunnerSecret string `config:",env=ACTION_RUNNER_SECRET,required"`

	// Config for scheduled service - see ScheduledConfig
	ScheduledLoopSleep           time.Duration `config:"1m,env=SCHEDULE_LOOP_SLEEP_DURATION"`
	ScheduledReassignWorkAfter   time.Duration `config:"3m,env=SCHEDULE_REASSIGN_AFTER_DURATION"`
	ScheduledScatterOffset       time.Duration `config:"30s,env=SCHEDULE_SCATTER_OFFSET_DURATION"`
	ScheduledTaskPerTick         int           `config:"10,env=SCHEDULE_TASKS_PER_TICK"`
	ScheduledTierCacheExpiration time.Duration `config:"3h,env=SCHEDULE_TIER_CACHE_EXPIRATION"`

	EmulatePreparedStatements     bool          `config:"false,env=EMULATE_PREPARED_STATEMENTS"`
	UseUTCForMySQL                bool          `config:"false,env=USE_UTC_FOR_MYSQL"`
	ForceCharsetForMySQL          bool          `config:"false,env=FORCE_CHARSET_FOR_MYSQL"`
	MySQLBreakerConsecutiveErrors int           `config:"500,env=MYSQL_CIRCUIT_BREAKER_CONSECUTIVE_ERRORS"`
	MySQLMaxOpenConns             int           `config:"512,env=MYSQL_MAX_OPEN_CONNS"`
	MySQLMaxIdleConns             int           `config:"512,env=MYSQL_MAX_IDLE_CONNS"`
	MySQLMaxIdleTime              time.Duration `config:"25s,env=MYSQL_MAX_IDLE_TIME"`
	MySQLMaxLifetime              time.Duration `config:"5m,env=MYSQL_MAX_LIFETIME"`

	// HMACKeyInternalAPI is used to make service-to-service calls to the api/internal handles in dotcom
	// To change this: add new key to comma separated list of keys in Dotcom's vault, deploy, then change here. After
	// it's deployed and no deployments are using the old key, you can remove the old key from dotcom's vault.
	HMACKeyInternalAPI string `config:",env=API_INTERNAL_HMAC_KEY"`

	// TenantKeyGenerator
	TenantKeyGeneratorBufferSize int `config:"10,env=TENANT_KEY_GENERATOR_BUFFER_SIZE"`
	TenantKeyGeneratorWorkers    int `config:"1,env=TENANT_KEY_GENERATOR_WORKERS"`

	// Aqueduct
	AqueductApp                  string `config:"actions,env=AQUEDUCT_APP"`
	AqueductURL                  string `config:",env=AQUEDUCT_URL"`
	AqueductAPIKey               string `config:",env=AQUEDUCT_API_KEY"`
	AqueductAPIKeyVersion        int    `config:"0,env=AQUEDUCT_API_KEY_VERSION"`
	ResultsAqueductAPIKey        string `config:",env=RESULTS_AQUEDUCT_API_KEY"`
	ResultsAqueductAPIKeyVersion int    `config:"0,env=RESULTS_AQUEDUCT_API_KEY_VERSION"`
	AqueductQueueScheduled       string `config:"scheduled_builds,env=AQUEDUCT_QUEUE_SCHEDULED_BUILDS"`
	AqueductQueueDynamic         string `config:"dynamic_builds,env=AQUEDUCT_QUEUE_DYNAMIC_BUILDS"`
	MaxRedeliveryAttempts        int    `config:"3,env=AQUEDUCT_MAX_REDELIVERY_ATTEMPTS"`
	RedeliveryTimeoutSecs        int    `config:"60,env=AQUEDUCT_REDELIVERY_TIMEOUT_SECS"`

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
	config.AzureProviderConfig
	roundtrippers.RoundTripperConfig

	// Chaos Mode, beware this could unleash gremlins
	ChaosMode     bool   `config:"false"`
	ChaosScenario string `config:""`

	// Settings for an external actions resolver app
	ResolverConfig resolver.Config

	// Billing Platform config
	BillingPlatformURL        string `config:",env=BILLING_PLATFORM_URL"`
	BillingPlatformHMACSecret string `config:",env=BILLING_PLATFORM_HMAC_SECRET"`
}

// GetGraphQLServiceToken returns a ServiceToken for the configured token
func (c Config) GetGraphQLServiceToken() tokens.ServiceToken {
	return tokens.ServiceToken(c.GraphQLServiceToken)
}

func (c Config) KredzHMACSecrets() []string {
	return strings.Split(c.KredzHMACSecret, ",")
}

func (c Config) DeployerHMACVerifySecrets() []string {
	return strings.Split(c.DeployerHMACVerifySecret, ",")
}
