package main

import (
	"strings"
	"time"

	"github.com/pkg/errors"

	"github.com/github/launch/clients/launchblob"
	"github.com/github/launch/clients/launchredis"
	"github.com/github/launch/pkg/abreaker"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchconfig"
	tokenauth "github.com/github/launch/services/auth/token"
	"github.com/github/launch/utils/roundtrippers"
	"github.com/github/launch/workflowbuild/azp/config"
)

// Config is the complete configuration definition for the launch-receiver
// application.
//
// It is read from the environment variables present in the container on which
// this application is run, and initialized using the 'config' package
// (see: github.com/github/go-config/v2)
type Config struct {
	launchconfig.CommonConfig

	EnterpriseVersion string `config:"latest,env=ENTERPRISE_INSTALLED_VERSION"`

	DeployerTWIRPAddr string `config:",env=DEPLOYER_TWIRP_ADDR,required"`

	// The secret to use to sign requests to deployer for HMAC verification.
	// This should match one of the secrets in Deployer's DEPLOYER_HMAC_VERIFY_SECRETS
	DeployerHMACSigningSecret string `config:",env=DEPLOYER_HMAC_SECRET,required"`

	launchcache.CacheConfig
	launchredis.RedisConfig
	launchblob.BlobConfig

	// DB Settings
	DatabaseURL                   string        `config:",env=DATABASE_URL,required"`
	ReadOnlyDatabaseURL           string        `config:",env=READ_ONLY_DATABASE_URL,required"`
	PayloadsDatabaseURL           string        `config:",env=PAYLOADS_DATABASE_URL"`
	EmulatePreparedStatements     bool          `config:"false,env=EMULATE_PREPARED_STATEMENTS"`
	UseUTCForMySQL                bool          `config:"false,env=USE_UTC_FOR_MYSQL"`
	ForceCharsetForMySQL          bool          `config:"false,env=FORCE_CHARSET_FOR_MYSQL"`
	MySQLBreakerConsecutiveErrors int           `config:"500,env=MYSQL_CIRCUIT_BREAKER_CONSECUTIVE_ERRORS"`
	MySQLMaxOpenConns             int           `config:"512,env=MYSQL_MAX_OPEN_CONNS"`
	MySQLMaxIdleConns             int           `config:"512,env=MYSQL_MAX_IDLE_CONNS"`
	MySQLMaxIdleTime              time.Duration `config:"25s,env=MYSQL_MAX_IDLE_TIME"`
	MySQLMaxLifetime              time.Duration `config:"5m,env=MYSQL_MAX_LIFETIME"`

	FrenoURL             string `config:",env=LAUNCH_FRENO_URL"`
	FrenoOverrideCluster string `config:",env=LAUNCH_FRENO_OVERRIDE_CLUSTER"`

	// From RECEIVER_ACTION_RUNNER_SECRET in vault
	ActionRunnerSecret string `config:",env=ACTION_RUNNER_SECRET,required"`

	ActionRunnerSecretDurationHours int `config:"1,env=ACTION_RUNNER_SECRET_DURATION_HOURS"`

	// ReceiverURL is currently used in HKDF verification of incoming requests from actions service, because
	// it matches the URL sent to actions service in queue build payloads (also RECEIVER_URL in deployer).
	ReceiverURL string `config:",env=RECEIVER_URL"`

	// ReceiverInternalURL is the URL that the receiver will listen on for internal traffic from run-service
	ReceiverInternalURL string `config:",env=RECEIVER_INTERNAL_URL"`

	// GitHub Twirp Configuration
	GitHubTwirpHMACSecret string `config:",env=GITHUB_TWIRP_HMAC_SECRET,required"`
	GitHubTwirpAddr       string `config:",env=GITHUB_TWIRP_ADDR,required"`

	// Kredz
	KredzHTTPAddr     string `config:",env=KREDZ_HTTP_ADDR,required"`
	KredzHMACSecret   string `config:",env=KREDZ_HMAC_SECRET,required"`
	SecretsAppRelayID string `config:",env=GITHUB_SECRETS_APP_RELAY_ID,required"`

	// Varz
	VarzHTTPAddr   string `config:",env=VARZ_HTTP_ADDR"`
	VarzHMACSecret string `config:",env=VARZ_HMAC_SECRET"`

	// Hydro configuration
	KafkaRootCAPath string `config:",env=KAFKA_ROOT_CA_PATH"`
	KafkaBrokers    string `config:"disabled,env=KAFKA_BROKERS"`
	KafkaVersion    string `config:",env=KAFKA_VERSION"`

	// network configuration service
	NetworkConfigServiceURL  string `config:",env=NETWORK_CONFIGURATION_SERVICE_URL"`
	NetworkConfigServiceKeys string `config:",env=CPS_NETWORK_SERVICE_HMAC_SECRETS"`

	// Diet earthsmoke crypto keys
	DietEarthsmokeCustomTasksKey string `config:",env=EARTHSMOKE_CUSTOM_TASKS_KEY"`
	DependabotSecretsKey         string `config:",env=EARTHSMOKE_DEPENDABOT_SECRETS_KEY"`

	ActionsAuthHMACKeyPrimary   string `config:",env=ACTIONS_AUTH_HMAC_KEY_PRIMARY"`
	ActionsAuthHMACKeySecondary string `config:",env=ACTIONS_AUTH_HMAC_KEY_SECONDARY"`
	// key will be used directly for enterprise scenarios
	ActionsAppRealmWideHmacKeyPrimary   string `config:",env=ACTIONS_APP_REALM_WIDE_HMAC_KEY_PRIMARY"`
	ActionsAppRealmWideHmacKeySecondary string `config:",env=ACTIONS_APP_REALM_WIDE_HMAC_KEY_SECONDARY"`
	// Key will be fetched from vault based upon key name
	ActionsAppRealmWideHmacKeyNamePrimary   string `config:",env=ACTIONS_APP_REALM_WIDE_HMAC_KEY_NAME_PRIMARY"`
	ActionsAppRealmWideHmacKeyNameSecondary string `config:",env=ACTIONS_APP_REALM_WIDE_HMAC_KEY_NAME_SECONDARY"`

	config.AzureProviderConfig
	BreakerConfig abreaker.Config
	roundtrippers.RoundTripperConfig

	TokenAuth tokenauth.Config

	// Chaos Mode, beware this could unleash gremlins
	ChaosMode     bool   `config:"false"`
	ChaosScenario string `config:""`

	// Billing Platform config
	BillingPlatformURL        string `config:",env=BILLING_PLATFORM_URL"`
	BillingPlatformHMACSecret string `config:",env=BILLING_PLATFORM_HMAC_SECRET"`
}

// Validate confirms a configuration is semantically valid.
func (c Config) Validate() error {
	if c.ActionRunnerSecret == "" {
		return errors.New("ACTION_RUNNER_SECRET can not be empty")
	}
	return nil
}

func (c Config) KredzHMACSecrets() []string {
	return strings.Split(c.KredzHMACSecret, ",")
}

func (c Config) VarzHMACSecrets() []string {
	return strings.Split(c.VarzHMACSecret, ",")
}
