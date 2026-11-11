package log

import (
	"maps"

	"go.uber.org/zap/zapcore"
)

// Option lets you change the behavior of the logger
// see the exported functions in this file for details.
type Option func(*Config)

// WithIncludedResources overrides which resource attributes are logged with each
// log entry. service.name is always included regardless of the keys provided,
// because it is required for log routing and retention. See
// defaultIncludeResources for the set of attributes used when this option is
// not specified.
//
// Example:
//
//	// Logs will include service.name (always) plus telemetry.sdk.name
//	log.WithIncludedResources("telemetry.sdk.name")
func WithIncludedResources(resourceKeys ...string) Option {
	rs := make(map[string]struct{}, len(requiredResources)+len(resourceKeys))
	maps.Copy(rs, requiredResources)
	for _, r := range resourceKeys {
		rs[r] = struct{}{}
	}
	return func(lc *Config) {
		lc.includeResourceAttributes = rs
	}
}

// WithJSONConsole sets the log output format to JSON.
func WithJSONConsole() Option {
	return func(lc *Config) {
		lc.outputFormat = outputFormatJSON
	}
}

// WithLogLevel sets the log level for the logger.
func WithLogLevel(level Level) Option {
	return func(lc *Config) {
		lc.level = level
	}
}

// WithDurationFormat configures the serialization for durations.
func WithDurationFormat(df DurationFormat) Option {
	return func(lc *Config) {
		lc.durationFormat = df
	}
}

// WriteSyncer abstracts zapcore.WriteSyncer
// so that consumers don't import the zap library.
// It is essentially an io.Writer + Sync() error.
type WriteSyncer = zapcore.WriteSyncer

// WithWriteSyncer lets you change the destination of the
// logs to your own io.Writer implementation.
func WithWriteSyncer(ws WriteSyncer) Option {
	return func(lc *Config) {
		lc.writeSyncer = ws
	}
}
