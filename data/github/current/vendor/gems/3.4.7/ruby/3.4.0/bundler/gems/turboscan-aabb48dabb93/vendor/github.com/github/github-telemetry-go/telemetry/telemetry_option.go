package telemetry

import (
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/trace"
)

// TelemetryOption let us configure telemetry using Telemetry Config
type TelemetryOption func(*Config) //nolint:revive // Can't change the name of exported types

// WithTracerOptions sets options for tracer
//
// For example:
//
//	 tp, err := NewFromConfig(cfg,
//		   WithTracerOptions(
//		     trace.WithExporter(trace.ExporterStdout),
//			    trace.WithExporterWriter(tbuffer),
//		   ),
//		 )
func WithTracerOptions(tracerOpts ...trace.TracerOption) TelemetryOption {
	return func(opts *Config) {
		if opts.tracingOpts == nil {
			opts.tracingOpts = make([]trace.TracerOption, 0, len(tracerOpts))
		}
		opts.tracingOpts = append(opts.tracingOpts, tracerOpts...)
	}
}

// WithLoggerOptions sets options for logging
//
// For example:
//
//		tp, err := NewFromConfig(cfg,
//		  WithLoggerOptions(
//			log.WithIncludedResources("testResource"),
//		  ),
//	 )
func WithLoggerOptions(loggerOpts ...log.Option) TelemetryOption {
	return func(opts *Config) {
		if opts.loggingOpts == nil {
			opts.loggingOpts = make([]log.Option, 0, len(loggerOpts))
		}
		opts.loggingOpts = append(opts.loggingOpts, loggerOpts...)
	}
}
