package config

import (
	"fmt"

	"github.com/github/go-config"
	"github.com/joho/godotenv"
)

type Environment string

const (
	Dev        Environment = "dev"
	Lab        Environment = "lab"
	Production Environment = "production"
)

type ApiServerConfig struct {
	Telemetry      TelemetryConfig
	Http           HttpConfig
	Kusto          KustoConfig
	StorageAccount StorageAccountConfig
}

type ApiServerPublicConfig struct {
	Port int `config:"8080,env=PORT"`

	Telemetry TelemetryConfig
}

type StorageAccountConfig struct {
	AccountName string `config:",env=STORAGE_ACCOUNT_NAME"`
	ServicePrincipalConfig
}

type HttpConfig struct {
	Port int `config:"8080,env=PORT"`

	HMACPrimary   string `config:",env=HMAC_PRIMARY"`
	HMACSecondary string `config:",env=HMAC_SECONDARY"`

	TwirpInternalApiUrl  string `config:",env=TWIRP_INTERNAL_API_URL"`
	TwirpInternalApiHMAC string `config:",env=API_INTERNAL_TWIRP_HMAC_KEYS_FOR_ACTIONS_USAGE_METRICS"`
}

type ServicePrincipalConfig struct {
	TenantId     string `config:",env=SERVICE_PRINCIPAL_TENANT_ID"`
	ClientId     string `config:",env=SERVICE_PRINCIPAL_CLIENT_ID"`
	ClientSecret string `config:",env=SERVICE_PRINCIPAL_CLIENT_SECRET"`

	IsDev bool `config:"false,env=IS_DEV"` // use dev auth (AZ CLI for codespace and access token for CI)
}

type KustoConfig struct {
	ServicePrincipalConfig
	ConnectionString    string   `config:",env=KUSTO_CONNECTION_STRING"`
	Database            string   `config:",env=KUSTO_DATABASE"`         // main DB containing metrics info
	RepoDatabase        string   `config:",env=KUSTO_REPO_DATABASE"`    // repo DB containing repo info used to map repo id -> name
	KustoDevOrgsMapping []string `config:",env=KUSTO_DEV_ORG_MAPPINGS"` // orgs to map to github, e.g. owner id 1 -> 9919.
}

type TelemetryConfig struct {
	Service           string      `config:"actions-usage-metrics,env=SERVICE"`
	KubeClusterName   string      `config:",env=KUBE_CLUSTER_NAME"`
	KubeContainerName string      `config:",env=KUBE_CONTAINER_NAME"`
	KubeNamespace     string      `config:",env=KUBE_NAMESPACE"`
	PodName           string      `config:",env=POD_NAME"`
	Environment       Environment `config:",env=GH_OTEL_DEPLOYMENT_ENVIRONMENT"`

	LogLevel      string `config:"info,env=LOG_LEVEL"`
	StdoutMetrics bool   `config:"false,env=STDOUT_METRICS"`

	TraceSampleRate float64 `config:"1,env=TRACE_SAMPLE_RATE"`

	DatadogAgentHost         string   `config:",env=DD_AGENT_HOST"`
	DatadogAgentPort         int      `config:"8125,env=DD_DOGSTATSD_PORT"`
	OwnerIdsToIncludeInStats []string `config:",env=OWNER_IDS_TO_INCLUDE_IN_STATS"`

	FailbotHaystackURL string `config:",env=FAILBOT_HAYSTACK_URL"`

	WaitForDebugger bool `config:"false,env=WAIT_FOR_DEBUGGER"`
}

func Load[T any]() (*T, error) {
	var cfg T

	// Load config from environment variables
	if err := config.Load(&cfg); err != nil {
		return nil, err
	}

	return &cfg, nil
}

func LoadFromFile[T any](file string) (*T, error) {
	err := godotenv.Load(file)
	if err != nil {
		return nil, fmt.Errorf("failed to load env file: %w", err)
	}

	return Load[T]()
}
