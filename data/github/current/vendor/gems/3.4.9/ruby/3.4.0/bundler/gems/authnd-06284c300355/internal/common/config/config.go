package config

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"os"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	goconfig "github.com/github/go-config"
	"github.com/github/go-ctxutil/sigctx"
	"github.com/github/go-exceptions"
	httpexporter "github.com/github/go-exceptions/exporters/http"
	"github.com/github/go-exceptions/exporters/writer"
	"github.com/github/go-stats"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/go-sql-driver/mysql"
	"github.com/pkg/errors"
)

// CommonConfig defines configuration values common to all authnd services
type CommonConfig struct {
	AppName     string `config:"authnd,env=APP_NAME"`
	ServiceName string

	StatsAddr   string        `config:",env=STATS_ADDR"`
	StatsPeriod time.Duration `config:"10s,env=STATS_PERIOD"`
	StatsPrefix string

	KafkaYukonBrokers   string `config:"localhost:9092,env=KAFKA_YUKON_BROKERS"`
	KafkaPotomacBrokers string `config:"localhost:9092,env=KAFKA_POTOMAC_BROKERS"`
	KafkaVersion        string `config:"1.1.1,env=KAFKA_VERSION"` // Seems to be necessary to connect to kafka-lite
	KafkaCACert         string `config:",env=KAFKA_CA_CERT"`
	KafkaDevelopmentEnv bool   `config:"false,env=KAFKA_DEVELOPMENT"`

	DeploymentEnvironment string `config:"development,env=HEAVEN_DEPLOYED_ENV"`
	DeploymentSHA         string `config:"unknown,env=HEAVEN_DEPLOYED_SHA"`
	DeploymentRef         string `config:"unknown,env=HEAVEN_DEPLOYED_REF"`
	IsEnterpriseServer    bool   `config:"false,env=IS_ENTERPRISE_SERVER"`
	IsProxima             bool   `config:"false,env=IS_PROXIMA"`
	DotcomCIMode          bool   `config:"false,env=DOTCOM_CI_MODE"`

	KubeClusterGroup string `config:"unknown,env=KUBE_CLUSTER_GROUP"`
	KubeClusterName  string `config:"unknown,env=KUBE_CLUSTER_NAME"`
	KubeDatacenter   string `config:"unknown,env=KUBE_DATACENTER"`
	KubeHostname     string `config:"unknown,env=KUBE_NODE_HOSTNAME"`
	KubeRegion       string `config:"unknown,env=KUBE_REGION"`
	KubeSite         string `config:"unknown,env=KUBE_SITE"`

	DatabaseConfigPath   string `config:",env=DATABASE_CONFIG_PATH"`
	MysqlConnMaxIdleTime string `config:"25s,env=MYSQL_CONN_MAX_IDLE_TIME"`
	MysqlConnMaxLifetime string `config:"285s,env=MYSQL_CONN_MAX_LIFETIME"`
	MysqlMaxOpenConns    int    `config:"100,env=MYSQL_MAX_OPEN_CONNS"`
	MysqlMaxIdleConns    int    `config:"100,env=MYSQL_MAX_IDLE_CONNS"`

	FrenoHost              string `config:"freno.service.github.net:8111,env=FRENO_HOST"`
	FrenoThrottlingEnabled bool   `config:"false,env=FRENO_THROTTLING_ENABLED"`

	// Tracing
	OTelServiceName string `config:",env=OTEL_SERVICE_NAME"`

	// We need to load db config once and only once (for thread-safety)
	// So this bundles up the loaded db config, a sync.Once, and an error field so that `DatabaseConfigFor` can lazy-load DB config in a thread-safe way.
	dbConfig struct {
		config map[string]*mysql.Config
		once   sync.Once
		err    error
	}
}

func NewCommonConfigFromEnvironment() (*CommonConfig, error) {
	cfg := &CommonConfig{}
	if err := goconfig.Load(cfg); err != nil {
		return nil, errors.WithStack(err)
	}

	return cfg, nil
}

