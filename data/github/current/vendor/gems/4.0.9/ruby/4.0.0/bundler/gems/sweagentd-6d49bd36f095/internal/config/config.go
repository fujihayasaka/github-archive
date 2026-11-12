// Package config contains the configuration options and initializers of dependencies for the service.
package config

import (
	"fmt"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-config"
	"github.com/github/sweagentd/internal/goerrors"
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

	// HTTP Rate Limiting (activation is controlled by the CopilotSWEAgentHTTPRateLimit feature flag)
	HTTPRateLimitRequestsPerMinute   int `config:"600,env=HTTP_RATE_LIMIT_REQUESTS_PER_MINUTE"`
	TokensRateLimitRequestsPerMinute int `config:"60,env=TOKENS_RATE_LIMIT_REQUESTS_PER_MINUTE"`

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
	HydroSyncGroupName       string   `config:"sweagentd-sync,env=HYDRO_SYNC_GROUP_NAME"`
	HydroWorkerGroupName     string   `config:"sweagentd-worker,env=HYDRO_WORKER_GROUP_NAME"`

	AuthndURL     string `config:",env=AUTHND_URL"`      // For using authnd in a codespace, the URL is "http://localhost:8092/twirp"
	AuthndHMACKey string `config:",env=AUTHND_HMAC_KEY"` // For using authnd in a codespace, the key is "octocat"
	// OIDCAuthndEnabled enables the authnd IdentityManager service for OIDC
	// token issuance. When true, tokens are minted by authnd instead of being
	// signed locally. Defaults to false and is typically enabled via configuration
	// in production/staging. Requires AuthndURL and AuthndHMACKey to be set.
	OIDCAuthndEnabled bool `config:"false,env=OIDC_AUTHND_ENABLED"`

	// OIDCDevSignerIssuerURL overrides the OIDC issuer URL. When empty, the issuer is
	// derived from codespace port forwarding or CopilotAPIURL. Only set this when
	// you need the URL to be from a different source (e.g. a different port forwarder).
	OIDCDevSignerIssuerURL string `config:",env=OIDC_DEV_SIGNER_ISSUER_URL"`
	OIDCHTTPProxy          string `config:",env=SWEAGENTD_HTTP_PROXY"`
	OIDCHTTPSProxy         string `config:",env=SWEAGENTD_HTTPS_PROXY"`

	CopilotAPIURL        string `config:"https://api.githubcopilot.com,env=COPILOT_API_URL"`
	GitHubAPIURL         string `config:"https://api.github.com/,env=GITHUB_API_BASE_URL"`
	GitHubInternalAPIURL string `config:",env=GITHUB_INTERNAL_API_BASE_URL"`
	GitHubServerURL      string `config:"https://github.com,env=GITHUB_SERVER_URL"`
	GitHubUploadsURL     string `config:"https://uploads.github.com/user-attachments/assets,env=GITHUB_UPLOADS_URL"`
	GitHubDownloadsURL   string `config:"https://api.github.com/internal/user-attachments/assets,env=GITHUB_DOWNLOADS_URL"`
	SecretScanningURL    string `config:"https://scanning-api.github.com/api/v1/scan/multipart,env=SECRET_SCANNING_URL"`
	GitHubAdvisoriesURL  string `config:"https://api.github.com/advisories,env=GITHUB_ADVISORIES_URL"`

	AgentCallbackURL string `config:",env=AGENT_CALLBACK_URL"`

	ModelOverride string `config:",env=MODEL_OVERRIDE"`

	MCPEnabled bool `config:"false,env=COPILOT_MCP_ENABLED"`
	// Development only option to allow the GitHub MCP URL to be different than CAPI
	GitHubMCPURLOverride string `config:",env=GITHUB_MCP_URL_OVERRIDE"`

	AnthropicAPIKey string `config:",env=ANTHROPIC_API_KEY"`

	// Token for authenticating with GitHub Copilot API used in development
	// in conjunction with the Docker launcher
	GitHubCopilotAPIToken string `config:",env=GITHUB_COPILOT_API_TOKEN"`

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

	// DockerEnginePath is the local filesystem path to an engine project directory.
	// When set, the Docker launcher will mount this directory and use it as the
	// engine entry point instead of the built-in runtime. Development only.
	DockerEnginePath string `config:",env=DOCKER_ENGINE_PATH"`
	// DockerEngineInferenceToken is a token that can call production for model inference.
	// Used only in engine mode for local development.
	DockerEngineInferenceToken string `config:",env=DOCKER_ENGINE_INFERENCE_TOKEN"`

	// Sandbox VM configuration
	// LaunchTwirpAPIURL is the base URL for Launch deployer's internal sandbox Twirp API.
	LaunchTwirpAPIURL string `config:",env=LAUNCH_TWIRP_API_URL"`
	// LaunchTwirpHMACKey is the request HMAC key for Launch deployer's internal sandbox Twirp API.
	LaunchTwirpHMACKey string `config:",env=LAUNCH_TWIRP_HMAC_KEY"`
	// SandboxMCBaseURL is the Mission Control base URL forwarded into sandboxes for --remote support.
	SandboxMCBaseURL string `config:",env=SANDBOX_MC_BASE_URL"`
	// SandboxUseDocker uses a local Docker daemon instead of the cloud Sandbox API.
	SandboxUseDocker bool `config:"false,env=SANDBOX_USE_DOCKER"`

	// config for CosmosDB persistence layer
	AzureCosmosDBDatabase string `config:"sweagentd,env=AZURE_COSMOSDB_DATABASE"`

	AzureCosmosDBContainerAssignment         string `config:"assignments,env=AZURE_COSMOSDB_CONTAINER_ASSIGNMENT"`
	AzureCosmosDBContainerJobs               string `config:"jobs,env=AZURE_COSMOSDB_CONTAINER_JOBS"`
	AzureCosmosDBContainerProgress           string `config:"job-logs,env=AZURE_COSMOSDB_CONTAINER_PROGRESS"`
	AzureCosmosDBContainerMemory             string `config:"memory,env=AZURE_COSMOSDB_CONTAINER_MEMORY"`
	AzureCosmosDBContainerCommands           string `config:"job-commands,env=AZURE_COSMOSDB_CONTAINER_COMMANDS"`
	AzureCosmosDBContainerRepositoryAgents   string `config:"repo-agents,env=AZURE_COSMOSDB_CONTAINER_REPOSITORY_AGENTS"`
	AzureCosmosDBContainerOrganizationAgents string `config:"org-agents,env=AZURE_COSMOSDB_CONTAINER_ORGANIZATION_AGENTS"`
	AzureCosmosDBContainerEnterpriseAgents   string `config:"enterprise-agents,env=AZURE_COSMOSDB_CONTAINER_ENTERPRISE_AGENTS"`
	AzureCosmosDBContainerIntervalTriggers   string `config:"interval-triggers,env=AZURE_COSMOSDB_CONTAINER_INTERVAL_TRIGGERS"`

	// Scheduler configuration
	SchedulerTickInterval       time.Duration `config:"30s,env=SCHEDULER_TICK_INTERVAL"`
	SchedulerBatchSize          int           `config:"50,env=SCHEDULER_BATCH_SIZE"`
	SchedulerStaleLockThreshold time.Duration `config:"3m,env=SCHEDULER_STALE_LOCK_THRESHOLD"`

	AzureCosmosDBEndpoint         string `config:",env=AZURE_COSMOSDB_ENDPOINT"`
	AzureCosmosDBConnectionString string `config:",env=AZURE_COSMOSDB_CONNECTION_STRING"`
	AzureCosmosDBSPNName          string `config:",env=AZURE_COSMOSDB_SPN_NAME"`

	// These values have different keys per environment, based on the SPN name and must be explicitly loaded
	AzureCosmosDBSPNTenantID string
	AzureCosmosDBSPNClientID string

	// These are used in service startup
	GitHubAppID int64 `config:"0,env=GITHUB_APP_ID"`

	GitHubTwirpAPIURL  string `config:"http://api.github.localhost/internal,env=MONOLITH_TWIRP_API_URL"`
	GitHubTwirpHMACKey string `config:"sweagentdhmac,env=MONOLITH_TWIRP_HMAC_KEY"`

	CopilotMissionControlTwirpURL string `config:",env=COPILOT_MISSION_CONTROL_TWIRP_URL"`
	// This is sweagentd's caller HMAC key, not a CMC-specific secret. The env var
	// name is historical: secrets-federation sends APP_HMAC_KEY_COPILOT_API to CMC
	// as SWEAGENTD_HMAC_KEY, and CMC validates that key to authenticate sweagentd.
	CopilotMissionControlTwirpHMACKey          string `config:",env=APP_HMAC_KEY_COPILOT_API"`
	CopilotMissionControlTwirpRequestTimeoutMs int    `config:"5000,env=COPILOT_MISSION_CONTROL_TWIRP_REQUEST_TIMEOUT_MS"`

	LimiterTwirpAPIURL string `config:",env=COPILOT_LIMITER_API_URL"`
	// LimiterTwirpHMAC is the HMAC key used to sign requests to the limiter service.
	// The env value needs to match the one in the limiter, which has to be named like so.
	LimiterTwirpHMAC             string `config:"sweagentdhmac,env=LIMITER_TWIRP_HMAC_KEY"`
	LimiterTwirpRequestTimeoutMs int    `config:"400"`

	// secret for authenticating with CAPI - specify the CopilotIntegrationID and then the HMAC secret
	CopilotIntegrationID string `config:"copilot-developer,env=COPILOT_INTEGRATION_ID"`
	CapiHMACKey          string `config:",env=CAPI_HMAC_KEY"`

	// Secret for authenticating with the Internal GitHub API for Dynamic Workflows
	// The default value is only valid for development environments and should be overridden in production
	DynamicWorkflowsHMACKey string `config:"octocat,env=API_INTERNAL_ACTIONS_DYNAMIC_WORKFLOWS_HMAC_CLIENT_KEY"`

	// ForceListenAllInterfaces is used to force the service to listen on all interfaces, even in a Development environment.
	ForceListenAllInterfaces bool `config:"false,env=FORCE_LISTEN_ALL_INTERFACES"`

	// 32-byte hex-encoded encryption key to encrypt/decrypt short-lived tokens temporarily stored in the database
	// To generate a new key, you can use the following command within a vault-bastion shell:
	// ```bash
	// existing_value=$(vault-secret --application sweagentd --environment <environment> -k ENCRYPTION_KEY)
	// new_value=$(head --bytes=32 /dev/urandom | xxd -p -c 0 | tr -d '\n')
	// echo "${existing_value},${new_value}" | vault-secret --application sweagentd --environment <environment> -k ENCRYPTION_KEY -v --stdin
	// ```
	EncryptionKey string `config:",env=ENCRYPTION_KEY"`

	// Experiments
	// ExperimentationAPIURL is the URL of the experimentation service (legacy TAS flow).
	ExperimentationAPIURL string `config:"https://default.exp-tas.com/vscode/ab,env=EXPERIMENTATION_API_URL"`
	// ExperimentationSDKBlobURI is the Azure Blob Storage URI for the exp-go-sdk config.
	// See https://github.com/github/learning-machine/blob/fde38fc9e76571d082eeac602ef42ceaf5491541/docs/exp/onboarding/README.md#sdk
	ExperimentationSDKBlobURI string `config:",env=EXPERIMENTATION_SDK_BLOB_URI"`
	// ExperimentationSDKScopes is a comma-separated list of ExP subscription scopes.
	// Scopes limit which experiments are evaluated per assignment call, reducing latency.
	// Example: "subscription-id-1,subscription-id-2"
	ExperimentationSDKScopes string `config:",env=EXPERIMENTATION_SDK_SCOPES"`
	// ExperimentationSPNName is the environment variable key that holds the SPN client secret,
	// and is also used to derive the environment variable keys for the tenant and client IDs for ExP auth.
	ExperimentationSPNName string `config:",env=EXPERIMENTATION_SPN_NAME"`
	// These values are loaded from environment variables whose keys vary by environment:
	// the tenant and client IDs use keys derived from the SPN name. Both
	// must be explicitly loaded by the initialization code.
	ExperimentationSPNTenantID string
	ExperimentationSPNClientID string
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

	// In-memory cache for automations.Lookup.HasActiveForEvent.
	AutomationLookupCacheSize int           `config:"10000,env=AUTOMATION_LOOKUP_CACHE_SIZE"`
	AutomationLookupCacheTTL  time.Duration `config:"60s,env=AUTOMATION_LOOKUP_CACHE_TTL"`

	// Staging and production use the same secret environment, but not the same aqueduct secrets because we want to use a different worker pool in staging to prevent cross traffic.
	AqueductStagingAPIKey                  string `config:"test,env=AQUEDUCT_STAGING_API_KEY"`
	AqueductStagingAPIKeyVersion           int    `config:"0,env=AQUEDUCT_STAGING_API_KEY_VERSION"`
	AqueductStagingJediKnightAPIKey        string `config:"test,env=AQUEDUCT_STAGING_JEDI_KNIGHT_API_KEY"`
	AqueductStagingJediKnightAPIKeyVersion int    `config:"0,env=AQUEDUCT_STAGING_JEDI_KNIGHT_API_KEY_VERSION"`
	AqueductStagingSithLordAPIKey          string `config:"test,env=AQUEDUCT_STAGING_SITH_LORD_API_KEY"`
	AqueductStagingSithLordAPIKeyVersion   int    `config:"0,env=AQUEDUCT_STAGING_SITH_LORD_API_KEY_VERSION"`
	AqueductStagingBabyYodaAPIKey          string `config:"test,env=AQUEDUCT_STAGING_BABY_YODA_API_KEY"`
	AqueductStagingBabyYodaAPIKeyVersion   int    `config:"0,env=AQUEDUCT_STAGING_BABY_YODA_API_KEY_VERSION"`

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
	// AgentLauncherSandbox represents the Sandbox VM launcher.
	AgentLauncherSandbox AgentLauncher = "sandbox"
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

	// Check if Redis dev environment file exists and add it to the list
	_, err = os.Stat(".env.redis-dev")
	if err == nil {
		configFiles = append(configFiles, ".env.redis-dev")
	}

	// Always load .env last so it can override other settings
	configFiles = append(configFiles, ".env")

	cfg, err := LoadFiles(configFiles...)
	if err != nil {
		return nil, goerrors.Errorf("loading config: %w", err)
	}

	env, err := ParseEnvironment(cfg.EnvironmentName)
	if err != nil {
		return nil, goerrors.Errorf("invalid environment: %w", err)
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
		return observability.Exporters{}, goerrors.Errorf("failed to create logger: %w", err)
	}
	logger := telemetryProvider.Logger.Named(loggerName)
	log.SetDefault(logger)
	tracer := telemetryProvider.Tracer.Tracer

	// Exceptions
	exceptionsReporter, err := exceptions.NewReporter(cfg.IsDevelopment(), cfg.ServiceName, cfg.EnvironmentName, cfg.Sha, cfg.Ref, logger)
	if err != nil {
		return observability.Exporters{}, goerrors.Errorf("failed to create exception reporter: %w", err)
	}

	// Stats
	statsClient, err := stats.NewClient(cfg.IsDevelopment(), cfg.StatsPeriod, cfg.StatsAddr, cfg.ServiceName, cfg.EnvironmentName, cfg.KubePodName, cfg.KubeContainerName, cfg.KubeNamespace)
	if err != nil {
		return observability.Exporters{}, goerrors.Errorf("failed to create stats client: %w", err)
	}
	statsClient.Run()

	// Hydro
	hydroPublisher, err := hydro.NewPublisher(cfg.IsDevelopment(), cfg.HydroClientID, cfg.HydroKafkaVersion, cfg.HydroBrokers, logger, exceptionsReporter, statsClient)
	if err != nil {
		return observability.Exporters{}, goerrors.Errorf("failed to create hydro publisher: %w", err)
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

		return -1, goerrors.Errorf("unknown environment: %s", s)
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

// CommitterIdentity returns the committer name and email for GitHub's
// web-flow identity, derived from GitHubServerURL. This identity must match
// the web-flow user on the target GitHub instance so that GPG signature
// verification succeeds.
//
// For dotcom:  ("GitHub", "noreply@github.com")
// For Proxima: ("GitHub Enterprise", "noreply@ghe.com")
// For local dev: ("GitHub", "noreply@github.localhost")
func (cfg *Config) CommitterIdentity() (name, email string) {
	if cfg.Environment == EnvironmentProxima {
		return "GitHub Enterprise", "noreply@ghe.com"
	}

	name = "GitHub"
	host := "github.com"
	serverURL := cfg.GitHubServerURL
	// url.Parse treats schemeless strings (e.g. "github.mycompany.com") as a
	// path, not a host. Prepend https:// so Hostname() works correctly.
	if serverURL != "" && !strings.Contains(serverURL, "://") {
		serverURL = "https://" + serverURL
	}
	u, err := url.Parse(serverURL)
	if err == nil && u.Hostname() != "" {
		host = u.Hostname()
	}
	email = "noreply@" + host
	return name, email
}

func (cfg *Config) populateSPNValues() {
	cfg.AzureCosmosDBSPNTenantID = os.Getenv(fmt.Sprintf("%s_tenant_id", cfg.AzureCosmosDBSPNName))
	cfg.AzureCosmosDBSPNClientID = os.Getenv(fmt.Sprintf("%s_client_id", cfg.AzureCosmosDBSPNName))

	if cfg.ExperimentationSPNName != "" {
		cfg.ExperimentationSPNTenantID = os.Getenv(fmt.Sprintf("%s_tenant_id", cfg.ExperimentationSPNName))
		cfg.ExperimentationSPNClientID = os.Getenv(fmt.Sprintf("%s_client_id", cfg.ExperimentationSPNName))
	}
}
