package launchconfig

import "time"

type LoggerConfig struct {
	// Logging
	LogDebug              bool   `config:"false,env=LAUNCH_LOG_DEBUG"`
	LogFormat             string `config:"logfmt,env=GITHUB_TELEMETRY_LOGS_CONSOLE_ENCODING"`
	LogResourceAttributes string `config:",env=GITHUB_TELEMETRY_LOGS_INCLUDE_RESOURCE_ATTRIBUTES"`
	LogLevel              string `config:"info,env=GITHUB_TELEMETRY_LOGS_LEVEL"`
	LogPrecision          string `config:"nanosecond,env=GITHUB_TELEMETRY_LOGS_PRECISION"`
	LogTimezone           string `config:"utc,env=GITHUB_TELEMETRY_LOGS_TZ"`
	LogTraceIgnoredKeys   string `config:",env=GITHUB_TELEMETRY_TRACE_IGNORED_KEYS"`
}

// CommonConfig is the configuration common to all Launch processes.
// We can gradually move more configuration here over time as useful.
type CommonConfig struct {
	LaunchEnv  string `config:"production,env=LAUNCH_ENV"`
	LaunchMode string `config:"hosted,env=LAUNCH_MODE"`

	// IsMultiTenant indicates whether Launch is running in multi-tenant mode
	IsMultiTenant bool `config:"false,env=LAUNCH_IS_MULTI_TENANT"`

	// Logging
	LoggerConfig

	// Metrics
	StatsAddr   string        `config:"127.0.0.1:28125,env=STATS_ADDR"`
	StatsPrefix string        `config:"launch,env=STATS_PREFIX"`
	StatsPeriod time.Duration `config:"10s,env=STATS_PERIOD"`

	// Tracing configuration
	TracingEnabled bool `config:"false,env=TRACING_ENABLED"`
}

func (c CommonConfig) Environment() AppEnv {
	return AppEnv(c.LaunchEnv)
}

func (c CommonConfig) AppMode() AppMode {
	return ParseMode(c.LaunchMode)
}

func (c CommonConfig) IsEnterprise() bool {
	return c.AppMode() == EnterpriseAppMode
}

func (c CommonConfig) IsLab() bool {
	return c.Environment().IsLab()
}

func (c CommonConfig) IsDevelopment() bool {
	return c.Environment().IsDevelopment()
}
