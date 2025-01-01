package log

import (
	"go.uber.org/zap/zapcore"
)

// Option lets you change the behavior of the logger
// see the exported functions in this file for details.
type Option func(*Config)

// WithIncludedResources overrides which resources are logged with each log entry. See
// defaultIncludeResources for the default set of resources.q
func WithIncludedResources(resourceKeys ...string) Option {
	rs := make(map[string]struct{}, len(resourceKeys))
	for _, r := range resourceKeys {
		rs[r] = struct{}{}
	}

	return func(lc *Config) {
		lc.includeResourceAttributes = rs
	}
}

func WithJSONConsole() Option {
	return func(lc *Config) {
		lc.outputFormat = outputFormatJSON
	}
}

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
