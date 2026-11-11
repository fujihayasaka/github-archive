// Package config provides a configuration loader.
package config

import (
	"crypto/tls"
	"crypto/x509"
	"errors"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/IBM/sarama"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-config"
	"github.com/github/go-exceptions"
	httpexporter "github.com/github/go-exceptions/exporters/http"
	"github.com/github/go-exceptions/exporters/writer"
	"github.com/github/go-exceptions/stacktracers/pkgerrors"
	"github.com/github/go-stats"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
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
	ServiceName string `config:"osslicensecompliance,env=APP_NAME"`
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
	DependencyGraphHMACSecret  string `config:",env=DEPENDENCY_GRAPH_HMAC_SECRET"`
	DependencyGraphEndpoint    string `config:"https://dependency-graph-api-slow-queries.service.iad.github.net,env=DEPENDENCY_GRAPH_ENDPOINT"`
	DependencySnapshotEndpoint string `config:"https://dependency-snapshots-api-production.service.iad.github.net,env=DEPENDENCY_SNAPSHOT_ENDPOINT"`

	// Azure blob storage configuration
	AzureStorageAccount string `config:",env=AZURE_STORAGE_ACCOUNT"`
	AzureBlobEndpoint   string `config:",env=AZURE_BLOB_ENDPOINT"`

	// Hydro/Kafka configuration (defaults are for dotcom Codespaces)
	KafkaClientID        string `config:"olc-dev,env=KAFKA_CLIENT_ID"`
	HydroKafkaBrokers    string `config:"127.0.0.1:9092,env=HYDRO_KAFKA_BROKERS"`
	KafkaSSLCertLocation string `config:",env=KAFKA_SSL_CERTIFICATE_LOCATION"`
	KafkaStatsEnabled    bool   `config:"false,env=KAFKA_STATS_ENABLED"`
}

// Load parses configuration from the environment and places it in a newly
// allocated Config struct.
func Load() (*Config, error) {
	// initialize configuration
	port := flag.Int("port", defaultPort, "port number to run http server on")
	//revive:disable-next-line:deep-exit // Load() is called by main; parsing flags here is intentional.
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
		// Use the failbotg URL from environment variable for production
		failbotURL := os.Getenv("FAILBOT_HAYSTACK_URL")
		if failbotURL == "" {
			return nil, errors.New("FAILBOT_HAYSTACK_URL environment variable is required in production")
		}

		exporter, err = httpexporter.NewExporter(
			httpexporter.WithURL(failbotURL),
		)
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

// IsDevelopment returns true if the configuration is set to development environment
func (cfg *Config) IsDevelopment() bool {
	return cfg.Environment == DevelopmentEnv
}

// IsStaging returns true if the configuration is set to staging environment
func (cfg *Config) IsStaging() bool {
	return cfg.Environment == StagingEnv
}

// NewKafkaConfig creates and configures a new Hydro Kafka configuration based on the application config.
// It sets up brokers, SSL/TLS settings, logging, and stats collection according to the configuration.
func (cfg *Config) NewKafkaConfig(logger log.Logger, statter stats.Client) (*hydro.KafkaConfig, error) {
	brokers := splitComma(cfg.HydroKafkaBrokers)

	opts := []hydro.KafkaConfigOption{
		hydro.WithKafkaLogger(NewHydroLogger(logger.Named("hydro-kafka"))),
	}

	if cfg.KafkaStatsEnabled {
		opts = append(opts, hydro.WithKafkaStats(statter))
	}
	if cfg.IsDevelopment() {
		opts = append(opts, hydro.WithKafkaVersion(sarama.V1_1_1_0.String()))
	}

	if certPath := cfg.KafkaSSLCertLocation; certPath != "" {
		pem, err := os.ReadFile(certPath)
		if err != nil {
			return nil, fmt.Errorf("read kafka root CA: %w", err)
		}
		pool := x509.NewCertPool()
		if ok := pool.AppendCertsFromPEM(pem); !ok {
			return nil, errors.New("append kafka root CA: invalid pem")
		}
		tlsCfg := &tls.Config{RootCAs: pool, MinVersion: tls.VersionTLS12}
		opts = append(opts, hydro.WithTLS(tlsCfg))
	}

	kc, err := hydro.NewKafkaConfig(brokers, opts...)
	if err != nil {
		return nil, fmt.Errorf("new kafka config: %w", err)
	}

	return kc, nil
}

// splitComma splits a comma-separated string into a slice of trimmed strings.
func splitComma(s string) []string {
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if v := strings.TrimSpace(p); v != "" {
			out = append(out, v)
		}
	}
	return out
}
