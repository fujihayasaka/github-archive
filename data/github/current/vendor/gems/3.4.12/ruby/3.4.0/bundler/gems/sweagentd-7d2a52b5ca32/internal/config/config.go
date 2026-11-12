// Package config contains the configuration options and initializers of dependencies for the service.
package config

import (
	"encoding/base64"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-config"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/observability/exceptions"
	"github.com/github/sweagentd/internal/observability/hydro"
	"github.com/github/sweagentd/internal/observability/stats"
	"github.com/joho/godotenv"
)

// Config holds application configuration, including statting and tracing configs.
type Config struct {
	RedisConfigSection

	HTTPPort        int         `config:"2208,env=PORT"`
	ServiceName     string      `config:"sweagentd,env=APP_NAME"`
	EnvironmentName string      `config:"development,env=HEAVEN_DEPLOYED_ENV"`
	Environment     Environment // populated from EnvironmentString in our load function
	Sha             string      `config:",env=APP_SHA"`
	Ref             string      `config:",env=APP_REF"`

	StatsAddr   string        `config:",env=STATS_ADDR"`
	StatsPeriod time.Duration `config:"10s,env=STATS_PERIOD"`

	KubePodName       string `config:"sweagentd,env=KUBE_POD_NAME"`
	KubeContainerName string `config:"sweagentd,env=KUBE_CONTAINER_NAME"`
	KubeNamespace     string `config:"development,env=KUBE_NAMESPACE"`

	DisableHydroConsumer     bool     `config:"false,env=DISABLE_HYDRO_CONSUMER"`
	HydroBrokers             []string `config:"kafka-lite.localhost:9092,env=HYDRO_BROKERS"`
	HydroClientID            string   `config:"sweagentd,env=HYDRO_CLIENT_ID"`
	HydroGroupName           string   `config:"sweagentd,env=HYDRO_GROUP_NAME"`
	HydroKafkaVersion        string   `config:"1.1.1,env=HYDRO_KAFKA_VERSION"`
	HydroQueueWorkerPoolSize string   `config:"1,env=HYDRO_QUEUE_WORKER_POOL_SIZE"`

	AuthndURL     string `config:",env=AUTHND_URL"`
	AuthndHMACKey string `config:",env=AUTHND_HMAC_KEY"`

	CopilotAPIURL        string `config:"https://api.githubcopilot.com,env=COPILOT_API_URL"`
	GitHubAPIURL         string `config:"https://api.github.com/,env=GITHUB_API_BASE_URL"`
	GitHubInternalAPIURL string `config:",env=GITHUB_INTERNAL_API_BASE_URL"`
	GitHubServerURL      string `config:"https://github.com,env=GITHUB_SERVER_URL"`
	GitHubUploadsURL     string `config:"https://uploads.github.com/user-attachments/assets,env=GITHUB_UPLOADS_URL"`
	GitHubDownloadsURL   string `config:"https://api.github.com/internal/user-attachments/assets,env=GITHUB_DOWNLOADS_URL"`

	AgentCallbackURL string `config:",env=AGENT_CALLBACK_URL"`

	ModelOverride string `config:",env=MODEL_OVERRIDE"`

	MCPEnabled bool `config:"false,env=COPILOT_MCP_ENABLED"`

	AnthropicAPIKey string `config:",env=ANTHROPIC_API_KEY"`

	AgentLauncher AgentLauncher `config:",env=AGENT_LAUNCHER"` // one of
	// Indicates whether the Docker launcher should output debug messages from the agent
	AgentDebug bool `config:"false,env=COPILOT_AGENT_DEBUG"`
	// Agent firewall config - used in Actions and Docker launchers
	AgentFirewallEnabledDefault          bool   `config:"false,env=COPILOT_AGENT_FIREWALL_ENABLED_DEFAULT"`
	AgentFirewallAllowListDefault        string `config:",env=COPILOT_AGENT_FIREWALL_ALLOW_LIST_DEFAULT"`
	AgentFirewallRuleSetAllowListDefault string `config:",env=COPILOT_AGENT_FIREWALL_RULESET_ALLOW_LIST"`
	AgentFirewallRequiredAllowList       string `config:",env=COPILOT_AGENT_FIREWALL_REQUIRED_ALLOW_LIST"`

	// Runs on labels and group for Actions runners. Set to label to "self-hosted" when developing with github/github
	ActionsDefaultRunsOnLabels string `config:"ubuntu-latest,env=ACTIONS_DEFAULT_RUNS_ON_LABELS"`

	// config for running the service in Docker
	DockerAIPProxy            bool   `config:"false,env=DOCKER_AIP_PROXY"`
	DockerUseHostNetworking   bool   `config:"true,env=DOCKER_HOST_NETWORKING"`
	DockerAgentContainerImage string `config:",env=DOCKER_AGENT_CONTAINER_IMAGE"`
	DockerMapPort             int    `config:"0,env=DOCKER_MAP_PORT"`

	// config for CosmosDB persistence layer
	AzureCosmosDBDatabase string `config:"sweagentd,env=AZURE_COSMOSDB_DATABASE"`

	AzureCosmosDBContainerAssignment string `config:"assignments,env=AZURE_COSMOSDB_CONTAINER_ASSIGNMENT"`
	AzureCosmosDBContainerJobs       string `config:"jobs,env=AZURE_COSMOSDB_CONTAINER_JOBS"`
	AzureCosmosDBContainerLogs       string `config:"job-logs,env=AZURE_COSMOSDB_CONTAINER_LOGS"`
	AzureCosmosDBContainerMemory     string `config:"memory,env=AZURE_COSMOSDB_CONTAINER_MEMORY"`
	AzureCosmosDBContainerCommands   string `config:"job-commands,env=AZURE_COSMOSDB_CONTAINER_COMMANDS"`

	AzureCosmosDBEndpoint         string `config:",env=AZURE_COSMOSDB_ENDPOINT"`
	AzureCosmosDBConnectionString string `config:",env=AZURE_COSMOSDB_CONNECTION_STRING"`
	AzureCosmosDBSPNName          string `config:",env=AZURE_COSMOSDB_SPN_NAME"`

	// These three values have different keys per environment, based on the SPN name and must be explicitly loaded
	AzureCosmosDBSPNTenantID     string
	AzureCosmosDBSPNClientID     string
	AzureCosmosDBSPNClientSecret string

	// config for using an external github app
	GitHubAppPrivateKey   string `config:",env=GITHUB_APP_PRIVATE_KEY"`
	GitHubAppID           int64  `config:"0,env=GITHUB_APP_ID"`
	GitHubAppLogin        string `config:",env=GITHUB_APP_LOGIN"`
	GitHubAppClientID     string `config:",env=GITHUB_APP_CLIENT_ID"`
	GitHubAppClientSecret string `config:",env=GITHUB_APP_CLIENT_SECRET"`
	GitHubCommitLogin     string `config:",env=GITHUB_COMMIT_LOGIN"`
	GitHubCommitEmail     string `config:",env=GITHUB_COMMIT_EMAIL"`
	GitHubBotLogin        string `config:",env=GITHUB_BOT_LOGIN"` // the login of the GitHub App's bot user - `GitHubAppLogin` + `[bot]`
	GitHubTwirpAPIURL     string `config:"http://api.github.localhost/internal,env=MONOLITH_TWIRP_API_URL"`
	GitHubTwirpHMACKey    string `config:"sweagentdhmac,env=MONOLITH_TWIRP_HMAC_KEY"`

	LimiterTwirpAPIURL string `config:",env=COPILOT_LIMITER_API_URL"`
	// LimiterTwirpAPIHMAC is the HMAC key used to sign requests to the limiter service.
	// the env value needs to match the one in the limiter, which has to be named like so.
	LimiterTwirpHMAC             string `config:"sweagentdhmac,env=LIMITER_TWIRP_HMAC_KEY"`
	LimiterTwirpRequestTimeoutMs int    `config:"1000"`

	// secret for authenticating with CAPI - specify the CopilotIntegrationID and then the HMAC secret
	CopilotIntegrationID string `config:"copilot-developer,env=COPILOT_INTEGRATION_ID"`
	CapiHMACKey          string `config:",env=CAPI_HMAC_KEY"`

	// Secret for authenticating with the Internal GitHub API for Dynamic Workflows
	// The default value is only valid for development environments and should be overridden in production
	DynamicWorkflowsHMACKey string `config:"octocat,env=API_INTERNAL_ACTIONS_DYNAMIC_WORKFLOWS_HMAC_CLIENT_KEY"`

	// ForceListenAllInterfaces is used to force the service to listen on all interfaces, even in a Development environment.
	ForceListenAllInterfaces bool `config:"false,env=FORCE_LISTEN_ALL_INTERFACES"`

	// 32-byte hex-encoded encryption key to encrypt/decrypt short-lived tokens temporarily stored in the database
	EncryptionKey string `config:",env=ENCRYPTION_KEY"`

	// Experiments
	// ExperimentationAPIURL is the URL of the experimentation service.
	ExperimentationAPIURL string `config:"https://default.exp-tas.com/vscode/ab,env=EXPERIMENTATION_API_URL"`
	// These values currently match the defaults in the experiments client.
	ExperimentCacheTTL             time.Duration `config:"10m"`
	ExperimentCacheMaxSize         int           `config:"5000"`
	ExperimentCacheCleanupInterval time.Duration `config:"1m"`
	ExperimentsTimeout             time.Duration `config:"1s"`

	// This is the number of workers that will be started to handle events
	// from the event queue. The number of workers should be equal to the
	// number of CPU cores available. With that said, increments to this number
	// affect all of our downstream services such as GitHub.com, Cosmos, CAPI, and Actions.
	// We should only increase this number if we are sure that the downstream services can handle it.
	EventWorkers int `config:"4,env=EVENT_WORKERS"`

	// Where the runtime app compressed file is located, served and usable when the docker build happens.
	RuntimeAppPath string `config:",env=RUNTIME_APP_PATH"`

	// How long until the runtime should be terminated due to timeout. It is currently up to the launcher to
	// determine how to accomplish the termination. The runtime will not terminate itself.
	AgentTimeoutMin int `config:"59,env=AGENT_TIMEOUT"`

	// Aqueduct configuration
	AqueductURL                    string `config:"http://127.0.0.1:18081,env=AQUEDUCT_URL"`
	AqueductApp                    string `config:"sweagentd,env=AQUEDUCT_APP"`
	AqueductAPIKey                 string `config:"test,env=AQUEDUCT_API_KEY"`
	AqueductAPIKeyVersion          int    `config:"0,env=AQUEDUCT_API_KEY_VERSION"`
	AqueductWorkerCount            int    `config:"1,env=AQUEDUCT_WORKER_COUNT"`
	AqueductRequeueIntervalSeconds int    `config:"5,env=AQUEDUCT_REQUEUE_INTERVAL_SECONDS"`

	// Staging and production use the same secret environment, but not the same aqueduct secrets because we want to use a different worker pool in staging to prevent cross traffic.
	AqueductStagingAPIKey                  string `config:"test,env=AQUEDUCT_STAGING_API_KEY"`
	AqueductStagingAPIKeyVersion           int    `config:"0,env=AQUEDUCT_STAGING_API_KEY_VERSION"`
	AqueductStagingJediKnightAPIKey        string `config:"test,env=AQUEDUCT_STAGING_JEDI_KNIGHT_API_KEY"`
	AqueductStagingJediKnightAPIKeyVersion int    `config:"0,env=AQUEDUCT_STAGING_JEDI_KNIGHT_API_KEY_VERSION"`
	AqueductStagingSithLordAPIKey          string `config:"test,env=AQUEDUCT_STAGING_SITH_LORD_API_KEY"`
	AqueductStagingSithLordAPIKeyVersion   int    `config:"0,env=AQUEDUCT_STAGING_SITH_LORD_API_KEY_VERSION"`

	// Token Scanning configuration
	TokenScanningURL     string `config:"https://scanning-api.github.com,env=TOKEN_SCANNING_URL"`
	TokenScanningHMACKey string `config:",env=PUBLIC_SCANNING_API_FOR_AGENT_MEMORY_HMAC_KEYS"`

	SpokesURL  string `config:"http://localhost:28081,env=SPOKESD_URL"`
	SpokesCert string `config:",env=SWEAGENTD_PRODUCTION_SPOKESD_CLIENT_CERT"`
	SpokesKey  string `config:",env=SWEAGENTD_PRODUCTION_SPOKESD_CLIENT_CERT_KEY"`
	SpokesCA   string `config:",env=SPOKESD_CA_CHAIN"`

	// Billing
	BillingClientURL     string `config:"http://localhost:8989,env=BILLING_PLATFORM_HOST"`
	BillingClientHMACKey string `config:"billing-platform,env=BILLING_PLATFORM_HMAC_KEY"`
}