// IsDevelopment returns true if this is the development environment; false, otherwise
func (cfg *CommonConfig) IsDevelopment() bool {
	return cfg.DeploymentEnvironment == "development"
}

// IsDevelopmentOrTest returns true if this is the development or test environment; false, otherwise
func (cfg *CommonConfig) IsDevelopmentOrTest() bool {
	return cfg.IsDevelopment() || cfg.IsTest()
}

// IsTest returns true if this is the test environment; false, otherwise
func (cfg *CommonConfig) IsTest() bool {
	return cfg.DeploymentEnvironment == "test"
}

// IsDotcomCI return true if the environment is the dotcom CI environment; false, otherwise
func (cfg *CommonConfig) IsDotcomCI() bool {
	return cfg.DotcomCIMode
}

// IsProductionLike returns true if this is the production-like environment and false otherwise
func (cfg *CommonConfig) IsProductionLike() bool {
	for _, keyword := range []string{
		"production",
		"staff-wus2-01",
		"prod-weu-01",
		"prod-sdc-01",
	} {
		if strings.Contains(cfg.DeploymentEnvironment, keyword) {
			return true
		}
	}
	return false
}

// IsCanary returns true if this is a canary environment; false, otherwise
func (cfg *CommonConfig) IsCanary() bool {
	return strings.Contains(cfg.DeploymentEnvironment, "canary")
}

// Removes "/canary" from the 'production/canary' environment string if present for scenarios that require this
func (cfg *CommonConfig) DeploymentEnvironmentWithoutCanary() string {
	environment := cfg.DeploymentEnvironment
	if cfg.IsCanary() {
		environment = strings.TrimSuffix(environment, "/canary")
	}
	return environment
}

func (cfg *CommonConfig) HMACAuthRequired() bool {
	if cfg.IsProxima {
		// Disabled in Proxima because we have Istio for mTLS and namespace
		// allowlisting to secure client connections to authnd
		return false
	}

	if cfg.IsDotcomCI() {
		// Disabled in dev/test for Dotcom Codespaces/CI because
		// Dotcom tests make liberal use of Timecop, which doesn't play well with
		// time-based HMACs.
		return false
	}

	return true
}

