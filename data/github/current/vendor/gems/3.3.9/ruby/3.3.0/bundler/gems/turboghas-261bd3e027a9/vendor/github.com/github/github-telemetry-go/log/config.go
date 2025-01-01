package log

import (
	"go.opentelemetry.io/otel/sdk/resource"
	"go.uber.org/zap/zapcore"
)

// DurationFormat is used to configure how [time.Duration] instances are
// serialized.
type DurationFormat int

const (
	// Serialize durations as fractional seconds. The default.
	DurationFormatFractionalSeconds = iota
	// Serialize durations as an integer number of milliseconds.
	DurationFormatMillis
	// Serialize durations as an integer number of nanoseconds.
	DurationFormatNanos
	// Serialize durations as a string from [time.Duration.String].
	DurationFormatString
)

// Config is used to configure the logging system. The common usage will be that this
// struct is filled with values from environment variables.
//
// Remember if you add fields to Config, you need to update the clone() method below!
type Config struct {
	Environment                  string `config:",env=GITHUB_TELEMETRY_ENVIRONMENT"`
	LogConsoleEncoding           string `config:"logfmt,env=GITHUB_TELEMETRY_LOGS_CONSOLE_ENCODING"`
	LogIncludeResourceAttributes string `config:"<DEFAULT>,env=GITHUB_TELEMETRY_LOGS_INCLUDE_RESOURCE_ATTRIBUTES"`
	LogLevel                     string `config:",env=GITHUB_TELEMETRY_LOGS_LEVEL"`
	LogPrecision                 string `config:",env=GITHUB_TELEMETRY_LOGS_PRECISION"`
	LogTimezone                  string `config:",env=GITHUB_TELEMETRY_LOGS_TZ"`

	// Comparing with https://github.com/github/github-telemetry-ruby/blob/main/lib/github/telemetry/logs.rb
	// There is some disparity:
	//   Ruby: GITHUB_TELEMETRY_LOGS_STDOUT     Go: N/A
	//   Ruby: GITHUB_TELEMETRY_LOGS_LIB_LEVEL  Go: N/A
	//   Ruby: N/A                              Go: GITHUB_TELEMETRY_LOGS_PRECISION
	//   Ruby: N/A                              Go: GITHUB_TELEMETRY_LOGS_TZ
	// In the future, we may choose to change these defaults in pursuit of a standard.

	encoder                   *zapcore.Encoder
	environment               string
	serviceName               *string
	serviceVersion            *string
	instanceID                string
	includeResourceAttributes map[string]struct{}
	isSetup                   bool
	level                     Level
	outputFormat              outputFormat
	resource                  *resource.Resource
	writeSyncer               zapcore.WriteSyncer
	precision                 precision
	timezone                  timezone
	durationFormat            DurationFormat

	// Name and version for the sdk
	sdkname    string
	sdkversion string
}

func (lc *Config) clone() *Config {
	var newEncoder *zapcore.Encoder

	if lc.encoder != nil {
		clonedEncoder := (*lc.encoder).Clone()
		newEncoder = &clonedEncoder
	}

	return &Config{
		Environment:                  lc.Environment,
		LogConsoleEncoding:           lc.LogConsoleEncoding,
		LogIncludeResourceAttributes: lc.LogIncludeResourceAttributes,
		LogLevel:                     lc.LogLevel,
		LogPrecision:                 lc.LogPrecision,
		LogTimezone:                  lc.LogTimezone,

		encoder:                   newEncoder,
		environment:               lc.environment,
		instanceID:                lc.instanceID,
		includeResourceAttributes: lc.includeResourceAttributes,
		isSetup:                   lc.isSetup,
		level:                     lc.level,
		outputFormat:              lc.outputFormat,
		resource:                  lc.resource,
		writeSyncer:               lc.writeSyncer,
		precision:                 lc.precision,
		timezone:                  lc.timezone,
		durationFormat:            lc.durationFormat,
		sdkname:                   lc.sdkname,
		sdkversion:                lc.sdkversion,
		serviceName:               lc.serviceName,
		serviceVersion:            lc.serviceVersion,
	}
}