// AgentLauncher represents the type of launcher used for agents.
type AgentLauncher string

const (
	// AgentLauncherActions represents the GitHub Actions launcher.
	AgentLauncherActions AgentLauncher = "actions"
	// AgentLauncherDocker represents the Docker launcher.
	AgentLauncherDocker AgentLauncher = "docker"
)

// Load parses configuration from the environment and places it in a newly
// allocated Config struct.
func Load() (*Config, error) {
	configFiles := []string{".env.feature_flags_development"}

	// Check if Cosmos dev environment file exists and add it to the list
	_, err := os.Stat(".env.cosmos-dev")
	if err == nil {
		configFiles = append(configFiles, ".env.cosmos-dev")
	}

	// Always load .env last so it can override other settings
	configFiles = append(configFiles, ".env")

	cfg, err := LoadFiles(configFiles...)
	if err != nil {
		return nil, fmt.Errorf("loading config: %w", err)
	}

	env, err := ParseEnvironment(cfg.EnvironmentName)
	if err != nil {
		return nil, fmt.Errorf("invalid environment: %w", err)
	}

	cfg.Environment = env

	cfg.populateSPNValues()

	return cfg, nil
}

// LoadFiles loads configuration from specified .env files and environment variables.
func LoadFiles(configs ...string) (*Config, error) {
	// Load environment variables from .env files.
	// Load doesn't really return an error, so we ignore it.
	// This is the same behavior as behavior when we autoloaded the pkg.

	// First, load the environment variables from the .env files so we can handle OVERRIDE properties
	envConfig, _ := godotenv.Read(configs...)
	if envConfig["GITHUB_API_BASE_URL_OVERRIDE"] != "" {
		os.Setenv("GITHUB_API_BASE_URL", envConfig["GITHUB_API_BASE_URL_OVERRIDE"])
	}
	if envConfig["GITHUB_SERVER_URL_OVERRIDE"] != "" {
		os.Setenv("GITHUB_SERVER_URL", envConfig["GITHUB_SERVER_URL_OVERRIDE"])
	}
	if envConfig["GITHUB_TOKEN_OVERRIDE"] != "" {
		os.Setenv("GITHUB_TOKEN", envConfig["GITHUB_TOKEN_OVERRIDE"])
	}

	// Next load the rest of environment variables, but don't overload/override
	_ = godotenv.Load(configs...)

	cfg := &Config{}

	err := config.Load(cfg)
	if err != nil {
		return nil, err
	}

	// Decode the GitHub App private key, since it's stored in base64
	// in the environment.
	decodedKey, err := base64.StdEncoding.DecodeString(cfg.GitHubAppPrivateKey)
	if err == nil {
		cfg.GitHubAppPrivateKey = string(decodedKey)
	}

	return cfg, nil
}