func (cfg *CommonConfig) NewRootContext() (context.Context, error) {
	ctx := sigctx.WithSignal(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	ctx = diagnostics.WithLogger(ctx, cfg.NewLogger())
	ctx = diagnostics.WithStatter(ctx, cfg.NewStatsClient())

	reporter, err := cfg.newExceptionReporter(diagnostics.Logger(ctx))
	if err != nil {
		return nil, err
	}
	ctx = diagnostics.WithReporter(ctx, reporter)
	return ctx, nil
}

// Log fields must use semantic conventions: https://thehub.github.com/epd/engineering/dev-practicals/observability/semantic-conventions/user-guide/.
// NewLogger creates a new logger, with the specified serviceName.
func (cfg *CommonConfig) NewLogger() log.Logger {
	var logger log.Logger
	var err error
	switch {
	case cfg.IsProductionLike():
		// logger = log.New(log.InfoLevel, &log.Logfmt{Sink: log.Stdout})
		logger, err = log.NewFromEnv()
	default:
		logger, err = log.NewFromConfig(log.Config{
			LogLevel:           "debug",
			LogConsoleEncoding: "console",
		})
	}
	if err != nil {
		panic(fmt.Sprintf("failed to construct otel logger: %v", err))
	}

	// Always tag logs with the "service", since we have multiple separate services (authnd, replicator, etc.) in the app
	return logger.WithFields(
		kvp.String("service", cfg.ServiceName),
		// https://thehub.github.com/epd/engineering/dev-practicals/observability/language-guides/go/semconv-migration/#haystack-api-compatibility
		// this field needs to break from semantic conventions to remain compatible with haystack
		kvp.String("deployed_to", cfg.DeploymentEnvironment),
		kvp.String("deployment.release", cfg.DeploymentSHA),
		kvp.String("deployment.ref", cfg.DeploymentRef))
}

// NewStatsClient generates a new statter for use with DataDog (or collectd in a GHES environment).
func (cfg *CommonConfig) NewStatsClient() stats.Client {
	var statter stats.Client

	if cfg.StatsPrefix == "" {
		cfg.StatsPrefix = "authnd"
	}

	switch cfg.StatsAddr {
	case "":
		statter = stats.NullStatter
	case "stdout":
		statter = stats.NewClient(os.Stdout, cfg.StatsPeriod, cfg.StatsPrefix)
	default:
		statter = stats.NewClient(stats.UDPSink(cfg.StatsAddr), cfg.StatsPeriod, cfg.StatsPrefix)
	}

	if cfg.IsEnterpriseServer {
		statter = stats.NewCollectdClient(statter)
	}

	tags := stats.Tags{"deployed_to": cfg.DeploymentEnvironment, "service": cfg.ServiceName}
	return statter.WithTags(tags)
}

// Exception fields must use semantic conventions: https://thehub.github.com/epd/engineering/dev-practicals/observability/semantic-conventions/user-guide/.
// NewExceptionReporter configures a new exceptions reporter based on the config.
// It prints reports to stdout in development environment, but sends them to
// Failbot in production.
func (cfg *CommonConfig) newExceptionReporter(logger log.Logger) (*exceptions.Reporter, error) {
	var err error
	var exporter exceptions.Exporter = writer.NewExporter(os.Stdout)

	if cfg.IsProductionLike() {
		exporter, err = httpexporter.NewExporter()
		if err != nil {
			return nil, errors.WithStack(err)
		}
	}

	options := []exceptions.Option{
		exceptions.WithExporter(exporter),
		exceptions.WithApplication(cfg.AppName),
		exceptions.WithValues(map[string]string{
			"service": cfg.ServiceName,
			// https://thehub.github.com/epd/engineering/dev-practicals/observability/language-guides/go/semconv-migration/#haystack-api-compatibility
			// this field needs to break from semantic conventions to remain compatible with haystack
			"deployed_to":        cfg.DeploymentEnvironment,
			"deployment.release": cfg.DeploymentSHA,
			"deployment.ref":     cfg.DeploymentRef,
		}),
		exceptions.WithStacktraceFunc(diagnostics.NewStackTracer()),
		exceptions.WithErrorLogger(func(reportErr, exceptionErr error, payload map[string]string) {
			if reportErr != nil {
				logger.WithError(reportErr).Error("failed to report error to exception tracker",
					kvp.String("exception.err", exceptionErr.Error()),
				)
			}
		}),
	}

	reporter, err := exceptions.NewReporter(options...)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return reporter, nil
}

// NewKafkaConfig creates a new Hydro Kafka Configuration for the configured brokers and provided client ID.
func (cfg *CommonConfig) NewHydroKafkaConfig(brokers string, opts ...hydro.KafkaConfigOption) (*hydro.KafkaConfig, error) {
	brokerList := strings.Split(brokers, ",")

	if cfg.KafkaCACert != "" {
		rootCA, err := os.ReadFile(cfg.KafkaCACert)
		if err != nil {
			return nil, errors.WithStack(err)
		}

		certPool := x509.NewCertPool()
		if ok := certPool.AppendCertsFromPEM(rootCA); !ok {
			return nil, errors.WithStack(err)
		}

		opts = append(opts,
			hydro.WithTLS(&tls.Config{RootCAs: certPool}))
	}

	if cfg.KafkaVersion != "" {
		opts = append(opts, hydro.WithKafkaVersion(cfg.KafkaVersion))
	}
	config, err := hydro.NewKafkaConfig(brokerList, opts...)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return config, nil
}

func (cfg *CommonConfig) HydroSite() string {
	if cfg.IsDevelopmentOrTest() {
		return "localhost"
	}
	return hydro.DefaultSite
}

func (cfg *CommonConfig) MySQLWriteThrottlingEnabled() bool {
	return cfg.FrenoThrottlingEnabled && !cfg.IsDevelopmentOrTest()
}
