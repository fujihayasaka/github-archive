package mu

import (
	"context"
	"crypto/rsa"
	"crypto/tls"
	"net/http"
	"time"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability/logger"
	stats "github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/launchconfig"
)

type configger interface {
	OnConfig(*Config) error
}

type starter interface {
	OnStartUp(*Service) error
}

// Old version of the OnShutDown handler, without a context.
type oldStopper interface {
	OnShutDown(*Service) error
}

// stopper represents a service that provides an OnShutdown callback.
type stopper interface {
	OnShutdown(context.Context, *Service) error
}

// beforeStopper represents a service that provides a BeforeShutdown callback.
type beforeStopper interface {
	BeforeShutdown(context.Context, *Service) error
}

type healthChecker interface {
	OnHealthCheck(*Service) (status HealthCheckStatus, checks map[string]interface{})
}

type healthCheckerStr interface {
	OnHealthCheck(*Service) (status string, checks map[string]interface{})
}

// HealthCheckStatus is the response from a service health check endpoint.
type HealthCheckStatus string

// HealthCheckOK is when a service is OK.
var HealthCheckOK HealthCheckStatus = "OK"

// HealthCheckError is when a service is unhealthy.
var HealthCheckError HealthCheckStatus = "ERROR"

// UnhealthyStatusCode is the status code returned when a service is unhealthy.
var UnhealthyStatusCode = http.StatusServiceUnavailable

type healthCheckResponse struct {
	Status       HealthCheckStatus      `json:"status"`
	HostName     string                 `json:"hostname"`
	BuildVersion string                 `json:"buildVersion"`
	MuVersion    string                 `json:"muVersion"`
	Now          time.Time              `json:"now"`
	Boot         time.Time              `json:"boot"`
	Uptime       time.Duration          `json:"uptime"`
	Checks       map[string]interface{} `json:"checks,omitempty"`
}

// Config is the application configuration loaded from the environment.
//
//nolint:maligned
type Config struct {
	// App config, set at startup from mu applications.
	Name         string
	BuildVersion string
	MuVersion    string
	Application  starter

	// HTTP Config
	HTTPAddr      string `config:",env=HTTP_ADDR"`
	HTTPTLSConfig *tls.Config

	// Internal Listener Config
	InternalAddr         string         `config:""`
	ChatopsAuthPublicKey *rsa.PublicKey `config:""`
	ChatopsAuthBaseURL   string         `config:",env=CHATOPS_AUTH_BASE_URL"`

	// Logger config
	HaystackHostname string `config:""`
	LogDebug         bool   `config:"true,env=LAUNCH_LOG_DEBUG"`
	SyslogProto      string `config:""`
	SyslogAddr       string `config:""`
	HaystackApp      string `config:""`
	HaystackURL      string `config:",env=FAILBOT_HAYSTACK_URL"`
	GrpcLogLevel     string `config:"info,env=LAUNCH_GRPC_LOG_LEVEL"`
	DefaultLogFields []kvp.Field

	// Statter config
	StatsAddr   string        `config:"127.0.0.1:28125"`
	StatsLog    bool          `config:"false"` // Set to true to log stats to standard out. Takes precedence over StatsAddr.
	StatsPrefix string        `config:""`
	StatsPeriod time.Duration `config:"10s"`
	StatsTags   stats.Tags

	// Admin Service config
	AdminCredentials string `config:""`

	// File for shutdown socket
	ShutdownSocket string `config:""`

	// Launch specific overrides added during the transition off of mu
	LaunchMode string `config:"hosted,env=LAUNCH_MODE"`
}

// NewLogger returns the logger.Logger instance for this config.
func (cfg *Config) NewLogger(loggerConfig launchconfig.LoggerConfig) logger.Logger {
	return logger.New(cfg.loggerConfig(loggerConfig))
}

// NewStatter returns the stats.Statter instance for this config.
// If you're going to use this, call Statter.Start first!!
func (cfg *Config) NewStatter() stats.Statter {
	if cfg.IsEnterprise() {
		// https://github.com/github/c2c-actions-experience/issues/2982#issuecomment-661206260
		return stats.NullStatter()
	}
	return stats.New(cfg.statterConfig())
}

func (cfg *Config) loggerConfig(loggerConfig launchconfig.LoggerConfig) *logger.Config {
	haystackHost := cfg.HaystackHostname
	if len(haystackHost) == 0 {
		haystackHost = AppHost()
	}

	haystackApp := cfg.HaystackApp
	if len(haystackApp) == 0 {
		haystackApp = cfg.Name
	}

	return &logger.Config{
		Debug:        cfg.LogDebug,
		App:          haystackApp,
		ReportURL:    cfg.HaystackURL,
		Hostname:     haystackHost,
		LoggerConfig: loggerConfig,
		// Report the following fields as tags to Sentry
		FieldTags: logger.DefaultFieldTags,
	}
}

func (cfg *Config) statterConfig() *stats.Config {
	prefix := cfg.StatsPrefix
	if len(prefix) == 0 {
		prefix = cfg.Name
	}

	return &stats.Config{
		Log:    cfg.StatsLog,
		Addr:   cfg.StatsAddr,
		Prefix: prefix,
		Period: cfg.StatsPeriod,
		Tags:   cfg.StatsTags,
	}
}

func (cfg *Config) hasHTTPAddrConfigured() bool {
	return len(cfg.HTTPAddr) != 0
}

func (cfg *Config) hasInternalAddrConfigured() bool {
	return len(cfg.InternalAddr) != 0
}

// Launch specific overrides as part of moving off mu
func (cfg *Config) IsEnterprise() bool {
	return cfg.LaunchMode == "enterprise"
}