// PopulateFirewallConfiguration populates firewall configuration settings with default values if not already set.
func (cfg *Config) PopulateFirewallConfiguration(logger log.Logger) {
	if cfg.AgentFirewallRequiredAllowList == "" {
		cfg.AgentFirewallRequiredAllowList = GenerateRequiredFirewallAllowList(cfg)
	}
	encodedRulesetContent, err := GenerateEncodedDefaultRulesSetEnv()
	if err != nil {
		logger.WithError(err).Error("failed to generate default ruleset content")
	} else {
		cfg.AgentFirewallRuleSetAllowListDefault = encodedRulesetContent
	}
}

// IsProductionLike returns true if the environment is a production like environment.
// We consider staging as productionlike.
func (cfg *Config) IsProductionLike() bool {
	return !cfg.IsDevelopment()
}

// IsStaging returns true if the environment is staging specifically.
func (cfg *Config) IsStaging() bool {
	return cfg.EnvironmentName == "staging"
}

// IsDevelopment returns true if the environment is development.
func (cfg *Config) IsDevelopment() bool {
	return cfg.EnvironmentName == "development"
}

// GetMemoryAlphaURL returns the Memory Alpha URL for the current environment.
func (cfg *Config) GetMemoryAlphaURL() string {
	// Some downstream services (e.g. storage account / container naming) may not
	// accept dashes in the environment segment. Normalize by stripping dashes.
	sanitizedEnv := strings.ReplaceAll(cfg.EnvironmentName, "-", "")
	return fmt.Sprintf("https://memoryalpha%s.blob.core.windows.net/", sanitizedEnv)
}

