package launchchaos

import (
	"context"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/pkg/fault"
)

type logReporter struct {
	log logger.Logger
}

func NewLogReporter(log logger.Logger) fault.Reporter {
	return &logReporter{log: log}
}

func (l *logReporter) Report(ctx context.Context, name string, state fault.InjectorState) {
	l.log.Debug(ctx, name, kvp.Int("gh.launch.injector_state", int(state)))
}
