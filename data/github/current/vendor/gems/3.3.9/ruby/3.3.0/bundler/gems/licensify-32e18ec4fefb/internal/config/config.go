// Package config holds all the environment configuration for the service.
package config

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-config"
	exceptions "github.com/github/go-exceptions"
	httpexporter "github.com/github/go-exceptions/exporters/http"
	"github.com/github/go-exceptions/exporters/writer"
	"github.com/github/go-exceptions/stacktracers/pkgerrors"
	"github.com/github/go-stats"
)

// Config holds all the environment configuration for the service.
type Config struct {
	ServiceName string `config:"licensify,env=APP_NAME"`
	HeavenEnv   string `config:",env=HEAVEN_DEPLOYED_ENV"`
	Sha         string `config:",env=APP_SHA"`
	Ref         string `config:",env=APP_REF"`

	StatsAddr   string        `config:"null,env=STATS_ADDR"`
	StatsPeriod time.Duration `config:"10s,env=STATS_PERIOD"`
	StatsPrefix string        `config:"licensify,env=STATS_PREFIX"`

	HydroConsumerGroupID string `config:"licensify-development,env=HYDRO_CONSUMER_GROUP_ID"`
	HydroKafkaBrokers    string `config:"127.0.0.1:9092,env=HYDRO_KAFKA_BROKERS"`
	HydroKafkaCAPath     string `config:",env=HYDRO_KAFKA_CA_PATH"`

	HTTPPort int `config:"12345,env=HTTP_PORT"`

	DBReadWriteSPNTenantID     string `config:",env=DB_READ_WRITE_SPN_TENANT_ID"`
	DBReadWriteSPNClientID     string `config:",env=DB_READ_WRITE_SPN_CLIENT_ID"`
	DBReadWriteSPNClientSecret string `config:",env=DB_READ_WRITE_SPN_CLIENT_SECRET"`

	DBConnectionString string `config:",env=DB_CONNECTION_STR"`
	DatabaseEndpoint   string `config:",env=AZURE_COSMOS_ENDPOINT"`
	DatabaseName       string `config:",env=DB_NAME"`
	ContainerName      string `config:",env=CONTAINER_NAME"`

	HmacKeys string `config:",env=HMAC_KEYS"`
	SkipHmac bool   `config:"false,env=SKIP_HMAC"`

	TurboghasURL     string `config:"http://localhost:8866,env=TURBOGHAS_URL"`
	TurboghasHMACKey string `config:"turboghashmac,env=TURBOGHAS_HMAC_KEY"`

	AqueductAPIKey        string `config:",env=AQUEDUCT_API_KEY"`
	AqueductAPIKeyVersion int    `config:"0,env=AQUEDUCT_API_KEY_VERSION"`
	AqueductApp           string `config:"licensify-development,env=AQUEDUCT_APP"`
	AqueductURL           string `config:"http://localhost:18081,env=AQUEDUCT_URL"`
	AqueductWorkerCount   int    `config:"1,env=AQUEDUCT_WORKER_COUNT"`
	AqueductWorkerType    string `config:"standard-priority,env=AQUEDUCT_WORKER_TYPE"`

	MonolithTwirpURL     string `config:"https://api.github.localhost/internal,env=MONOLITH_TWIRP_URL"`
	MonolithTwirpHMACKey string `config:"licensinghmac,env=MONOLITH_TWIRP_HMAC_KEY"`

	FeaturesAPIURL     string `config:"https://api.github.localhost/internal,env=MONOLITH_TWIRP_URL"`
	FeaturesAPIHMACKey string `config:"licensinghmac,env=MONOLITH_TWIRP_HMAC_KEY"`
}

// Load loads the configuration from the environment.
func Load() (*Config, error) {
	cfg := &Config{}
	if err := config.Load(cfg); err != nil {
		return nil, err
	}
	return cfg, nil
}

// IsProduction returns true if the app is running in a env deployed by heaven.
func (cfg *Config) IsProduction() bool {
	return cfg.HeavenEnv != ""
}

// ParsedHydroKafkaBrokers returns the list of Kafka brokers from the config.
func (cfg *Config) ParsedHydroKafkaBrokers() []string {
	return strings.Split(cfg.HydroKafkaBrokers, ",")
}

// ConfigureLogger configures the provided logger with the default settings.
func (cfg *Config) ConfigureLogger(logger log.Logger, namespace string) log.Logger {
	// Set the default logger level based on the environment
	if cfg.IsProduction() {
		logger = logger.WithLevel(log.InfoLevel)
	} else {
		logger = logger.WithLevel(log.DebugLevel)
	}

	// Set the top-level namespace for the logger
	// Subsequent calls to logger.Named() will append to the scope
	// Example: logger.Named("TopLevel").Named("SubComponent")
	// Log Message:  InstrumentationScope=TopLevel.SubComponent
	logger = logger.Named(namespace)

	return logger
}

// NewExceptionReporter configures a new exceptions reporter based on the config.
// It prints reports to stderr in development environment, but sends them to
// Failbotg (which is proxied to Sentry) in production.
func (cfg *Config) NewExceptionReporter() (*exceptions.Reporter, error) {
	var err error
	var exporter exceptions.Exporter = writer.NewExporter(os.Stderr)

	if cfg.IsProduction() {
		exporter, err = httpexporter.NewExporter()
		if err != nil {
			return nil, fmt.Errorf("failed to initialize a new httpexporter: %w", err)
		}
	}

	reporter, err := exceptions.NewReporter(
		exceptions.WithExporter(exporter),
		exceptions.WithApplication(cfg.ServiceName),
		exceptions.WithCatalogService("licensify"),
		exceptions.WithStacktraceFunc(pkgerrors.NewStackTracer()),
		exceptions.WithValues(map[string]string{
			"deployed_to": cfg.HeavenEnv,
			"release":     cfg.Sha,
			"ref":         cfg.Ref,
		}),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize exceptions reporter: %w", err)
	}

	return reporter, nil
}

// StatsClient generates a new statter for use with DataDog.
func (cfg *Config) StatsClient() stats.Client {
	var statsClient stats.Client
	switch cfg.StatsAddr {
	case "stdout":
		statsClient = stats.NewClient(
			os.Stdout,
			cfg.StatsPeriod,
			cfg.StatsPrefix,
		)
	case "null":
		statsClient = stats.NullStatter
	default:
		statsClient = stats.NewClient(
			stats.UDPSink(cfg.StatsAddr),
			cfg.StatsPeriod,
			cfg.StatsPrefix,
		)
	}
	return statsClient
}

// SkipHmacForLocalDev returns true if HMAC verification should be skipped for local development.
func (cfg *Config) SkipHmacForLocalDev() bool {
	return cfg.SkipHmac && (!cfg.IsProduction())
}

// GetAllHmacKeys returns all the HMAC keys from the config.
func (cfg *Config) GetAllHmacKeys() []string {
	return strings.Split(cfg.HmacKeys, " ")
}