// NewObservabilityExporters creates new observability exporters configured for the current environment.
func (cfg *Config) NewObservabilityExporters(loggerName string) (observability.Exporters, error) {
	if cfg.IsDevelopment() {
		// set some env vars (if not already set) to make logging in dev nicer.
		setEnv := func(name, val string) {
			if _, exists := os.LookupEnv(name); !exists {
				_ = os.Setenv(name, val)
			}
		}
		setEnv("GITHUB_TELEMETRY_LOGS_CONSOLE_ENCODING", "console")
		setEnv("GITHUB_TELEMETRY_LOGS_INCLUDE_RESOURCE_ATTRIBUTES", "")
		setEnv("GITHUB_TELEMETRY_LOGS_TZ", "local")
		setEnv("GITHUB_TELEMETRY_LOGS_PRECISION", "millisecond")
	}

	telemetryProvider, err := telemetry.NewFromEnv()
	if err != nil {
		return observability.Exporters{}, fmt.Errorf("failed to create logger: %w", err)
	}
	logger := telemetryProvider.Logger.Named(loggerName)
	log.SetDefault(logger)
	tracer := telemetryProvider.Tracer.Tracer

	// Exceptions
	exceptionsReporter, err := exceptions.NewReporter(cfg.IsDevelopment(), cfg.ServiceName, cfg.EnvironmentName, cfg.Sha, cfg.Ref, logger)
	if err != nil {
		return observability.Exporters{}, fmt.Errorf("failed to create exception reporter: %w", err)
	}

	// Stats
	statsClient, err := stats.NewClient(cfg.IsDevelopment(), cfg.StatsPeriod, cfg.StatsAddr, cfg.ServiceName, cfg.EnvironmentName, cfg.KubePodName, cfg.KubeContainerName, cfg.KubeNamespace)
	if err != nil {
		return observability.Exporters{}, fmt.Errorf("failed to create stats client: %w", err)
	}
	statsClient.Run()

	// Hydro
	hydroPublisher, err := hydro.NewPublisher(cfg.IsDevelopment(), cfg.HydroClientID, cfg.HydroKafkaVersion, cfg.HydroBrokers, logger, exceptionsReporter, statsClient)
	if err != nil {
		return observability.Exporters{}, fmt.Errorf("failed to create hydro publisher: %w", err)
	}

	// Observability clients
	return observability.NewExporters(
		tracer,
		exceptionsReporter,
		statsClient,
		hydroPublisher,
		logger,
	), nil
}

