package telemetry

import (
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/trace"
)

// Config is used to configure the telemetry system. It's a composite of the configuration
// values from each of the individual telemetry components. The common usage will be that this
// struct's sub-values are filled with values from environment variables.
type Config struct {
	Logging log.Config
	Tracing trace.Config

	loggingOpts []log.Option
	tracingOpts []trace.TracerOption
}
