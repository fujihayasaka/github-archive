// Package config provides a configuration loader.
package config

import (
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/github/go-config"
	"github.com/github/go-exceptions"
	httpexporter "github.com/github/go-exceptions/exporters/http"
	"github.com/github/go-exceptions/exporters/writer"
	"github.com/github/go-exceptions/stacktracers/pkgerrors"
	"github.com/github/go-stats"
)

const (
	// DevelopmentEnv represents the development environment
	DevelopmentEnv = "development"
	// StagingEnv represents the staging environment
	StagingEnv  = "staging"
	defaultPort = 8080
)

// Config holds application configuration, including statting and tracing configs.
type Config struct {
	HTTPPort    int    `config:"8080,env=HTTP_PORT"`
	ServiceName string `config:"osscompliance,env=APP_NAME"`
	Environment string `config:"development,env=HEAVEN_DEPLOYED_ENV"`
	Sha         string `config:",env=APP_SHA"`
	Ref         string `config:",env=APP_REF"`

	// SubSystems controls the real or null stub systems
	// "real" subsystems are mysql DB and dependency graph API
	// "null" being sqlite and stubbed Null dependencies
	// Must use a combination of Environment: development and SubSystems: null
	SubSystems string `config:"real,env=SUBSYSTEMS"`

	StatsAddr   string        `config:",env=STATS_ADDR"`
	StatsPeriod time.Duration `config:"10s,env=STATS_PERIOD"`

	// CHATOPS_AUTH_PUBLIC_KEY is set in vault and will be injected as env var on moda servers.
	ChatopsAuthPublicKey       string   `config:",env=CHATOPS_AUTH_PUBLIC_KEY"`
	ChatopsAuthAltPublicKey    string   `config:",env=CHATOPS_AUTH_ALT_PUBLIC_KEY"`
	ChatopsAuthBaseURL         string   `config:"http://localhost:8008/_chatops,env=CHATOPS_AUTH_BASE_URL"`
	ChatopsHTTPAddr            string   `config:":8008,env=CHATOPS_HTTP_ADDR"`
	ChatopsHealthHTTPAddr      string   `config:":8009,env=CHATOPS_HEALTH_HTTP_ADDR"`
	DevForceHmacAuthentication bool     `config:"false,env=DEV_FORCE_HMAC_AUTH"`
	HMACSecret                 string   `config:":test_secret,env=CHATOPS_HMAC_SECRET"`
	TwirpHMACKeys              []string `config:",env=TWIRP_HMAC_KEYS"`

	// Mode is the application mode, either "live" or "test".
	// This controls how the database and other subsystems are configured.
	Mode string `config:"live,env=MODE"`

	// MySQL is the configuration for the MySQL database. Here are the
	// environment variables you can set:
	// OLC_MYSQL_USER
	// OLC_MYSQL_PASSWORD
	// OLC_MYSQL_HOST
	// OLC_MYSQL_PORT
	// OLC_MYSQL_DATABASE
	MySQL map[string]string `config:",env-prefix=OLC_MYSQL_"`

	// DependencyGraphHMACKey is for local use obtained from .dg hmac
	DependencyGraphHMACKey string `config:",env=DEPENDENCY_GRAPH_HMAC_KEY"`
	// DependencyGraphHMACSecret must be provided for deployed services
	DependencyGraphHMACSecret string `config:",env=DEPENDENCY_GRAPH_HMAC_SECRET"`
	DependencyGraphEndpoint   string `config:"https://dependency-graph-api.service.iad.github.net,env=DEPENDENCY_GRAPH_ENDPOINT"`

	// Azure blob storage configuration
	AzureStorageAccount string `config:",env=AZURE_STORAGE_ACCOUNT"`
	AzureBlobEndpoint   string `config:",env=AZURE_BLOB_ENDPOINT"`
}

// Load parses configuration from the environment and places it in a newly
// allocated Config struct.
func Load() (*Config, error) {
	// initialize configuration
	port := flag.Int("port", defaultPort, "port number to run http server on")
	flag.Parse()

	cfg := &Config{
		HTTPPort: *port,
	}

	if err := config.Load(cfg); err != nil {
		return nil, err
	}

	return cfg, nil
}

// NewExceptionReporter configures a new exceptions reporter based on the config.
// It prints reports to stderr in development environment, but sends them to
// Failbotg (which is proxied to Sentry) in production.
func (cfg *Config) NewExceptionReporter() (*exceptions.Reporter, error) {
	var err error
	var exporter exceptions.Exporter = writer.NewExporter(os.Stderr)

	if cfg.Environment == "production" {
		exporter, err = httpexporter.NewExporter()
		if err != nil {
			return nil, err
		}
	}

	reporter, err := exceptions.NewReporter(
		exceptions.WithExporter(exporter),
		exceptions.WithApplication(cfg.ServiceName),
		exceptions.WithStacktraceFunc(pkgerrors.NewStackTracer()),
		exceptions.WithValues(map[string]string{
			"deployment.environment": cfg.Environment,
			"gh.deployment.sha":      cfg.Sha,
			"gh.deployment.ref":      cfg.Ref,
		}),
	)
	if err != nil {
		return nil, err
	}

	return reporter, nil
}

// NewStatsClient generates a new statter for use with DataDog.
func (cfg *Config) NewStatsClient() (stats.Client, error) {
	if cfg.StatsAddr == "" {
		return stats.NullStatter, nil
	}

	return stats.NewClient(stats.UDPSink(cfg.StatsAddr), cfg.StatsPeriod, "osscompliance"), nil
}

// AzureStorageSPNCredentials holds the service principal credentials for Azure Storage authentication.
type AzureStorageSPNCredentials struct {
	ClientSecret string
	ClientID     string
	TenantID     string
}

// GetAzureStorageCreds retrieves Azure Storage service principal credentials from environment variables.
// It returns the credentials struct and a boolean indicating whether all required credentials were found.
func (cfg *Config) GetAzureStorageCreds() (AzureStorageSPNCredentials, bool) {
	creds := AzureStorageSPNCredentials{}
	storageSPNEnv := os.Getenv("AZURE_STORAGE_SPN")
	creds.ClientSecret = os.Getenv(storageSPNEnv)
	creds.TenantID = os.Getenv(fmt.Sprintf("%s_tenant_id", storageSPNEnv))
	creds.ClientID = os.Getenv(fmt.Sprintf("%s_client_id", storageSPNEnv))
	return creds, creds.ClientSecret != "" && creds.ClientID != "" && creds.TenantID != ""
}

// IsDevelopment returns true if the configuration is set to development environment
func (cfg *Config) IsDevelopment() bool {
	return cfg.Environment == DevelopmentEnv
}

// IsStaging returns true if the configuration is set to staging environment
func (cfg *Config) IsStaging() bool {
	return cfg.Environment == StagingEnv
}