// Environment represents the deployment environment.
type Environment int

const (
	// EnvironmentDevelopment represents the development environment.
	EnvironmentDevelopment Environment = iota
	// EnvironmentProxima represents the proxima environment.
	EnvironmentProxima
	// EnvironmentStaging represents the staging environment.
	EnvironmentStaging
	// EnvironmentProduction represents the production environment.
	EnvironmentProduction
)

// ParseEnvironment parses a string into an Environment value.
func ParseEnvironment(s string) (Environment, error) {
	switch s {
	case "development":
		return EnvironmentDevelopment, nil
	case "production":
		return EnvironmentProduction, nil
	default:
		if IsStaging(s) {
			return EnvironmentStaging, nil
		}

		if IsProxima(s) {
			return EnvironmentProxima, nil
		}

		return -1, fmt.Errorf("unknown environment: %s", s)
	}
}

// IsProxima returns true if the environment is a Proxima environment.
func IsProxima(s string) bool {
	return strings.HasPrefix(s, "staff-") || strings.HasPrefix(s, "prod-") || strings.HasPrefix(s, "test-")
}

// IsStaging returns true if the environment is a staging environment.
func IsStaging(s string) bool {
	return strings.HasPrefix(s, "staging-") || s == "staging"
}

func (cfg *Config) populateSPNValues() {
	cfg.AzureCosmosDBSPNTenantID = os.Getenv(fmt.Sprintf("%s_tenant_id", cfg.AzureCosmosDBSPNName))
	cfg.AzureCosmosDBSPNClientID = os.Getenv(fmt.Sprintf("%s_client_id", cfg.AzureCosmosDBSPNName))
	cfg.AzureCosmosDBSPNClientSecret = os.Getenv(cfg.AzureCosmosDBSPNName)
}
